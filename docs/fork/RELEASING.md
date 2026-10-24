# Releasing the fork

Every release is rebuilt from scratch: the original project's latest `main`, plus the fork features picked for that release, plus this branch (`fork/release-config`). Nothing carries over from the previous release, so leaving a feature out of a release is just a matter of not listing it.

## Quick reference

| Goal | Command |
| --- | --- |
| Build the next release locally and check it | `.\scripts\release.ps1` |
| Publish it for Claude's review (pull request into `stable`) | `.\scripts\release.ps1 -Publish` |
| Release it after `claude-verdict` passed | `.\scripts\release.ps1 -Promote 0.2.0` |
| Test build (GitHub pre-release, no review) | `.\scripts\release.ps1 -PreRelease 1 -Publish` |
| Also compile the Rust side while checking | add `-CargoCheck` |

The version and the features come from `fork/release.json` on this branch.

## Branches

| Branch | What it is | Rules |
| --- | --- | --- |
| `main` | Exact copy of the original project's `main` | Never commit to it. Only sync it from `upstream`. |
| `feature/<name>` | One fork feature, e.g. `feature/compact-window` | Branch from `main`, keep it rebased on `main`. Its docs go in `docs/features/<name>.md` on the same branch. |
| `fork/release-config` | Fork-wide files: this doc, the fork README (`.github/README.md`), `fork/release.json`, `scripts/release.ps1`, the Claude review workflows, the pre-release workflow tweak | Branched from `main`. Included in every release. |
| `release/<version>` | One per published version, e.g. `release/0.0.1` | Created by the script. Never changed afterwards, so every release stays reproducible. |
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
   { "version": "0.2.0", "features": ["feature/session-viewer"] }
   ```
   Use the fork's own version line, never the original project's numbers: `0.x.y` while developing, `1.0.0` for the first workable version (see [Decisions](#decisions-change-them-here-if-they-change)).
4. **Build and check.** From a clean working tree:
   ```
   .\scripts\release.ps1
   ```
   It creates `release/0.2.0` from `main`, merges each listed feature and `fork/release-config`, sets the version in all five version files, fills the feature list in `.github/README.md` from `docs/features/*.md`, commits, then runs `npm ci`, the type-check and the front-end build. Add `-CargoCheck` to also compile the Rust side. If a feature conflicts, the script stops, removes the half-built branch and names the feature; go back to step 2.
5. **Open it for review.** Run the script with `-Publish` (delete the local `release/0.2.0` from step 4 first), or push the branch by hand and open a pull request `release/0.2.0 -> stable`:
   ```
   .\scripts\release.ps1 -Publish
   ```
   The script opens the pull request with `gh` if it is installed, otherwise it prints the link to open it. Claude then reviews it (see [Claude review](#claude-review)).
6. **Fix what the review finds** (the pull request is labelled `waiting-for-author`), until it is approved and labelled `ready-to-promote`. Fixes made on the release branch must also go to the feature branch they belong to, or the next release won't have them.
7. **Promote.**
   ```
   .\scripts\release.ps1 -Promote 0.2.0
   ```
   It refuses unless `claude-verdict` passed on the branch's latest commit. Then it tags `v0.2.0` and moves `stable` to `release/0.2.0`, which also marks the pull request as merged. Never press **Merge** on a release pull request: a release replaces `stable`, it is not merged into it. The tag starts `.github/workflows/release.yml`, which builds the installers and creates the GitHub release (about 10 minutes).

## Test builds

```
.\scripts\release.ps1 -PreRelease 1 -Publish
```

This builds `release/0.2.0-rc.1` with app version `0.2.0-1`, tags `v0.2.0-rc.1`, and the workflow publishes it as a GitHub **pre-release**. `stable` is not moved. MSI installers only accept a number after the dash, which is why the app version is `0.2.0-1` while the tag says `rc.1`.

## Claude review

Every pull request into `stable` is reviewed by Claude (`.github/workflows/claude-code-review.yml`). It runs on the Claude subscription behind the `CLAUDE_CODE_OAUTH_TOKEN` repository secret, not on API billing.

- **`claude-verdict`** is one Claude run. It posts an **inline comment on the exact line** of each problem, marked **Blocking** (real defects: bugs, build or type errors, security, data loss, broken release tooling) or **Suggestion** (at most 3, no pure style). Then it returns the verdict, a one-line summary, and a short list of what it checked. It fails when anything is blocking.
- **`claude-decision`** acts on the verdict:
  - **No blocking issues:** approves with a short note (why it passed, and a "Checked:" list), removes `waiting-for-author`, and **merges**. Release pull requests (`release/*`) are approved and labelled `ready-to-promote` instead, because a release replaces `stable` (step 7).
  - **Blocking issues:** requests changes with the summary (details are in the inline comments) and labels the pull request `waiting-for-author`.
- All of it runs again on every push to the pull request, so pushing fixes leads to an automatic approval and merge once they pass.

Reviews and merges are made by `github-actions[bot]`. For it to approve, enable **Settings > Actions > General > Workflow permissions > "Allow GitHub Actions to create and approve pull requests"**. Without that, it comments instead of approving.

**Fixing the comments:**
- **Claude desktop app:** open the pull request in a Claude Code session and turn on **Auto-fix**. The session reacts to new review comments and failing checks, pushes fixes to the branch, and the review runs again.
- **On GitHub:** reply to a comment with `@claude fix this` (`.github/workflows/claude.yml`), and Claude pushes the fix to the branch.

Either way, carry real fixes back to the feature branch (step 6 above).

**Make the review required.** Settings > Rules > Rulesets > New branch ruleset:
- Target: `stable`.
- Rules: *Restrict deletions*, *Block force pushes*, *Require a pull request before merging*, *Require status checks to pass* with the check `claude-verdict`.
- Bypass list: *Repository admin*, set to *Always allow*. The release script's force-move of `stable` needs this.

**Limits:**
- **The review only runs if `claude-code-review.yml` in the pull request matches the copy on `stable`** (the default branch). A pull request that changes the workflow itself is therefore never reviewed: Claude skips it and `claude-verdict` fails with "no verdict". Merge such a change into `stable` on its own first, using your ruleset bypass, then build the release. Release branches carry the workflow from `fork/release-config`, so keep `stable` and `fork/release-config` in step.
- Pull requests from forks of this fork get no secrets, so their review can't run and the required check blocks them.
- The token from `claude setup-token` expires after one year. Create a new one and update the secret.

## Common situations

- **Drop a feature from the next release:** remove it from `fork/release.json`. Its branch stays, so it can come back in a later release.
- **Fix a bug in a shipped feature:** fix it on the feature branch, bump the version (e.g. `0.2.1`) and build a new release. Released branches are never edited.
- **The original project adopts a feature** (e.g. after a pull request): the script notices the feature is already in `main` and skips it. Remove it from `fork/release.json` afterwards.
- **Offer a feature to the original project:** open a pull request from `feature/<name>` to `sattatrapy/...:main`. Leave `docs/features/<name>.md` out of it if they don't want fork docs.
- **Update fork docs between releases:** commit to `fork/release-config`. They reach `stable` with the next release. To publish them right away, open a pull request `fork/release-config -> stable`. After Claude's review passes, merging it normally is fine, because that branch is part of every release anyway.
- **The original project changes `.github/workflows/release.yml`:** `fork/release-config` changes one line in it, so merging may conflict. Rebase `fork/release-config` on `main` and keep their change plus the `prerelease:` line.

## Decisions (change them here if they change)

- **Versioning:** the fork has its own version line, independent of the original project's numbers. `0.x.y` means in development: `0.0.1` is the first build, and later ones are `0.0.2`, `0.1.0` and so on. `1.0.0` is reserved for the first version that counts as workable. The original version a release is based on is visible in its branch history.
- **Downgrading on your own PC:** a build installed with a higher version (e.g. the deleted test release `2.0.0`) blocks installing a lower one, because the MSI refuses downgrades. Uninstall the app first; settings survive.
- **App ID:** the original `com.fedin.sattatracker` is kept, so a fork install replaces the original app and keeps its settings. A different ID would let both be installed, but `productName` would also need to change, because both would otherwise install into the same folder.
- **Pre-releases:** every `0.x` release (tag `v0.*`) and every tag with a `-` (like `v0.2.0-rc.1`) is published as a GitHub pre-release. From `1.0.0` on, releases without a `-` are normal releases.
