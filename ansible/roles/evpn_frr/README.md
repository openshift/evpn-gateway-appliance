# evpn_frr

Shared FRR lifecycle handling for the appliance, cloud relay, and cloud VTEP
roles.

The calling role owns rendering `/etc/frr/frr.conf` and starting FRR. This role
reconciles a changed running configuration with `frr-reload.py` inside the
existing FRR container. It only restarts FRR when the reload helper is not
available or when the daemon configuration requires a restart.
