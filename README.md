# OpenConnect VPN Container

A small Docker image for running an [OpenConnect](https://www.infradead.org/openconnect/) client as a reusable Docker Compose VPN gateway.

The intended pattern is: run one `vpn` service, then attach any containers that must use the VPN with `network_mode: "service:vpn"`.

```text
compose project
├── vpn                  # owns OpenConnect + tun0
├── app-a              # network_mode: service:vpn
├── app-b              # network_mode: service:vpn
└── app-c              # network_mode: service:vpn
```

## Why this pattern

- VPN credentials and behavior live in one container.
- Multiple application containers can share the same VPN tunnel.
- Restarting an application container does not reconnect the VPN.
- It is harder for a selected container to accidentally bypass the VPN.
- The setup is easy to move into another Docker Compose project.

## Scope

This project provides a small OpenConnect container wrapper for Docker Compose VPN gateway use cases.

Non-goals:

- managing host VPN clients;
- browser-based SSO automation;
- strict firewall kill-switch by default;
- full VPN orchestration platform.

## Quick start

```bash
cp .env.example .env
# Edit .env with your real VPN values. Never commit it.

docker build -t openconnect-vpn:local .
```

Then copy `compose.example.yaml` into your real Compose project and replace `app-example` with your services.

```bash
docker compose -f compose.example.yaml up -d --build
```

> Note: this environment may use either `docker compose` or legacy `docker-compose` depending on your host. The example assumes the Compose v2 plugin.

## Required container privileges

OpenConnect needs a TUN device and network administration capability:

```yaml
cap_add:
  - NET_ADMIN
devices:
  - /dev/net/tun:/dev/net/tun
```

Do not run this image with fully privileged mode unless your environment specifically requires it.

## Configuration

Environment variables are read directly or through `*_FILE` secret-file variants.

| Variable | Required | Description |
| --- | --- | --- |
| `VPN_HOST` | yes | VPN server hostname or URL accepted by `openconnect`. |
| `VPN_USER` | yes | VPN username. |
| `VPN_PASS` / `VPN_PASS_FILE` | yes | Password, token, or file containing the password/token. |
| `VPN_SERVERCERT` / `VPN_SERVERCERT_FILE` | recommended | Server certificate pin, e.g. `pin-sha256:...`. |
| `VPN_AUTHGROUP` | no | OpenConnect auth group. |
| `VPN_PROTOCOL` | no | OpenConnect protocol, e.g. `anyconnect`, if needed. |
| `VPN_RECONNECT_TIMEOUT` | no | Reconnect timeout in seconds. Default: `60`. |
| `OPENCONNECT_EXTRA_ARGS` | no | Additional advanced flags passed to `openconnect`. |
| `VPN_PRESERVE_DOCKER_DNS` | no | Keep Docker embedded DNS (`127.0.0.11`) after VPN connect so Compose service names keep resolving. Default: `1`. Set `0` for stock vpnc-script DNS behavior. |
| `VPN_HEALTHCHECK_URL` | no | Internal URL that must respond for the container to be healthy. |
| `VPN_HEALTHCHECK_TIMEOUT` | no | Curl timeout for `VPN_HEALTHCHECK_URL`. Default: `5`. |
| `VPN_TUN_IFACE` | no | Tunnel interface checked by healthcheck. Default: `tun0`. |

## Docker secrets example

```yaml
services:
  vpn:
    build: .
    cap_add: [NET_ADMIN]
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      VPN_HOST: vpn.example.com
      VPN_USER: your_username
      VPN_PASS_FILE: /run/secrets/vpn_pass
      VPN_SERVERCERT_FILE: /run/secrets/vpn_servercert
    secrets:
      - vpn_pass
      - vpn_servercert

secrets:
  vpn_pass:
    file: ./secrets/vpn_pass.txt
  vpn_servercert:
    file: ./secrets/vpn_servercert.txt
```

## Using it as a VPN gateway

Dependent services should share the `vpn` service network namespace:

```yaml
services:
  vpn:
    build: ./openconnect
    cap_add: [NET_ADMIN]
    devices:
      - /dev/net/tun:/dev/net/tun
    env_file:
      - .env

  my-app:
    image: my-app:latest
    network_mode: "service:vpn"
    depends_on:
      vpn:
        condition: service_healthy
```

### Important port rule

A service using `network_mode: "service:vpn"` cannot publish its own ports. Publish ports on the `vpn` service instead:

```yaml
services:
  vpn:
    ports:
      - "8081:8081" # port used by my-app inside the shared namespace

  my-app:
    network_mode: "service:vpn"
```

Also make sure services sharing the namespace do not listen on the same port.

### Docker DNS preservation

By default this image preserves Docker embedded DNS (`127.0.0.11`) after OpenConnect connects. This keeps Docker Compose service discovery working for attached containers, so a service behind the VPN gateway can still resolve peers such as `camofox` on the same user-defined Docker network.

The wrapper still lets the stock vpnc script configure tunnel routes, but hides VPN DNS from the child script so it does not replace Docker's resolver. VPN-provided search domains are retained in `/etc/resolv.conf` when available.

If your VPN site requires the stock behavior where VPN DNS replaces container DNS, set:

```env
VPN_PRESERVE_DOCKER_DNS=0
```

## Health checks

The built-in healthcheck passes when:

1. the tunnel interface exists, default `tun0`; and
2. if `VPN_HEALTHCHECK_URL` is set, that URL returns successfully.

For production use, set `VPN_HEALTHCHECK_URL` to a stable private-network endpoint. Checking only `tun0` proves the tunnel device exists, but not that private network resources are reachable.

## MFA / SSO notes

This image is best for VPN setups where OpenConnect can authenticate non-interactively with username/password, password+OTP, a cookie, or site-specific flags.

If your VPN requires a browser SSO flow, you may need one of these instead:

- host-managed VPN plus Docker routing through the host VPN;
- an external process that periodically refreshes an OpenConnect cookie;
- site-specific `OPENCONNECT_EXTRA_ARGS`.

## Security notes

- Do not commit `.env`, secrets, certs, or cookies.
- Pin `VPN_SERVERCERT` whenever possible.
- Prefer Docker secrets or a local untracked `.env` file over hardcoded credentials.
- This image does not enable a strict firewall kill-switch by default. Add one only after confirming it does not block VPN authentication/bootstrap traffic in your environment.

## Local verification

```bash
bash -n start-openconnect.sh
bash -n scripts/healthcheck.sh
docker build -t openconnect-vpn:local .
```

Runtime verification requires real VPN credentials and a host/container environment with `/dev/net/tun` available.
