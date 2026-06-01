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
