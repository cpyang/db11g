#!/bin/bash
# Bootstrap script for Oracle 11gR2 RAC nodes
# This runs before Ansible provisioning

set -e

HOSTNAME=$1
PUBLIC_IP=$2
PRIVATE_IP=$3
VIP=$4
SCAN_IP=$5

echo "=== Bootstrap: Configuring ${HOSTNAME} ==="
echo "Public IP: ${PUBLIC_IP}"
echo "Private IP: ${PRIVATE_IP}"
echo "VIP: ${VIP}"
echo "SCAN IP: ${SCAN_IP}"

# Disable SELinux
echo "Disabling SELinux..."
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
sed -i 's/^SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
setenforce 0 2>/dev/null || true

# Disable firewall
echo "Disabling iptables..."
service iptables stop 2>/dev/null || true
chkconfig iptables off 2>/dev/null || true
yum install -y iptables-services 2>/dev/null || true

# Disable firewall6
service ip6tables stop 2>/dev/null || true
chkconfig ip6tables off 2>/dev/null || true

# Disable NetworkManager (use network service instead)
echo "Configuring network service..."
chkconfig NetworkManager off 2>/dev/null || true
service NetworkManager stop 2>/dev/null || true
chkconfig network on
service network start 2>/dev/null || true

# Install EPEL repository
echo "Installing EPEL repository..."
yum install -y epel-release 2>/dev/null || yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm 2>/dev/null || true

# Update system
echo "Updating system packages..."
yum update -y --exclude=kernel* 2>/dev/null || true

# Install required packages for Ansible
echo "Installing Ansible prerequisites..."
yum install -y python2 python2-pip 2>/dev/null || true

# Configure NTP
echo "Configuring NTP..."
yum install -y ntp
chkconfig ntpd on
service ntpd start 2>/dev/null || true

# Create required directories
echo "Creating required directories..."
mkdir -p /u01/{app,install_packages,install_logs}
mkdir -p /u01/app/oracle
mkdir -p /u01/app/oraInventory

# Set proper permissions (will be finalized by Ansible)
chmod -R 775 /u01

echo "=== Bootstrap complete for ${HOSTNAME} ==="
