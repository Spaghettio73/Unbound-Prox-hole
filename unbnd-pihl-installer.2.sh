#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Check for appropriate elevated privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or use sudo."
    exit 1
fi

# Update the system
echo "Updating system packages..."
apt update && apt upgrade -y

# Install necessary dependencies
echo "Installing dependencies..."
apt install -y curl unbound unbound-host

# Check if the system is Debian Bullseye or later
if [ "$(lsb_release -cs)" = "bullseye" ] || [ "$(lsb_release -cs)" = "bookworm" ]; then
    echo "Detected Debian Bullseye or later. Configuring resolvconf settings..."

    # Disable resolvconf.conf entry for unbound
    if systemctl is-active unbound-resolvconf.service >/dev/null 2>&1; then
        echo "Disabling unbound-resolvconf.service..."
        sudo systemctl disable --now unbound-resolvconf.service
    else
        echo "unbound-resolvconf.service is not active or not installed."
    fi

    # Disable resolvconf_resolvers.conf from being generated
    echo "Modifying /etc/resolvconf.conf to disable unbound_conf..."
    sudo sed -Ei 's/^unbound_conf=/#unbound_conf=/' /etc/resolvconf.conf
    echo "Removing /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf..."
    sudo rm -f /etc/unbound/unbound.conf.d/resolvconf_resolvers.conf
else
    echo "This is not Debian Bullseye or later. Skipping resolvconf configuration."
fi

# Install Pi-hole
echo "Installing Pi-hole..."
curl -sSL https://install.pi-hole.net | bash

# Configure Unbound for recursive DNS resolution
echo "Configuring Unbound..."
cat <<EOF > /etc/unbound/unbound.conf.d/pi-hole.conf
server:
    # If no logfile is specified, syslog is used
    # logfile: "/var/log/unbound/unbound.log"
    verbosity: 0

    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    # May need to adjust access-control if not default local-only
    access-control: 127.0.0.0/8 allow

    # Perform DNSSEC validation
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    
    # May be set to yes if you have IPv6 connectivity
    do-ip6: no

    # You want to leave this to no unless you have *native* IPv6. With 6to4 and
    # Terredo tunnels your web browser should favor IPv4 for the same reasons
    prefer-ip6: no

    # Use this only when you downloaded the list of primary root servers!
    # If you use the default dns-root-data package, unbound will find it automatically
    #root-hints: "/var/lib/unbound/root.hints"

    # Trust glue only if it is within the server's authority
    harden-glue: yes

    # Require DNSSEC data for trust-anchored zones, if such data is absent, the zone becomes BOGUS
    harden-dnssec-stripped: yes

    # Don't use Capitalization randomization as it known to cause DNSSEC issues sometimes
    # see https://discourse.pi-hole.net/t/unbound-stubby-or-dnscrypt-proxy/9378 for further details
    use-caps-for-id: no

    # Reduce EDNS reassembly buffer size.
    edns-buffer-size: 1232

    # Perform prefetching of close to expired message cache entries
    prefetch: yes

    # One thread should be sufficient, can be increased on beefy machines.
    num-threads: 1

    # Ensure kernel buffer is large enough to not lose messages in traffic spikes
    so-rcvbuf: 1m

    # Minimize any data leakage by using minimal responses
    minimal-responses: yes
    # Cache settings
    cache-min-ttl: 3600
    cache-max-ttl: 86400

    # Ensure privacy of local IP ranges
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
EOF

# Update Pi-hole's DNS server to use Unbound
echo "Setting DNS server to use Unbound in /etc/pihole/setupVars.conf..."
sudo sed -i 's/^PIHOLE_DNS_1=.*/PIHOLE_DNS_1="127.0.0.1#5335"/' /etc/pihole/setupVars.conf
sudo sed -i 's/^PIHOLE_DNS_2=.*/PIHOLE_DNS_2="127.0.0.1#5335"/' /etc/pihole/setupVars.conf

# Start and enable Unbound
echo "Starting and enabling Unbound..."
systemctl enable unbound
systemctl start unbound

# Test validation
echo "Testing validation..."
dig pi-hole.net @127.0.0.1 -p 5335

# Restart Pi-hole to apply changes
echo "Restarting Pi-hole..."
pihole restartdns

# Script for updating Pi-hole
echo "Creating a script for updating Pi-hole..."
cat <<EOF > /usr/local/bin/update_pihole
#!/bin/bash
# Update Pi-hole
pihole -up
# Update system packages
apt update && apt upgrade -y
EOF

# Make the update script executable
chmod +x /usr/local/bin/update_pihole

echo "Setup complete. You can use 'update_pihole' to update Pi-hole and your system in the future."
