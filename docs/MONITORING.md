# 📊 Monitoring Guide

[Documentation](README.md) · [Tools](TOOLS.md) · [Control port](CONTROL-PORT.md)

Monitor four distinct signals: the Tor process, active configuration, bootstrap readiness, and freshness of the observation. Public reachability and consensus membership require separate external evidence.

## 🔎 Local checks

```sh
docker exec tor-relay status
docker exec tor-relay health | jq '{liveness,readiness,config_valid,fresh,reason}'
docker exec tor-relay doctor --json
docker inspect tor-relay --format '{{.State.Health.Status}}'
docker stats --no-stream tor-relay
```

A healthy Docker container means the expected process and valid config are present. A bootstrapping container can be healthy while readiness is false. Do not automatically restart a relay just because it is still bootstrapping.

The notice log observation starts at the current Tor run. Log rotation produces a stale observation until a new entrypoint boundary is established. If a mounted configuration logs elsewhere, configure notice logging at `TOR_LOG_DIR/notices.log` or use your own control-port observer.

## 🛰️ Fleet inventory and textfile metrics

```sh
sh scripts/utilities/relay-inventory.sh --json tor-relay tor-bridge
sh scripts/utilities/relay-inventory.sh --prometheus tor-relay tor-bridge
```

Without container arguments, inventory selects containers bearing this project's source label. The output distinguishes Docker running state from availability of a health observation. A stopped or incompatible container has no invented Tor version or readiness.

| Metric | Meaning |
| --- | --- |
| `tor_relay_running` | Docker running state |
| `tor_relay_observation_available` | A JSON health observation was available |
| `tor_relay_liveness` | One Tor process observed |
| `tor_relay_config_valid` | Active config passed Tor validation |
| `tor_relay_readiness` | Current-run bootstrap reached 100% |
| `tor_relay_fresh` | Observation belongs to the current run and log |
| `tor_relay_bootstrap_percent` | Last current-run bootstrap percentage |

A host collector can redirect output into a temporary textfile and atomically rename it after a successful invocation. Schedule it with your existing monitoring system. Alert on observation age as well as value; these gauges do not include an HTTP endpoint or scheduler.

## 🌐 External evidence

Use your relay fingerprint to inspect [Tor Metrics Relay Search](https://metrics.torproject.org/rs.html). Check host firewall and provider port access independently. Bridge lines containing valid local obfs4 state do not prove that users can connect through NAT.

For detailed bandwidth, circuits and traffic accounting, use a separately maintained Tor control-port exporter or Nyx. Restrict the control port to an explicitly trusted path and follow the [control-port guide](CONTROL-PORT.md). No control or monitoring port is exposed automatically.

Keep logs local, rotate them deliberately, and include them in an encrypted backup only when needed. Avoid exporting private bridge lines, torrc contents or key material to general monitoring systems.
