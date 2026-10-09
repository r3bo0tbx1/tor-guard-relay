# 🏗️ Architecture

[Documentation](README.md) · [Deployment](DEPLOYMENT.md) · [Release process](../scripts/release/README.md)

The runtime is Alpine, Tor, Lyrebird, Tini and POSIX shell tools. Backup encryption, fleet collection and release preparation run on the host. No Python, age, HTTP metrics server or scheduler is added to the relay image.

## 🔄 Runtime flow

```mermaid
flowchart LR
  Tini --> Entrypoint
  Entrypoint --> Ownership[Resolve config ownership]
  Ownership --> Candidate[Validate generated candidate or mounted torrc]
  Candidate --> Tor
  Tor --> Notices[Current-run notice evidence]
  Notices --> Tools[Health, status and doctor]
```

Tini handles PID 1 responsibilities. The entrypoint resolves official bridge aliases, creates runtime directories, validates configuration and launches Tor. Generated files are published by same-directory atomic rename only after validation. Mounted config files remain authoritative.

Shared `lib/config.sh` owns ENV validation/rendering. Shared `lib/runtime.sh` owns exact Tor process discovery, config inspection and health JSON. This keeps healthcheck, status, health, doctor and refresh aligned.

## 🔎 Process and observations

Process discovery uses exact `/proc/PID/comm` values rather than substring matches. Ambiguous processes produce a reason code rather than a combined PID. Active configuration comes from the process command; fingerprint lookup uses the effective DataDirectory.

The entrypoint records PID, process start time, notice-log inode and byte offset at launch. Health reads only events after that boundary. Restarted logs cannot inherit successful bootstrap; rotation invalidates freshness. A custom mounted config without the expected notice log produces missing evidence.

Liveness, configuration validity, readiness and observation freshness are separate booleans. Bootstrap readiness does not prove network reachability. Docker health checks process and config so a normal bootstrap delay does not create a restart loop.

SIGHUP reload validates the active torrc, checks process identity and confirms the same process survives. SIGTERM shutdown has a configurable bounded wait; natural Tor failures retain their exit status. Generated configurations log to the notice file, which the entrypoint streams once to Docker output.

## 🗂️ Paths and ownership

| Path | Purpose |
| --- | --- |
| `/etc/tor/torrc` | Default configuration; custom TOR_CONFIG is supported |
| `/var/lib/tor` | Default persistent identity, family keys, state and transport state |
| `/var/log/tor/notices.log` | Default observation source |
| `/run/tor/relay.state` | Ephemeral current-run boundary |
| `/build-info.txt` | Project version, build date and architecture |
| `/usr/local/lib/relay` | Shared shell libraries |

The image runs as UID 100/GID 101. Operators prepare persistent-volume ownership before deployment. Startup does not grant itself host privileges to repair a volume.

## 📦 Build and release

Stable runtime uses Alpine 3.24.2 pinned by digest; edge follows Alpine edge. Both require Tor 0.4.9.14 or newer. Lyrebird source and Go dependency graph are pinned. The native Go builder cross-compiles the requested architecture; the actual target runtime is tested separately.

Source-pin proposals and Go security fixes are independent review paths. Host/CI source reachability analysis verifies matching candidate transport bytes; no scanner enters the runtime. Scheduled publication resolves release source and current reviewed security policy separately. Read-only periodic checks analyze current source and published registry digests, retaining full evidence without altering a running relay.

Release jobs load and validate four candidates before any promotion. Exported image archives, checksums and image IDs carry evidence into promotion, which assembles manifests from the pushed candidate digests without rebuilding. SBOMs and scan results accompany curated notes. Schedules resolve the latest released tag, preserving source identity.

## 🔐 Host recovery boundary

The backup command obtains Docker tar streams from a stopped source, combines configuration and state with an integrity manifest, compresses and encrypts directly into ciphertext. Complete verification happens before staged extraction. Restore uses a network-disabled Tor validation helper and never activates the identity automatically.

[Recovery](BACKUP.md) documents include restrictions, external master-key custody and shared-writer limits. Host inventory uses Docker inspection and JSON health; it adds no public listener.

## 🤝 Compatibility

Guard/middle, exit and bridge share the runtime contract. Official bridge ENV aliases and Happy Family configuration remain supported. Advanced directives belong in a mounted torrc. Operators own external networking, firewall policy, control-port authentication and relay activation.
