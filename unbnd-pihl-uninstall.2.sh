#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Check for appropriate elevated privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or use sudo."
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "Uninstalling Pi-hole..."

# Uninstall Pi-hole
if command_exists pihole; then
    pihole uninstall
else
    echo "Pi-hole is not installed."
fi

# Stop and disable Unbound
echo "Stopping and disabling Unbound..."
if command_exists systemctl; then
    systemctl stop unbound || echo "Unbound is not running."
    systemctl disable unbound || echo "Unbound is not enabled."
else
    echo "Systemd is not available, skipping service management."
fi

# Uninstall Unbound
echo "Uninstalling Unbound..."
apt purge -y unbound unbound-host

# Remove Pi-hole package
echo "Removing Pi-hole package..."
apt purge -y pi-hole

# Remove any unused dependencies
echo "Removing unused dependencies..."
apt autoremove -y

# Cleanup configuration files
echo "Cleaning up configuration files..."
rm -rf /etc/unbound
rm -rf /etc/pihole

# Remove update script
echo "Removing the update script..."
rm -f /usr/local/bin/update_pihole

# Optionally remove resolvconf configuration changes if applicable
if [ -f /etc/resolvconf.conf ]; then
    echo "Restoring /etc/resolvconf.conf..."
    sudo sed -Ei 's/^#unbound_conf=/#unbound_conf=/' /etc/resolvconf.conf
fi

# Confirm completion
echo "Uninstallation complete. The system has been returned to its previous state."
