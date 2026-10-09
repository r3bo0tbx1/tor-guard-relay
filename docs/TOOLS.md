# Operator tools

[Documentation](README.md) · [Monitoring](MONITORING.md) · [Encrypted recovery](BACKUP.md)

Run container tools with `docker exec tor-relay COMMAND`. JSON is written to stdout; jq remains a host dependency. The image exposes no monitoring listener.

| Command | Purpose |
| --- | --- |
| `status` | Human report from the same observation as health |
| `health` | JSON process, bootstrap, config and observation state |
| `doctor [--json]` | Reason and suggested next action; exits 1 until ready |
| `config validate [file]` | Quiet Tor syntax validation |
| `config diff candidate` | Directive-only comparison; every value redacted |
| `config apply candidate [--reload]` | Validated atomic replacement of generated config |
| `refresh` | Validate active config, signal the exact Tor PID, confirm it survives |
| `fingerprint` | Relay identity and Metrics link |
| `bridge-line [--plain\|--json] --address ADDRESS [--port PORT]` | obfs4 line from local transport state |
| `gen-auth` | Control-port password/hash helper |
| `gen-family [--show]` | Family key generation and inspection |

## Health contract

```sh
docker exec tor-relay health
docker exec tor-relay doctor --json
docker exec tor-relay health | jq '{liveness,readiness,config_valid,fresh,reason}'
```

Existing fields remain: `status`, `pid`, `uptime`, `bootstrap`, `reachable`, `errors`, `nickname`, `fingerprint`, `tor_version`, `relay_mode`, `build_version` and `config_source`. The new fields are booleans `liveness`, `readiness`, `config_valid`, `fresh`, plus `reason` and `config_path`. The legacy `reachable` field remains the string `true`, `false` or `unknown`.

Liveness requires one exact Tor process. Readiness additionally requires valid active configuration and a current-run 100% bootstrap observation. It does not prove public reachability, consensus membership or a guard flag. The Docker healthcheck uses liveness plus configuration validity, allowing a relay time to bootstrap.

Current-run evidence uses PID, process start time, notice-log inode and byte offset recorded by the entrypoint. Restarted or rotated logs cannot supply an old successful bootstrap. Custom mounted configurations should log notices to `TOR_LOG_DIR/notices.log` to provide readiness evidence. A missing observation remains unknown; it is never converted into success.

| Reason | Next step |
| --- | --- |
| `process_missing` | Inspect startup and exit status |
| `process_ambiguous` | Run one Tor process per container |
| `config_invalid` | Validate paths, permissions and syntax |
| `observation_missing` / `observation_stale` | Inspect notice logging and restart boundary |
| `bootstrap_pending` | Inspect current notices, DNS, firewall and connectivity |
| `ready` | Check external reachability separately |

## Change configuration

```sh
docker cp ./candidate.torrc tor-relay:/tmp/candidate.torrc
docker exec tor-relay config validate /tmp/candidate.torrc
docker exec tor-relay config diff /tmp/candidate.torrc
docker exec tor-relay config apply /tmp/candidate.torrc --reload
```

Apply is for generated configurations. A mounted torrc is authoritative: edit and validate its host source, then reload or recreate deliberately. Every diff value is hidden, so value-only changes will not appear. Review the candidate securely before applying. Invalid candidates retain the active file. Generated ENV configurations are regenerated on restart, so put lasting changes into deployment ENV or switch to a mounted torrc.

`refresh` sends SIGHUP only after validation and confirms the process start identity is unchanged. Tor decides which directives can reload; changes requiring restart still need recreation. Neither refresh nor config apply modifies deployment ENV.

## Bridge lines

```sh
docker exec tor-bridge bridge-line --plain --address 203.0.113.10
docker exec tor-bridge bridge-line --json --address 2001:db8::10 --port 9002
```

Use your reachable public address; documentation addresses above are examples. The transport must have written its local obfs4 state and Tor must have a fingerprint. The command reports missing-state/config reasons instead of prescribing a fixed waiting period. Share bridge information only through your intended distribution channel.

## Host commands

```sh
sh scripts/utilities/relay-inventory.sh tor-relay tor-bridge
sh scripts/utilities/relay-inventory.sh --json tor-relay
sh scripts/utilities/relay-inventory.sh --prometheus tor-relay
sh scripts/utilities/relay-backup.sh --help
```

Inventory reports the local Docker image ID, available registry digests, project and Tor versions, pinned Lyrebird revision, relay mode and health. Metrics can be collected by a host textfile collector; the command starts no HTTP service. See [Monitoring](MONITORING.md) and [Backup](BACKUP.md).
