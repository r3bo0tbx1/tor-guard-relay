# Lyrebird dependency lock

The Dockerfiles fetch the reviewed Lyrebird revision, then use this go.mod/go.sum graph with readonly module resolution. Source updates and dependency updates are separate review steps: compare upstream changes, build both architectures, inspect the linked transport metadata, and run candidate security checks before publication.

Do not replace the graph with upstream defaults without checking the Pion STUN security floor. Renovate can propose Go module updates; component checks and offline image acceptance remain required.
