# Migration

[Documentation](README.md) · [Encrypted recovery](BACKUP.md) · [Deployment](DEPLOYMENT.md)

Preserve identity and transport state before changing image, ownership or storage. The v2.2.0 candidate upgrades Tor and the runtime without intentionally rotating relay identity.

## Prepare

Record source image digest, deployment, fingerprint, public listeners and mount layout. Identify the active torrc, all include files and the effective DataDirectory. Preserve family key material and obfs4 pt_state with identity keys.

Create and verify an [encrypted backup](BACKUP.md), then rehearse restore into a new staging directory using a compatible local image. Keep the original data untouched until recovery and fingerprint checks pass.

## Upgrade an existing deployment

1. Review ENV versus mounted config ownership. Persist lasting changes in the deployment.
2. Validate torrc and Compose/template syntax.
3. Stop the old relay and confirm no other writer shares the data.
4. Recreate with the validated image, retaining the original data and include mounts.
5. Confirm Tor 0.4.9.14 or newer and the original fingerprint.
6. Check fresh bootstrap evidence and public listeners independently.
7. Keep the previous image/deployment and backup until the new relay is verified.

Avoid volume deletion commands. Do not remove keys or pt_state to fix configuration errors.

## Official bridge ownership

Earlier Debian-based bridge deployments commonly used UID 101; this image uses UID 100/GID 101. Inspect actual ownership before changing it. Apply ownership fixes only to the intended stopped relay data, after verified recovery. Retain the original owner information for rollback.

The interactive [migration assistant](../scripts/migration/README.md) now requires encrypted backup creation and verification before mutation. Unsupported source layouts fail instead of silently falling back to a plaintext archive. Manual staged recovery is preferable for layouts the assistant cannot identify.

## Happy Family and accounting

Preserve family keys and FamilyId settings. Accounting state is part of DataDirectory, so keep it with the configuration defining AccountingMax and AccountingStart. IPv6 listener/policy changes also require provider and firewall checks; syntax validity does not prove connectivity.

## Rollback

Stop the new relay before bringing back the old image with the old deployment. Preserve the current data for investigation. If restoring is necessary, restore into a new directory, validate offline, compare the original fingerprint, and activate explicitly. Never run both copies of the identity.

## Historical references

The [v1.1.x record](MIGRATION-V1.1.X.md) and [bridge troubleshooting record](TROUBLESHOOTING-BRIDGE-MIGRATION.md) describe older ownership/configuration problems. Their plaintext backup and automatic-cleanup procedures have been retired in favor of the current staged recovery workflow.
