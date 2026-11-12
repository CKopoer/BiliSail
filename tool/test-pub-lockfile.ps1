$ErrorActionPreference = 'Stop'
# Exercise the actual check helper with a controlled Pub command. Strict Pub
# accepts quoted Git refs; ordinary Pub can still rewrite their YAML spelling.
$ast = [Management.Automation.Language.Parser]::ParseFile(
  (Join-Path $PSScriptRoot 'check.ps1'), [ref]$null, [ref]$null)
$helper = @($ast.FindAll({
  param($node)
  $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-PubCheck'
}, $true))
if ($helper.Count -ne 1) { throw 'Expected one production Pub check helper.' }
. ([scriptblock]::Create($helper[0].Extent.Text))

function Invoke-Check([string]$Executable, [string[]]$Parameters) {
  $command = $Parameters -join ' '
  $script:pubCommands.Add("$Executable $command")
  if ($script:rejectStrict -and $command -eq 'pub get --enforce-lockfile') {
    throw 'Fixture strict resolution rejected.'
  }
  if ($script:rewrite -and $command -eq 'pub get') {
    [IO.File]::WriteAllText((Join-Path $PWD 'pubspec.lock'), "ref: eaae0273`n")
  }
}

$directory = Join-Path ([IO.Path]::GetTempPath()) "bilisail-pub-lock-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $directory | Out-Null
$cases = @(
  @{ Runner = 'flutter'; Lint = $true; Strict = $true; Rewrite = $false; RejectStrict = $false; Calls = 2; Error = $null },
  @{ Runner = 'dart'; Lint = $true; Strict = $true; Rewrite = $false; RejectStrict = $false; Calls = 2; Error = $null },
  @{ Runner = 'flutter'; Lint = $true; Strict = $true; Rewrite = $true; RejectStrict = $false; Calls = 2; Error = 'pub get changed pubspec.lock' },
  @{ Runner = 'dart'; Lint = $true; Strict = $true; Rewrite = $false; RejectStrict = $true; Calls = 1; Error = 'Fixture strict resolution rejected' },
  @{ Runner = 'flutter'; Lint = $false; Strict = $true; Rewrite = $true; RejectStrict = $false; Calls = 1; Error = $null },
  @{ Runner = 'dart'; Lint = $true; Strict = $false; Rewrite = $true; RejectStrict = $false; Calls = 1; Error = $null }
)
Push-Location $directory
try {
  foreach ($case in $cases) {
    [IO.File]::WriteAllText((Join-Path $directory 'pubspec.lock'), "ref: `"eaae0273`"`n")
    $runLint = $case.Lint
    $EnforceLockfile = $case.Strict
    $script:rewrite = $case.Rewrite
    $script:rejectStrict = $case.RejectStrict
    $script:pubCommands = [Collections.Generic.List[string]]::new()
    $parameters = @('pub', 'get')
    if ($EnforceLockfile) { $parameters += '--enforce-lockfile' }
    $message = $null
    try { Invoke-PubCheck $case.Runner $parameters } catch { $message = $_.Exception.Message }
    if ($script:pubCommands.Count -ne $case.Calls -or
        ($case.Error -and (!$message -or !$message.Contains($case.Error))) -or
        (!$case.Error -and $message)) {
      throw "Unexpected Pub guard behavior: commands=$($script:pubCommands -join ', '); error=$message"
    }
    if ($script:pubCommands[0] -cne "$($case.Runner) $($parameters -join ' ')") {
      throw 'The Pub check changed the requested runner or resolution mode.'
    }
  }
} finally {
  Pop-Location
  Remove-Item -LiteralPath $directory -Recurse -Force
}
Write-Output "Pub lockfile checks passed: $($cases.Count)"
