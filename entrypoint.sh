#!/bin/sh
# Start tailscaled in userspace mode, join the tailnet, advertise as an exit
# node, then block on tailscaled. If tailscaled dies the container exits
# non-zero and Render restarts it.
set -eu

: "${TS_AUTHKEY:?TS_AUTHKEY is required (reusable + ephemeral + tagged auth key)}"

authkey="$TS_AUTHKEY"
unset TS_AUTHKEY            # keep the key out of tailscaled's environment

hostname="${TS_HOSTNAME:-render-exit}"
state_dir="${TS_STATE_DIR:-/var/lib/tailscale}"
extra_args="${TS_EXTRA_ARGS:-}"
socket="/var/run/tailscale/tailscaled.sock"

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

daemon_args="--tun=userspace-networking --state=$state_dir/tailscaled.state --socket=$socket"
# Off by default: do not ship tailscaled logs to Tailscale's log service.
if [ "${TS_UPLOAD_LOGS:-false}" != "true" ]; then
    daemon_args="$daemon_args --no-logs-no-support"
fi

log "starting tailscaled (userspace networking)"
# shellcheck disable=SC2086
tailscaled $daemon_args &
daemon_pid=$!

shutdown() {
    log "signal received, stopping tailscaled"
    kill -TERM "$daemon_pid" 2>/dev/null || true
    wait "$daemon_pid" 2>/dev/null || true
    exit 0
}
trap shutdown TERM INT

i=0
until [ -S "$socket" ]; do
    i=$((i + 1))
    if ! kill -0 "$daemon_pid" 2>/dev/null; then
        log "tailscaled exited during startup"; exit 1
    fi
    if [ "$i" -ge 30 ]; then
        log "tailscaled socket not ready after 30s"; exit 1
    fi
    sleep 1
done

log "joining tailnet as ${hostname}"
# --reset makes every restart converge on exactly these settings.
# shellcheck disable=SC2086
tailscale --socket="$socket" up \
    --reset \
    --auth-key="$authkey" \
    --hostname="$hostname" \
    --advertise-exit-node \
    --accept-routes=false \
    --accept-dns=false \
    --ssh=false \
    --timeout=90s \
    $extra_args
unset authkey

log "exit node online: $(tailscale --socket="$socket" ip -4 2>/dev/null || echo '?')"

wait "$daemon_pid" || true
log "tailscaled exited"
exit 1
