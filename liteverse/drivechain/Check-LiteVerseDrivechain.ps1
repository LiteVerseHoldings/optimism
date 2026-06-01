param(
  [string]$DrivechainEvmDir = "",
  [string]$ConfigPath = "",
  [string]$EvmRpcUrl = "http://127.0.0.1:9545",
  [string]$RollupRpcUrl = "http://127.0.0.1:9547",
  [string]$LitecoinRpcUrl = "http://127.0.0.1:39333/",
  [string]$EnforcerRpcUrl = "http://127.0.0.1:8123/",
  [string]$LitecoinRpcUser = "user",
  [string]$LitecoinRpcPassword = "password",
  [int]$ExpectedChainId = 713318,
  [int]$SidechainId = 1,
  [switch]$RequireCtip,
  [switch]$RunBridgeDoctor
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

function Get-EnvFileValue {
  param(
    [string]$Path,
    [string]$Name,
    [string]$Default = ""
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $Default
  }

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

function Import-EnvFile {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing env file: $Path"
  }

  foreach ($rawLine in (Get-Content -LiteralPath $Path)) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#")) {
      continue
    }
    $match = [regex]::Match($line, "^([^=]+)=(.*)$")
    if (-not $match.Success) {
      throw "Invalid env line in ${Path}: ${line}"
    }
    $name = $match.Groups[1].Value.Trim()
    $value = $match.Groups[2].Value.Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    Set-Item -Path "Env:$name" -Value $value
  }
}

function Invoke-JsonRpc {
  param(
    [string]$Uri,
    [string]$Method,
    [object[]]$Params = @(),
    [hashtable]$Headers = @{}
  )

  $body = @{
    jsonrpc = "2.0"
    id = $Method
    method = $Method
    params = $Params
  } | ConvertTo-Json -Depth 20 -Compress

  Invoke-RestMethod -Uri $Uri -Method Post -Body $body -ContentType "application/json" -Headers $Headers
}

function Convert-HexToUInt64 {
  param([string]$Hex)
  if (-not $Hex) {
    return 0
  }
  return [Convert]::ToUInt64(($Hex -replace "^0x", ""), 16)
}

if (Test-Path -LiteralPath $ConfigPath) {
  $EvmRpcUrl = Get-EnvFileValue -Path $ConfigPath -Name "EVM_RPC_URL" -Default $EvmRpcUrl
  $LitecoinRpcUrl = Get-EnvFileValue -Path $ConfigPath -Name "LITECOIN_RPC_URL" -Default $LitecoinRpcUrl
  $EnforcerRpcUrl = Get-EnvFileValue -Path $ConfigPath -Name "ENFORCER_RPC_URL" -Default $EnforcerRpcUrl
  $LitecoinRpcUser = Get-EnvFileValue -Path $ConfigPath -Name "LITECOIN_RPC_USER" -Default $LitecoinRpcUser
  $LitecoinRpcPassword = Get-EnvFileValue -Path $ConfigPath -Name "LITECOIN_RPC_PASSWORD" -Default $LitecoinRpcPassword
  $SidechainId = [int](Get-EnvFileValue -Path $ConfigPath -Name "SIDECHAIN_ID" -Default ([string]$SidechainId))
}

$chain = Invoke-JsonRpc -Uri $EvmRpcUrl -Method "eth_chainId"
$chainId = Convert-HexToUInt64 $chain.result
if ($ExpectedChainId -gt 0 -and $chainId -ne $ExpectedChainId) {
  throw "Expected OP EVM #2 chain ID $ExpectedChainId, got $chainId at $EvmRpcUrl."
}
Write-Host "[ok] OP EVM #2 execution RPC $EvmRpcUrl chainId=$chainId"

$block = Invoke-JsonRpc -Uri $EvmRpcUrl -Method "eth_blockNumber"
Write-Host "     blockNumber=$($block.result)"

$sync = Invoke-JsonRpc -Uri $RollupRpcUrl -Method "optimism_syncStatus"
if (-not $sync.result) {
  throw "OP EVM #2 rollup RPC did not return sync status at $RollupRpcUrl."
}
Write-Host "[ok] OP EVM #2 rollup RPC $RollupRpcUrl"

$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${LitecoinRpcUser}:${LitecoinRpcPassword}"))
$litecoin = Invoke-JsonRpc -Uri $LitecoinRpcUrl -Method "getblockchaininfo" -Headers @{ Authorization = "Basic $auth" }
Write-Host "[ok] Litecoin RPC $LitecoinRpcUrl chain=$($litecoin.result.chain) blocks=$($litecoin.result.blocks)"

$ping = Invoke-JsonRpc -Uri $EnforcerRpcUrl -Method "validator.ping"
Write-Host "[ok] Drivechain enforcer $EnforcerRpcUrl ping=$($ping.result)"

$ctip = Invoke-JsonRpc -Uri $EnforcerRpcUrl -Method "validator.ctip" -Params @($SidechainId)
if ($ctip.result) {
  Write-Host "[ok] Sidechain $SidechainId CTIP $($ctip.result | ConvertTo-Json -Depth 8 -Compress)"
} elseif ($RequireCtip) {
  throw "Sidechain $SidechainId has no CTIP."
} else {
  Write-Host "[warn] Sidechain $SidechainId CTIP is not available yet."
}

if ($RunBridgeDoctor) {
  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Bridge doctor requires a configured env file: $ConfigPath"
  }
  $bridgeAddress = Get-EnvFileValue -Path $ConfigPath -Name "BRIDGE_ADDRESS"
  $relayerPrivateKey = Get-EnvFileValue -Path $ConfigPath -Name "RELAYER_PRIVATE_KEY"
  if ($bridgeAddress -notmatch "^0x[0-9a-fA-F]{40}$" -or $bridgeAddress -match "^0x0{40}$") {
    throw "Bridge doctor requires a real BRIDGE_ADDRESS in $ConfigPath."
  }
  if ($relayerPrivateKey -notmatch "^0x[0-9a-fA-F]{64}$" -or $relayerPrivateKey -match "^0x0{64}$") {
    throw "Bridge doctor requires a real RELAYER_PRIVATE_KEY in $ConfigPath."
  }

  $relayerDir = Join-Path $DrivechainEvmDir "bridge-relayer"
  $entrypoint = Join-Path $relayerDir "dist\index.js"
  if (-not (Test-Path -LiteralPath $entrypoint)) {
    throw "Missing bridge relayer build at $entrypoint. Run npm run build in $relayerDir."
  }

  Import-EnvFile -Path $ConfigPath
  Push-Location $relayerDir
  try {
    node dist/index.js doctor
    if ($LASTEXITCODE -ne 0) {
      throw "Bridge relayer doctor failed."
    }
  } finally {
    Pop-Location
  }
}

Write-Host "LiteVerse OP Stack Drivechain check: PASS"
