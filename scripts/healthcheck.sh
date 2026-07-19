#!/usr/bin/env bash
set -Eeuo pipefail

# Healthy when the VPN tunnel interface exists and, optionally, an internal URL responds.
# Set VPN_HEALTHCHECK_URL to a private-network endpoint for stronger validation.

if ! ip link show "${VPN_TUN_IFACE:-tun0}" >/dev/null 2>&1; then
  echo "VPN tunnel interface ${VPN_TUN_IFACE:-tun0} is not present" >&2
  exit 1
fi

if [[ -n "${VPN_HEALTHCHECK_URL:-}" ]]; then
  curl -fsS --max-time "${VPN_HEALTHCHECK_TIMEOUT:-5}" "$VPN_HEALTHCHECK_URL" >/dev/null
fi
