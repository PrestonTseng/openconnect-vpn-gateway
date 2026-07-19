# Security Policy

## Supported usage

This project is a small OpenConnect container wrapper. It is intended for private infrastructure use where operators control the Docker host and Compose configuration.

## Reporting issues

Do not open public issues that include VPN hosts, usernames, passwords, cookies, certificate pins, or private-network URLs. Report privately through your normal repository security process.

## Secrets handling

- Never commit `.env`, real certs, cookies, password files, or private hostnames if they are sensitive.
- Prefer `VPN_PASS_FILE` / Docker secrets for shared deployments.
- Pin `VPN_SERVERCERT` where possible.
