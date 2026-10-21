#!/bin/bash
# ============================================================
# bootstrap.sh — minimal EL7 guest prep so host-side Ansible works.
# Deliberately tiny: everything Oracle-related lives in ansible/
# so the playbooks are the single source of truth.
# (Rewritten for the oraclelinux/7 box — the previous version was
#  EL6-era: chkconfig/service/python2/EPEL6, none of which apply.)
# ============================================================
set -eux

FQDN=${1:-}
PUBLIC_IP=${2:-}
PRIVATE_IP=${3:-}
VIP=${4:-}
SCAN_IP=${5:-}

echo "=== bootstrap: ${FQDN:-?} pub=${PUBLIC_IP:-?} priv=${PRIVATE_IP:-?} vip=${VIP:-?} scan=${SCAN_IP:-?} ==="

# SELinux: fully disable at runtime + persistently (11.2 installer needs it
# off; the playbook re-verifies and reboots once if the box came up enforcing).
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

# Firewalld off (lab network).
systemctl disable --now firewalld 2>/dev/null || true

# python3 is the Ansible target interpreter (ansible-core 2.16 supports 3.6;
# NOTE: ansible-core >= 2.17 CANNOT manage these EL7 targets — see README).
if ! command -v python3 >/dev/null 2>&1; then
  yum install -y python3 yum-utils
fi

# NetworkManager off, classic network scripts on (Vagrant manages ifcfg-*).
systemctl disable --now NetworkManager 2>/dev/null || true
systemctl enable network 2>/dev/null || true

echo "=== bootstrap complete (ansible playbooks do the rest) ==="
