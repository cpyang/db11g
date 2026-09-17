#!/bin/bash
# ============================================================
# Script: ansible-provision.sh
# Purpose: Generate SSH config from vagrant ssh-config and run
#          Ansible playbook with the generated config
# ============================================================

set -e

NODE_NAME="${1:-}"
SSH_CONFIG="/tmp/vagrant-ssh-config"
PLAYBOOK_DIR="/home/cpyang/src/db11g/ansible/playbooks"
INVENTORY="/home/cpyang/src/db11g/ansible/inventory/hosts"
PLAYBOOK="01-configure-os.yml"

echo "==> Generating SSH config for ${NODE_NAME}..."

# Generate SSH config using vagrant ssh-config
vagrant ssh-config > "${SSH_CONFIG}" 2>/dev/null

if [ ! -f "${SSH_CONFIG}" ]; then
    echo "ERROR: Failed to generate SSH config"
    exit 1
fi

echo "==> SSH config generated at ${SSH_CONFIG}"

# Run Ansible with the generated SSH config
echo "==> Running Ansible playbook..."
ANSIBLE_SSH_ARGS="-F ${SSH_CONFIG}" ansible-playbook \
    --connection=ssh \
    --timeout=30 \
    --extra-vars="ansible_user=vagrant" \
    --limit="all" \
    -i "${INVENTORY}" \
    -v \
    "${PLAYBOOK_DIR}/${PLAYBOOK}"

# Cleanup
rm -f "${SSH_CONFIG}"

echo "==> Ansible provisioning complete"
