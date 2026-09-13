# tailscale-exit-render

A Tailscale exit node that runs on Render as a background worker. Traffic from
your Tailscale devices egresses from the Render region you pick.

Secure by default, and nothing that isn't needed:

- **No public surface.** Deployed as a Render *worker*, so there is no URL,
  no inbound port. Tailscale only needs outbound
  connectivity.
- **Unprivileged.** `tailscaled` runs as a non-root user in userspace
  networking mode.
- **Pinned, verified binaries.** `tailscaled` and `tailscale` are copied from
  the official `tailscale/tailscale` image at a pinned version. No download
  step, no extra packages beyond CA certificates.
- **Locked-down node.** `--accept-routes=false`, `--accept-dns=false`,
  `--ssh=false`, and log upload to Tailscale disabled. The auth key is
  removed from the daemon's environment before it starts.
- **Ephemeral.** Use an ephemeral auth key and the node deletes itself from
  the tailnet when the container stops. No stale machines, no cleanup scripts.

## Prerequisites

1. A Tailscale account with admin access to the tailnet.
2. A Render account. Workers have no free tier; **Starter** is the smallest
   plan that runs them.
3. This repo pushed to GitHub or GitLab so Render can build it.

## 1. (Optional) Tailnet policy

Optionally, ddd the following to your tailnet policy file (Admin console → Access
controls). It creates a tag for the node, auto-approves it as an exit node so
you never have to click "approve" in the console, and lets members use it. Otherwise, you will need to approve this in the machine's settings under "Edit route settings..."

```jsonc
{
  "tagOwners": {
    "tag:exit": ["autogroup:admin"]
  },
  "autoApprovers": {
    "exitNode": ["tag:exit"]
  },
  "acls": [
    // members may route internet traffic through exit nodes
    { "action": "accept", "src": ["autogroup:member"], "dst": ["autogroup:internet:*"] }
  ]
}
```

## 2. Auth key

Admin console → Settings → Keys → **Generate auth key**:

| Setting       | Value      | Why                                                    |
| ------------- | ---------- | ------------------------------------------------------ |
| Reusable      | on         | Render restarts and redeploys the container.           |
| Ephemeral     | on         | Node is removed from the tailnet when it goes offline. |
| Tags          | `tag:exit` | Ties the node to the policy above.                     |
| Expiration    | your call  | Only affects *joining*. Rotate it before it expires.   |

## 3. Deploy

1. Render dashboard → **New** → **Blueprint** → select this repo.
2. Render reads `render.yaml` and prompts for `TS_AUTHKEY`. Paste the key.
3. Deploy. The log ends with `exit node online: 100.x.y.z`.
4. On any device: Tailscale → Exit node → `render-exit`.

To change region or plan, edit `render.yaml` before the first deploy, or in
the dashboard afterwards.

## Configuration

| Variable          | Required | Default            | Purpose                                                     |
| ----------------- | -------- | ------------------ | ----------------------------------------------------------- |
| `TS_AUTHKEY`      | yes      |                    | Auth key from step 2. Set in the dashboard, never in git.   |
| `TS_HOSTNAME`     | no       | `render-exit`      | Machine name in the tailnet.                                |
| `TS_EXTRA_ARGS`   | no       |                    | Extra `tailscale up` flags, e.g. `--advertise-tags=tag:exit`. |
| `TS_UPLOAD_LOGS`  | no       | `false`            | Set `true` to send daemon logs to Tailscale for support.    |
| `TS_STATE_DIR`    | no       | `/var/lib/tailscale` | Where node state lives. Ephemeral on Render.              |

Build-time: `TAILSCALE_VERSION` and `ALPINE_VERSION` are `ARG`s at the top of
the `Dockerfile`. Bump them there.

## How it works

`entrypoint.sh` starts `tailscaled --tun=userspace-networking`, waits for its
control socket, runs `tailscale up` with the flags above, then blocks on the
daemon. If `tailscaled` exits, the container exits non-zero and Render
restarts it. `SIGTERM` from Render stops the daemon cleanly and the ephemeral
node disappears from the tailnet.

Userspace networking uses Tailscale's netstack to forward exit-node traffic,
so it works without kernel privileges. Throughput is lower than a kernel TUN
exit node but fine for browsing and general use.

## Run locally

```sh
docker build -t tailscale-exit-render .
docker run --rm -e TS_AUTHKEY=tskey-auth-... tailscale-exit-render
```

## Rotating the key

1. Generate a new key (step 2).
2. Update `TS_AUTHKEY` in Render → service → Environment. Render redeploys.
3. Revoke the old key in the Tailscale admin console.

## Notes and limits

- Exit-node traffic counts against Render's outbound bandwidth allowance.
- Render assigns the container's public IP. It can change between deploys.
- Render Starter provides half a shared CPU and 512 MB RAM. That is plenty for
  `tailscaled`.
- Direct WireGuard connections need outbound UDP. If Render's network blocks
  it, Tailscale falls back to DERP relays over TCP 443 and still works.

## Credits

Inspired by [rutvik2611/tailscale-render-exit-node](https://github.com/rutvik2611/tailscale-render-exit-node).
This project keeps the same idea and strips it down: a Render worker instead
of a web service, no HTTP status page, non-root userspace `tailscaled`, and an
ephemeral node in place of API-based cleanup.
