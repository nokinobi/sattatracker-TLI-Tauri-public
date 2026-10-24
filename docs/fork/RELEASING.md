# Releasing the fork

Every release is rebuilt from scratch: the original project's latest `main`, plus the fork features picked for that release, plus this branch (`fork/release-config`). Nothing carries over from the previous release, so leaving a feature out of a release is just a matter of not listing it.

## Versions

Versions are `x.y.z`, on the fork's own line, never the original project's numbers.

| Version | Meaning | Reviewed into | GitHub release |
| --- | --- | --- | --- |
| `x.0.0`, `x >= 1` (e.g. `1.0.0`) | **Ready version**: a bundle of features, ready to use | `stable` | normal |
| `x.0.z`, `z >= 1` (e.g. `1.0.1`) | **Fix to a ready version** | `stable` | normal |
| `0.y.z`, and `x.y.z` with `y >= 1` (e.g. `0.1.0`, `1.2.0`) | **Pre-major build**: features, fixes and work in progress toward the next ready version | `preview` | pre-release |

- `z` counts fixes to the same `x.y` (`0.1.1` fixes `0.1.0`; `1.0.1` fixes `1.0.0`).
- `stable` only ever holds ready versions. `preview` holds the newest pre-major build.
- GitHub's "latest release" skips pre-releases, so it always points at the newest ready version.

## Commit messages

All commits use [Conventional Commits](https://www.conventionalcommits.org/):

```
type(optional-scope): short description
```

| Type | Use for |
| --- | --- |
| `feat` | a new feature or user-visible ability |
| `fix` | a bug fix |
| `docs` | documentation only |
| `style` | formatting, no code change |
| `refactor` | code change that neither fixes a bug nor adds a feature |
| `perf` | performance improvement |
| `test` | tests |
| `build` | build system, dependencies, versions |
| `ci` | GitHub workflows |
| `chore` | maintenance, including the release script's own commits (`chore(release): ...`) |
| `revert` | reverting an earlier commit |

- **Scope** is optional and names the area, e.g. `feat(compact-window): ...` or `fix(release): ...`.
- **Breaking changes:** add `!` before the colon, e.g. `feat(settings)!: ...`.
- **Description:** lowercase, imperative ("add", not "added"), no period at the end.
- Merge commits are exempt.

Two checks enforce it. A local `commit-msg` hook in `.git/hooks/` rejects a non-conforming message when you commit; see [Setup on a new clone](#setup-on-a-new-clone). The `commit-lint` workflow fails pull requests into `stable` or `preview` that contain one. Commits written before the rule (24 October 2026) are left as they are.

The commit subjects become the release notes, so a good description pays off twice.

## Quick reference

| Goal | Command |
| --- | --- |
| Build the next release locally and check it | `.\scripts\release.ps1` |
| Publish it for Claude's review (pull request into `stable` or `preview`) | `.\scripts\release.ps1 -Publish` |
| Release it after `claude-verdict` passed | `.\scripts\release.ps1 -Promote 0.2.0` |
| Quick test build (pre-release, no review) | `.\scripts\release.ps1 -PreRelease 1 -Publish` |
| Also compile the Rust side while checking | add `-CargoCheck` |

The version and the features come from `fork/release.json` on this branch.

## Branches

| Branch | What it is | Rules |
| --- | --- | --- |
| `main` | Exact copy of the original project's `main` | Never commit to it. Only sync it from `upstream`. |
| `feature/<name>` | One fork feature, e.g. `feature/compact-window` | Branch from `main`, keep it rebased on `main`. Its docs go in `docs/features/<name>.md` on the same branch. |
| `fork/release-config` | Fork-wide files: this doc, the fork README (`.github/README.md`), `fork/release.json`, `scripts/release.ps1`, the review and release workflows, and `docs/releases/` (all release notes) | Branched from `main`. Included in every release. |
| `release/<version>` | One per published version, e.g. `release/0.1.0` | Created by the script. Never changed afterwards, so every release stays reproducible. |
| `stable` | Latest **ready** version; the fork's default branch on GitHub | Never commit to it. `-Promote` force-moves it to each new ready release. |
| `preview` | Latest **pre-major** build | Never commit to it. `-Promote` force-moves it to each new pre-major release. |

Remotes in the local clone: `origin` is this fork (nokinobi), `upstream` is the original project (sattatrapy).

### Setup on a new clone

```
git clone https://github.com/nokinobi/sattatracker-TLI-Tauri-public.git
cd sattatracker-TLI-Tauri-public
git remote add upstream https://github.com/sattatrapy/sattatracker-TLI-Tauri-public.git
git fetch upstream
git config rerere.enabled true
cmd /c "git show origin/fork/release-config:scripts/commit-msg > .git\hooks\commit-msg"
```

The last command installs the Conventional Commits check for every branch of that clone. It goes through `cmd` because PowerShell's `>` would save the file in an encoding Git's shell can't run.

Windows blocks `.ps1` scripts by default. If `.\scripts\release.ps1` is refused, run it as `powershell -ExecutionPolicy Bypass -File .\scripts\release.ps1` (same parameters). `-Publish` opens pull requests with the GitHub CLI (`gh`) when it is on `PATH`, otherwise it prints the link.

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
   { "version": "0.2.0", "features": ["feature/compact-window", "feature/session-viewer"] }
   ```
   See [Versions](#versions) for which number to use.
4. **Build and check.** From a clean working tree:
   ```
   .\scripts\release.ps1
   ```
   It:
   - creates `release/0.2.0` from `main` and merges each listed feature, then `fork/release-config`;
   - sets the version in all five version files and fills the feature list in `.github/README.md` from `docs/features/*.md`;
   - writes the [release notes](#release-notes) to `docs/releases/release-0.2.0.md`;
   - commits, then runs `npm ci`, the type-check and the front-end build. Add `-CargoCheck` to also compile the Rust side.

   If a feature conflicts, the script stops, removes the half-built branch and names the feature; go back to step 2.
5. **Open it for review.** Run the script with `-Publish` (delete the local `release/0.2.0` from step 4 first):
   ```
   .\scripts\release.ps1 -Publish
   ```
   It pushes the branch and opens a pull request into `preview` (pre-major) or `stable` (ready). Claude then reviews it (see [Claude review](#claude-review)).
6. **Fix what the review finds** (the pull request is labelled `waiting-for-author`), until it is approved and labelled `ready-to-promote`. Fixes made on the release branch must also go to the feature branch they belong to, or the next release won't have them.
7. **Promote.**
   ```
   .\scripts\release.ps1 -Promote 0.2.0
   ```
   It refuses unless `claude-verdict` passed on the branch's latest commit. Then it:
   - tags `v0.2.0`, which starts `.github/workflows/release.yml`: it builds the installers and creates the GitHub release, with the release notes as its description (about 10 minutes);
   - moves `preview` (or `stable`) to `release/0.2.0`, which also marks the pull request as merged;
   - copies the release notes to `fork/release-config`, so `docs/releases/` keeps the full history.

   Never press **Merge** on a release pull request: a release replaces `preview`/`stable`, it is not merged into it.

## Release notes

Each release gets `docs/releases/release-<version>.md`, generated by the script from the commits that went into it:

- version, type (ready or pre-major), date, the original project's commit it is based on, and the previous release;
- the features included, with their one-line description from `docs/features/<name>.md`;
- per feature: the commits added since the previous release;
- features removed since the previous release;
- release tooling and docs changes (commits on `fork/release-config`);
- the original project's commits since the previous release (up to 20).

Commit subjects become the bullet points, so write them as short descriptions of the change. The notes are part of the release branch, so the review can comment on them, and they become the GitHub release description.

## Quick test builds

```
.\scripts\release.ps1 -PreRelease 1 -Publish
```

This builds `release/0.2.0-rc.1` with app version `0.2.0-1`, tags `v0.2.0-rc.1`, and publishes it right away as a GitHub **pre-release**, without review. No branch is moved. MSI installers only accept a number after the dash, which is why the app version is `0.2.0-1` while the tag says `rc.1`.

## Fixing a ready version (`x.0.z`)

The script rebuilds every release from the latest `main` and the current feature branches. By the time `1.0.0` needs a fix, those branches may already contain unfinished work for `1.1.0`, which a rebuilt `1.0.1` would pick up. Until the script supports it, build ready fixes by hand from the previous ready release:

```
git checkout -b release/1.0.1 v1.0.0
git cherry-pick <fix commits>
```

Then set the version to `1.0.1` in the five version files, add `docs/releases/release-1.0.1.md`, commit `chore(release): v1.0.1`, push the branch, open a pull request into `stable`, and `-Promote 1.0.1` as usual. Also make sure the fix is on its feature branch, so later releases keep it. The script warns when you ask it to build a ready fix.

## Claude review

Every pull request into `stable` or `preview` is reviewed by Claude (`.github/workflows/claude-code-review.yml`). It runs on the Claude subscription behind the `CLAUDE_CODE_OAUTH_TOKEN` repository secret, not on API billing.

- **`claude-verdict`** is one Claude run. It posts an **inline comment on the exact line** of each problem, marked **Blocking** (real defects: bugs, build or type errors, security, data loss, broken release tooling) or **Suggestion** (at most 3, no pure style). Then it returns the verdict, a one-line summary, and a short list of what it checked. It fails when anything is blocking.
- **`claude-decision`** acts on the verdict:
  - **No blocking issues:** approves with a short note (why it passed, and a "Checked:" list), removes `waiting-for-author`, and **merges**. Release pull requests (`release/*`) are approved and labelled `ready-to-promote` instead, because a release replaces `preview`/`stable` (step 7).
  - **Blocking issues:** requests changes with the summary (details are in the inline comments) and labels the pull request `waiting-for-author`.
- All of it runs again on every push to the pull request, so pushing fixes leads to an automatic approval and merge once they pass.

Reviews and merges are made by `github-actions[bot]`. For it to approve, enable **Settings > Actions > General > Workflow permissions > "Allow GitHub Actions to create and approve pull requests"**. Without that, it comments instead of approving.

**Fixing the comments:**
- **Claude desktop app:** open the pull request in a Claude Code session and turn on **Auto-fix**. The session reacts to new review comments and failing checks, pushes fixes to the branch, and the review runs again.
- **On GitHub:** reply to a comment with `@claude fix this` (`.github/workflows/claude.yml`), and Claude pushes the fix to the branch.

Either way, carry real fixes back to the feature branch (step 6 above).

**Make the review required.** Settings > Rules > Rulesets > New branch ruleset:
- Targets: `stable` and `preview`.
- Rules: *Restrict deletions*, *Block force pushes*, *Require a pull request before merging*, *Require status checks to pass* with the check `claude-verdict`.
- Bypass list: *Repository admin*, set to *Always allow*. The release script's force-move of `stable` and `preview` needs this.

**Limits:**
- **The review only runs if `claude-code-review.yml` in the pull request matches the copy on `stable`** (the default branch). A pull request that changes the workflow itself is therefore never reviewed: Claude skips it and `claude-verdict` fails with "no verdict". Merge such a change into `stable` on its own first, using your ruleset bypass, then build the release. Release branches carry the workflow from `fork/release-config`, so keep `stable` and `fork/release-config` in step.
- Pull requests from forks of this fork get no secrets, so their review can't run and the required check blocks them.
- The token from `claude setup-token` expires after one year. Create a new one and update the secret.

## Common situations

- **Drop a feature from the next release:** remove it from `fork/release.json`. Its branch stays, so it can come back in a later release. The release notes list it under "Removed".
- **Fix a bug in a pre-major build:** fix it on the feature branch, bump `z` (e.g. `0.2.1`) and build a new release. Released branches are never edited.
- **The original project adopts a feature** (e.g. after a pull request): the script notices the feature is already in `main` and skips it. Remove it from `fork/release.json` afterwards.
- **Offer a feature to the original project:** open a pull request from `feature/<name>` to `sattatrapy/...:main`. Leave `docs/features/<name>.md` out of it if they don't want fork docs.
- **Update fork docs between releases:** commit to `fork/release-config`. They reach `stable`/`preview` with the next release. To publish them right away, open a pull request `fork/release-config -> stable`. After Claude's review passes, it is merged automatically, which is fine because that branch is part of every release anyway.
- **The original project changes `.github/workflows/release.yml`:** `fork/release-config` changes it (pre-release rule and release notes), so merging may conflict. Rebase `fork/release-config` on `main` and keep their change plus the `meta` step and the `releaseBody`/`prerelease` inputs.

## Decisions (change them here if they change)

- **Versioning:** see [Versions](#versions). The first fork build is `0.1.0`; `1.0.0` will be the first ready version.
- **Downgrading on your own PC:** a build installed with a higher version (e.g. the deleted test release `2.0.0`) blocks installing a lower one, because the MSI refuses downgrades. Uninstall the app first; settings survive.
- **App ID:** the original `com.fedin.sattatracker` is kept, so a fork install replaces the original app and keeps its settings. A different ID would let both be installed, but `productName` would also need to change, because both would otherwise install into the same folder.
