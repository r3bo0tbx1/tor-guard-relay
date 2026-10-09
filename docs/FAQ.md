# Frequently asked questions

[Documentation](README.md) · [Tools](TOOLS.md) · [Deployment](DEPLOYMENT.md)

## Which image should I use?

Stable is the normal deployment choice; edge follows Alpine's rolling packages. This checkout prepares v2.2.0. Use a locally built candidate before publication, and check the published release before choosing a remote version tag.

## Why update Tor immediately?

Tor 0.4.9.14 fixes high-severity issues affecting relays and other Tor components. The Tor Project recommends updating as soon as possible. This source requires at least that version in both variants. See the [upstream announcement](https://forum.torproject.org/t/security-release-0-4-9-14/22241).

## Does healthy mean my relay is ready?

Docker health means one Tor process and valid active configuration. JSON readiness requires a current-run 100% bootstrap observation. Public reachability, consensus membership and a guard flag are separate checks. Use `doctor --json` for the local reason and next action.

## Why is readiness unknown after log rotation?

Observation freshness is tied to the current Tor process and original log inode/offset. Restart through the entrypoint to establish a new boundary. Do not reuse old successful bootstrap lines as current proof.

## Why did my ENV change not affect mounted torrc?

A mounted configuration is authoritative. Edit its host source and validate before reload. Generated configurations are regenerated from ENV on restart. `config apply` changes a generated file atomically, but does not update deployment ENV.

## Why is the config diff empty?

The diff shows directive changes and redacts every value, including unknown directives. Value-only changes are deliberately hidden. Review sensitive candidates privately.

## Does bridge-line require a 24–48 hour wait?

No fixed wait is required. It needs local obfs4 transport state, a fingerprint and your explicit reachable public address. It does not prove external connectivity or distribution by BridgeDB.

## How do I preserve identity?

Persist the complete DataDirectory and use [encrypted backup and recovery](BACKUP.md). Keys, family material and pt_state belong in the same recovery set. Keep offline/external master keys separately. Never start the same restored identity twice.

## Can I use Docker Desktop and WSL?

Yes for local testing and host recovery. The scripts prefer docker.exe from WSL when present. Production host-network examples target Linux. A local offline test does not validate Windows port forwarding or public relay routing.

## Are updates fully automatic?

Scheduled jobs rebuild the latest released tag, validate candidates and then promote. They cannot publish new main-branch features under an old release. Pinned base and source updates require a reviewed source release. Operators still need to recreate running containers to use new images.

## Does the image expose a monitoring port?

No. Use JSON tools or host fleet metrics. A control port or external exporter is an explicit deployment choice; authenticate and restrict it.

## Will a relay immediately become a guard?

Tor authorities determine flags over time. The container's guard mode prepares a non-exit relay; it does not grant a flag or guarantee a timetable.

## Where should I report a problem?

Use the project's issue tracker with image identity, mode and redacted diagnostic output. Follow [Security](../SECURITY.md) for vulnerabilities and [Legal considerations](LEGAL.md) before operating an exit.
