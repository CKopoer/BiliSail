param([string]$Destination = 'artifacts/windows-x64/diagnostics')
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = [IO.Path]::GetFullPath((Join-Path $repoRoot $Destination))
if (!$output.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Diagnostics must stay inside the workspace.'
}
New-Item -ItemType Directory -Path $output -Force | Out-Null
$sensitive = @(Get-ChildItem Env: | Where-Object {
  $_.Name -match 'TOKEN|SECRET|PASSWORD|CREDENTIAL|COOKIE|CERTIFICATE|PRIVATE_KEY|KEYSTORE' -and $_.Value.Length -ge 4
} | Sort-Object { $_.Value.Length } -Descending)
$hooks = Join-Path $repoRoot '.dart_tool/hooks_runner'
if (Test-Path -LiteralPath $hooks) {
  Get-ChildItem -LiteralPath $hooks -Recurse -File | Where-Object {
    $_.Name -in @('stdout.txt', 'stderr.txt', 'input.json', 'output.json')
  } | ForEach-Object {
    $text = [IO.File]::ReadAllText($_.FullName)
    foreach ($entry in $sensitive) { $text = $text.Replace($entry.Value, '[REDACTED]') }
    $text = [regex]::Replace($text, '(?i)(https?://[^\s"''?]+)\?[^\s"'']+', '$1?[REDACTED]')
    $relative = [IO.Path]::GetRelativePath($hooks, $_.FullName)
    $target = Join-Path $output $relative
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
    [IO.File]::WriteAllText($target, $text)
    Write-Host "Collected native build diagnostics: $relative"
    if ($_.Name -eq 'stderr.txt' -and $text.Trim()) { Write-Host $text }
  }
}
Get-Command tar, dart, flutter, cmake -All -ErrorAction SilentlyContinue |
  Select-Object Name, Source | Format-Table | Out-String |
  Set-Content -LiteralPath (Join-Path $output 'tools.txt')
