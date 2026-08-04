#!/bin/bash
# Run this script once after creating the VPN LXC (vpn-01)
#
# Usage:
#   bash bootstrap-vpn.sh
#
# Tailscale exit node. Clients abroad select this node as their exit node and
# their internet traffic leaves through the home connection, i.e. with a Korean
# IP. This is not a subnet router - the LAN (192.168.0.0/24) stays closed.
#
# PREREQUISITE - do this on the Proxmox host first, or tailscaled cannot build
# a tunnel. An unprivileged LXC has no /dev/net/tun by default:
#
#   cat >> /etc/pve/lxc/103.conf <<'EOF'
#   lxc.cgroup2.devices.allow: c 10:200 rwm
#   lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
#   EOF
#   pct restart 103
#
# The proxmox_lxc resource cannot express those lines, so this stays a manual
# step. It is documented here and in README rather than left as silent drift.

set -e

if [ ! -c /dev/net/tun ]; then
  echo "ERROR: /dev/net/tun is missing."
  echo "Add the two lxc.* lines to /etc/pve/lxc/103.conf on the Proxmox host"
  echo "and run 'pct restart 103', then run this script again."
  exit 1
fi

echo "=== Enabling IP forwarding ==="
# An exit node routes other machines' traffic, which the kernel drops without
# forwarding enabled. ip_forward is usually already on; IPv6 usually is not.
cat > /etc/sysctl.d/99-tailscale.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-tailscale.conf

echo "=== Installing Tailscale ==="
export DEBIAN_FRONTEND=noninteractive
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
tailscale version

systemctl enable --now tailscaled
systemctl --no-pager --lines=0 status tailscaled || true

echo
echo "=== Bringing the node up ==="
echo "This prints a login URL. Open it, approve the machine, then approve the"
echo "exit node under Machines -> vpn-01 -> Edit route settings in the admin console."
echo
tailscale up --advertise-exit-node --hostname=vpn-01

echo
echo "=== Status ==="
tailscale status || true
tailscale ip -4 || true

echo
echo "=== Bootstrap complete ==="
echo "Approve the exit node in the Tailscale admin console, then pick vpn-01 as"
echo "the exit node on the client. Verify the client's public IP is Korean."
