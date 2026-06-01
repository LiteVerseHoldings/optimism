param(
  [string]$DrivechainEvmDir = "",
  [string]$DeployerPrivateKey = "",
  [string]$OperatorAddress = "",
  [int]$SidechainId = 1,
  [string]$EvmRpcUrl = "http://127.0.0.1:9545",
  [string]$DeploymentOut = "",
  [string]$ConfigPath = "",
  [switch]$UpdateConfig
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$optimismRoot = Resolve-Path (Join-Path $scriptRoot "..\..")
$workspaceRoot = Split-Path $optimismRoot -Parent

if (-not $DrivechainEvmDir) {
  $DrivechainEvmDir = Join-Path $workspaceRoot "drivechain-evm"
}
$DrivechainEvmDir = (Resolve-Path -LiteralPath $DrivechainEvmDir).Path

if (-not $DeploymentOut) {
  $DeploymentOut = Join-Path $scriptRoot "bridge-deployment.local.json"
}
if (-not [System.IO.Path]::IsPathRooted($DeploymentOut)) {
  $DeploymentOut = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot $DeploymentOut))
}

if (-not $ConfigPath) {
  $ConfigPath = Join-Path $scriptRoot "bridge-relayer.env"
}
if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
  $ConfigPath = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot $ConfigPath))
}

if (-not $DeployerPrivateKey) {
  throw "DeployerPrivateKey is required."
}

$deployArgs = @{
  DeployerPrivateKey = $DeployerPrivateKey
  SidechainId = $SidechainId
  EvmRpcUrl = $EvmRpcUrl
  DeploymentOut = $DeploymentOut
}
if ($OperatorAddress) {
  $deployArgs.OperatorAddress = $OperatorAddress
}

& (Join-Path $DrivechainEvmDir "scripts\Deploy-EvmBridge.ps1") @deployArgs
if ($LASTEXITCODE -ne 0) {
  throw "LiteVerseBridge deployment failed."
}

$deployment = Get-Content -LiteralPath $DeploymentOut -Raw | ConvertFrom-Json
Write-Host "op-stack-bridge-address: $($deployment.bridgeAddress)"
Write-Host "op-stack-bridge-block: $($deployment.blockNumber)"

if ($UpdateConfig) {
  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Copy-Item -LiteralPath (Join-Path $scriptRoot "bridge-relayer.env.example") -Destination $ConfigPath
  }

  $lines = Get-Content -LiteralPath $ConfigPath
  $updates = @{
    BRIDGE_ADDRESS = [string]$deployment.bridgeAddress
    FROM_BLOCK = [string]$deployment.blockNumber
    EVM_RPC_URL = $EvmRpcUrl
    SIDECHAIN_ID = [string]$SidechainId
  }

  foreach ($name in @($updates.Keys)) {
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match "^$name=") {
        $lines[$i] = "$name=$($updates[$name])"
        $found = $true
      }
    }
    if (-not $found) {
      $lines += "$name=$($updates[$name])"
    }
  }

  Set-Content -LiteralPath $ConfigPath -Value $lines
  Write-Host "Updated relayer config: $ConfigPath"
}
