# Public identity confirmed in Microsoft Partner Center. Never derive it from
# a signing certificate or an environment override.
function Confirm-WindowsMsixIdentity([xml]$Manifest, [string]$Version, [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64') {
  $identity = $Manifest.Package.Identity
  $displayName = $Manifest.Package.Properties.PublisherDisplayName
  if ($identity.Name -cne 'JerryHsu.BiliSail' -or
      $identity.Publisher -cne 'CN=D34F8E82-088B-4DC8-9296-620B8683A539' -or
      $displayName -cne 'Jerry Hsu') {
    throw 'MSIX identity must match Partner Center: JerryHsu.BiliSail, CN=D34F8E82-088B-4DC8-9296-620B8683A539, Jerry Hsu.'
  }
  if ($identity.Version -cne $Version.Replace('+', '.')) {
    throw 'Packaged MSIX version does not match the requested version.'
  }
  if ($identity.ProcessorArchitecture -cne $Architecture) {
    throw 'Packaged MSIX architecture does not match the requested target.'
  }
  return [ordered]@{
    name = [string]$identity.Name
    publisher = [string]$identity.Publisher
    publisherDisplayName = [string]$displayName
    version = [string]$identity.Version
    architecture = [string]$identity.ProcessorArchitecture
  }
}

function Get-WindowsMsixFamilyName([string]$Name, [string]$Publisher) {
  if (!$IsWindows) { throw 'PackageFamilyNameFromId requires Windows.' }
  if (!('BiliSailPackageIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class BiliSailPackageIdentity {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct PackageId {
    public uint Reserved;
    public uint ProcessorArchitecture;
    public ulong Version;
    [MarshalAs(UnmanagedType.LPWStr)] public string Name;
    [MarshalAs(UnmanagedType.LPWStr)] public string Publisher;
    [MarshalAs(UnmanagedType.LPWStr)] public string ResourceId;
    [MarshalAs(UnmanagedType.LPWStr)] public string PublisherId;
  }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
  private static extern int PackageFamilyNameFromId(ref PackageId id, ref uint length, StringBuilder familyName);
  public static string GetFamilyName(string name, string publisher) {
    var id = new PackageId { Name = name, Publisher = publisher, ProcessorArchitecture = 9 };
    var result = new StringBuilder(256);
    uint length = (uint)result.Capacity;
    int error = PackageFamilyNameFromId(ref id, ref length, result);
    if (error != 0) throw new System.ComponentModel.Win32Exception(error);
    return result.ToString();
  }
}
'@
  }
  return [BiliSailPackageIdentity]::GetFamilyName($Name, $Publisher)
}

function Confirm-WindowsMsixSignature([string]$Package, [string]$ExpectedThumbprint) {
  Add-Type -AssemblyName System.Security.Cryptography.Pkcs
  $archive = [System.IO.Compression.ZipFile]::OpenRead($Package)
  try {
    $entry = $archive.GetEntry('AppxSignature.p7x')
    if (!$entry) { throw 'MSIX signature is missing.' }
    $stream = $entry.Open()
    $buffer = [System.IO.MemoryStream]::new()
    try { $stream.CopyTo($buffer); $bytes = $buffer.ToArray() }
    finally { $stream.Dispose(); $buffer.Dispose() }
    if ($bytes.Length -le 4 -or [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4) -cne 'PKCX') {
      throw 'MSIX signature header is invalid.'
    }
    $cms = [System.Security.Cryptography.Pkcs.SignedCms]::new()
    $cms.Decode([byte[]]$bytes[4..($bytes.Length - 1)])
    # Check cryptographic validity without changing machine certificate trust.
    $cms.CheckSignature($true)
    if ($cms.SignerInfos.Count -ne 1 -or $cms.SignerInfos[0].Certificate.Thumbprint -cne $ExpectedThumbprint) {
      throw 'MSIX signer does not match the selected signing certificate.'
    }
    Write-Output 'Verified MSIX CMS signature and signer certificate (system trust not asserted).' | Out-Host
  } finally { $archive.Dispose() }
}
