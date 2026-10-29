# Synthetic subprocess for the cross-platform release-supervisor regression.
# No application, account or platform Keychain is used here.
$scenario = $args[0]
$phase = $args[2]
$runId = $args[3]
$marker = "BILISAIL_RELEASE_SMOKE_OK:${phase}:$runId"

function Write-DartEntry {
  [Console]::Error.WriteLine('BILISAIL_RELEASE_STAGE:dart-entry')
}

switch ($scenario) {
  'slow-launch' { Start-Sleep -Milliseconds 1200 }
  'launch-timeout' { Start-Sleep -Seconds 6; exit 0 }
  'native-hang' {
    [Console]::Error.WriteLine('BILISAIL_NATIVE_STAGE:plugins-register')
    Start-Sleep -Seconds 6
    exit 0
  }
  'no-entry' { [Console]::Out.WriteLine($marker); exit 0 }
}
Write-DartEntry
switch ($scenario) {
  'probe-timeout' {
    [Console]::Error.WriteLine('BILISAIL_CREDENTIAL_STAGE:deleted')
    Start-Sleep -Seconds 6
  }
  'duplicate-entry' {
    Start-Sleep -Milliseconds 700
    Write-DartEntry
    Start-Sleep -Milliseconds 700
  }
  'failure' { [Console]::Error.WriteLine('native private https://example.invalid/?token=private'); exit 7 }
  'missing-ack' { exit 0 }
  'stderr-ack' { [Console]::Error.WriteLine($marker); exit 0 }
  'flood' {
    $nativeLine = 'native private https://example.invalid/?token=private ' + ('x' * 128)
    for ($index = 0; $index -lt 1024; $index++) {
      [Console]::Out.WriteLine($nativeLine)
      [Console]::Error.WriteLine($nativeLine)
    }
  }
}
[Console]::Error.WriteLine('BILISAIL_CREDENTIAL_STAGE:deleted')
[Console]::Out.WriteLine($marker)
