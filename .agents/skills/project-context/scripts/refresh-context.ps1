$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$bootstrapRefresh = Join-Path $env:USERPROFILE '.codex\skills\project-context-bootstrap\scripts\refresh-project-context.ps1'
if (-not (Test-Path -LiteralPath $bootstrapRefresh)) {
    throw "Global project-context refresh script not found: $bootstrapRefresh"
}
& powershell -ExecutionPolicy Bypass -File $bootstrapRefresh -Path $projectRoot
