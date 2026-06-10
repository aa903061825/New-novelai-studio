param(
  [int]$DelayMs = 12000,
  [int]$RetryCount = 20,
  [int]$RetryDelayMs = 30000
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$logPath = Join-Path $PSScriptRoot 'strict-nai-generation.log'

Set-Location $repoRoot

function Write-LogLine {
  param([string]$Message)
  $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  "[$stamp] $Message" | Tee-Object -FilePath $logPath -Append
}

function Invoke-Queue {
  param([string]$QueuePath)

  Write-LogLine "START queue=$QueuePath"
  & dart run tool\nai_asset_library_generate.dart `
    "--queue=$QueuePath" `
    "--limit=9999" `
    "--delay-ms=$DelayMs" `
    "--retry-count=$RetryCount" `
    "--retry-delay-ms=$RetryDelayMs" 2>&1 |
    Tee-Object -FilePath $logPath -Append

  if ($LASTEXITCODE -ne 0) {
    throw "NAI generator failed for $QueuePath with exit code $LASTEXITCODE"
  }

  Write-LogLine "DONE queue=$QueuePath"
}

Set-Content -Path $logPath -Value ''
Write-LogLine "STRICT NAI GENERATION START"
Invoke-Queue 'tool\asset-library-strict-character-queue.json'
Invoke-Queue 'tool\asset-library-strict-artist-preview-queue.json'
Write-LogLine "STRICT NAI GENERATION COMPLETE"
