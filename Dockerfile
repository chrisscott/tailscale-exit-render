# syntax=docker/dockerfile:1

# Tailscale exit node for Render.
#
# Binaries are copied from the official, signed tailscale/tailscale image so
# there is no curl/tar download step to verify by hand. The final image is a
# minimal Alpine base plus CA certificates, tailscaled, the tailscale CLI, and
# a small POSIX entrypoint. It runs as an unprivileged user in userspace
# networking mode, which is the only mode Render supports (no /dev/net/tun,
# no NET_ADMIN).

ARG TAILSCALE_VERSION=1.102.3
ARG ALPINE_VERSION=3.22

FROM tailscale/tailscale:v${TAILSCALE_VERSION} AS tailscale

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache ca-certificates \
 && addgroup -S -g 10001 tailscale \
 && adduser  -S -u 10001 -G tailscale -h /var/lib/tailscale -s /sbin/nologin tailscale \
 && mkdir -p /var/lib/tailscale /var/run/tailscale \
 && chown tailscale:tailscale /var/lib/tailscale /var/run/tailscale \
 && chmod 0700 /var/lib/tailscale /var/run/tailscale

COPY --from=tailscale /usr/local/bin/tailscaled /usr/local/bin/tailscale /usr/local/bin/
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint

USER tailscale:tailscale
WORKDIR /var/lib/tailscale

ENTRYPOINT ["/usr/local/bin/entrypoint"]
