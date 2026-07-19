# Contributing

Thanks for improving this project. Keep changes small and focused.

## Before opening a pull request

- Do not include real VPN hosts, usernames, passwords, cookies, certificate pins, private URLs, or other secrets.
- If you change shell scripts, run:

  ```bash
  bash -n start-openconnect.sh
  bash -n openconnect-dns-wrapper.sh
  bash -n scripts/healthcheck.sh
  scripts/test-preserve-docker-dns.sh
  ```

- If you change the Dockerfile or copied runtime files, run:

  ```bash
  docker build -t openconnect-vpn:local .
  ```

- If Docker Compose is available, validate the example:

  ```bash
  docker compose -f compose.example.yaml config
  ```

## Scope

This repository should stay a small Docker Compose VPN gateway wrapper around OpenConnect. Avoid adding orchestration features unless they are necessary for the common case.
