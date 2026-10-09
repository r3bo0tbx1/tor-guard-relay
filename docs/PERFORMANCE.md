# ⚡ Performance and Limits

[Documentation](README.md) · [Monitoring](MONITORING.md) · [Deployment](DEPLOYMENT.md)

Measure your relay before tuning it. Traffic, consensus weight, provider capacity and Tor flags affect utilization; the container cannot promise a throughput or guard-flag timetable.

## 📊 Establish a baseline

```sh
docker stats --no-stream tor-relay
docker exec tor-relay health
sh scripts/utilities/relay-inventory.sh --json tor-relay
```

Record image identity, current Tor version, CPU/memory usage, bootstrap and reachability evidence. Use an authenticated control-port observer for detailed bandwidth and circuits; host inventory reports health, not traffic counters.

## 🧠 CPU and memory

Use Docker CPU and memory limits according to measured load and leave room for bootstrap/state growth. `NumCPUs` and `MaxMemInQueues` are Tor settings for advanced mounted configs; syntax validation does not establish that a chosen limit is sufficient. Review Tor notices and host OOM events after changes.

Keep SocksPort disabled for a relay. Do not copy client-only circuit tuning directives into relay configuration expecting throughput improvements.

## 📶 Bandwidth and accounting

`TOR_BANDWIDTH_RATE` and `TOR_BANDWIDTH_BURST` control generated relay bandwidth limits. Monthly accounting can use:

```sh
TOR_ACCOUNTING_MAX="500 GB"
TOR_ACCOUNTING_START="month 1 00:00"
```

Accounting can cause hibernation when limits are reached. Match provider billing rules and validate the resulting torrc. Preserve the state file and accounting config together through encrypted backup and migration.

## 🌐 IPv6

Set an explicit additional listener with `TOR_ORPORT_IPV6`. `TOR_ADDRESS_DISABLE_IPV6`, `TOR_IPV6_EXIT` and `TOR_EXIT_POLICY_IPV6` cover common policy settings. IPv6 requires working host/provider routing and deliberate firewall access; accepting a config does not prove connectivity.

Use the actual public listener and policy for your role. Test IPv4 and IPv6 independently after recreation. Public bridge-line generation accepts a supplied IPv6 address, but does not test routing.

## 🛡️ Safe tuning sequence

1. Record baseline image/config and health.
2. Create and verify an encrypted recovery set.
3. Change one measured bottleneck or limit.
4. Validate the candidate and review values securely.
5. Reload only directives Tor supports reloading; otherwise recreate.
6. Compare resource usage, notices and external connectivity.
7. Keep the previous deployment available for rollback.

No host sysctl changes, HTTP exporter or monitoring scheduler is installed automatically.
