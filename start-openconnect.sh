#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[openconnect-vpn] %s\n' "$*" >&2
}

read_secret() {
  # Usage: read_secret ENV_NAME [ENV_FILE_NAME]
  # If ENV_NAME is set, use it. Otherwise, if ENV_FILE_NAME points to a file, read that file.
  local env_name="$1"
  local file_env_name="${2:-${env_name}_FILE}"
  local value="${!env_name:-}"
  local file_path="${!file_env_name:-}"

  if [[ -n "$value" && -n "$file_path" ]]; then
    log "Both ${env_name} and ${file_env_name} are set; refusing ambiguous secret source."
    return 1
  fi

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return 0
  fi

  if [[ -n "$file_path" ]]; then
    if [[ ! -r "$file_path" ]]; then
      log "Secret file from ${file_env_name} is not readable: ${file_path}"
      return 1
    fi
    # Strip one trailing newline, preserving other characters.
    python3 - "$file_path" <<'PYREADSECRET'
from pathlib import Path
import sys
sys.stdout.write(Path(sys.argv[1]).read_text().rstrip('\n'))
PYREADSECRET
    return 0
  fi

  return 2
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    log "${name} is required."
    exit 2
  fi
}

start_keepalive() {
  if [[ -z "${VPN_KEEPALIVE_URL:-}" ]]; then
    log "VPN_KEEPALIVE_URL is not set; tunnel idle-timeout prevention is disabled."
    return 0
  fi

  local interval="${VPN_KEEPALIVE_INTERVAL:-300}"
  local timeout="${VPN_KEEPALIVE_TIMEOUT:-5}"

  log "Starting VPN keepalive: ${VPN_KEEPALIVE_URL} every ${interval}s."
  (
    while true; do
      sleep "$interval"
      if curl -fsS --max-time "$timeout" "$VPN_KEEPALIVE_URL" >/dev/null 2>&1; then
        if [[ "${VPN_KEEPALIVE_LOG_SUCCESS:-0}" == "1" ]]; then
          log "VPN keepalive succeeded: ${VPN_KEEPALIVE_URL}"
        fi
      else
        log "VPN keepalive failed: ${VPN_KEEPALIVE_URL}"
      fi
    done
  ) &
  KEEPALIVE_PID=$!
}

main() {
  require_env VPN_HOST
  require_env VPN_USER

  local vpn_pass=""
  if ! vpn_pass="$(read_secret VPN_PASS)"; then
    log "VPN_PASS or VPN_PASS_FILE is required."
    exit 2
  fi

  local servercert_args=()
  if [[ -n "${VPN_SERVERCERT:-}" ]]; then
    servercert_args+=(--servercert "$VPN_SERVERCERT")
  elif [[ -n "${VPN_SERVERCERT_FILE:-}" ]]; then
    if [[ ! -r "$VPN_SERVERCERT_FILE" ]]; then
      log "VPN_SERVERCERT_FILE is not readable: ${VPN_SERVERCERT_FILE}"
      exit 2
    fi
    servercert_args+=(--servercert "$(<"$VPN_SERVERCERT_FILE")")
  else
    log "Warning: VPN_SERVERCERT is not set. Pinning the server certificate is strongly recommended."
  fi

  local authgroup_args=()
  if [[ -n "${VPN_AUTHGROUP:-}" ]]; then
    authgroup_args+=(--authgroup "$VPN_AUTHGROUP")
  fi

  local protocol_args=()
  if [[ -n "${VPN_PROTOCOL:-}" ]]; then
    protocol_args+=(--protocol "$VPN_PROTOCOL")
  fi

  local reconnect_timeout="${VPN_RECONNECT_TIMEOUT:-60}"

  local extra_args=()
  if [[ -n "${OPENCONNECT_EXTRA_ARGS:-}" ]]; then
    # Intentional word splitting for power users who need extra openconnect flags.
    # shellcheck disable=SC2206
    extra_args=(${OPENCONNECT_EXTRA_ARGS})
  fi

  if [[ ! -e /dev/net/tun ]]; then
    log "/dev/net/tun is missing. Run the container with: --device /dev/net/tun:/dev/net/tun"
    exit 3
  fi

  local restart_delay="${VPN_RESTART_DELAY:-10}"

  log "Starting OpenConnect to ${VPN_HOST} as ${VPN_USER}."
  log "If the VPN needs MFA, set VPN_PASS to the full password/token value accepted by the server, or use OPENCONNECT_EXTRA_ARGS for site-specific flags."

  KEEPALIVE_PID=""
  OPENCONNECT_PID=""
  trap '[[ -n "${KEEPALIVE_PID:-}" ]] && kill "$KEEPALIVE_PID" >/dev/null 2>&1 || true; [[ -n "${OPENCONNECT_PID:-}" ]] && kill "$OPENCONNECT_PID" >/dev/null 2>&1 || true; [[ -f /tmp/openconnect.pid ]] && kill "$(cat /tmp/openconnect.pid)" >/dev/null 2>&1 || true' TERM INT EXIT
  start_keepalive

  while true; do
    openconnect "$VPN_HOST" \
      --user="$VPN_USER" \
      --passwd-on-stdin \
      "${servercert_args[@]}" \
      "${authgroup_args[@]}" \
      "${protocol_args[@]}" \
      --script /usr/local/bin/openconnect-dns-wrapper.sh \
      --reconnect-timeout="$reconnect_timeout" \
      --pid-file=/tmp/openconnect.pid \
      "${extra_args[@]}" \
      < <(printf '%s\n' "$vpn_pass") &
    OPENCONNECT_PID=$!

    if wait "$OPENCONNECT_PID"; then
      log "OpenConnect exited cleanly; reconnecting in ${restart_delay}s without restarting the container."
    else
      local rc=$?
      log "OpenConnect exited with code ${rc}; reconnecting in ${restart_delay}s without restarting the container."
    fi
    OPENCONNECT_PID=""

    rm -f /tmp/openconnect.pid
    sleep "$restart_delay"
  done
}

main "$@"
