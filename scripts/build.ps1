param(
    [string]$Go = 'go',
    [string[]]$Targets = @(),
    [switch]$All
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$allowed = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'targets.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($All -or $Targets.Count -eq 0) { $Targets = $allowed }
foreach ($target in $Targets) { if ($target -notin $allowed) { throw "Unsupported target: $target" } }
$previous = @{}
foreach ($name in @('GOOS','GOARCH','GOARM','CGO_ENABLED','GOFLAGS')) { $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
Push-Location $projectRoot
function Invoke-Go([string[]]$GoArgs) { & $Go @GoArgs; if ($LASTEXITCODE -ne 0) { throw "Go failed: $($GoArgs -join ' ')" } }
try {
    $dist = Join-Path $projectRoot 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    foreach ($target in $Targets) {
        $parts = $target.Split('-')
        $targetOS = $parts[0]
        $targetArch = $parts[1]
        $env:GOOS = $targetOS
        $env:GOARCH = if ($targetArch -eq 'armv7') { 'arm' } else { $targetArch }
        $env:GOARM = if ($targetArch -eq 'armv7') { '7' } else { '' }
        $env:CGO_ENABLED = '0'
        $env:GOFLAGS = '-buildvcs=false'
        $suffix = if ($targetOS -eq 'windows') { '.exe' } else { '' }
        $binary = Join-Path $dist "openflux-$target$suffix"
        Write-Host "Building $target -> $binary"
        Invoke-Go @('build','-C','core','-trimpath','-ldflags=-s -w','-o',$binary,'.')
        $hashStream = [IO.File]::OpenRead($binary)
        $hasher = [Security.Cryptography.SHA256]::Create()
        try {
            $binaryHash = [BitConverter]::ToString($hasher.ComputeHash($hashStream)).Replace('-', '').ToLowerInvariant()
        } finally {
            $hashStream.Dispose()
            $hasher.Dispose()
        }
        $checksumLine = $binaryHash + '  ' + (Split-Path -Leaf $binary) + "`n"
        [IO.File]::WriteAllText("$binary.sha256", $checksumLine, [Text.Encoding]::ASCII)

        if ($targetOS -eq 'linux' -and ($targetArch -eq 'amd64' -or $targetArch -eq 'arm64')) {
            $opensub = Join-Path $dist "opensub-$target"
            Write-Host "Building $opensub"
            Invoke-Go @('build','-C','core','-trimpath','-ldflags=-s -w','-o',$opensub,'./cmd/opensub')
            $hashStream = [IO.File]::OpenRead($opensub)
            $hasher = [Security.Cryptography.SHA256]::Create()
            try {
                $opensubHash = [BitConverter]::ToString($hasher.ComputeHash($hashStream)).Replace('-', '').ToLowerInvariant()
            } finally {
                $hashStream.Dispose()
                $hasher.Dispose()
            }
            $opensubLine = $opensubHash + '  ' + (Split-Path -Leaf $opensub) + "`n"
            [IO.File]::WriteAllText("$opensub.sha256", $opensubLine, [Text.Encoding]::ASCII)
        }
    }
} finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
    Pop-Location
}
