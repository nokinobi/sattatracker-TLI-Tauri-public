<#
.SYNOPSIS
    Builds a fork release branch: the author's latest main + the features listed in
    fork/release.json + the fork/release-config branch. See docs/fork/RELEASING.md.

.EXAMPLE
    .\scripts\release.ps1
    Builds release/<version> locally and runs the checks. Nothing is pushed.

.EXAMPLE
    .\scripts\release.ps1 -Publish
    Same, then pushes the branch and opens a pull request into 'stable', where Claude
    reviews it (claude-code-review.yml). Nothing is tagged yet.

.EXAMPLE
    .\scripts\release.ps1 -Promote 2.1.0
    After the claude-verdict check passed on the pull request: tags v2.1.0 (this starts
    the GitHub build of the installers) and moves 'stable' to release/2.1.0.

.EXAMPLE
    .\scripts\release.ps1 -PreRelease 1 -Publish
    Test build: version <version>-1, branch release/<version>-rc.1, tag v<version>-rc.1.
    Published right away as a GitHub pre-release, without review; 'stable' is not moved.
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
        $slug = $feature -replace '^feature/', ''
        $doc = "docs/features/$slug.md"
        $title = $slug
        $summary = ''
        if (Test-Path $doc) {
            $content = Get-Content $doc -Encoding UTF8
            $heading = $content | Where-Object { $_ -match '^# ' } | Select-Object -First 1
            if ($heading) { $title = $heading -replace '^# ', '' }
            $first = $content | Where-Object { $_ -and $_ -notmatch '^(#|!\[|<|>)' } | Select-Object -First 1
            if ($first) { $summary = " - $first" }
            $lines += "- [$title](../$doc)$summary"
        } else {
            $lines += "- $title"
        }
    }
    if ($lines.Count -eq 0) { $lines = @('- No fork features in this release.') }
    $text = [System.IO.File]::ReadAllText($readme)
    $block = "<!-- features:start -->`n" + ($lines -join "`n") + "`n<!-- features:end -->"
    $text = [regex]::Replace($text, '(?s)<!-- features:start -->.*?<!-- features:end -->', { param($m) $block })
    [System.IO.File]::WriteAllText($readme, $text, $Utf8NoBom)
}

# --- Preconditions -----------------------------------------------------------

if (& git status --porcelain) { throw 'Working tree has uncommitted changes. Commit or stash them first.' }

Write-Host "Fetching $UpstreamRemote and $ForkRemote..." -ForegroundColor Cyan
Invoke-Git fetch $UpstreamRemote --prune
Invoke-Git fetch $ForkRemote --prune

# --- Promote a reviewed release ------------------------------------------------

if ($Promote) {
    if ($Promote -notmatch '^\d+\.\d+\.\d+$') { throw "-Promote takes a version like 2.1.0 (got '$Promote')." }
    $tag = "v$Promote"
    $branch = "release/$Promote"
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
    if (-not $check) { throw "No claude-verdict check on $sha. Is the pull request into stable open, and has the review run?" }
    if ($check.status -ne 'completed') { throw "claude-verdict is still running on $sha. Try again when it finishes." }
    if ($check.conclusion -ne 'success') { throw "claude-verdict is '$($check.conclusion)' on $sha. Address the review first: $($check.html_url)" }
    Write-Host "claude-verdict passed on $sha" -ForegroundColor Green

    $releaseCommit = (& git log --grep "^Release $tag$" --format=%H -1)
    if ($releaseCommit) {
        $fixes = & git log --format='  %h %s' "$($releaseCommit.Trim())..HEAD"
        if ($fixes) {
            Write-Host 'Commits added during review. Port them to their feature branch (or fork/release-config), or the next release will not have them:' -ForegroundColor Yellow
            $fixes | ForEach-Object { Write-Host $_ }
        }
    }

    Invoke-Git tag $tag
    Invoke-Git push $ForkRemote $tag
    # 'stable' is a pointer to the latest release; moving it also marks the pull request as merged.
    Invoke-Git push --force $ForkRemote "${branch}:refs/heads/stable"
    Write-Host "Tagged $tag (the GitHub workflow is building the installers) and moved stable to $branch." -ForegroundColor Green
    return
}

$configRef = Resolve-Branch $ConfigBranch
$config = (& git show "${configRef}:fork/release.json") -join "`n" | ConvertFrom-Json
if ($config.version -notmatch '^\d+\.\d+\.\d+$') { throw "fork/release.json: version must look like 2.1.0 (got '$($config.version)')." }
foreach ($feature in $config.features) {
    if ($feature -match '^feature/') { throw "fork/release.json: '$feature' is not a feature branch (names must start with feature/)." }
}

$version = $config.version
$tag = "v$version"
$branch = "release/$version"
if ($PreRelease -gt 0) {
    # MSI installers only accept a numeric pre-release part, so the app version is 2.1.0-1
    # while the tag and branch carry the readable rc suffix.
    $version = "$version-$PreRelease"
    $tag = "v$($config.version)-rc.$PreRelease"
    $branch = "release/$($config.version)-rc.$PreRelease"
}

if (Test-Git rev-parse --verify --quiet "refs/heads/$branch") { throw "Branch $branch already exists locally." }
if (Test-Git rev-parse --verify --quiet "refs/remotes/$ForkRemote/$branch") { throw "Branch $branch already exists on $ForkRemote." }
if (Test-Git rev-parse --verify --quiet "refs/tags/$tag") { throw "Tag $tag already exists." }

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
    & git merge --no-ff --no-edit -m "Release ${tag}: add $Name" $Ref | Out-Host
    if ($LASTEXITCODE -ne 0) {
        & git merge --abort | Out-Host
        & git checkout --quiet main | Out-Host
        & git branch -D $branch | Out-Null
        throw "Merging $Name conflicts with the release. Rebase $Name on main, fix the conflicts there, then run the script again."
    }
    Write-Host "  added $Name" -ForegroundColor Green
    return $true
}

Write-Host "Building $branch ($tag)" -ForegroundColor Cyan
$included = @()
foreach ($feature in $config.features) {
    if (Merge-IntoRelease $feature (Resolve-Branch $feature)) { $included += $feature }
}
Merge-IntoRelease $ConfigBranch $configRef | Out-Null

# --- Version and README --------------------------------------------------------

Set-FileVersion 'package.json'              '(?m)^(\s*"version":\s*")[^"]+(")' $version
Set-FileVersion 'package-lock.json'         '(?m)^(\s*"version":\s*")[^"]+(")' $version 2
Set-FileVersion 'src-tauri/tauri.conf.json' '(?m)^(\s*"version":\s*")[^"]+(")' $version
Set-FileVersion 'src-tauri/Cargo.toml'      '(?m)^(version\s*=\s*")[^"]+(")' $version
Set-FileVersion 'src-tauri/Cargo.lock'      '(name = "tli-sattatracker"\r?\nversion = ")[^"]+(")' $version
Update-ReadmeFeatures $included

Invoke-Git add -A
Invoke-Git commit --quiet -m "Release $tag" -m ("Features: " + ($(if ($included) { $included -join ', ' } else { 'none' })))
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
        Write-Host "To publish it for review:  git push $ForkRemote $branch, then open a pull request $branch -> stable"
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

# Final releases go through Claude's review on a pull request into 'stable'.
$repo = Get-GitHubRepo
$title = "Release $tag"
$body = "Features: $(if ($included) { $included -join ', ' } else { 'none' })`n`n" +
        "Claude reviews this pull request. When the claude-verdict check passes, run " +
        "``.\scripts\release.ps1 -Promote $($config.version)``. Do not press Merge: the release replaces stable, it is not merged into it."
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
    & gh pr create --repo $repo --base stable --head $branch --title $title --body $body
    if ($LASTEXITCODE -ne 0) { throw 'gh pr create failed.' }
} else {
    Write-Host "Open the pull request (title: $title):" -ForegroundColor Cyan
    Write-Host "  https://github.com/$repo/compare/stable...$($branch)?expand=1"
}
Write-Host "When claude-verdict passes:  .\scripts\release.ps1 -Promote $($config.version)" -ForegroundColor Green
