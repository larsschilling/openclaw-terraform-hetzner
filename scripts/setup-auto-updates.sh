#!/bin/bash
# =============================================================================
# Manual Auto-Updates Setup for Existing VPS
# =============================================================================
# Purpose: Enable automated security updates on existing VPS
# Usage: ./scripts/setup-auto-updates.sh [VPS_IP]
#
# This script can be run on existing VPS to enable automated security updates
# without affecting other configurations. It's idempotent and safe to run multiple times.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

VPS_USER="openclaw"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"

# Terraform directory (optional)
TERRAFORM_DIR="infra/terraform/envs/prod"

# -----------------------------------------------------------------------------
# Get VPS IP
# -----------------------------------------------------------------------------

if [[ -n "${1:-}" ]]; then
    VPS_IP="$1"
else
    # Try to get IP from tofu output (optional)
    if command -v tofu &> /dev/null && [[ -d "$TERRAFORM_DIR/.terraform" ]]; then
        VPS_IP=$(cd "$TERRAFORM_DIR" && tofu output -raw server_ip 2>/dev/null) || {
            echo "Error: Could not get VPS IP from tofu output."
            echo "Usage: $0 <VPS_IP>"
            exit 1
        }
    else
        echo "Error: No VPS IP provided."
        echo "Usage: $0 <VPS_IP>"
        exit 1
    fi
fi

echo "=== Setting up Automated Security Updates ==="
echo "VPS IP: $VPS_IP"
echo ""

# -----------------------------------------------------------------------------
# Verify SSH connectivity
# -----------------------------------------------------------------------------

echo "Verifying SSH connectivity..."
if ! ssh $SSH_OPTS "$VPS_USER@$VPS_IP" "echo 'SSH connection successful'" 2>/dev/null; then
    echo "Error: Cannot connect to $VPS_USER@$VPS_IP"
    echo "Make sure:"
    echo "  1. The VPS is running"
    echo "  2. Your SSH key is correct"
    exit 1
fi

# -----------------------------------------------------------------------------
# Execute setup on VPS
# -----------------------------------------------------------------------------

echo "Setting up automated security updates..."
ssh $SSH_OPTS "$VPS_USER@$VPS_IP" sudo bash -s << 'REMOTE_SCRIPT'
set -euo pipefail

echo "=== Automated Security Updates Setup (Manual) ==="
echo ""

# Update package list
echo "Updating package list..."
apt-get update

# Install packages
echo "Installing unattended-upgrades..."
apt-get install -y unattended-upgrades apt-listchanges

# Configure unattended-upgrades
echo "Configuring unattended-upgrades..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
// Only allow security updates
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Enable automatic reboot after 02:00 AM
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Disable email notifications
Unattended-Upgrade::Mail "";

// Enable verbose logging
Unattended-Upgrade::Verbose "true";

// Remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Remove unused kernel packages
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Clean up downloaded packages
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
EOF

# Configure periodic updates
echo "Configuring periodic updates..."
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::RandomizedDelaySec "900";
EOF

# Create systemd timer if it doesn't exist
echo "Adjusting systemd timer..."
if ! systemctl list-unit-files | grep -q unattended-upgrades.timer; then
    echo "Creating unattended-upgrades.timer..."
    cat > /etc/systemd/system/unattended-upgrades.timer << 'EOF'
[Unit]
Description=Unattended Upgrades Timer

[Timer]
OnCalendar=*-*-* 01:30:00
RandomizedDelaySec=900
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
fi

# Create override directory
mkdir -p /etc/systemd/system/unattended-upgrades.timer.d

# Create timer override to run at 01:30 AM
cat > /etc/systemd/system/unattended-upgrades.timer.d/override.conf << 'EOF'
[Timer]
OnCalendar=*-*-* 01:30:00
RandomizedDelaySec=900
Persistent=true
EOF

# Reload systemd
systemctl daemon-reload

# Enable and start services
echo "Enabling services..."
systemctl enable unattended-upgrades
systemctl start unattended-upgrades

# Enable and start timer if it exists
if systemctl list-unit-files | grep -q unattended-upgrades.timer; then
    systemctl enable unattended-upgrades.timer
    systemctl start unattended-upgrades.timer
    echo "[OK] unattended-upgrades timer enabled and started"
else
    echo "[WARN] unattended-upgrades.timer not found, skipping"
fi

# Create log directory
mkdir -p /var/log/unattended-upgrades
chown root:root /var/log/unattended-upgrades
chmod 755 /var/log/unattended-upgrades

# Verify
echo ""
echo "Verifying setup..."
if systemctl is-active unattended-upgrades.timer >/dev/null 2>&1; then
    echo "[OK] unattended-upgrades timer is active"
else
    echo "[WARN] unattended-upgrades timer is not active"
fi

echo ""
echo "Next timer run:"
systemctl list-timers unattended-upgrades.timer --no-pager

echo ""
echo "Testing dry-run..."
if command -v unattended-upgrades >/dev/null 2>&1; then
    echo "Dry-run output (first few lines):"
    unattended-upgrades --dry-run 2>&1 | head -10
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Automated security updates are configured:"
echo "  - Updates: Security-only packages"
echo "  - Schedule: Daily at 01:30 AM (with random delay)"
echo "  - Reboot: After 02:00 AM if required"
echo "  - Logs: /var/log/unattended-upgrades/"
echo ""
echo "To monitor logs:"
echo "  sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log"
echo ""
echo "To stop temporarily:"
echo "  sudo systemctl stop unattended-upgrades.timer"
echo ""
REMOTE_SCRIPT

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "=== Manual Setup Complete ==="
echo ""
echo "Automated security updates have been configured on $VPS_IP"
echo ""
echo "Next steps:"
echo "  1. Check logs: ssh $VPS_USER@$VPS_IP 'sudo tail -20 /var/log/unattended-upgrades/unattended-upgrades.log'"
echo "  2. Verify timer: ssh $VPS_USER@$VPS_IP 'systemctl list-timers unattended-upgrades.timer'"
echo ""
