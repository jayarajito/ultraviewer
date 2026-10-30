# Invalidate Flutter's compiled flutter_tools snapshot so our edit to
# visual_studio.dart (VS 2026 generator mapping) takes effect on next run.
$repo = Split-Path -Parent $PSScriptRoot
$fRoot = Join-Path $repo 'tools\flutter-3.24.5\flutter'
$stamp = Join-Path $fRoot 'bin\cache\flutter_tools.stamp'
$snap  = Join-Path $fRoot 'bin\cache\flutter_tools.snapshot'
foreach ($f in @($stamp, $snap)) {
    if (Test-Path $f) { Remove-Item $f -Force; Write-Output "removed $f" }
    else { Write-Output "absent  $f" }
}
Write-Output "done"
