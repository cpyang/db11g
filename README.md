# Oracle Database 11gR2 RAC Testing Environment

> Automated two-node Oracle RAC cluster setup using Vagrant, VirtualBox, and Ansible.

## Overview

This project provisions a **2-node Oracle Database 11gR2 RAC (Real Application Clusters)** testing environment on your local machine. It uses:

- **Vagrant + VirtualBox** for VM provisioning
- **Ansible** for OS configuration and Oracle software installation
- **Silent installation** (response files) for unattended Oracle setup

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Host Machine                         │
│                                                         │
│  ┌──────────────┐    ┌──────────────┐                  │
│  │   Node 1     │    │   Node 2     │                  │
│  │  db11g-rac1  │    │  db11g-rac2  │                  │
│  │              │    │              │                  │
│  │ 192.168.56.11│    │ 192.168.56.12│                  │
│  │ 10.10.10.11  │    │ 10.10.10.12  │                  │
│  │ 192.168.56.1 │    │ 192.168.56.2 │                  │
│  └──────────────┘    └──────────────┘                  │
│         │                    │                          │
│         └────────┬───────────┘                          │
│                  │                                      │
│          Shared Storage (VirtualBox)                    │
│          ASM disks for clusterware + database           │
└─────────────────────────────────────────────────────────┘
```

### Node Naming Convention

| Component | Node 1 | Node 2 |
|-----------|--------|--------|
| Public IP | 192.168.56.11 | 192.168.56.12 |
| Private IP | 10.10.10.11 | 10.10.10.12 |
| Virtual IP | 192.168.56.101 | 192.168.56.102 |
| SCAN IP | 192.168.56.100 | (shared) |
| Scan Listener Port | 1521 | - |
| Oracle SID prefix | rac | rac1, rac2 |

### Storage Layout

| Disk | Size | Purpose |
|------|------|---------|
| `/dev/sdb` | 10 GB | Oracle Grid Infrastructure (OCR + Voting Disk) |
| `/dev/sdc` | 20 GB | ASM disk group for database files (DATA) |
| `/dev/sdd` | 10 GB | ASM disk group for flash recovery (FRA) |

## Prerequisites

### On Host Machine

| Software | Minimum Version | Purpose |
|----------|----------------|---------|
| [VirtualBox](https://www.virtualbox.org/) | 6.1+ | Hypervisor |
| Vagrant | 2.3+ | VM lifecycle management |
| Ansible | 2.9+ | Configuration management |
| Oracle Linux 6 ISO | - | Guest OS image (or CentOS 6) |
| Oracle 11gR2 software | - | Two zip files: `linux.x64_11gR2_database_1of2.zip`, `linux.x64_11gR2_database_2of2.zip` |

### Resource Requirements

| Resource | Per Node | Total |
|----------|----------|-------|
| CPU | 2 vCPUs | 4 vCPUs |
| RAM | 4 GB | 8 GB |
| Disk (OS) | 20 GB | 40 GB |
| Shared Disks | - | 40 GB |

> **Note:** Minimum system RAM should be 12 GB to run both nodes comfortably. 16 GB recommended.

## Quick Start

### 1. Clone this repository

```bash
git clone <repository-url>
cd oracle-rac-vagrant
```

### 2. Place Oracle installation files

```bash
# Download from Oracle Technology Network
# https://www.oracle.com/database/technologies/oracle11g-linux-downloads.html

mkdir -p packages
# Place these files in the packages directory:
#   - linux.x64_11gR2_database_1of2.zip
#   - linux.x64_11gR2_database_2of2.zip
```

### 3. Provision the cluster

```bash
# Bring up both nodes
vagrant up

# Or provision step by step
vagrant up db11g-rac1
vagrant up db11g-rac2
```

### 4. Verify the installation

```bash
# SSH into a node
vagrant ssh db11g-rac1

# Check Oracle processes
ps -ef | grep pmon

# Check ASM disks
su - grid
asmcmd lsdg

# Check listener status
lsnrctl status

# Check cluster status
crsctl check cluster
crsctl stat res -t
```

## Project Structure

```
oracle-rac-vagrant/
├── README.md                      # This file
├── Vagrantfile                    # VM definitions and provisioning
├── ansible/
│   ├── ansible.cfg                # Ansible configuration
│   ├── inventory/
│   │   ├── hosts                  # Inventory file
│   │   └── group_vars/
│   │       ├── all.yml            # Variables for all nodes
│   │       └── rac.yml            # Variables for RAC nodes
│   ├── playbooks/
│   │   ├── 01-configure-os.yml    # OS hardening and packages
│   │   ├── 02-configure-cluster.yml # Clusterware prerequisites
│   │   ├── 03-install-grid.yml    # Grid Infrastructure installation
│   │   └── 04-install-db.yml      # Database software installation
│   ├── roles/
│   │   ├── common/
│   │   │   ├── tasks/
│   │   │   │   └── main.yml
│   │   │   ├── templates/
│   │   │   │   ├── 99-oracle.yaml.j2
│   │   │   │   ├── limits.conf.j2
│   │   │   │   ├── oracle-params.j2
│   │   │   │   └── hosts.j2
│   │   │   └── handlers/
│   │   │       └── main.yml
│   │   ├── grid/
│   │   │   ├── tasks/
│   │   │   │   └── main.yml
│   │   │   └── templates/
│   │   │       └── grid.rsp.j2
│   │   └── database/
│   │       ├── tasks/
│   │       │   └── main.yml
│   │       └── templates/
│   │           └── db_install.rsp.j2
│   └── scripts/
│       ├── share-oracle.sh        # Share Oracle packages with VMs
│       └── setup-shared-disks.sh  # Prepare shared ASM disks
├── packages/                      # Oracle installation files
│   ├── linux.x64_11gR2_database_1of2.zip
│   └── linux.x64_11gR2_database_2of2.zip
└── vagrant/
    └── scripts/
        ├── bootstrap.sh           # Initial VM bootstrap
        └── ansible-provision.sh   # Ansible provisioning script
```

## What Gets Configured

### Operating System (Ansible)

- **User & groups**: `oracle`, `grid` with proper passwordless SSH
- **Kernel parameters**: `/etc/sysctl.conf` for Oracle requirements
- **Resource limits**: `/etc/security/limits.conf` for oracle/grid users
- **Packages**: gcc, make, binutils, compat-lib*, etc.
- **Directories**: `/u01`, `/u02` with proper ownership
- **Hosts file**: Static entries for all cluster nodes
- **Time synchronization**: NTP configuration

### Grid Infrastructure

- Oracle Grid Infrastructure 11gR2 installation
- ASM disk group configuration (DATA, FRA)
- OCR and Voting Disk setup
- Cluster verification

### Database Software

- Oracle Database 11gR2 software installation
- Oracle Net configuration (listener.ora, tnsnames.ora)

## Customization

### Change Node Resources

Edit the `Vagrantfile` and modify:

```ruby
config.vm.define "db11g-rac1" do |node|
  node.vm.provider "virtualbox" do |vb|
    vb.memory = "4096"    # Change this
    vb.cpus = 2            # Change this
  end
end
```

### Change Network

Modify the network configuration in `Vagrantfile`:

```ruby
config.vm.network "private_network", type: "dhcp"  # Use DHCP instead of static
```

### Add More Nodes

Duplicate the node definition in `Vagrantfile` and update the inventory file.

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Shared disks not visible | Ensure VirtualBox has permission to access host storage |
| Oracle install fails | Check `/u01/install_logs/` on each node |
| Cluster not starting | Run `crsctl stat res -t` and check logs in `/u01/app/grid/diag/` |
| SSH issues | Verify passwordless SSH is configured between nodes |
| Ansible connection fails | Check SSH connectivity: `vagrant ssh db11g-rac1` |

### Log Locations

| Component | Log Path |
|-----------|----------|
| Oracle install | `/u01/app/oraInventory/logs/` |
| Grid install | `/u01/app/grid/cfgtoollogs/` |
| Ansible | `ansible-playbook` output on host |
| VM bootstrap | `/var/log/vagrant-scripts.log` |

### Useful Commands Inside VMs

```bash
# Check cluster status
crsctl check cluster
crsctl stat res -t

# Check ASM
su - grid
asmcmd lsdg
asmcmd lsap

# Check listener
lsnrctl status
lsnrctl service

# Check database
sqlplus / as sysdba
SELECT name, open_mode FROM v$database;
SELECT inst_id, instance_name, status FROM gv$instance;

# Check ASM disks
ls -l /dev/oracleasm/disks/
```

## Cleanup

```bash
# Destroy the cluster
vagrant destroy -f

# Remove all data (including shared disks)
vagrant destroy --force
vboxmanage closemedium disk --delete <shared-disk-uuid>
```

## Security Notes

- This is a **testing/lab environment** only
- No firewall is configured (for ease of setup)
- Default Oracle passwords are used (change for production!)
- Shared disks are stored on the host filesystem

## License

This project is provided as-is for educational and testing purposes.

## References

- [Oracle Database 11gR2 Installation Guide](https://docs.oracle.com/cd/E11882_01/install.112/e47689/toc.htm)
- [Oracle RAC Documentation](https://docs.oracle.com/cd/E11882_01/rac.112/e41961/toc.htm)
- [Vagrant Documentation](https://www.vagrantup.com/docs)
- [Ansible Documentation](https://docs.ansible.com/)
