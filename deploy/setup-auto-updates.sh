#!/bin/bash
# =============================================================================
# Automated Security Updates Setup
# =============================================================================
# Purpose: Install and configure unattended-upgrades for automatic security updates
# Usage: ./deploy/setup-auto-updates.sh [VPS_IP]
#
# Features:
#   - Installs unattended-upgrades and dependencies
#   - Configures security-only updates
#   - Sets automatic reboot after 02:00 AM
#   - Configures systemd timer for 01:30 AM
#   - Idempotent (can be run multiple times)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

VPS_USER="openclaw"
SSH_OPTS="-o StrictHostKeyChecking=accept-new"

# Terraform directory (relative to repo root)
TERRAFORM_DIR="infra/terraform/envs/prod"

# -----------------------------------------------------------------------------
# Get VPS IP
# -----------------------------------------------------------------------------

if [[ -n "${1:-}" ]]; then
    VPS_IP="$1"
else
    # Try to get IP from tofu output
    if command -v tofu &> /dev/null && [[ -d "$TERRAFORM_DIR/.terraform" ]]; then
        VPS_IP=$(cd "$TERRAFORM_DIR" && tofu output -raw server_ip 2>/dev/null) || {
            echo "Error: Could not get VPS IP from tofu output."
            echo "Usage: $0 <VPS_IP>"
            exit 1
        }
    else
        echo "Error: No VPS IP provided and tofu not available."
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
    exit 1
fi

# -----------------------------------------------------------------------------
# Install packages
# -----------------------------------------------------------------------------

echo ""
echo "Installing required packages..."
ssh $SSH_OPTS "$VPS_USER@$VPS_IP" sudo bash -s << 'REMOTE_SCRIPT'
set -euo pipefail

# Update package list
apt-get update

# Install unattended-upgrades and dependencies
apt-get install -y unattended-upgrades apt-listchanges

echo "[OK] Packages installed"
REMOTE_SCRIPT

# -----------------------------------------------------------------------------
# Configure unattended-upgrades
# -----------------------------------------------------------------------------

echo ""
echo "Configuring unattended-upgrades..."
ssh $SSH_OPTS "$VPS_USER@$VPS_IP" sudo bash -s << 'REMOTE_SCRIPT'
set -euo pipefail

# Create main configuration
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

echo "[OK] unattended-upgrades configured"
REMOTE_SCRIPT

# -----------------------------------------------------------------------------
# Configure auto-upgrades
# -----------------------------------------------------------------------------

echo ""
echo "Configuring auto-upgrades..."
ssh $SSH_OPTS "$VPS_USER@$VPS_IP" sudo bash -s << 'REMOTE_SCRIPT'
set -euo pipefail

# Enable periodic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::RandomizedDelaySec "900";
EOF

echo "[OK] Auto-upgrades periodic configuration set"
REMOTE_SCRIPT

# -----------------------------------------------------------------------------
# Adjust systemd timer
# -----------------------------------------------------------------------------

echo ""
echo "Adjusting systemd timer..."
ssh $SSH_OPTS "$VPS_USER@$VPS_IP" sudo bash -s << 'REMOTE_SCRIPT'
set -euo pipefail

# Create override directory
mkdir -p /etc/systemd/system/unattended-upgrades.service.d

# Create timer override to run at 01:30 AM
cat > /etc/systemd/system/unattended-upgrades.timer.d/override.conf << 'EOF'
[Timer]
OnCalendar=*-*-* 01:30:00
RandomizedDelaySec=900
Persistent=true
EOF

# Reload systemd
systemctl daemon-reload

echo "[OK] Systemd timer adjusted for 01:30 AM"
REMOTE_SCRIPT

# -----------------------------------------------------------------------------
# Enable and verify
# -----------------------------------------------------------------------------

echo ""
echo "Enabling and verifying services..."
ssh $SSH_OPTS "$VPS_USER@$VPS_IP" sudo bash -s << 'REMOTE_SCRIPT'
set -euo pipefail

# Enable and start services
systemctl enable unattended-upgrades
systemctl start unattended-upgrades
systemctl enable unattended-upgrades.timer
systemctl start unattended-upgrades.timer

# Verify timer is active
if systemctl is-active unattended-upgrades.timer >/dev/null 2>&1; then
    echo "[OK] unattended-upgrades timer is active"
else
    echo "[WARN] unattended-upgrades timer is not active"
fi

# Show next timer run
echo "Next timer run:"
systemctl list-timers unattended-upgrades.timer --no-pager

# Test dry-run
echo ""
echo "Testing unattended-upgrades dry-run..."
if unattended-upgrades --dry-run 2>&1 | grep -q "No packages have been kept back"; then
    echo "[OK] Dry-run successful"
else
    echo "[INFO] Dry-run completed (may show updates available)"
fi

echo "[OK] Automated security updates are configured"
REMOTE_SCRIPT

# -----------------------------------------------------------------------------
# Create log directory if needed
# -----------------------------------------------------------------------------

echo ""
echo "Ensuring log directory exists..."
ssh $SSH_OPTS "$VPS_USER@$VPS_IP" sudo bash -s << 'REMOTE_SCRIPT'
set -euo pipefail

# Create log directory
mkdir -p /var/log/unattended-upgrades
chown root:root /var/log/unattended-upgrades
chmod 755 /var/log/unattended-upgrades

echo "[OK] Log directory created at /var/log/unattended-upgrades"
REMOTE_SCRIPT

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Automated security updates are now configured:"
echo "  - Updates: Security-only packages"
echo "  - Schedule: Daily at 01:30 AM (with 15 min random delay)"
echo "  - Reboot: After 02:00 AM if required"
echo "  - Logs: /var/log/unattended-upgrades/"
echo ""
echo "To check status:"
echo "  ssh $VPS_USER@$VPS_IP 'sudo systemctl status unattended-upgrades'"
echo "  ssh $VPS_USER@$VPS_IP 'sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log'"
echo ""
echo "To stop temporarily:"
echo "  ssh $VPS_USER@$VPS_IP 'sudo systemctl stop unattended-upgrades.timer'"
echo ""
