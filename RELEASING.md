# Publishing a release

This directory is the intended GitHub repository root. The surrounding working project, device data, toolchain caches, and private signed builds do not belong in the repository.

1. Review the original-game-content redistribution status. The package includes the original Chuzzle executable/assets and game-derived translations. No rights-holder permission is established by the open-source runtime license. This is the remaining content-rights decision before public upload; this preparation does not certify it.
2. Commit the source and create a version tag matching `OriginalPort/ios/Info.plist`.
3. Attach `Chuzzle.ipa`, `Chuzzle-source.zip`, `Chuzzle-runtime-sources.zip`, and `SHA256SUMS` to the same GitHub Release. The first archive is unsigned and requires the recipient's signing method. The source archive must match the tagged source and the binary.
4. Use the prepared release notes, with the unsigned-installation requirement intact. Keep source downloads available with the corresponding binary releases.
5. Do not attach a private development IPA: it contains a provisioning profile, certificate metadata, and a device list.

The public source folder already excludes old experiments, historical builds, evidence logs, save data, Apple profiles, private keys, personal Xcode settings, and local Git history. `Chuzzle-source.zip` includes the same repository contents, including modified third-party source. Runtime-source archives retain upstream provenance and checksums.

For a future release, build from the tagged source, use `Scripts/package_ipa.py`, run `Scripts/audit_release.py`, and verify launch, touch dragging, all four modes, save/restore, background/resume, and physical-device performance. The audit checks packaging hygiene; it is not a determination of redistribution rights.
