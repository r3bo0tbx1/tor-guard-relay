# Historical bridge migration troubleshooting

[Documentation](README.md) · [Current migration](MIGRATION.md) · [Encrypted recovery](BACKUP.md)

This record concerns the earlier migration from thetorproject/obfs4-bridge to this Alpine image. The old emergency script, plaintext backup examples and automatic torrc deletion steps are retired.

## Symptoms and original causes

- Configuration validation failed when an old torrc remained authoritative but used incompatible paths or directives.
- UID mismatch between the earlier Debian deployment and Alpine prevented access to persistent data.
- Fingerprints changed when keys were not preserved at the effective DataDirectory.

A changing fingerprint is a reason to stop and inspect the storage layout. It is not a reason to regenerate or delete keys.

## Diagnose with current tools

```sh
docker exec tor-bridge doctor --json
docker exec tor-bridge config validate
docker exec tor-bridge health
docker inspect tor-bridge --format '{{json .Mounts}}'
```

Inspect mount destinations and ownership privately. Avoid printing full environment variables or private config in issue reports. If a bridge line is unavailable, use the reason from `bridge-line --json --address YOUR_PUBLIC_ADDRESS`; local state availability has no fixed waiting period.

## Recovery today

Use [Backup](BACKUP.md) and [Migration](MIGRATION.md) to preserve config, includes, identity, family keys and pt_state before any repair. Validate a staged recovery with networking disabled, compare fingerprints, and activate only after the old identity is stopped.

If ownership must change, check the exact intended volume and original UID/GID first. Keep the old image and deployment. Roll back by stopping the new relay and deliberately activating the old deployment or validated staged data.
