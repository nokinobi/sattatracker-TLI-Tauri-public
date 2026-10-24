# Releasing the fork

Every release is rebuilt from scratch: the original project's latest `main`, plus the fork features picked for that release, plus this branch (`fork/release-config`). Nothing carries over from the previous release, so leaving a feature out of a release is just a matter of not listing it.

## Branches

| Branch | What it is | Rules |
| --- | --- | --- |
| `main` | Exact copy of the original project's `main` | Never commit to it. Only sync it from `upstream`. |
| `feature/<name>` | One fork feature, e.g. `feature/compact-window` | Branch from `main`, keep it rebased on `main`. Its docs go in `docs/features/<name>.md` on the same branch. |
| `fork/release-config` | Fork-wide files: this doc, the fork README (`.github/README.md`), `fork/release.json`, `scripts/release.ps1`, the pre-release workflow tweak | Branched from `main`. Included in every release. |
| `release/<version>` | One per published version, e.g. `release/2.0.0` | Created by the script. Never changed afterwards, so every release stays reproducible. |
| `stable` | Points to the latest release; the fork's default branch on GitHub | Never commit to it. The script force-moves it to each new release. |

Remotes in the local clone: `origin` is this fork (nokinobi), `upstream` is the original project (sattatrapy).

Windows blocks `.ps1` scripts by default. If `.\scripts\release.ps1` is refused, run it as `powershell -ExecutionPolicy Bypass -File .\scripts\release.ps1` (same parameters).

## Release checklist

1. **Sync main.** On GitHub press *Sync fork*, or let the script do it: it fast-forwards `main` to `upstream/main` and stops if `main` has commits of its own.
2. **Refresh features.** For each feature you want to ship, rebase it on the new `main` and fix any conflicts on that branch:
   ```
   git checkout feature/compact-window
   git rebase main
   git push --force-with-lease origin feature/compact-window
   ```
   `rerere` is enabled in this clone, so a conflict fixed once is fixed automatically the next time.
3. **Pick features and version.** On `fork/release-config`, edit `fork/release.json` and commit it:
   ```json
   { "version": "2.1.0", "features": ["feature/session-viewer"] }
   ```
   Use your own version line (2.x and up), never the original project's numbers.
4. **Build and check.** From a clean working tree:
   ```
   .\scripts\release.ps1
   ```
   It creates `release/2.1.0` from `main`, merges each listed feature and `fork/release-config`, sets the version in all five version files, fills the feature list in `.github/README.md` from `docs/features/*.md`, commits, then runs `npm ci`, the type-check and the front-end build. Add `-CargoCheck` to also compile the Rust side. If a feature conflicts, the script stops, removes the half-built branch and names the feature; go back to step 2.
5. **Publish.** Run it again with `-Publish` instead (delete the local `release/2.1.0` first), or push the build from step 4 by hand:
   ```
   git push origin release/2.1.0
   git tag v2.1.0
   git push origin v2.1.0
   git push --force origin release/2.1.0:refs/heads/stable
   ```
   Pushing the tag starts `.github/workflows/release.yml`, which builds the installers and creates the GitHub release (about 10 minutes).

## Test builds

```
.\scripts\release.ps1 -PreRelease 1 -Publish
```

This builds `release/2.1.0-rc.1` with app version `2.1.0-1`, tags `v2.1.0-rc.1`, and the workflow publishes it as a GitHub **pre-release**. `stable` is not moved. MSI installers only accept a number after the dash, which is why the app version is `2.1.0-1` while the tag says `rc.1`.

## Common situations

- **Drop a feature from the next release:** remove it from `fork/release.json`. Its branch stays, so it can come back in a later release.
- **Fix a bug in a shipped feature:** fix it on the feature branch, bump the version (e.g. `2.1.1`) and build a new release. Released branches are never edited.
- **The original project adopts a feature** (e.g. after a pull request): the script notices the feature is already in `main` and skips it. Remove it from `fork/release.json` afterwards.
- **Offer a feature to the original project:** open a pull request from `feature/<name>` to `sattatrapy/...:main`. Leave `docs/features/<name>.md` out of it if they don't want fork docs.
- **Update fork docs between releases:** commit to `fork/release-config`. They reach `stable` with the next release; to publish right away, merge `fork/release-config` into `stable`.
- **The original project changes `.github/workflows/release.yml`:** `fork/release-config` changes one line in it, so merging may conflict. Rebase `fork/release-config` on `main` and keep their change plus the `prerelease:` line.

## Decisions (change them here if they change)

- **Versioning:** own line starting at `2.0.0`, so fork versions never collide with the original project's `1.x`. The original version a release is based on is visible in its branch history.
- **App ID:** the original `com.fedin.sattatracker` is kept, so a fork install replaces the original app and keeps its settings. A different ID would let both be installed, but `productName` would also need to change, because both would otherwise install into the same folder.
- **Pre-releases:** tags with a `-` (like `v2.1.0-rc.1`) are published as GitHub pre-releases.
