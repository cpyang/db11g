# -*- mode: ruby -*-
# vi: set ft=ruby :
#
# Oracle 11.2.0.4 RAC — two nodes on VirtualBox, driven by host-side Ansible.
#
# SHARED DISK STRATEGY (validated on this host family with VBox 7.x)
# -------------------------------------------------------------------
# VirtualBox only allows one VDI to be mounted by multiple VMs when ALL of:
#   1. The medium was created --variant Fixed AND set --type shareable
#      (VBox 7 REJECTS --mtype shareable for DYNAMIC media).
#   2. Every storageattach call uses --mtype shareable.
#   3. The SAS controller exists before storageattach runs.
# The previous version of this file created DYNAMIC VDIs and never attached
# them to anything — ASM had no shared disks at all. Shared ASM disks now get
# DISTINCT sizes (12/20/10 GB): guests map devices to ASM labels by exact
# sector size, never by /dev/sdX letters, and unique sizes are the identity.
#
# NETWORK NOTE
# ------------
# 192.168.56.0/24 and 10.10.10.0/24 are already owned by the 19c RAC lab
# (oracle_dr_on_aws) on this host, so this lab lives on 192.168.86.0/24
# (public, host-only) and a VBox internal network 10.90.90.0/24
# (interconnect). Do not "align" these ranges with the other lab.
#
# Vagrant applies private_network IPs only on FIRST boot — if VMs are
# recreated over existing media, check both NICs are addressed after boot.

require 'fileutils'

# Set DB11G_SKIP_DISK_PREP=1 to parse the file without touching host disk
# media (used by `vagrant validate` / lint runs).
SKIP_DISK_PREP = ENV['DB11G_SKIP_DISK_PREP'] == '1'

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------
DOMAIN        = 'db11g.lab'
NETWORK       = '192.168.86'   # host-only "public"
PRIV_NETWORK  = '10.90.90'     # VBox internal network (cluster interconnect)
SCAN_IP       = "#{NETWORK}.100"
INTNET_NAME   = 'db11g-priv-net'

VAGRANT_ROOT = File.dirname(File.expand_path(__FILE__))
DISK_DIR     = File.join(VAGRANT_ROOT, '.vagrant', 'shared_disks')
MACHINES_DIR = File.join(VAGRANT_ROOT, '.vagrant', 'machines')
ASM_CTRL     = 'ASM_SCSI'

# Shared ASM disks — sizes MUST stay pairwise distinct (size = identity).
SHARED_DISKS = {
  'db11g_crs'  => 12,   # GB — OCR + voting disks (disk group CRS)
  'db11g_data' => 20,   # GB — database files     (disk group DATA)
  'db11g_fra'  => 10,   # GB — flash recovery area (disk group FRA)
}
SWAP_DISK_GB = 6        # node-exclusive; CVU wants swap ~= RAM (6 GB)

NODES = {
  'db11g-rac1' => {
    fqdn: "db11g-rac1.#{DOMAIN}",
    public_ip: "#{NETWORK}.11",
    private_ip: "#{PRIV_NETWORK}.11",
    vip: "#{NETWORK}.101",
    memory: 6144,
    cpus: 2,
    grid_home: '/u01/app/11.2.0/grid',
    oracle_home: '/u01/app/oracle/product/11.2.0/dbhome_1',
  },
  'db11g-rac2' => {
    fqdn: "db11g-rac2.#{DOMAIN}",
    public_ip: "#{NETWORK}.12",
    private_ip: "#{PRIV_NETWORK}.12",
    vip: "#{NETWORK}.102",
    memory: 6144,
    cpus: 2,
    grid_home: '/u01/app/11.2.0/grid',
    oracle_home: '/u01/app/oracle/product/11.2.0/dbhome_1',
  },
}

# --------------------------------------------------------------------------
# Host-side disk helpers (run at parse time unless SKIP_DISK_PREP)
# --------------------------------------------------------------------------
def create_shared_disk(name, size_gb, disk_dir)
  disk_path = File.join(disk_dir, "#{name}.vdi")
  unless File.exist?(disk_path)
    puts "  [shared-disk] Creating #{disk_path} (#{size_gb} GB, Fixed+shareable)..."
    ok = system("vboxmanage createmedium disk --filename \"#{disk_path}\" " \
                "--size #{size_gb * 1024} --format VDI --variant Fixed")
    abort "  ERROR: createmedium failed for #{name}" unless ok
    system("vboxmanage modifymedium disk \"#{disk_path}\" --type shareable")
  end

  # Register-by-path may fail if a stale registry entry holds another path.
  info = `vboxmanage showmediuminfo "#{disk_path}" 2>&1`
  if info =~ /with UUID \{(.*?)\} already exists/
    uuid = $1
    puts "  [shared-disk] Fixing stale registry path for #{name} (UUID #{uuid})..."
    system("vboxmanage closemedium disk #{uuid}")
    info = `vboxmanage showmediuminfo "#{disk_path}" 2>&1`
  end
  # VBox 7 rejects --mtype shareable for DYNAMIC media. Fail loudly instead
  # of producing a half-attached cluster (the old disks/*.vdi were dynamic).
  abort "  ERROR: #{disk_path} is DYNAMIC media — remove it (must be " \
        "unattached+empty) and let the Vagrantfile recreate it Fixed.\n" \
        "  Check: vboxmanage showmediuminfo \"#{disk_path}\"" if
        info.include?('Format variant: dynamic')
  disk_path
end

def create_node_disk(name, size_gb, disk_dir)
  disk_path = File.join(disk_dir, "#{name}.vdi")
  unless File.exist?(disk_path)
    puts "  [node-disk] Creating #{disk_path} (#{size_gb} GB, dynamic)..."
    ok = system("vboxmanage createmedium disk --filename \"#{disk_path}\" " \
                "--size #{size_gb * 1024} --format VDI")
    abort "  ERROR: createmedium failed for #{name}" unless ok
  end
  disk_path
end

def attach_disk(vb, ctrl, port, disk_path, mtype = 'shareable')
  vb.customize ['storageattach', :id,
                '--storagectl', ctrl,
                '--port', port.to_s,
                '--device', '0',
                '--type', 'hdd',
                '--medium', disk_path,
                '--mtype', mtype]
end

# Remove ASM_SCSI before every up/reload so storagectl --add is idempotent
# (vb.customize re-runs on every boot, not just creation). reload does not
# fire :up triggers, hence both. Copied from the sibling 19c lab.
def ensure_clean_scsi_ctrl(node, vm_name, ctrl)
  [:up, :reload].each do |trigger_cmd|
    node.trigger.before trigger_cmd do |t|
      t.name = "[#{vm_name}] Remove stale #{ctrl} before #{trigger_cmd}"
      t.ruby do |env, machine|
        id_file = File.join(MACHINES_DIR, vm_name, 'virtualbox', 'id')
        next unless File.exist?(id_file)
        uuid = File.read(id_file).strip
        state = `vboxmanage showvminfo "#{uuid}" --machinereadable 2>/dev/null | grep '^VMState=' | cut -d'"' -f2`.strip
        if !state.empty? && state != 'poweroff'
          puts "  [pre-#{trigger_cmd} #{vm_name}] VM is '#{state}' — powering off for controller cleanup..."
          system("vboxmanage controlvm \"#{uuid}\" poweroff 2>/dev/null || true")
          sleep 2
        end
        if system("vboxmanage showvminfo \"#{uuid}\" 2>/dev/null | grep -q '#{ctrl}'")
          puts "  [pre-#{trigger_cmd} #{vm_name}] Removing stale #{ctrl}..."
          system("vboxmanage storagectl \"#{uuid}\" --name \"#{ctrl}\" --remove 2>/dev/null || true")
        end
      end
    end
  end
end

# --------------------------------------------------------------------------
# Pre-create media before any VM boots
# --------------------------------------------------------------------------
FileUtils.mkdir_p(DISK_DIR)
DISK_VARS = {}
unless SKIP_DISK_PREP
  SHARED_DISKS.each { |name, gb| DISK_VARS[name] = create_shared_disk(name, gb, DISK_DIR) }
  NODES.each_key    { |n|   DISK_VARS["#{n}_swap"] = create_node_disk("#{n}-swap", SWAP_DISK_GB, DISK_DIR) }
end

# --------------------------------------------------------------------------
Vagrant.configure('2') do |config|
  config.vm.box              = 'oraclelinux/7'
  config.vm.box_url          = 'https://oracle.github.io/vagrant-projects/boxes/oraclelinux/7.json'
  config.vm.box_check_update = false

  # 50 GB root disk: /u01 (GI + DB homes + extracted media) lives on it.
  config.vm.disk :disk, size: '50GB', primary: true

  # The repo folder must NOT rsync GB-scale zips/VDIs into every guest.
  config.vm.synced_folder '.', '/vagrant', disabled: true

  # Installation media: read-only VirtualBox shared folder (no copying).
  config.vm.synced_folder 'staging', '/u01/staging',
    type: 'virtualbox', mount_options: %w[ro fmode=644 dmode=755 uid=0 gid=0]

  NODES.each do |node_name, node|
    # primary: plain `vagrant ssh`/status targets node1 (adopted from di's
    # WIP Vagrantfile, 2026-09). Node DEFINITION order stays rac1→rac2:
    # serial `vagrant up` boots node1 first, which owns ASM init.
    config.vm.define node_name, primary: (node_name == NODES.keys.first) do |cfg|
      cfg.vm.hostname = node[:fqdn]

      cfg.vm.network 'private_network', ip: node[:public_ip]
      cfg.vm.network 'private_network', ip: node[:private_ip],
                     virtualbox__intnet: INTNET_NAME

      ensure_clean_scsi_ctrl(cfg, node_name, ASM_CTRL)

      cfg.vm.provider 'virtualbox' do |vb|
        vb.name   = node_name
        vb.memory = node[:memory]
        vb.cpus   = node[:cpus]
        vb.customize ['modifyvm', :id, '--audio', 'none']
        vb.customize ['storagectl', :id, '--name', ASM_CTRL, '--add', 'sas',
                      '--portcount', '16', '--hostiocache', 'off']
        unless SKIP_DISK_PREP
          # Ports 0-2: shared ASM disks in identical order on both nodes.
          # Port 3: node-exclusive swap (mtype normal — VB7 forbids
          # shareable on dynamic media).
          attach_disk(vb, ASM_CTRL, 0, DISK_VARS['db11g_crs'])
          attach_disk(vb, ASM_CTRL, 1, DISK_VARS['db11g_data'])
          attach_disk(vb, ASM_CTRL, 2, DISK_VARS['db11g_fra'])
          attach_disk(vb, ASM_CTRL, 3, DISK_VARS["#{node_name}_swap"], 'normal')
        end
      end

      # Minimal guest prep so host-side Ansible can run. Bootstrap needs no
      # IPs (they come from Vagrant's network config); args are informational.
      cfg.vm.provision :shell,
        path: 'vagrant/scripts/bootstrap.sh',
        args: [node[:fqdn], node[:public_ip], node[:private_ip], node[:vip], SCAN_IP]

      # Swap disk re-armed every boot (idempotent, self-elevating).
      cfg.vm.provision :shell, path: 'vagrant/scripts/swap_setup.sh', run: 'always'
    end
  end

  config.vm.post_up_message = <<~MSG
    == db11g node up ==
    Oracle install is driven from the HOST, not by vagrant provision:
      cd ansible && source ../.venv-ansible/bin/activate
      ansible-playbook playbooks/01-configure-os.yml   # OS prep, both nodes
      ansible-playbook playbooks/02-configure-cluster.yml  # ASM disks/trust
      ansible-playbook playbooks/03-install-grid.yml   # GI install + root.sh + DGs
      ansible-playbook playbooks/04-install-db.yml     # RDBMS software + root.sh
      ansible-playbook playbooks/05-create-db.yml      # dbca (optional)
    Order matters. See README.md for details and idempotency notes.
  MSG
end
