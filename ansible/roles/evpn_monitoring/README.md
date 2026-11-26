# evpn_monitoring

Controls the appliance image's `frr-metrics.service`, which runs the embedded FRR image's
`frr-metrics`, with `monitoring.frr_exporter`: unset or true enables and starts it and waits until
`http://127.0.0.1:7573/metrics` answers without a failed BGP collector; false stops and disables it, as teardown
does. Hosts without the unit, such as `provision-aws.yml`'s CentOS routers, are skipped. The role
always removes the legacy `frr_exporter` container, so update appliances to an image with the unit
before or with this collection; otherwise FRR metrics stop until they are. An earlier collection
does not manage the unit and leaves it running, so before going back to one, set
`monitoring.frr_exporter: false` and deploy, or run `teardown.yml`.

Series change from the legacy exporter's `frr_*` to `frrk8s_*`; migrate alerts and dashboards.

Deploys `node_exporter` via the image's systemd unit when present, otherwise via Podman.

Optionally installs an overlay path probe (`evpn_monitoring_path_probe_target`); see
[`monitoring/README.md`](../../../monitoring/README.md#overlay-path-probe).

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`monitoring.frr_exporter`, `monitoring.node_exporter`, the pinned node-exporter
image variable and the probe target).

## Known limitations (tracked, not fixed by this role)

- The image's exporters bind loopback and are unauthenticated, so any local process can read
  them; remote scraping needs the access path from CORENET-7704.
- The non-bootc node-exporter container uses `network: host` without a listen address or
  host firewall, exposing unauthenticated metrics on every interface (source-audit.md §1).
  It still uses a community image (`prometheus/node-exporter`); supportable payloads are
  tracked in kickoff-decisions.md #10.
