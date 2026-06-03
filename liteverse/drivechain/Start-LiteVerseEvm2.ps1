param(
  [string]$OptimismExampleDir = "",
  [switch]$Start,
  [switch]$Status,
  [switch]$AllowMissingArtifacts,
  [switch]$SequencerOnly
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$optimismRoot = Resolve-Path (Join-Path $scriptRoot "..\..")
$workspaceRoot = Split-Path $optimismRoot -Parent

if (-not $OptimismExampleDir) {
  $OptimismExampleDir = Join-Path $optimismRoot "docs\public-docs\create-l2-rollup-example"
}
$resolvedExample = Resolve-Path -LiteralPath $OptimismExampleDir -ErrorAction SilentlyContinue
if (-not $resolvedExample) {
  throw "Optimism example directory not found: $OptimismExampleDir"
}

$baseCompose = Join-Path $resolvedExample "docker-compose.yml"
$overrideCompose = Join-Path $scriptRoot "docker-compose.evm2.override.yml"
if (-not (Test-Path -LiteralPath $baseCompose)) {
  throw "Missing Optimism base compose file: $baseCompose"
}
if (-not (Test-Path -LiteralPath $overrideCompose)) {
  throw "Missing LiteVerse EVM #2 compose override: $overrideCompose"
}

$requiredArtifacts = @(
  ".env",
  "sequencer\genesis.json",
  "sequencer\rollup.json",
  "sequencer\jwt.txt"
)
if (-not $SequencerOnly) {
  $requiredArtifacts += @(
    "batcher\.env",
    "proposer\.env",
    "challenger\.env"
  )
}

$missing = @()
foreach ($artifact in $requiredArtifacts) {
  $path = Join-Path $resolvedExample $artifact
  if (-not (Test-Path -LiteralPath $path)) {
    $missing += $artifact
  }
}

if ($missing.Count -gt 0 -and -not $AllowMissingArtifacts) {
  Write-Host "LiteVerse OP EVM #2 is not startable yet. Missing generated artifacts:"
  foreach ($item in $missing) {
    Write-Host " - $item"
  }
  Write-Host ""
  Write-Host "Generate them from the Optimism example after setting L1_RPC_URL, L1_BEACON_URL, PRIVATE_KEY, and L2_CHAIN_ID:"
  Write-Host "  cd $resolvedExample"
  Write-Host "  copy .example.env .env"
  Write-Host "  make init"
  Write-Host "  make setup"
  exit 1
}

function Get-EnvFileValue {
  param(
    [string]$Path,
    [string]$Name
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return ""
  }

  $line = Get-Content -LiteralPath $Path |
    Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } |
    Select-Object -Last 1
  if (-not $line -or $line -notmatch "^\s*[^=]+\s*=\s*(.*)\s*$") {
    return ""
  }

  return $Matches[1].Trim().Trim('"').Trim("'")
}

function Get-EvmAddressFromPrivateKey {
  param([string]$PrivateKey)

  if (-not $PrivateKey) {
    return ""
  }
  if ($PrivateKey -notmatch "^0x") {
    $PrivateKey = "0x$PrivateKey"
  }

  $cast = Get-Command cast -ErrorAction SilentlyContinue
  if ($cast) {
    $output = & $cast.Source wallet address --private-key $PrivateKey 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host ($output | Out-String)
      throw "Failed to derive OP role address from private key with cast."
    }
    return (($output | Select-Object -Last 1) | Out-String).Trim()
  }

  $node = Get-Command node -ErrorAction SilentlyContinue
  $relayerDir = Join-Path $workspaceRoot "drivechain-evm\bridge-relayer"
  if (-not $node -or -not (Test-Path -LiteralPath (Join-Path $relayerDir "node_modules\viem"))) {
    throw "cast or node with bridge-relayer viem dependencies is required to verify OP role private keys before starting full EVM #2 services."
  }

  Push-Location $relayerDir
  try {
    $script = "import('viem/accounts').then(({ privateKeyToAddress }) => console.log(privateKeyToAddress(process.argv[1]))).catch((error) => { console.error(error.message); process.exit(1); });"
    $output = & $node.Source -e $script $PrivateKey 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host ($output | Out-String)
      throw "Failed to derive OP role address from private key with node."
    }
    return (($output | Select-Object -Last 1) | Out-String).Trim()
  } finally {
    Pop-Location
  }
}

function Test-OpRoleKey {
  param(
    [object]$Roles,
    [string]$RoleName,
    [string]$EnvPath,
    [string]$EnvName
  )

  $expected = [string]$Roles.$RoleName
  $privateKey = Get-EnvFileValue -Path $EnvPath -Name $EnvName
  if (-not $expected) {
    throw "Rollup deployment state is missing role '$RoleName'."
  }
  if (-not $privateKey) {
    throw "$EnvPath is missing $EnvName."
  }

  $actual = Get-EvmAddressFromPrivateKey -PrivateKey $privateKey
  if ($actual.ToLowerInvariant() -ne $expected.ToLowerInvariant()) {
    throw "OP role key mismatch for $RoleName. $EnvName derives $actual, but rollup deployment expects $expected. Regenerate OP artifacts with real role addresses before starting full EVM #2 services."
  }
}

if (-not $SequencerOnly -and -not $AllowMissingArtifacts) {
  $statePath = Join-Path $resolvedExample "deployer\.deployer\state.json"
  if (-not (Test-Path -LiteralPath $statePath)) {
    throw "Missing OP deployer state: $statePath"
  }

  $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
  $roles = $state.appliedIntent.chains[0].roles
  Test-OpRoleKey -Roles $roles -RoleName "batcher" -EnvPath (Join-Path $resolvedExample "batcher\.env") -EnvName "OP_BATCHER_PRIVATE_KEY"
  Test-OpRoleKey -Roles $roles -RoleName "proposer" -EnvPath (Join-Path $resolvedExample "proposer\.env") -EnvName "OP_PROPOSER_PRIVATE_KEY"
  Test-OpRoleKey -Roles $roles -RoleName "challenger" -EnvPath (Join-Path $resolvedExample "challenger\.env") -EnvName "OP_CHALLENGER_PRIVATE_KEY"
}

$composeArgs = @(
  "compose",
  "-p", "liteverse-evm2",
  "-f", $baseCompose,
  "-f", $overrideCompose
)

if ($Status) {
  if ($SequencerOnly) {
    & docker @composeArgs ps op-geth op-node
  } else {
    & docker @composeArgs ps
  }
  exit $LASTEXITCODE
}

if ($Start) {
  Push-Location $resolvedExample
  try {
    if ($SequencerOnly) {
      & docker @composeArgs up -d op-geth op-node
    } else {
      & docker @composeArgs up -d
    }
    exit $LASTEXITCODE
  } finally {
    Pop-Location
  }
}

Write-Host "LiteVerse OP EVM #2 preflight"
Write-Host " Example:  $resolvedExample"
Write-Host " Compose:  $baseCompose"
Write-Host " Override: $overrideCompose"
Write-Host " Ports:"
Write-Host "  op-geth HTTP: http://127.0.0.1:9545"
Write-Host "  op-geth WS:   ws://127.0.0.1:9546"
Write-Host "  op-node RPC:  http://127.0.0.1:9547"
Write-Host "  op-node P2P:  9622"
Write-Host "  dispute-mon:  http://127.0.0.1:9730"
