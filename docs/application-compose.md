# Application containers behind the VPN gateway

This project is designed for the pattern where one `vpn` service owns the OpenConnect tunnel and one or more application containers share that network namespace.

## Minimal pattern

```yaml
services:
  vpn:
    build: ./openconnect
    cap_add: [NET_ADMIN]
    devices:
      - /dev/net/tun:/dev/net/tun
    env_file:
      - .env

  app-one:
    image: your-application-image
    network_mode: "service:vpn"
    depends_on:
      vpn:
        condition: service_healthy

  app-two:
    image: your-application-image
    network_mode: "service:vpn"
    depends_on:
      vpn:
        condition: service_healthy
```

## Operational notes

- Publish inbound ports on `vpn`, not on the attached services.
- Avoid port collisions between attached services because they share the same localhost/network namespace.
- Use a private-network `VPN_HEALTHCHECK_URL` to prove the tunnel reaches the expected network.
- Keep real `.env` files outside git.

## Verify routing from an attached service

After the stack is up, exec into an attached container and check a private-network resource:

```bash
docker exec -it <attached-container> sh
curl -fsS https://intranet.example.com/health
```

If that succeeds only when attached to `network_mode: "service:vpn"`, the gateway pattern is working.
