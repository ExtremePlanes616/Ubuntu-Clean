#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== 1. Purging Unwanted Packages & Telemetry ==="
apt-get purge -y ubuntu-pro-client ubuntu-advantage-tools ubuntu-report popularity-contest apport whoopsie snapd landscape-client-ui-install landscape-common totem totem-common totem-plugins zeitgeist-core zeitgeist-datahub || true
rm -f /etc/apt/apt.conf.d/20apt-esm-hook.conf
rm -f /var/lib/ubuntu-advantage/messages/*
rm -rf /root/snap /var/snap /var/lib/snapd /var/cache/snapd

# Pin snapd against reinstallation
cat <<EOF > /etc/apt/preferences.d/nosnap.pref
Package: snapd
Pin: release a=*
Pin-Priority: -10
EOF

echo "=== 2. Purging Desktop & Installing LXQt + SDDM ==="
apt-get purge -y gnome-shell gdm3 ubuntu-desktop generic-resources gnome-session || true
apt-get autoremove --purge -y
apt-get update
add-apt-repository -y universe
apt-get install -y lxqt sddm network-manager-gnome

echo "sddm shared/default-x-display-manager select sddm" | debconf-set-selections
dpkg-reconfigure -f noninteractive sddm

echo "=== 3. Configuring User Skeleton & GTK Dark Theme ==="
mkdir -p /etc/skel/.config/lxqt
mkdir -p /etc/skel/.config/pcmanfm-qt/default/
mkdir -p /etc/skel/.config/mpv
mkdir -p /etc/gtk-3.0

cat <<EOF > /etc/skel/.config/lxqt/panel.conf
[General]
plugins=mainmenu, quicklaunch, taskbar, spacer, statusnotifier, volume, clock
position=Bottom
alignment=Left

[mainmenu]
icon=/usr/share/icons/hicolor/scalable/apps/steam.svg
EOF

cat <<EOF > /etc/gtk-3.0/settings.ini
[Settings]
gtk-theme-name = Adwaita-dark
gtk-icon-theme-name = Breeze-Dark
gtk-application-prefer-dark-theme = true
EOF

echo "=== 4. Adding Mozilla Official Repository for Firefox ESR ==="
install -d -m 0755 /etc/apt/keyrings
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" > /etc/apt/sources.list.d/mozilla.list

cat <<EOF > /etc/apt/preferences.d/mozilla
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

apt-get update

echo "=== 5. Installing Core Utilities, Media Tools, qBittorrent & Firefox ESR ==="
apt-get install -y wget curl jq bzip2 ffmpeg python3 mpv keepassxc flatpak tor redsocks iptables firefox-esr qbittorrent \
    libunwind8 libssl-dev libxcb-xinerama0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-shape0

# mpv Hardened Configuration
cat <<EOF > /etc/skel/.config/mpv/mpv.conf
hwdec=auto
sub-ass-override=force
osc=no
scripts=no
EOF

cat <<EOF > /etc/skel/.config/mimeapps.list
[Default Applications]
video/mp4=mpv.desktop;
video/x-matroska=mpv.desktop;
video/x-msvideo=mpv.desktop;
video/quicktime=mpv.desktop;
video/webm=mpv.desktop;
audio/mpeg=mpv.desktop;
audio/ogg=mpv.desktop;
EOF

echo "=== 6. Installing Wireshark non-interactively ==="
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections
apt-get install -y wireshark tshark
groupadd -f wireshark
chown root:wireshark /usr/bin/dumpcap
chmod 750 /usr/bin/dumpcap
setcap cap_net_raw,cap_net_admin=eip /usr/bin/dumpcap

echo "=== 7. Installing Virtualization (Virt-Manager) ==="
apt-get install -y virt-manager qemu-desktop qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
groupadd -f libvirt
groupadd -f kvm

echo "=== 8. Installing Jackett ==="
JACKETT_URL=$(curl -s "https://api.github.com/repos/Jackett/Jackett/releases/latest" | \
      jq -r '.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url' | head -n 1)

if [ -n "$JACKETT_URL" ] && [ "$JACKETT_URL" != "null" ]; then
    echo "Downloading Jackett from: $JACKETT_URL"
    wget -q "$JACKETT_URL" -O /tmp/jackett.tar.gz
    mkdir -p /opt/jackett
    tar -xzf /tmp/jackett.tar.gz -C /opt/jackett --strip-components=1
    rm /tmp/jackett.tar.gz
else
    echo "Warning: Could not locate a valid release asset for Jackett."
fi

cat <<EOF > /etc/systemd/system/jackett.service
[Unit]
Description=Jackett Indexer Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/jackett/jackett --no-restart
TimeoutStopSec=5
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl enable jackett || true

echo "=== 9. Downloading & Installing Tor Browser ==="
TOR_VERSION=$(curl -s https://aus1.torproject.org/torbrowser/update_3/release/downloads.json | jq -r '.version' || echo "13.0.9")
TOR_TAR="tor-browser-linux-x86_64-${TOR_VERSION}.tar.xz"
TOR_URL="https://dist.torproject.org/torbrowser/${TOR_VERSION}/${TOR_TAR}"

wget -q "$TOR_URL" -O /tmp/tor-browser.tar.xz
if [ -s /tmp/tor-browser.tar.xz ]; then
    tar -xvJf /tmp/tor-browser.tar.xz -C /opt/
    rm /tmp/tor-browser.tar.xz
    if [ -d /opt/tor-browser ]; then
        cd /opt/tor-browser
        ./start-tor-browser.desktop --register-app || true
    fi
else
    echo "Warning: Tor Browser download failed, skipping installation."
fi

echo "=== 10. Downloading & Installing Hydra Launcher ==="
HYDRA_URL=$(curl -s "https://api.github.com/repos/hydralauncher/hydra/releases/latest" | \
      jq -r '.assets[] | select(.name | endswith(".deb")) | .browser_download_url' | head -n 1)

if [ -n "$HYDRA_URL" ] && [ "$HYDRA_URL" != "null" ]; then
    echo "Downloading Hydra Launcher from: $HYDRA_URL"
    wget -q "$HYDRA_URL" -O /tmp/hydra.deb
    apt-get install -y /tmp/hydra.deb
    rm /tmp/hydra.deb
else
    echo "Warning: Could not locate a valid .deb asset for Hydra Launcher."
fi

echo "=== 11. Configuring Flatpak ==="
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

cat <<EOF >> /etc/environment
XDG_DATA_DIRS="/var/lib/flatpak/exports/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
all_proxy="socks5h://127.0.0.1:9050"
ALL_PROXY="socks5h://127.0.0.1:9050"
EOF

mkdir -p /etc/flatpak/overrides
cat <<EOF > /etc/flatpak/overrides/global
[Context]
shared=network

[Environment]
http_proxy=socks5h://127.0.0.1:9050
https_proxy=socks5h://127.0.0.1:9050
EOF

echo "=== 12. Configuring System-wide Proxy, DNS, & Native Systemd Routing Services ==="

cat <<EOF > /etc/redsocks.conf
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 0.0.0.0;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 9050;
    type = socks5;
}
EOF

cat <<EOF >> /etc/tor/torrc
DNSPort 127.0.0.1:5353
EOF

# Create setup routing script executed by systemd
cat <<EOF > /usr/local/bin/setup-tor-routing.sh
#!/bin/sh
systemctl restart redsocks || true

# Initialize Libvirt network bridges
systemctl enable --now libvirtd || true
virsh net-autostart default || true
virsh net-start default || true

# Create unique iptables chain for Virt-Manager traffic isolation
iptables -t nat -N REDSOCKS_VM || true
iptables -t nat -F REDSOCKS_VM

iptables -t nat -A REDSOCKS_VM -d 127.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS_VM -d 192.168.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS_VM -d 10.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS_VM -d 172.16.0.0/12 -j RETURN

iptables -t nat -A PREROUTING -i virbr0 -p tcp --dport 80 -j REDSOCKS_VM
iptables -t nat -A PREROUTING -i virbr0 -p tcp --dport 443 -j REDSOCKS_VM
iptables -t nat -A REDSOCKS_VM -p tcp -j REDIRECT --to-ports 12345
EOF

chmod +x /usr/local/bin/setup-tor-routing.sh

# Create teardown script
cat <<EOF > /usr/local/bin/teardown-tor-routing.sh
#!/bin/sh
iptables -t nat -F REDSOCKS_VM || true
iptables -t nat -X REDSOCKS_VM || true
EOF

chmod +x /usr/local/bin/teardown-tor-routing.sh

# Register native systemd service for Tor routing/redsocks/libvirt initialization
cat <<EOF > /etc/systemd/system/tor-proxy.service
[Unit]
Description=Tor Transparent Proxy, Redsocks, and VM Isolation Routing
After=network.target tor.service
Wants=tor.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/setup-tor-routing.sh
ExecStop=/usr/local/bin/teardown-tor-routing.sh

[Install]
WantedBy=multi-user.target
EOF

# Enable native systemd services so they persist across the final install
systemctl enable tor || true
systemctl enable redsocks || true
systemctl enable tor-proxy || true

echo "=== 13. Cleanup ==="
apt-get autoremove --purge -y
apt-get clean
rm -rf /tmp/* /var/tmp/*

echo "Build script completely integrated with native systemd services!"
