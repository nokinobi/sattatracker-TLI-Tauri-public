# Releasing the fork

Each release gets its own branch, `release/<x.y.z>`, that starts from the original project's latest `main`. Fork features join it through pull requests, which Claude reviews one by one. The finished release is reviewed once more as a whole in a pull request into `stable`, then promoted: tagged, built by GitHub, and `stable` is moved to it.

Every release starts fresh from the original project, so leaving a feature out of a release just means not adding its pull request.

In this document `<x.y.z>` stands for the version of the release you're working on.

## Versions

Versions are `x.y.z`, on the fork's own line, independent of the original project's numbers.

| Version pattern | Meaning | GitHub release |
| --- | --- | --- |
| `x.0.0` with `x >= 1` | **Ready version**: a bundle of features, ready to use | normal; the newest is marked **Latest** |
| `x.0.z` with `x >= 1`, `z >= 1` | **Fix to a ready version** | normal |
| `0.y.z`, and `x.y.z` with `y >= 1` | **Pre-major build**: features, fixes and work in progress toward the next ready version | **pre-release** |

- `z` counts fixes to the same `x.y`.
- The version exists only in the branch name (`release/<x.y.z>`) and the tag (`v<x.y.z>`). The release workflow sets it in the app at build time, so the original project's version files (`package.json`, `tauri.conf.json`, `Cargo.toml`) are never changed. Local builds keep showing the original project's version.
- Release titles are the plain tag. GitHub's **Pre-release** badge and the first line of the release notes show the type.
- GitHub's "latest release" skips pre-releases, so it always points at the newest ready version.
- Before the first ready version, all releases are pre-major builds (`0.y.z`).

## Branches

| Branch | What it is | Rules |
| --- | --- | --- |
| `main` | Exact copy of the original project's `main` | Never commit to it. Only sync it from `upstream`. Used as the base of every release. |
| `feature/<name>` | One fork feature | Branch from `main`, keep it rebased on `main`. Its docs go in `docs/features/<name>.md` on the same branch. |
| `fork/release-config` | Fork-wide files: this doc, the fork README (`.github/README.md`), `scripts/`, the workflows, and `docs/release/versions/` (all release notes) | Branched from `main`. Merged into every release when it starts. |
| `release/<x.y.z>` | One release | Created by `-Start`. Changed only through reviewed pull requests until it is promoted, never after. |
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

## Changing a feature or the release setup

`feature/<name>` and `fork/release-config` are long-lived branches. Change them through short-lived branches and pull requests, which Claude reviews like any other:

| Change | Short-lived branch | Pull request into |
| --- | --- | --- |
| Release tooling, workflows, release docs | `fix/...`, `ci/...`, `docs/...`, `chore/...` | `fork/release-config` |
| A feature | `fix/...`, `refactor/...`, `perf/...`, `docs/...` | `feature/<name>` |

```
git checkout fork/release-config
git pull
git checkout -b fix/<topic>
# commit, one Conventional Commit per change
git push -u origin fix/<topic>
gh pr create --repo nokinobi/sattatracker-TLI-Tauri-public --base fork/release-config --head fix/<topic>
```

- **Prefix the branch with the change type**, matching the commit types. Never start it with `feature/`: the release script recognises features by "Merge pull request ... from .../feature/<name>", so a `feature/...` branch merged into a feature would be listed as a feature of its own.
- **Several fixes:**
  - related fixes: one branch, one commit each. Pushing more commits updates the open pull request, and the review runs again.
  - independent fixes: one branch and pull request each.
- **Merged branches are done.** Don't reuse them; start a new branch from the current long-lived branch. Turn on *Settings > General > Automatically delete head branches* so GitHub removes them after merging.
- **The long-lived branch moved meanwhile:** update the pull request with GitHub's *Update branch* button, or rebase on it.
- **How changes reach users:**
  - a feature change ships with the next release that adds that feature (`-AddFeature`);
  - a `fork/release-config` change is part of every release from the next `-Start` on.
  - A change to `claude-code-review.yml` must also go into `stable` right away, see [Limits](#claude-review).
- **Every change is reviewed twice:** once in its own pull request, and again inside the whole feature when it is added to a release.

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
| `build` | build system, dependencies |
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
| 1. Start the release branch | `.\scripts\release.ps1 -Start -Version <x.y.z>` |
| 2. Add each feature (one pull request each) | `.\scripts\release.ps1 -AddFeature feature/<name>` |
| 3. Finish: notes, checks, pull request into `stable` | `.\scripts\release.ps1 -Finish` |
| 4. Release it after the review passed | `.\scripts\release.ps1 -Promote <x.y.z>` |

- `-AddFeature` and `-Finish` find the version themselves: the checked-out `release/<x.y.z>` branch, or else the only release branch on the fork that isn't released yet. Pass `-Version <x.y.z>` when several are open.
- `-Start` and `-Finish` accept `-NoPush` for a local try-out, and `-Finish` accepts `-CargoCheck` to also compile the Rust side.

0. **Prepare.** Pick the version (see [Versions](#versions)). Rebase each feature you want to ship on the latest `main`, and fix any conflicts on that branch:
   ```
   git checkout feature/<name>
   git rebase main
   git push --force-with-lease origin feature/<name>
   ```
   `rerere` is enabled in this clone, so a conflict fixed once is fixed automatically the next time.
1. **Start.**
   - The script fast-forwards `main` to the original project and creates `release/<x.y.z>` from it. A ready fix starts from the previous release of its line instead, see [Fixing a ready version](#fixing-a-ready-version).
   - It merges `fork/release-config` and pushes the branch.
2. **Add features.** Each `-AddFeature` opens a pull request `feature/<name> -> release/<x.y.z>`. Claude reviews it:
   - **no blocking issues:** it is approved and merged automatically;
   - **blocking issues:** it is labelled `waiting-for-author` until fixes pushed to the feature branch pass.

   Fixes found while preparing the release are made the same way, as a pull request into the release branch, ideally from the feature branch they belong to.
3. **Finish.**
   - The script reads which features were merged (from their pull request merge commits) and fills the README feature list from `docs/features/*.md`.
   - It writes the [release notes](#release-notes), commits them as `chore(release): v<x.y.z>`, and runs `npm ci`, the type-check and the front-end build.
   - Then it pushes and opens the pull request `release/<x.y.z> -> stable`. Claude reviews the whole release; when it passes, the pull request is approved and labelled `ready-to-promote`.
4. **Promote.** The script refuses unless `claude-verdict` passed on the branch's latest commit. Then it:
   - tags `v<x.y.z>`, which starts `.github/workflows/release.yml`. The workflow builds the installers with the version taken from the tag, and creates the GitHub release with the release notes as its description and the pre-release flag set from the version (about 10 minutes);
   - moves `stable` to `release/<x.y.z>`, which also marks the release pull request as merged;
   - copies the release notes to `fork/release-config`, so `docs/release/versions/` keeps the full history.

   Never press **Merge** on the release pull request: a release replaces `stable`, it is not merged into it. Merging would keep features you dropped.

## Release notes

`-Finish` writes `docs/release/versions/<x.y.z>.md`, one file per release. Together they are the fork's release history.

- version, type (ready or pre-major), date, the original project's commit it is based on, and the previous release;
- the features included, with their one-line description from `docs/features/<name>.md`;
- per feature: the commits its pull request brought in, minus those already in the previous release;
- features in the previous release that this one leaves out;
- release tooling and docs changes (commits on `fork/release-config` since the previous release);
- the original project's commits since the previous release (up to 20).

The notes are part of the release pull request, so the review covers them, and they become the GitHub release description.

## Fixing a ready version

A fix to a ready version `x.0.z` must not pick up work in progress for the next pre-major build. So `-Start -Version x.0.z` creates the release branch from the previous `vx.0.*` tag, not from `main`. Add the fix as a pull request into that release branch, from a branch based on the same tag, then `-Finish` and `-Promote` as usual. Also put the fix on its feature branch, so later releases keep it.

## Claude review

Every pull request into `stable`, a release branch, `fork/*` or `feature/*` is reviewed by Claude (`.github/workflows/claude-code-review.yml`). It runs on the Claude subscription behind the `CLAUDE_CODE_OAUTH_TOKEN` repository secret, not on API billing.

- **`claude-verdict`** is one Claude run. It posts an **inline comment on the exact line** of each problem, marked **Blocking** (real defects: bugs, build or type errors, security, data loss, broken release tooling) or **Suggestion** (at most 3, no pure style). Then it returns the verdict, a one-line summary, and a short list of what it checked. It fails when anything is blocking.
- **`claude-decision`** acts on the verdict:
  - **No blocking issues:** approves with a short note (why it passed, and a "Checked:" list) and removes `waiting-for-author`. Other pull requests (features into a release, fixes into `fork/*` or `feature/*`) are then **merged**. The release pull request (`release/<x.y.z> -> stable`) is labelled `ready-to-promote` instead.
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
- **Fix a bug in a pre-major build:** fix it on the feature branch, then make a new release with the next `z`. Released branches are never changed.
- **The original project adopts a feature** (e.g. after a pull request to them): stop adding that feature's pull request; the release already has it through `main`.
- **Offer a feature to the original project:** open a pull request from `feature/<name>` to `sattatrapy/...:main`. Leave `docs/features/<name>.md` out of it if they don't want fork docs.
- **Update fork docs between releases:** commit to `fork/release-config`. They reach `stable` with the next release. To publish them right away, open a pull request `fork/release-config -> stable`; after Claude's review passes it is merged automatically, which is fine because that branch is part of every release anyway.
- **The original project changes `.github/workflows/release.yml`:** `fork/release-config` changes it (version from the tag, pre-release rule, release notes), so merging may conflict. Rebase `fork/release-config` on `main` and keep their change plus the `meta` step and the `args`, `releaseBody` and `prerelease` inputs.

## Decisions (change them here if they change)

- **Versioning:** see [Versions](#versions).
- **Downgrading on your own PC:** a build installed with a higher version blocks installing a lower one, because the MSI refuses downgrades. Uninstall the app first; settings survive.
- **App ID:** the original `com.fedin.sattatracker` is kept, so a fork install replaces the original app and keeps its settings. A different ID would let both be installed, but `productName` would also need to change, because both would otherwise install into the same folder.
