$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).ProviderPath
$codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    $env:CODEX_HOME
} else {
    Join-Path $env:USERPROFILE '.codex'
}
$bootstrapReview = Join-Path $codexHome 'skills\project-context-bootstrap\scripts\review-project-history-cleanup.ps1'
if (-not (Test-Path -LiteralPath $bootstrapReview)) {
    throw "Global project-context history cleanup review script not found: $bootstrapReview"
}
$engine = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
& $engine -NoProfile -ExecutionPolicy Bypass -File $bootstrapReview -Path $projectRoot @args
exit $LASTEXITCODE
