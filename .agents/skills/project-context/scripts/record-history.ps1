$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).ProviderPath
$codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    $env:CODEX_HOME
} else {
    Join-Path $env:USERPROFILE '.codex'
}
$bootstrapRecord = Join-Path $codexHome 'skills\project-context-bootstrap\scripts\record-project-history.ps1'
if (-not (Test-Path -LiteralPath $bootstrapRecord)) {
    throw "Global project-context history script not found: $bootstrapRecord"
}
$engine = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
& $engine -NoProfile -ExecutionPolicy Bypass -File $bootstrapRecord -Path $projectRoot @args
exit $LASTEXITCODE
