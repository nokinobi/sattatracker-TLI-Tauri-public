<#
.SYNOPSIS
    Builds a fork release branch: the author's latest main + the features listed in
    fork/release.json + the fork/release-config branch. See docs/fork/RELEASING.md.

.EXAMPLE
    .\scripts\release.ps1
    Builds release/<version> locally and runs the checks. Nothing is pushed.

.EXAMPLE
    .\scripts\release.ps1 -Publish
    Same, then pushes the branch, tags v<version> (this starts the GitHub build)
    and moves 'stable' to the new release.

.EXAMPLE
    .\scripts\release.ps1 -PreRelease 1 -Publish
    Test build: version <version>-1, branch release/<version>-rc.1, tag v<version>-rc.1.
    Published as a GitHub pre-release; 'stable' is not moved.
#>
param(
    [switch]$Publish,
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

$configRef = Resolve-Branch $ConfigBranch
$config = (& git show "${configRef}:fork/release.json") -join "`n" | ConvertFrom-Json
if ($config.version -notmatch '^\d+\.\d+\.\d+$') { throw "fork/release.json: version must look like 2.1.0 (got '$($config.version)')." }

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
    Write-Host "To publish this build:"
    Write-Host "  git push $ForkRemote ${branch}"
    Write-Host "  git tag $tag; git push $ForkRemote $tag"
    if ($PreRelease -eq 0) { Write-Host "  git push --force $ForkRemote ${branch}:refs/heads/stable" }
    return
}

Invoke-Git push $ForkRemote $branch
Invoke-Git tag $tag
Invoke-Git push $ForkRemote $tag
if ($PreRelease -eq 0) {
    # 'stable' is a pointer to the latest release, not a branch anyone commits to.
    Invoke-Git push --force $ForkRemote "${branch}:refs/heads/stable"
    Write-Host "stable now points to $branch" -ForegroundColor Green
}
Write-Host "Pushed $branch and $tag. The GitHub workflow is building the release." -ForegroundColor Green
