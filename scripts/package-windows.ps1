param(
    [string]$ReleaseDirectory = (Join-Path $PSScriptRoot '..\apps\client\build\windows\x64\runner\Release'),
    [string]$Destination = (Join-Path $PSScriptRoot '..\apps\client\build\reelnest-windows-x64.zip')
)
$ErrorActionPreference = 'Stop'
$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDirectory 'reelnest.exe')) -or
    -not (Test-Path -LiteralPath (Join-Path $ReleaseDirectory 'data\app.so'))) {
    throw 'Build the production Windows Release before packaging.'
}
# Runtime allowlist: never publish portable configuration, credentials, cache,
# logs, temporary files, debug symbols or import staging folders.
$payload = @(Get-ChildItem -LiteralPath $ReleaseDirectory | Where-Object {
    ($_.PSIsContainer -and $_.Name -eq 'data') -or
    (-not $_.PSIsContainer -and ($_.Name -eq 'reelnest.exe' -or $_.Extension -eq '.dll'))
} | Select-Object -ExpandProperty FullName)
$destinationParent = Split-Path -Parent ([IO.Path]::GetFullPath($Destination))
New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
if (Test-Path -LiteralPath $Destination) { throw 'Archive already exists; use a new destination.' }
Compress-Archive -LiteralPath $payload -DestinationPath $Destination -CompressionLevel Optimal
Get-Item -LiteralPath $Destination | Select-Object Name,Length
