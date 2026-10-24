<#
.SYNOPSIS
    Fork release workflow. See docs/fork/RELEASING.md.

    A release branch release/<version> starts from the original project's latest main
    (plus fork/release-config). Features join it through pull requests, which Claude reviews.
    The finished release is reviewed once more in a pull request into 'stable', then
    promoted: tagged, built by GitHub, and 'stable' is moved to it.

    Versions are x.y.z: x.0.z with x >= 1 is a ready version (normal GitHub release);
    everything else (0.y.z, x.y.z with y >= 1) is a pre-major build (GitHub pre-release).
    The version comes from fork/release.json on fork/release-config, or -Version.

.EXAMPLE
    .\scripts\release.ps1 -Start
    Creates release/<version> from the latest main (a ready fix x.0.z starts from the previous
    ready release instead), merges fork/release-config, sets the version, pushes the branch.

.EXAMPLE
    .\scripts\release.ps1 -AddFeature feature/compact-window
    Opens a pull request feature/compact-window -> release/<version>. Claude reviews it and
    merges it when there are no blocking issues.

.EXAMPLE
    .\scripts\release.ps1 -Finish
    Writes docs/releases/release-<version>.md and the README feature list from the features
    merged into the release, runs the checks, pushes, and opens the pull request into 'stable'.

.EXAMPLE
    .\scripts\release.ps1 -Promote 0.2.0
    After claude-verdict passed on that pull request: tags v0.2.0 (GitHub builds the installers
    and publishes the release), moves 'stable' to release/0.2.0, and copies the release notes
    to fork/release-config.
#>
param(
    [switch]$Start,
    [string]$AddFeature = '',
    [switch]$Finish,
    [string]$Promote = '',
    [string]$Version = '',
    [switch]$NoPush,
    [switch]$SkipChecks,
    [switch]$CargoCheck,
    [string]$ConfigBranch = 'fork/release-config',
    [string]$UpstreamRemote = 'upstream',
    [string]$ForkRemote = 'origin'
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$actions = @($Start.IsPresent, [bool]$AddFeature, $Finish.IsPresent, [bool]$Promote) | Where-Object { $_ }
if ($actions.Count -ne 1) { throw 'Choose exactly one of -Start, -AddFeature <branch>, -Finish, -Promote <version>.' }

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

# Checks out a branch, created from or fast-forwarded to the fork's copy.
function Switch-ToForkBranch([string]$Name) {
    if (Test-Git rev-parse --verify --quiet "refs/heads/$Name") {
        Invoke-Git checkout --quiet $Name
        if (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$Name") {
            Invoke-Git merge --ff-only --quiet "$ForkRemote/$Name"
        }
    } else {
        Invoke-Git checkout --quiet -b $Name "$ForkRemote/$Name"
    }
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# owner/name of the fork, from the remote URL.
function Get-GitHubRepo {
    $url = (& git remote get-url $ForkRemote).Trim()
    if ($url -notmatch 'github\.com[:/](.+?)/(.+?)(\.git)?$') { throw "$ForkRemote is not a GitHub URL: $url" }
    return "$($Matches[1])/$($Matches[2])"
}

# Opens a pull request with the GitHub CLI, or prints the link when gh isn't available.
function Open-PullRequest([string]$Base, [string]$Head, [string]$Title, [string]$Body) {
    $repo = Get-GitHubRepo
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh -and (Test-Path "$env:ProgramFiles\GitHub CLI\gh.exe")) { $gh = Get-Command "$env:ProgramFiles\GitHub CLI\gh.exe" }
    if ($gh) {
        & $gh.Source pr create --repo $repo --base $Base --head $Head --title $Title --body $Body
        if ($LASTEXITCODE -ne 0) { throw 'gh pr create failed.' }
    } else {
        Write-Host "Open the pull request (title: $Title):" -ForegroundColor Cyan
        Write-Host "  https://github.com/$repo/compare/$Base...$($Head)?expand=1"
    }
}

function Get-ReleaseKind([string]$Ver) {
    $parts = $Ver.Split('.')
    if ([int]$parts[0] -ge 1 -and [int]$parts[1] -eq 0) { return 'Ready version (normal release)' }
    return 'Pre-major build (pre-release)'
}

function Test-ReadyFix([string]$Ver) {
    $parts = $Ver.Split('.')
    return ([int]$parts[0] -ge 1 -and [int]$parts[1] -eq 0 -and [int]$parts[2] -ge 1)
}

# The highest released x.y.z below $Ver; -Like limits it, e.g. 'v1.0.*'.
function Get-PreviousReleaseTag([string]$Ver, [string]$Like = 'v*') {
    $current = [version]$Ver
    $tags = & git tag -l $Like | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' } |
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

# Features merged into the current release branch through pull requests:
# name plus the commit range that merge brought in.
function Get-MergedFeatures {
    $features = [ordered]@{}
    $merges = & git log --merges --reverse --format='%H%x09%s' 'main..HEAD'
    foreach ($line in $merges) {
        $sha, $subject = $line -split "`t", 2
        if ($subject -match '^Merge pull request #\d+ from [^/]+/(feature/\S+)') {
            $features[$Matches[1]] = "$sha^1..$sha^2"
        }
    }
    Write-Output -NoEnumerate $features
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

function Set-AppVersion([string]$Ver) {
    Set-FileVersion 'package.json'              '(?m)^(\s*"version":\s*")[^"]+(")' $Ver
    Set-FileVersion 'package-lock.json'         '(?m)^(\s*"version":\s*")[^"]+(")' $Ver 2
    Set-FileVersion 'src-tauri/tauri.conf.json' '(?m)^(\s*"version":\s*")[^"]+(")' $Ver
    Set-FileVersion 'src-tauri/Cargo.toml'      '(?m)^(version\s*=\s*")[^"]+(")' $Ver
    Set-FileVersion 'src-tauri/Cargo.lock'      '(name = "tli-sattatracker"\r?\nversion = ")[^"]+(")' $Ver
}

# Rewrites the block between the feature markers in .github/README.md.
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

# Writes docs/releases/release-<version>.md from the features merged into the release.
function New-ReleaseNotes([string]$Ver, $Features) {
    $previous = Get-PreviousReleaseTag $Ver
    $since = @()
    if ($previous) { $since = @("^$previous") }
    $included = @($Features.Keys)

    $lines = @(
        "# Release $Ver", '',
        "- **Type:** $(Get-ReleaseKind $Ver)",
        "- **Date:** $(Get-Date -Format 'yyyy-MM-dd')",
        "- **Based on:** original project ``main`` at $(& git log -1 --format='`%h` %s' main)",
        "- **Previous release:** $(if ($previous) { $previous } else { 'none (first release)' })",
        '', '## Features', ''
    )
    if ($included.Count -eq 0) { $lines += '- No fork features in this release.' }
    foreach ($feature in $included) {
        $info = Get-FeatureInfo $feature
        $lines += "- **$($info.Title)**$(if ($info.Summary) { ": $($info.Summary)" })"
    }
    foreach ($feature in $included) {
        $commits = Get-CommitLines (@($Features[$feature]) + $since)
        $lines += '', "### $((Get-FeatureInfo $feature).Title)", ''
        if ($commits.Count) { $lines += $commits } else { $lines += "- No changes since $previous." }
    }

    if ($previous) {
        $body = (& git log -1 --format=%b --grep "^chore(release): $previous$" $previous) -join "`n"
        if ($body -match 'Features: (.+)') {
            $before = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'none' })
            $removed = @($before | Where-Object { $included -notcontains $_ })
            if ($removed.Count) {
                $lines += '', "## Removed since $previous", ''
                $lines += $removed | ForEach-Object { "- $((Get-FeatureInfo $_).Title) (``$_``)" }
            }
        }
    }

    $tooling = @(Get-CommitLines (@("main..$(Resolve-Branch $ConfigBranch)") + $since) |
        Where-Object { $_ -notmatch '^- docs\(release\): add notes for ' })
    if ($tooling.Count) { $lines += '', '## Release tooling and docs', ''; $lines += $tooling }

    if ($previous) {
        $base = (& git merge-base $previous main).Trim()
        $upstream = Get-CommitLines "$base..main"
        if ($upstream.Count) {
            $lines += '', "## Original project changes since $previous", ''
            $lines += $upstream | Select-Object -First 20
            if ($upstream.Count -gt 20) { $lines += "- ...and $($upstream.Count - 20) more." }
        }
    }

    $path = "docs/releases/release-$Ver.md"
    New-Item -ItemType Directory -Force -Path 'docs/releases' | Out-Null
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $path), (($lines -join "`n") + "`n"), $Utf8NoBom)
    Write-Host "Wrote $path" -ForegroundColor Green
}

# --- Preconditions -----------------------------------------------------------

if (& git status --porcelain) { throw 'Working tree has uncommitted changes. Commit or stash them first.' }

Write-Host "Fetching $UpstreamRemote and $ForkRemote..." -ForegroundColor Cyan
Invoke-Git fetch $UpstreamRemote --prune
Invoke-Git fetch $ForkRemote --prune --tags

if ($Promote) { $Version = $Promote }
if (-not $Version) {
    $configJson = (& git show "$(Resolve-Branch $ConfigBranch):fork/release.json") -join "`n" | ConvertFrom-Json
    $Version = $configJson.version
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 0.2.0 (got '$Version')." }
$tag = "v$Version"
$branch = "release/$Version"

# --- Start ---------------------------------------------------------------------

if ($Start) {
    if (Test-Git rev-parse --verify --quiet "refs/tags/$tag") { throw "Tag $tag already exists." }
    if (Test-Git rev-parse --verify --quiet "refs/heads/$branch") { throw "Branch $branch already exists locally." }
    if (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$branch") { throw "Branch $branch already exists on $ForkRemote." }

    if (-not (Test-Git merge-base --is-ancestor main "$UpstreamRemote/main")) {
        throw "main has commits that are not in $UpstreamRemote/main. main must stay an exact copy of the original project."
    }
    Invoke-Git checkout --quiet main
    Invoke-Git merge --ff-only --quiet "$UpstreamRemote/main"
    Write-Host "main is at $(& git log -1 --format='%h %s' main)" -ForegroundColor Cyan

    $base = 'main'
    if (Test-ReadyFix $Version) {
        # A fix to a ready version starts from the previous release of that line, so work
        # in progress for the next pre-major build can't slip in.
        $parts = $Version.Split('.')
        $base = Get-PreviousReleaseTag $Version "v$($parts[0]).0.*"
        if (-not $base) { throw "No earlier v$($parts[0]).0.x release to base the fix $Version on." }
        Write-Host "Ready fix: starting from $base instead of main." -ForegroundColor Yellow
    }

    Invoke-Git checkout --quiet -b $branch $base
    & git merge --no-ff --no-edit -m "chore(release): add $ConfigBranch to $tag" (Resolve-Branch $ConfigBranch) | Out-Host
    if ($LASTEXITCODE -ne 0) {
        & git merge --abort | Out-Host
        & git checkout --quiet main | Out-Host
        & git branch -D $branch | Out-Null
        throw "$ConfigBranch conflicts with $base. Rebase $ConfigBranch on main, then try again."
    }
    Set-AppVersion $Version
    Invoke-Git add -A
    Invoke-Git commit --quiet -m "chore(release): start $tag"
    Write-Host "Created $branch from $base with version $Version." -ForegroundColor Green

    if ($NoPush) { Write-Host 'Not pushed (-NoPush).'; return }
    Invoke-Git push --quiet -u $ForkRemote $branch
    Write-Host "Pushed $branch. Add features with:  .\scripts\release.ps1 -AddFeature feature/<name>" -ForegroundColor Green
    return
}

# --- Add a feature -------------------------------------------------------------

if ($AddFeature) {
    if ($AddFeature -notmatch '^feature/') { throw "Feature branches are named feature/<name> (got '$AddFeature')." }
    if (-not (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$branch")) { throw "$branch is not on $ForkRemote. Run -Start first." }
    if (-not (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$AddFeature")) { throw "$AddFeature is not on $ForkRemote. Push it first." }
    if (-not (Test-Git merge-base --is-ancestor main "$ForkRemote/$AddFeature")) {
        Write-Host "Note: $AddFeature is not rebased on the latest main. Rebase it first if the pull request shows conflicts." -ForegroundColor Yellow
    }
    $info = Get-FeatureInfo $AddFeature
    $body = "Adds $AddFeature to $tag.$(if ($info.Summary) { "`n`n$($info.Summary)" })"
    Open-PullRequest $branch $AddFeature "Add $($info.Title) to $tag" $body
    return
}

# --- Finish --------------------------------------------------------------------

if ($Finish) {
    if (-not (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$branch") -and
        -not (Test-Git rev-parse --verify --quiet "refs/heads/$branch")) { throw "$branch doesn't exist. Run -Start first." }
    if (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$branch") {
        Switch-ToForkBranch $branch
    } else {
        Invoke-Git checkout --quiet $branch
    }

    $features = Get-MergedFeatures
    Write-Host "Features in ${branch}: $(if ($features.Count) { @($features.Keys) -join ', ' } else { 'none' })" -ForegroundColor Cyan
    Update-ReadmeFeatures @($features.Keys)
    New-ReleaseNotes $Version $features

    Invoke-Git add -A
    $featureList = if ($features.Count) { @($features.Keys) -join ', ' } else { 'none' }
    Invoke-Git commit --quiet --allow-empty -m "chore(release): $tag" -m "Features: $featureList"
    Write-Host "Committed release notes for $tag." -ForegroundColor Green

    if (-not $SkipChecks) {
        Write-Host 'Checks: npm ci, type-check, front-end build' -ForegroundColor Cyan
        Invoke-Checked 'npm' @('ci', '--no-audit', '--no-fund')
        Invoke-Checked 'npx' @('vue-tsc', '--noEmit')
        Invoke-Checked 'npx' @('vite', 'build')
        if ($CargoCheck) { Invoke-Checked 'cargo' @('check', '--manifest-path', 'src-tauri/Cargo.toml') }
        if (& git status --porcelain) { throw 'The checks changed tracked files; review them before publishing.' }
    }

    if ($NoPush) { Write-Host 'Not pushed (-NoPush).'; return }
    Invoke-Git push --quiet $ForkRemote $branch
    $body = "$(Get-ReleaseKind $Version). Features: $featureList`n`n" +
            "Release notes: ``docs/releases/release-$Version.md```n`n" +
            "Claude reviews this release. When the claude-verdict check passes, run " +
            "``.\scripts\release.ps1 -Promote $Version``. Do not press Merge: the release replaces stable, it is not merged into it."
    Open-PullRequest 'stable' $branch "Release $tag" $body
    Write-Host "When claude-verdict passes:  .\scripts\release.ps1 -Promote $Version" -ForegroundColor Green
    return
}

# --- Promote -------------------------------------------------------------------

if (Test-Git rev-parse --verify --quiet "refs/tags/$tag") { throw "Tag $tag already exists." }
if (-not (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$branch")) { throw "$branch is not on $ForkRemote. Run -Finish first." }

# Fixes pushed during review (e.g. by Claude Auto-fix) are on the fork's copy.
Switch-ToForkBranch $branch
$sha = (& git rev-parse HEAD).Trim()
$repo = Get-GitHubRepo

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$checks = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/$sha/check-runs?check_name=claude-verdict" `
    -Headers @{ 'User-Agent' = 'fork-release-script'; 'Accept' = 'application/vnd.github+json' }
$check = $checks.check_runs | Sort-Object started_at -Descending | Select-Object -First 1
if (-not $check) { throw "No claude-verdict check on $sha. Is the pull request $branch -> stable open, and has the review run?" }
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
# 'stable' points to the latest release; moving it also marks the release pull request as merged.
Invoke-Git push --force $ForkRemote "${branch}:refs/heads/stable"
Write-Host "Tagged $tag (the GitHub workflow is building the installers) and moved stable to $branch." -ForegroundColor Green

# Keep every release's notes on the config branch, so later releases carry the history.
$notes = "docs/releases/release-$Version.md"
if (Test-Git cat-file -e "HEAD:$notes") {
    Switch-ToForkBranch $ConfigBranch
    Invoke-Git checkout $branch -- $notes
    Invoke-Git commit --quiet -m "docs(release): add notes for $tag"
    Invoke-Git push --quiet $ForkRemote $ConfigBranch
    Write-Host "Copied $notes to $ConfigBranch." -ForegroundColor Green
}
