[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ReleaseDir = 'dist',
    [string]$Go = 'go',
    [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$targets = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'targets.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$releasePath = if ([IO.Path]::IsPathRooted($ReleaseDir)) { [IO.Path]::GetFullPath($ReleaseDir) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $ReleaseDir)) }

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') -Go $Go -All
    [IO.Directory]::CreateDirectory($releasePath) | Out-Null
    $inputPath = Join-Path $projectRoot 'dist'
} else {
    $inputPath = $releasePath
}
if (-not (Test-Path -LiteralPath $releasePath -PathType Container)) {
    throw "Release directory not found: $releasePath"
}

$assets = @()
$checksums = @()
foreach ($target in $targets) {
    $suffix = if ($target.StartsWith('windows-')) { '.exe' } else { '' }
    $asset = "openflux-$target$suffix"
    $binary = Join-Path $inputPath $asset
    $sidecar = "$binary.sha256"
    foreach ($path in @($binary, $sidecar)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
            throw "Missing binary or SHA-256: $asset"
        }
    }
    $expected = [IO.File]::ReadAllText($sidecar).Trim()
    if ($expected -notmatch '^([0-9a-fA-F]{64}) [ *](.+)$') {
        throw "Invalid SHA-256 file: $asset"
    }
    $expectedHash = $Matches[1]
    if ($Matches[2] -cne $asset) { throw "Invalid SHA-256 filename: $asset" }
    $hashStream = [IO.File]::OpenRead($binary)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $actualHash = [BitConverter]::ToString($hasher.ComputeHash($hashStream)).Replace('-', '').ToLowerInvariant()
    } finally {
        $hashStream.Dispose()
        $hasher.Dispose()
    }
    if ($actualHash -ne $expectedHash) { throw "Binary SHA-256 mismatch: $asset" }
    $assets += $asset
    $checksums += "$actualHash  $asset"

    $opensubAsset = "opensub-$target"
    $opensubPath = Join-Path $inputPath $opensubAsset
    $opensubSidecar = "$opensubPath.sha256"
    if (Test-Path -LiteralPath $opensubPath -PathType Leaf) {
        $expectedSub = [IO.File]::ReadAllText($opensubSidecar).Trim()
        if ($expectedSub -notmatch '^([0-9a-fA-F]{64}) [ *](.+)$') {
            throw "Invalid SHA-256 file: $opensubAsset"
        }
        $expectedSubHash = $Matches[1]
        $hashStreamSub = [IO.File]::OpenRead($opensubPath)
        $hasherSub = [Security.Cryptography.SHA256]::Create()
        try {
            $actualSubHash = [BitConverter]::ToString($hasherSub.ComputeHash($hashStreamSub)).Replace('-', '').ToLowerInvariant()
        } finally {
            $hashStreamSub.Dispose()
            $hasherSub.Dispose()
        }
        if ($actualSubHash -ne $expectedSubHash) { throw "Binary SHA-256 mismatch: $opensubAsset" }
        $assets += $opensubAsset
        $checksums += "$actualSubHash  $opensubAsset"
    }
}

if ($inputPath -ne $releasePath) {
    foreach ($asset in $assets) {
        [IO.File]::Copy((Join-Path $inputPath $asset), (Join-Path $releasePath $asset), $true)
        [IO.File]::Copy((Join-Path $inputPath "$asset.sha256"), (Join-Path $releasePath "$asset.sha256"), $true)
    }
}
[IO.File]::WriteAllText((Join-Path $releasePath 'SHA256SUMS.txt'), ($checksums -join "`n") + "`n", [Text.Encoding]::ASCII)
Write-Host "Release ready: $($assets.Count) binaries, individual SHA-256 files and SHA256SUMS.txt in $releasePath."
