$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    $env:CODEX_HOME
} else {
    Join-Path $env:USERPROFILE '.codex'
}
$bootstrapDoctor = Join-Path $codexHome 'skills\project-context-bootstrap\scripts\doctor-project-context.ps1'
if (-not (Test-Path -LiteralPath $bootstrapDoctor)) {
    throw "Global project-context doctor script not found: $bootstrapDoctor"
}
$engine = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
& $engine -NoProfile -ExecutionPolicy Bypass -File $bootstrapDoctor -Path $projectRoot @args
exit $LASTEXITCODE
