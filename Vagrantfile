# -*- mode: ruby -*-
# vi: set ft=ruby :

# Oracle 11gR2 RAC - Vagrant Configuration
# Two-node RAC cluster with shared storage

Vagrant.require_version ">= 2.2.0"

# Network configuration
NETWORK = "192.168.56"
PRIVATE_NETWORK = "10.10.10"

# Node definitions
NODES = {
  "db11g-rac1" => {
    hostname: "db11g-rac1",
    public_ip: "#{NETWORK}.11",
    private_ip: "#{PRIVATE_NETWORK}.11",
    vip: "#{NETWORK}.101",
    scan_ip: "#{NETWORK}.100",
    memory: 4096,
    cpus: 2,
    sid_prefix: "rac",
    oracle_home: "/u01/app/oracle/product/11.2.0/dbhome_1",
    grid_home: "/u01/app/11.2.0/grid",
  },
  "db11g-rac2" => {
    hostname: "db11g-rac2",
    public_ip: "#{NETWORK}.12",
    private_ip: "#{PRIVATE_NETWORK}.12",
    vip: "#{NETWORK}.102",
    scan_ip: "#{NETWORK}.100",
    memory: 4096,
    cpus: 2,
    sid_prefix: "rac",
    oracle_home: "/u01/app/oracle/product/11.2.0/dbhome_1",
    grid_home: "/u01/app/11.2.0/grid",
  }
}

Vagrant.configure("2") do |config|
  # Use official Oracle Linux 7 box
  config.vm.box = "oraclelinux/7"
  config.vm.box_url = "https://oracle.github.io/vagrant-projects/boxes/oraclelinux/7.json"

  # Disable automatic box version checking
  config.vm.box_check_update = false

  # Configure shared disks (dynamically allocated VMDKs)
  DISK_PATH = File.join(__dir__, "disks")
  DISK_SIZES = {
    "ocr.vdi" => 10 * 1024,       # 10 GB for OCR + Voting Disk
    "data.vdi" => 20 * 1024,      # 20 GB for DATA
    "fra.vdi" => 10 * 1024        # 10 GB for FRA
  }

  # Create shared disks
  DISK_SIZES.each do |disk_name, size_mb|
    disk_path = File.join(DISK_PATH, disk_name)
    unless File.exist?(disk_path)
      system("VBoxManage createmedium disk --filename #{disk_path} --size #{size_mb} --format VDI")
    end
  end

  NODES.each do |node_name, node|
    config.vm.define node_name do |node_config|
      node_config.vm.hostname = node[:hostname]

      # Base box settings
      node_config.vm.provider "virtualbox" do |vb|
        vb.name = node[:hostname]
        vb.memory = node[:memory]
        vb.cpus = node[:cpus]
        vb.customize ["modifyvm", :id, "--nictype1", "Am79C973"]  # 82540EM for host-only
        vb.customize ["modifyvm", :id, "--nictype2", "Am79C973"]  # 82540EM for private
        vb.customize ["modifyvm", :id, "--audio", "none"]
        vb.customize ["modifyvm", :id, "--clipboard", "bidirectional"]
        vb.customize ["modifyvm", :id, "--draganddrop", "disabled"]
      end

      # Host-only network (public)
      node_config.vm.network "private_network", ip: node[:public_ip]

      # Private cluster network
      node_config.vm.network "private_network", ip: node[:private_ip]

      # Bootstrap provisioner (initial setup before Ansible)
      node_config.vm.provision :shell, 
        path: "vagrant/scripts/bootstrap.sh",
        privileged: true,
        args: [node[:hostname], node[:public_ip], node[:private_ip], node[:vip], node[:scan_ip]]
    end
  end
end
