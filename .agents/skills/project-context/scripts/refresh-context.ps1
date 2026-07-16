$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    $env:CODEX_HOME
} else {
    Join-Path $env:USERPROFILE '.codex'
}
$bootstrapRefresh = Join-Path $codexHome 'skills\project-context-bootstrap\scripts\refresh-project-context.ps1'
if (-not (Test-Path -LiteralPath $bootstrapRefresh)) {
    throw "Global project-context refresh script not found: $bootstrapRefresh"
}
$engine = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
& $engine -NoProfile -ExecutionPolicy Bypass -File $bootstrapRefresh -Path $projectRoot @args
exit $LASTEXITCODE
