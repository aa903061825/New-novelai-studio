$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$bootstrapDoctor = Join-Path $env:USERPROFILE '.codex\skills\project-context-bootstrap\scripts\doctor-project-context.ps1'
if (-not (Test-Path -LiteralPath $bootstrapDoctor)) {
    throw "Global project-context doctor script not found: $bootstrapDoctor"
}
& powershell -ExecutionPolicy Bypass -File $bootstrapDoctor -Path $projectRoot
