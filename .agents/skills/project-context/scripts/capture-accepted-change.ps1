$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$bootstrapCapture = Join-Path $env:USERPROFILE '.codex\skills\project-context-bootstrap\scripts\capture-accepted-change.ps1'
if (-not (Test-Path -LiteralPath $bootstrapCapture)) {
    throw "Global project-context accepted-change script not found: $bootstrapCapture"
}
& powershell -ExecutionPolicy Bypass -File $bootstrapCapture -Path $projectRoot @args
