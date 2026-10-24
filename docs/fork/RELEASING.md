# Releasing the fork

Each release gets its own branch, `release/x.y.z`, that starts from the original project's latest `main`. Fork features join it through pull requests, which Claude reviews one by one. The finished release is reviewed once more as a whole in a pull request into `stable`, then promoted: tagged, built by GitHub, and `stable` is moved to it.

Every release starts fresh from the original project, so leaving a feature out of a release just means not adding its pull request.

## Versions

Versions are `x.y.z`, on the fork's own line, never the original project's numbers.

| Version | Meaning | GitHub release |
| --- | --- | --- |
| `x.0.0`, `x >= 1` (e.g. `1.0.0`) | **Ready version**: a bundle of features, ready to use | normal; the newest is marked **Latest** |
| `x.0.z`, `z >= 1` (e.g. `1.0.1`) | **Fix to a ready version** | normal |
| `0.y.z`, and `x.y.z` with `y >= 1` (e.g. `0.1.0`, `1.2.0`) | **Pre-major build**: features, fixes and work in progress toward the next ready version | **pre-release** |

- `z` counts fixes to the same `x.y` (`0.1.1` fixes `0.1.0`; `1.0.1` fixes `1.0.0`).
- Release titles are the plain tag (`v0.1.0`). GitHub's **Pre-release** badge and the first line of the release notes show the type.
- GitHub's "latest release" skips pre-releases, so it always points at the newest ready version.

## Branches

| Branch | What it is | Rules |
| --- | --- | --- |
| `main` | Exact copy of the original project's `main` | Never commit to it. Only sync it from `upstream`. Used as the base of every release. |
| `feature/<name>` | One fork feature, e.g. `feature/compact-window` | Branch from `main`, keep it rebased on `main`. Its docs go in `docs/features/<name>.md` on the same branch. |
| `fork/release-config` | Fork-wide files: this doc, the fork README (`.github/README.md`), `fork/release.json` (the next version), `scripts/`, the workflows, and `docs/releases/` (all release notes) | Branched from `main`. Merged into every release when it starts. |
| `release/x.y.z` | One release, e.g. `release/0.1.0` | Created by `-Start`. Changed only through reviewed pull requests until it is promoted, never after. |
| `stable` | The latest released version; the fork's default branch on GitHub | Never commit to it. `-Promote` force-moves it to each new release. |

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

Windows blocks `.ps1` scripts by default. If `.\scripts\release.ps1` is refused, run it as `powershell -ExecutionPolicy Bypass -File .\scripts\release.ps1` (same parameters). The script opens pull requests with the GitHub CLI (`gh`) when it is installed, otherwise it prints the link.

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

Two checks enforce it: the local `commit-msg` hook (see [Setup on a new clone](#setup-on-a-new-clone)) rejects a non-conforming message when you commit, and the `commit-lint` workflow fails pull requests that contain one. Commits written before the rule (24 October 2026) are left as they are.

The commit subjects become the release notes, so a good description pays off twice.

## Making a release

| Step | Command |
| --- | --- |
| 1. Start the release branch | `.\scripts\release.ps1 -Start` |
| 2. Add each feature (one pull request each) | `.\scripts\release.ps1 -AddFeature feature/<name>` |
| 3. Finish: notes, checks, pull request into `stable` | `.\scripts\release.ps1 -Finish` |
| 4. Release it after the review passed | `.\scripts\release.ps1 -Promote 0.2.0` |

`-Start` and `-Finish` accept `-NoPush` for a local try-out, and `-Finish` accepts `-CargoCheck` to also compile the Rust side.

0. **Prepare.**
   - **Version:** on `fork/release-config`, set the next version in `fork/release.json` (`{ "version": "0.2.0" }`) and commit it. See [Versions](#versions).
   - **Features:** rebase each feature you want to ship on the latest `main`, and fix any conflicts on that branch:
     ```
     git checkout feature/compact-window
     git rebase main
     git push --force-with-lease origin feature/compact-window
     ```
     `rerere` is enabled in this clone, so a conflict fixed once is fixed automatically the next time.
1. **Start.**
   - The script fast-forwards `main` to the original project and creates `release/0.2.0` from it. A ready fix such as `1.0.1` starts from the previous `v1.0.x` release instead, see [Fixing a ready version](#fixing-a-ready-version-x0z).
   - It merges `fork/release-config`, sets the version in the five version files, and pushes the branch.
2. **Add features.** Each `-AddFeature` opens a pull request `feature/<name> -> release/0.2.0`. Claude reviews it:
   - **no blocking issues:** it is approved and merged automatically;
   - **blocking issues:** it is labelled `waiting-for-author` until fixes pushed to the feature branch pass.

   Fixes found while preparing the release are made the same way, as a pull request into the release branch, ideally from the feature branch they belong to.
3. **Finish.**
   - The script reads which features were merged (from their pull request merge commits) and fills the README feature list from `docs/features/*.md`.
   - It writes the [release notes](#release-notes), commits them as `chore(release): v0.2.0`, and runs `npm ci`, the type-check and the front-end build.
   - Then it pushes and opens the pull request `release/0.2.0 -> stable`. Claude reviews the whole release; when it passes, the pull request is approved and labelled `ready-to-promote`.
4. **Promote.** The script refuses unless `claude-verdict` passed on the branch's latest commit. Then it:
   - tags `v0.2.0`, which starts `.github/workflows/release.yml`: it builds the installers and creates the GitHub release, with the release notes as its description and the pre-release flag set from the version (about 10 minutes);
   - moves `stable` to `release/0.2.0`, which also marks the release pull request as merged;
   - copies the release notes to `fork/release-config`, so `docs/releases/` keeps the full history.

   Never press **Merge** on the release pull request: a release replaces `stable`, it is not merged into it. Merging would keep features you dropped.

## Release notes

`-Finish` writes `docs/releases/release-<version>.md`:

- version, type (ready or pre-major), date, the original project's commit it is based on, and the previous release;
- the features included, with their one-line description from `docs/features/<name>.md`;
- per feature: the commits its pull request brought in, minus those already in the previous release;
- features in the previous release that this one leaves out;
- release tooling and docs changes (commits on `fork/release-config` since the previous release);
- the original project's commits since the previous release (up to 20).

The notes are part of the release pull request, so the review covers them, and they become the GitHub release description.

## Fixing a ready version (`x.0.z`)

A fix to `1.0.0` must not pick up work in progress for `1.1.0`. So `-Start` with version `1.0.1` creates `release/1.0.1` from the `v1.0.0` tag, not from `main`. Add the fix as a pull request into `release/1.0.1`, from a branch based on `v1.0.0`, then `-Finish` and `-Promote` as usual. Also put the fix on its feature branch, so later releases keep it.

## Claude review

Every pull request into a release branch or into `stable` is reviewed by Claude (`.github/workflows/claude-code-review.yml`). It runs on the Claude subscription behind the `CLAUDE_CODE_OAUTH_TOKEN` repository secret, not on API billing.

- **`claude-verdict`** is one Claude run. It posts an **inline comment on the exact line** of each problem, marked **Blocking** (real defects: bugs, build or type errors, security, data loss, broken release tooling) or **Suggestion** (at most 3, no pure style). Then it returns the verdict, a one-line summary, and a short list of what it checked. It fails when anything is blocking.
- **`claude-decision`** acts on the verdict:
  - **No blocking issues:** approves with a short note (why it passed, and a "Checked:" list) and removes `waiting-for-author`. Feature and fix pull requests into a release branch are then **merged**. The release pull request (`release/x.y.z -> stable`) is labelled `ready-to-promote` instead.
  - **Blocking issues:** requests changes with the summary (details are in the inline comments) and labels the pull request `waiting-for-author`.
- All of it runs again on every push to the pull request, so pushing fixes leads to an automatic approval (and merge) once they pass.
- **`commit-lint`** checks the commit messages of the same pull requests.

Reviews and merges are made by `github-actions[bot]`. For it to approve, enable **Settings > Actions > General > Workflow permissions > "Allow GitHub Actions to create and approve pull requests"**.

**Fixing the comments:**
- **Claude desktop app:** open the pull request in a Claude Code session and turn on **Auto-fix**. The session reacts to new review comments and failing checks, pushes fixes to the branch, replies in the comment threads, and the review runs again.
- **On GitHub:** reply to a comment with `@claude fix this` (`.github/workflows/claude.yml`), and Claude pushes the fix to the branch.

**Make the review required.** Settings > Rules > Rulesets > New branch ruleset:
- Targets: `stable` and `release/**`.
- Rules: *Restrict deletions* and *Block force pushes* (on `stable`), *Require a pull request before merging*, *Require status checks to pass* with the checks `claude-verdict` and `commit-lint`.
- Bypass list: *Repository admin*, set to *Always allow*. The release script pushes the release branch and force-moves `stable`, which needs this.

**Limits:**
- **The review only runs if `claude-code-review.yml` in the pull request matches the copy on `stable`** (the default branch). A pull request that changes the workflow itself is therefore never reviewed: Claude skips it and `claude-verdict` fails with "no verdict". Merge such a change into `stable` on its own first, using your ruleset bypass. Release branches carry the workflow from `fork/release-config`, so keep `stable` and `fork/release-config` in step.
- Pull requests from forks of this fork get no secrets, so their review can't run and the required check blocks them.
- The token from `claude setup-token` expires after one year. Create a new one and update the secret.

## Common situations

- **Drop a feature from the next release:** don't add its pull request. Its branch stays, so it can come back later. The release notes list it under "Removed".
- **Fix a bug in a pre-major build:** fix it on the feature branch, then make a new release with the next `z` (e.g. `0.2.1`). Released branches are never changed.
- **The original project adopts a feature** (e.g. after a pull request to them): stop adding that feature's pull request; the release already has it through `main`.
- **Offer a feature to the original project:** open a pull request from `feature/<name>` to `sattatrapy/...:main`. Leave `docs/features/<name>.md` out of it if they don't want fork docs.
- **Update fork docs between releases:** commit to `fork/release-config`. They reach `stable` with the next release. To publish them right away, open a pull request `fork/release-config -> stable`; after Claude's review passes it is merged automatically, which is fine because that branch is part of every release anyway.
- **The original project changes `.github/workflows/release.yml`:** `fork/release-config` changes it (pre-release rule and release notes), so merging may conflict. Rebase `fork/release-config` on `main` and keep their change plus the `meta` step and the `releaseBody`/`prerelease` inputs.

## Decisions (change them here if they change)

- **Versioning:** see [Versions](#versions). The first fork build is `0.1.0`; `1.0.0` will be the first ready version.
- **Downgrading on your own PC:** a build installed with a higher version (e.g. the deleted test release `2.0.0`) blocks installing a lower one, because the MSI refuses downgrades. Uninstall the app first; settings survive.
- **App ID:** the original `com.fedin.sattatracker` is kept, so a fork install replaces the original app and keeps its settings. A different ID would let both be installed, but `productName` would also need to change, because both would otherwise install into the same folder.
