<#
.SYNOPSIS
    Builds a fork release branch: the author's latest main + the features listed in
    fork/release.json + the fork/release-config branch. See docs/fork/RELEASING.md.

    Versions are x.y.z:
      x.0.0 / x.0.z with x >= 1   ready version (z = fix)  -> reviewed into 'stable', normal release
      everything else (0.y.z, x.y.z with y >= 1)         -> reviewed into 'preview', pre-release

.EXAMPLE
    .\scripts\release.ps1
    Builds release/<version> locally, writes docs/releases/release-<version>.md and runs
    the checks. Nothing is pushed.

.EXAMPLE
    .\scripts\release.ps1 -Publish
    Same, then pushes the branch and opens a pull request into 'stable' or 'preview',
    where Claude reviews it (claude-code-review.yml). Nothing is tagged yet.

.EXAMPLE
    .\scripts\release.ps1 -Promote 0.2.0
    After the claude-verdict check passed on the pull request: tags v0.2.0 (this starts the
    GitHub build of the installers), moves 'preview' (or 'stable') to release/0.2.0 and
    copies the release notes to fork/release-config.

.EXAMPLE
    .\scripts\release.ps1 -PreRelease 1 -Publish
    Quick test build without review: version <version>-1, branch release/<version>-rc.1,
    tag v<version>-rc.1, published as a GitHub pre-release. No branch is moved.
#>
param(
    [switch]$Publish,
    [string]$Promote = '',
    [int]$PreRelease = 0,
    [switch]$SkipChecks,
    [switch]$CargoCheck,
    [string]$ConfigBranch = 'fork/release-config',
    [string]$UpstreamRemote = 'upstream',
    [string]$ForkRemote = 'origin'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed (exit $LASTEXITCODE)" }
}

function Test-Git {
    # Windows PowerShell 5.1 turns redirected native stderr into errors under 'Stop'.
    $ErrorActionPreference = 'Continue'
    & git @args 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed (exit $LASTEXITCODE)" }
}

# Prefer the local branch; fall back to the fork's copy.
function Resolve-Branch([string]$Name) {
    if (Test-Git rev-parse --verify --quiet "refs/heads/$Name") { return $Name }
    if (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$Name") { return "$ForkRemote/$Name" }
    throw "Branch '$Name' not found locally or on $ForkRemote."
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# owner/name of the fork, from the remote URL.
function Get-GitHubRepo {
    $url = (& git remote get-url $ForkRemote).Trim()
    if ($url -notmatch 'github\.com[:/](.+?)/(.+?)(\.git)?$') { throw "$ForkRemote is not a GitHub URL: $url" }
    return "$($Matches[1])/$($Matches[2])"
}

# Ready versions (x >= 1, y = 0) go to 'stable'; everything else is a pre-major build for 'preview'.
function Get-ReleaseTarget([string]$Version) {
    $parts = $Version.Split('.')
    if ([int]$parts[0] -ge 1 -and [int]$parts[1] -eq 0) {
        return @{ Kind = 'ready'; Branch = 'stable'; Label = 'Ready version (normal release)' }
    }
    return @{ Kind = 'pre-major'; Branch = 'preview'; Label = 'Pre-major build (pre-release)' }
}

# The highest released x.y.z below $Version (rc tags are ignored).
function Get-PreviousReleaseTag([string]$Version) {
    $current = [version]$Version
    $tags = & git tag -l 'v*' | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' } |
        Where-Object { [version]($_.Substring(1)) -lt $current } |
        Sort-Object { [version]($_.Substring(1)) } -Descending
    return ($tags | Select-Object -First 1)
}

# Title and one-line summary of a feature, from docs/features/<name>.md in the working tree.
function Get-FeatureInfo([string]$Feature) {
    $slug = $Feature -replace '^feature/', ''
    $doc = "docs/features/$slug.md"
    $info = @{ Title = $slug; Summary = ''; Doc = $null }
    if (Test-Path $doc) {
        $info.Doc = $doc
        $content = Get-Content $doc -Encoding UTF8
        $heading = $content | Where-Object { $_ -match '^# ' } | Select-Object -First 1
        if ($heading) { $info.Title = $heading -replace '^# ', '' }
        $first = $content | Where-Object { $_ -and $_ -notmatch '^(#|!\[|<|>)' } | Select-Object -First 1
        if ($first) { $info.Summary = $first }
    }
    return $info
}

# "- subject (`hash`)" lines for the commits git log selects.
function Get-CommitLines {
    $out = & git log --no-merges --format='%h%x09%s' @args
    if ($LASTEXITCODE -ne 0) { throw "git log $($args -join ' ') failed" }
    return @($out | Where-Object { $_ } | ForEach-Object {
        $hash, $subject = $_ -split "`t", 2
        "- $subject (``$hash``)"
    })
}

# Replaces the first $Count matches, keeping the file's encoding (no BOM) and line endings.
function Set-FileVersion([string]$Path, [string]$Pattern, [string]$NewVersion, [int]$Count = 1) {
    $full = Join-Path (Get-Location) $Path
    $text = [System.IO.File]::ReadAllText($full)
    $regex = New-Object System.Text.RegularExpressions.Regex $Pattern
    if (-not $regex.IsMatch($text)) { throw "Version not found in $Path" }
    $text = $regex.Replace($text, ('${1}' + $NewVersion + '${2}'), $Count)
    [System.IO.File]::WriteAllText($full, $text, $Utf8NoBom)
}

# Rewrites the block between the feature markers in .github/README.md from the
# docs/features/<name>.md files of the features that made it into this release.
function Update-ReadmeFeatures([string[]]$Included) {
    $readme = Join-Path (Get-Location) '.github/README.md'
    if (-not (Test-Path $readme)) { return }
    $lines = @()
    foreach ($feature in $Included) {
        $info = Get-FeatureInfo $feature
        if ($info.Doc) {
            $summary = if ($info.Summary) { " - $($info.Summary)" } else { '' }
            $lines += "- [$($info.Title)](../$($info.Doc))$summary"
        } else {
            $lines += "- $($info.Title)"
        }
    }
    if ($lines.Count -eq 0) { $lines = @('- No fork features in this release.') }
    $text = [System.IO.File]::ReadAllText($readme)
    $block = "<!-- features:start -->`n" + ($lines -join "`n") + "`n<!-- features:end -->"
    $text = [regex]::Replace($text, '(?s)<!-- features:start -->.*?<!-- features:end -->', { param($m) $block })
    [System.IO.File]::WriteAllText($readme, $text, $Utf8NoBom)
}

# Writes docs/releases/release-<version>.md: what this release contains and which commits
# it adds since the previous release.
function New-ReleaseNotes([string]$Version, [string]$Tag, [string[]]$Included, [string]$ConfigRef) {
    $target = Get-ReleaseTarget $Version.Split('-')[0]
    $previous = Get-PreviousReleaseTag $Version.Split('-')[0]
    $since = @()
    if ($previous) { $since = @("^$previous") }

    $upstream = (& git log -1 --format='`%h` %s' main)
    $lines = @(
        "# Release $Version", '',
        "- **Type:** $(if ($PreRelease -gt 0) { 'Test build (pre-release, not reviewed)' } else { $target.Label })",
        "- **Date:** $(Get-Date -Format 'yyyy-MM-dd')",
        "- **Based on:** original project ``main`` at $upstream",
        "- **Previous release:** $(if ($previous) { $previous } else { 'none (first release)' })",
        '', '## Features', ''
    )
    if ($Included.Count -eq 0) { $lines += '- No fork features in this release.' }
    foreach ($feature in $Included) {
        $info = Get-FeatureInfo $feature
        $lines += "- **$($info.Title)**$(if ($info.Summary) { ": $($info.Summary)" })"
    }

    foreach ($feature in $Included) {
        $info = Get-FeatureInfo $feature
        $commits = Get-CommitLines (@('main..' + (Resolve-Branch $feature)) + $since)
        $lines += '', "### $($info.Title)", ''
        if ($commits.Count) { $lines += $commits } else { $lines += "- No changes since $previous." }
    }

    if ($previous -and (Test-Git cat-file -e "${previous}:fork/release.json")) {
        $previousConfig = (& git show "${previous}:fork/release.json") -join "`n"
        if ($previousConfig) {
            $removed = @(($previousConfig | ConvertFrom-Json).features | Where-Object { $Included -notcontains $_ })
            if ($removed.Count) {
                $lines += '', "## Removed since $previous", ''
                $lines += $removed | ForEach-Object { "- $((Get-FeatureInfo $_).Title) (``$_``)" }
            }
        }
    }

    $tooling = @(Get-CommitLines (@("main..$ConfigRef") + $since) | Where-Object { $_ -notmatch '^- docs\(release\): add notes for ' })
    if ($tooling.Count) { $lines += '', '## Release tooling and docs', ''; $lines += $tooling }

    if ($previous) {
        $base = (& git merge-base $previous main).Trim()
        $upstreamCommits = Get-CommitLines "$base..main"
        if ($upstreamCommits.Count) {
            $lines += '', "## Original project changes since $previous", ''
            $lines += $upstreamCommits | Select-Object -First 20
            if ($upstreamCommits.Count -gt 20) { $lines += "- ...and $($upstreamCommits.Count - 20) more." }
        }
    }

    $path = "docs/releases/release-$Version.md"
    New-Item -ItemType Directory -Force -Path 'docs/releases' | Out-Null
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $path), (($lines -join "`n") + "`n"), $Utf8NoBom)
    Write-Host "Wrote $path" -ForegroundColor Green
}

# --- Preconditions -----------------------------------------------------------

if (& git status --porcelain) { throw 'Working tree has uncommitted changes. Commit or stash them first.' }

Write-Host "Fetching $UpstreamRemote and $ForkRemote..." -ForegroundColor Cyan
Invoke-Git fetch $UpstreamRemote --prune
Invoke-Git fetch $ForkRemote --prune --tags

# --- Promote a reviewed release ------------------------------------------------

if ($Promote) {
    if ($Promote -notmatch '^\d+\.\d+\.\d+$') { throw "-Promote takes a version like 0.2.0 (got '$Promote')." }
    $tag = "v$Promote"
    $branch = "release/$Promote"
    $target = Get-ReleaseTarget $Promote
    if (Test-Git rev-parse --verify --quiet "refs/tags/$tag") { throw "Tag $tag already exists." }
    if (-not (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$branch")) { throw "$branch is not on $ForkRemote. Build it with -Publish first." }

    # Fixes pushed during review (e.g. by Claude Auto-fix) are on the fork's copy.
    if (Test-Git rev-parse --verify --quiet "refs/heads/$branch") {
        Invoke-Git checkout --quiet $branch
        Invoke-Git merge --ff-only --quiet "$ForkRemote/$branch"
    } else {
        Invoke-Git checkout --quiet -b $branch "$ForkRemote/$branch"
    }
    $sha = (& git rev-parse HEAD).Trim()
    $repo = Get-GitHubRepo

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $checks = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/$sha/check-runs?check_name=claude-verdict" `
        -Headers @{ 'User-Agent' = 'fork-release-script'; 'Accept' = 'application/vnd.github+json' }
    $check = $checks.check_runs | Sort-Object started_at -Descending | Select-Object -First 1
    if (-not $check) { throw "No claude-verdict check on $sha. Is the pull request into $($target.Branch) open, and has the review run?" }
    if ($check.status -ne 'completed') { throw "claude-verdict is still running on $sha. Try again when it finishes." }
    if ($check.conclusion -ne 'success') { throw "claude-verdict is '$($check.conclusion)' on $sha. Address the review first: $($check.html_url)" }
    Write-Host "claude-verdict passed on $sha" -ForegroundColor Green

    $releaseCommit = (& git log --grep "^chore(release): $tag$" --format=%H -1)
    if ($releaseCommit) {
        $fixes = & git log --format='  %h %s' "$($releaseCommit.Trim())..HEAD"
        if ($fixes) {
            Write-Host 'Commits added during review. Port them to their feature branch (or fork/release-config), or the next release will not have them:' -ForegroundColor Yellow
            $fixes | ForEach-Object { Write-Host $_ }
        }
    }

    Invoke-Git tag $tag
    Invoke-Git push $ForkRemote $tag
    # 'stable' and 'preview' are pointers to the latest release of their kind; moving one
    # also marks the release pull request as merged.
    Invoke-Git push --force $ForkRemote "${branch}:refs/heads/$($target.Branch)"
    Write-Host "Tagged $tag (the GitHub workflow is building the installers) and moved $($target.Branch) to $branch." -ForegroundColor Green

    # Keep every release's notes on the config branch, so later releases carry the history.
    $notes = "docs/releases/release-$Promote.md"
    if (Test-Git cat-file -e "HEAD:$notes") {
        if (Test-Git rev-parse --verify --quiet "refs/heads/$ConfigBranch") {
            Invoke-Git checkout --quiet $ConfigBranch
            Invoke-Git merge --ff-only --quiet "$ForkRemote/$ConfigBranch"
        } else {
            Invoke-Git checkout --quiet -b $ConfigBranch "$ForkRemote/$ConfigBranch"
        }
        Invoke-Git checkout $branch -- $notes
        Invoke-Git commit --quiet -m "docs(release): add notes for $tag"
        Invoke-Git push --quiet $ForkRemote $ConfigBranch
        Write-Host "Copied $notes to $ConfigBranch." -ForegroundColor Green
    }
    return
}

$configRef = Resolve-Branch $ConfigBranch
$config = (& git show "${configRef}:fork/release.json") -join "`n" | ConvertFrom-Json
if ($config.version -notmatch '^\d+\.\d+\.\d+$') { throw "fork/release.json: version must look like 0.2.0 (got '$($config.version)')." }
foreach ($feature in $config.features) {
    if ($feature -notmatch '^feature/') { throw "fork/release.json: '$feature' is not a feature branch (names must start with feature/)." }
}
$duplicates = @($config.features | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
if ($duplicates) { throw "fork/release.json lists these features more than once: $($duplicates -join ', ')" }

$version = $config.version
$tag = "v$version"
$branch = "release/$version"
$target = Get-ReleaseTarget $version
if ($PreRelease -gt 0) {
    # MSI installers only accept a numeric pre-release part, so the app version is 0.2.0-1
    # while the tag and branch carry the readable rc suffix.
    $version = "$version-$PreRelease"
    $tag = "v$($config.version)-rc.$PreRelease"
    $branch = "release/$($config.version)-rc.$PreRelease"
}

if (Test-Git rev-parse --verify --quiet "refs/heads/$branch") { throw "Branch $branch already exists locally." }
if (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$branch") { throw "Branch $branch already exists on $ForkRemote." }
if (Test-Git rev-parse --verify --quiet "refs/tags/$tag") { throw "Tag $tag already exists." }
if ($Publish -and $PreRelease -eq 0 -and -not (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$($target.Branch)")) {
    throw "The '$($target.Branch)' branch doesn't exist on $ForkRemote yet. Create it from stable first (see docs/fork/RELEASING.md)."
}
if ($target.Kind -eq 'ready' -and $config.version -notmatch '\.0$') {
    Write-Host "Ready fix $($config.version): it is rebuilt from the latest main and the current feature branches. Make sure they contain only the fix (see docs/fork/RELEASING.md)." -ForegroundColor Yellow
}

# --- main = the author's main ------------------------------------------------

if (-not (Test-Git merge-base --is-ancestor main "$UpstreamRemote/main")) {
    throw "main has commits that are not in $UpstreamRemote/main. main must stay an exact copy of the author's repo."
}
Invoke-Git checkout --quiet main
Invoke-Git merge --ff-only --quiet "$UpstreamRemote/main"
Write-Host "main is at $(& git log -1 --format='%h %s' main)" -ForegroundColor Cyan

# --- Assemble the release branch ---------------------------------------------

Invoke-Git checkout --quiet -b $branch main

function Merge-IntoRelease([string]$Name, [string]$Ref) {
    if (Test-Git merge-base --is-ancestor $Ref main) {
        Write-Host "  skip  $Name (already in the author's main)" -ForegroundColor DarkGray
        return $false
    }
    if (-not (Test-Git merge-base --is-ancestor main $Ref)) {
        Write-Host "  note  $Name is not rebased on the latest main" -ForegroundColor Yellow
    }
    & git merge --no-ff --no-edit -m "chore(release): add $Name to $tag" $Ref | Out-Host
    if ($LASTEXITCODE -ne 0) {
        & git merge --abort | Out-Host
        & git checkout --quiet main | Out-Host
        & git branch -D $branch | Out-Null
        throw "Merging $Name conflicts with the release. Rebase $Name on main, fix the conflicts there, then run the script again."
    }
    Write-Host "  added $Name" -ForegroundColor Green
    return $true
}

Write-Host "Building $branch ($tag, $($target.Kind))" -ForegroundColor Cyan
$included = @()
foreach ($feature in $config.features) {
    if (Merge-IntoRelease $feature (Resolve-Branch $feature)) { $included += $feature }
}
Merge-IntoRelease $ConfigBranch $configRef | Out-Null

# --- Version, README and release notes -------------------------------------------

Set-FileVersion 'package.json'              '(?m)^(\s*"version":\s*")[^"]+(")' $version
Set-FileVersion 'package-lock.json'         '(?m)^(\s*"version":\s*")[^"]+(")' $version 2
Set-FileVersion 'src-tauri/tauri.conf.json' '(?m)^(\s*"version":\s*")[^"]+(")' $version
Set-FileVersion 'src-tauri/Cargo.toml'      '(?m)^(version\s*=\s*")[^"]+(")' $version
Set-FileVersion 'src-tauri/Cargo.lock'      '(name = "tli-sattatracker"\r?\nversion = ")[^"]+(")' $version
Update-ReadmeFeatures $included
New-ReleaseNotes $version $tag $included $configRef

Invoke-Git add -A
Invoke-Git commit --quiet -m "chore(release): $tag" -m ("Features: " + ($(if ($included) { $included -join ', ' } else { 'none' })))
Write-Host "Committed version $version" -ForegroundColor Green

# --- Checks ------------------------------------------------------------------

if (-not $SkipChecks) {
    Write-Host 'Checks: npm ci, type-check, front-end build' -ForegroundColor Cyan
    Invoke-Checked 'npm' @('ci', '--no-audit', '--no-fund')
    Invoke-Checked 'npx' @('vue-tsc', '--noEmit')
    Invoke-Checked 'npx' @('vite', 'build')
    if ($CargoCheck) {
        Invoke-Checked 'cargo' @('check', '--manifest-path', 'src-tauri/Cargo.toml')
    }
    if (& git status --porcelain) { throw 'The checks changed tracked files; review them before publishing.' }
}

# --- Publish -------------------------------------------------------------------

if (-not $Publish) {
    Write-Host ""
    Write-Host "Built $branch locally. Nothing was pushed." -ForegroundColor Cyan
    if ($PreRelease -gt 0) {
        Write-Host "To publish this test build:  git push $ForkRemote $branch; git tag $tag; git push $ForkRemote $tag"
    } else {
        Write-Host "To publish it for review:  git push $ForkRemote $branch, then open a pull request $branch -> $($target.Branch)"
    }
    return
}

Invoke-Git push $ForkRemote $branch

if ($PreRelease -gt 0) {
    Invoke-Git tag $tag
    Invoke-Git push $ForkRemote $tag
    Write-Host "Pushed $branch and $tag. The GitHub workflow is building the pre-release." -ForegroundColor Green
    return
}

# Reviewed releases go through Claude's review on a pull request into 'stable' or 'preview'.
$repo = Get-GitHubRepo
$title = "Release $tag"
$body = "$($target.Label). Features: $(if ($included) { $included -join ', ' } else { 'none' })`n`n" +
        "Release notes: ``docs/releases/release-$version.md```n`n" +
        "Claude reviews this pull request. When the claude-verdict check passes, run " +
        "``.\scripts\release.ps1 -Promote $($config.version)``. Do not press Merge: the release replaces $($target.Branch), it is not merged into it."
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    & gh pr create --repo $repo --base $target.Branch --head $branch --title $title --body $body
    if ($LASTEXITCODE -ne 0) { throw 'gh pr create failed.' }
} else {
    Write-Host "Open the pull request (title: $title):" -ForegroundColor Cyan
    Write-Host "  https://github.com/$repo/compare/$($target.Branch)...$($branch)?expand=1"
}
Write-Host "When claude-verdict passes:  .\scripts\release.ps1 -Promote $($config.version)" -ForegroundColor Green
