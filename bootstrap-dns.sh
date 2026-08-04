#!/bin/bash
# Run this script once after creating the internal DNS LXC (dns-01)
#
# Usage:
#   bash bootstrap-dns.sh
#
# This container answers name lookups for the home network. The router
# (ipTIME) cannot hold custom local records - it only forwards - so the
# records have to live somewhere, and this is that somewhere.
#
# After running this, point the router's DHCP DNS at 192.168.0.102 so every
# device on the LAN uses it. Records are defined in LOCAL_RECORDS below.

set -e

LISTEN_IP="192.168.0.102"

# Internal-only names. These are deliberately absent from public DNS: adding
# a Cloudflare record for any of them would expose the service through the
# tunnel. Resolving here means they work at home and nowhere else.
declare -A LOCAL_RECORDS=(
  ["argocd.newhojin.com"]="192.168.0.151"
)

echo "=== Installing dnsmasq ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y dnsmasq

# Ubuntu ships systemd-resolved listening on 127.0.0.53, which does not
# collide with dnsmasq on the LAN address, but it does own /etc/resolv.conf.
# Leave it alone and simply bind dnsmasq to the LAN address.
echo "=== Writing /etc/dnsmasq.d/homelab.conf ==="
{
  echo "# Managed by bootstrap-dns.sh - edit the script, not this file."
  echo
  echo "# Answer only on the LAN address. Binding explicitly keeps dnsmasq off"
  echo "# the loopback address that systemd-resolved already owns."
  echo "listen-address=${LISTEN_IP}"
  echo "bind-interfaces"
  echo
  echo "# The router runs DHCP. This box does DNS only."
  echo "no-dhcp-interface="
  echo
  echo "# Upstream. Anything not defined below is forwarded here."
  echo "server=8.8.8.8"
  echo "server=1.1.1.1"
  echo
  echo "# Do not forward lookups that cannot be answered publicly anyway."
  echo "domain-needed"
  echo "bogus-priv"
  echo
  echo "cache-size=1000"
  echo
  echo "# Internal-only records."
  for name in "${!LOCAL_RECORDS[@]}"; do
    echo "address=/${name}/${LOCAL_RECORDS[$name]}"
  done
} > /etc/dnsmasq.d/homelab.conf

cat /etc/dnsmasq.d/homelab.conf

echo "=== Restarting dnsmasq ==="
systemctl enable dnsmasq
systemctl restart dnsmasq
systemctl --no-pager --lines=0 status dnsmasq || true

echo
echo "=== Verifying ==="
for name in "${!LOCAL_RECORDS[@]}"; do
  got="$(dig +short "${name}" "@${LISTEN_IP}" | head -1)"
  want="${LOCAL_RECORDS[$name]}"
  if [ "$got" = "$want" ]; then
    echo "  OK       ${name} -> ${got}"
  else
    echo "  MISMATCH ${name} -> '${got}' (expected ${want})"
  fi
done

fwd="$(dig +short google.com "@${LISTEN_IP}" | head -1)"
if [ -n "$fwd" ]; then
  echo "  OK       upstream forwarding works (google.com -> ${fwd})"
else
  echo "  FAILED   upstream forwarding returned nothing"
fi

echo
echo "=== Bootstrap complete ==="
echo "Next: set the router's DHCP DNS server to ${LISTEN_IP} so LAN clients use it."
