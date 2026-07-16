$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    $env:CODEX_HOME
} else {
    Join-Path $env:USERPROFILE '.codex'
}
$bootstrapCapture = Join-Path $codexHome 'skills\project-context-bootstrap\scripts\capture-accepted-change.ps1'
if (-not (Test-Path -LiteralPath $bootstrapCapture)) {
    throw "Global project-context accepted-change script not found: $bootstrapCapture"
}
$engine = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
& $engine -NoProfile -ExecutionPolicy Bypass -File $bootstrapCapture -Path $projectRoot @args
exit $LASTEXITCODE
