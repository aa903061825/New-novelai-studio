param(
  [int]$DelayMs = 12000,
  [int]$RetryCount = 20,
  [int]$RetryDelayMs = 30000
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'strict-artist-generation.log'

Set-Location $repoRoot
Set-Content -Path $logPath -Encoding utf8 -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] STRICT ARTIST PREVIEW GENERATION START"

& dart run tool\nai_asset_library_generate.dart `
  '--queue=tool\asset-library-strict-artist-preview-queue.json' `
  '--limit=9999' `
  "--delay-ms=$DelayMs" `
  "--retry-count=$RetryCount" `
  "--retry-delay-ms=$RetryDelayMs" *> $logPath

$exitCode = $LASTEXITCODE
Add-Content -Path $logPath -Encoding utf8 -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] STRICT ARTIST PREVIEW GENERATION EXIT $exitCode"
exit $exitCode
