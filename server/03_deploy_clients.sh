#!/usr/bin/env bash
echo Deploying clients...
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config.env"

if [ "$ACCOUNT_KEY" = "PASTE_ACCOUNT_KEY_HERE" ]; then
  echo "ERROR: Set ACCOUNT_KEY in config.env first."
  exit 1
fi

echo "[1/2] Updating Ansible variables from config.env..."

cat > "$ROOT_DIR/ansible/install_boinc_clients.generated.yml" <<EOF
- name: Install and configure BOINC clients
  hosts: boinc_clients
  become: true

  vars:
    project_url: "$PROJECT_URL"
    account_key: "$ACCOUNT_KEY"

  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes

    - name: Install BOINC client
      apt:
        name: "$BOINC_CLIENT_PACKAGE"
        state: present

    - name: Enable BOINC client service
      systemd:
        name: boinc-client
        enabled: yes
        state: started

    - name: Attach BOINC client to project
      command: boinccmd --project_attach {{ project_url }} {{ account_key }}
      become: true
      become_user: boinc
      register: attach_result
      failed_when: false
      changed_when: "'already attached' not in attach_result.stdout"

    - name: Show attach result
      debug:
        var: attach_result.stdout
EOF

echo "[2/2] Running Ansible..."
ansible-playbook \
  -i "$ROOT_DIR/ansible/inventory.ini" \
  "$ROOT_DIR/ansible/install_boinc_clients.generated.yml"

echo "Client deployment finished."