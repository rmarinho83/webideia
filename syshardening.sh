#!/bin/bash

# === CONFIGURATION ===
CUSTOM_SSH_PORT=""  # Example: 2222 (leave blank to skip port change)
REMOTE_LOG_SERVER="192.168.1.100"
BANNER_TEXT="WARNING: Unauthorized access to this system is prohibited and will be prosecuted."

# === FUNCTION TO INSTALL PACKAGES ===
install_packages() {
    echo "Installing required packages..."
    if [ -f /etc/redhat-release ]; then
        # Red Hat-based
        yum install -y rkhunter || dnf install -y rkhunter
        #systemctl enable --now sshd
        #systemctl enable --now rsyslog
    elif [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt update
        DEBIAN_FRONTEND=noninteractive apt install -y rkhunter
        #systemctl enable --now ssh
        #systemctl enable --now rsyslog
    else
        echo "✘ Unsupported OS. Install packages manually."
        exit 1
    fi
    echo "✔ Package installation complete."
}

# === SSH CONFIGURATION HELPERS ===
set_ssh_config() {
    local key="$1"
    local value="$2"
    sed -i "/^\s*${key}\s\+/Id" /etc/ssh/sshd_config
    echo "${key} ${value}" >> /etc/ssh/sshd_config
}

check_ssh_config() {
    local key="$1"
    local expected="$2"
    local actual
    actual=$(grep -i "^${key}" /etc/ssh/sshd_config | awk '{print $2}')
    if [[ "$actual" == "$expected" ]]; then
        echo "✔ $key is set to $expected"
    else
        echo "✘ $key is not correctly set (found: $actual, expected: $expected)"
    fi
}

# === BEGIN SCRIPT ===
install_packages

# Backup sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%F_%T)
echo "✔ Backup of sshd_config created."

# SSH hardening
set_ssh_config AllowTcpForwarding NO
check_ssh_config AllowTcpForwarding NO

set_ssh_config ClientAliveCountMax 2
check_ssh_config ClientAliveCountMax 2

set_ssh_config LogLevel VERBOSE
check_ssh_config LogLevel VERBOSE

set_ssh_config MaxAuthTries 3
check_ssh_config MaxAuthTries 3

set_ssh_config MaxSessions 2
check_ssh_config MaxSessions 2

set_ssh_config PermitRootLogin prohibit-password
check_ssh_config PermitRootLogin prohibit-password

if [[ -n "$CUSTOM_SSH_PORT" ]]; then
    set_ssh_config Port "$CUSTOM_SSH_PORT"
    check_ssh_config Port "$CUSTOM_SSH_PORT"
else
    echo "✔ SSH Port left unchanged (currently: $(grep -i '^Port' /etc/ssh/sshd_config | awk '{print $2}'))"
fi

set_ssh_config TCPKeepAlive NO
check_ssh_config TCPKeepAlive NO

set_ssh_config X11Forwarding NO
check_ssh_config X11Forwarding NO

set_ssh_config AllowAgentForwarding NO
check_ssh_config AllowAgentForwarding NO

# Remote logging
if ! grep -q "@$REMOTE_LOG_SERVER" /etc/rsyslog.conf; then
    echo "*.* @$REMOTE_LOG_SERVER" >> /etc/rsyslog.conf
    systemctl restart rsyslog
    echo "✔ Remote logging configured to $REMOTE_LOG_SERVER"
else
    echo "✔ Remote logging already configured"
fi

# Set login banners
echo "$BANNER_TEXT" > /etc/issue
echo "$BANNER_TEXT" > /etc/issue.net

if grep -Fxq "$BANNER_TEXT" /etc/issue && grep -Fxq "$BANNER_TEXT" /etc/issue.net; then
    echo "✔ Login banners set"
else
    echo "✘ Failed to set login banners"
fi

# Restart SSH service
echo "Restarting SSH service..."
if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
    echo "✔ SSH restarted"
else
    echo "✘ Failed to restart SSH"
fi

echo "✅ Hardening complete."
