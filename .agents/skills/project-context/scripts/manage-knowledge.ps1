$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$codexHome = if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$globalScript = Join-Path $codexHome 'skills\project-context-bootstrap\scripts\manage-project-knowledge.ps1'
if (-not (Test-Path -LiteralPath $globalScript)) { throw "Global project-context knowledge management script not found: $globalScript" }
$engine = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
& $engine -NoProfile -ExecutionPolicy Bypass -File $globalScript -Path $projectRoot @args
exit $LASTEXITCODE
