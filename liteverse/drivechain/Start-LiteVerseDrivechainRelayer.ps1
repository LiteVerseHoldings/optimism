param(
  [string]$DrivechainEvmDir = "",
  [string]$ConfigPath = "",
  [string]$StateDir = "",
  [switch]$Replace,
  [switch]$PrepareOnly
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$optimismRoot = Resolve-Path (Join-Path $scriptRoot "..\..")
$workspaceRoot = Split-Path $optimismRoot -Parent

if (-not $DrivechainEvmDir) {
  $DrivechainEvmDir = Join-Path $workspaceRoot "drivechain-evm"
}
$DrivechainEvmDir = (Resolve-Path -LiteralPath $DrivechainEvmDir).Path

if (-not $ConfigPath) {
  $ConfigPath = Join-Path $scriptRoot "bridge-relayer.env"
}
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
  $ConfigPath = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot $ConfigPath))
}

if (-not $StateDir) {
  $StateDir = Join-Path $scriptRoot "logs\bridge-relayer"
}
if (-not [System.IO.Path]::IsPathRooted($StateDir)) {
  $StateDir = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot $StateDir))
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
  $example = Join-Path $scriptRoot "bridge-relayer.env.example"
  throw "Missing $ConfigPath. Copy $example to $ConfigPath and fill BRIDGE_ADDRESS and RELAYER_PRIVATE_KEY."
}

function Get-EnvFileValue {
  param(
    [string]$Path,
    [string]$Name,
    [string]$Default = ""
  )

  foreach ($rawLine in (Get-Content -LiteralPath $Path)) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#")) {
      continue
    }
    $match = [regex]::Match($line, "^([^=]+)=(.*)$")
    if (-not $match.Success) {
      continue
    }
    if ($match.Groups[1].Value.Trim() -ne $Name) {
      continue
    }
    $value = $match.Groups[2].Value.Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    return $value
  }

  return $Default
}

$bridgeAddress = Get-EnvFileValue -Path $ConfigPath -Name "BRIDGE_ADDRESS"
$relayerPrivateKey = Get-EnvFileValue -Path $ConfigPath -Name "RELAYER_PRIVATE_KEY"
if ($bridgeAddress -notmatch "^0x[0-9a-fA-F]{40}$" -or $bridgeAddress -match "^0x0{40}$") {
  throw "Config has no real BRIDGE_ADDRESS: $ConfigPath"
}
if ($relayerPrivateKey -notmatch "^0x[0-9a-fA-F]{64}$" -or $relayerPrivateKey -match "^0x0{64}$") {
  throw "Config has no real RELAYER_PRIVATE_KEY: $ConfigPath"
}

& (Join-Path $scriptRoot "Check-LiteVerseDrivechain.ps1") `
  -DrivechainEvmDir $DrivechainEvmDir `
  -ConfigPath $ConfigPath `
  -RunBridgeDoctor:$false

if ($PrepareOnly) {
  Write-Host "LiteVerse OP Stack Drivechain relayer config is ready: $ConfigPath"
  return
}

$startArgs = @{
  ConfigPath = $ConfigPath
  StateDir = $StateDir
}
if ($Replace) {
  $startArgs.Replace = $true
}

& (Join-Path $DrivechainEvmDir "scripts\Start-EvmBridgeRelayer.ps1") @startArgs
