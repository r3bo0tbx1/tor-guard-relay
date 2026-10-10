# 🧹 Container image retention notice

We are enabling automatic cleanup of reviewed older container images. The first cleanup cannot occur before 14 full days after this notice is published; editing this notice restarts that window. Later cleanup runs are at least 14 days apart.

Current stable/edge images, both AMD64 and ARM64 architecture graphs, original-release images and reviewed deployment/rollback digests remain protected. At least two recent builds are kept; superseded recorded builds must be at least 14 days old.

The exact initial legacy digest list is in [build/retired-image-builds.json](https://github.com/r3bo0tbx1/tor-guard-relay/blob/main/build/retired-image-builds.json). This notice authorizes that reviewed list and the rolling retention policy, not arbitrary untagged images.

Operators pinned to older digests should migrate or request protection before the window ends. Fresh pulls of retired digests will fail, including on ARM64. Running containers alone do not guarantee a future pull. Verify encrypted recovery backups and relay fingerprints when upgrading.

Deletion remains conditional on fresh complete deployment protection, successful publication/security evidence and live registry checks. Interrupted cleanup requires reconciliation. GitHub releases, source tags and uploaded release assets remain available.

registry-retirement-policy-sha256: 3b75ea6eea41df1cab1a0ed9f0b4a6af1f8423d8e0f66497465c762359cd7256
