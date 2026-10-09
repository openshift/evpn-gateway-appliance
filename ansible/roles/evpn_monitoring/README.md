# evpn_monitoring

Deploys `frr_exporter` and `node_exporter` for Prometheus scraping: uses the
bootc image's baked-in systemd units when present, otherwise runs them
directly via Podman.

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`monitoring.frr_exporter`, `monitoring.node_exporter`, and the
pinned image variables).

## Known limitations (tracked, not fixed by this role)

- Both exporters run with `network: host` and neither sets a listen
  address, so their metrics endpoints are reachable unauthenticated on
  every interface, and no role in this collection configures a host
  firewall to restrict inbound access (source-audit.md §1; see the comment
  in `tasks/main.yml`). How this should be locked down in production is
  not yet decided.
- These remain community images (`tynany/frr_exporter`,
  `prometheus/node-exporter`) pending the payload decision in
  kickoff-decisions.md #10 on moving to Red Hat-built `frr-rhel9` /
  `frr-metrics` content; this role only pins the tags it uses today.
