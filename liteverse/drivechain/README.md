# LiteVerse Drivechain Integration

This directory gives the LiteVerse OP Stack checkout a Drivechain-facing runtime
surface. It does not fork OP Stack consensus. The Litecoin/Drivechain logic
continues to live in the sibling `drivechain-evm` repository:

```text
evm/
  drivechain-evm/
  optimism/
```

The OP Stack runtime is EVM #2:

| Field | Value |
| --- | --- |
| Stack | OP Stack |
| Chain ID | `713318` |
| Execution RPC | `http://127.0.0.1:9545` |
| Rollup RPC | `http://127.0.0.1:9547` |
| Drivechain sidechain ID | `1` |
| Enforcer RPC | `http://127.0.0.1:8123/` |
| Litecoin RPC proxy | `http://127.0.0.1:39333/` |

## What This Adds

- OP EVM #2 health checks for `op-geth` and `op-node`.
- Litecoin Core Plus / enforcer checks from the OP checkout.
- A relayer env template pointed at OP EVM #2.
- A wrapper to deploy `LiteVerseBridge` to OP EVM #2 using the
  `drivechain-evm` contract tooling.
- A wrapper to start the existing `drivechain-evm` bridge relayer against OP
  EVM #2.

## Check Runtime

Start or inspect OP EVM #2 from this checkout:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\liteverse\drivechain\Start-LiteVerseEvm2.ps1 -Status -SequencerOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\liteverse\drivechain\Start-LiteVerseEvm2.ps1 -Start -SequencerOnly
```

Check the OP runtime and Drivechain services:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\liteverse\drivechain\Check-LiteVerseDrivechain.ps1
```

Add `-RequireCtip` when sidechain slot `1` should already have a CTIP.

## Configure Bridge Relayer

```powershell
copy .\liteverse\drivechain\bridge-relayer.env.example .\liteverse\drivechain\bridge-relayer.env
```

Fill:

- `BRIDGE_ADDRESS`
- `RELAYER_PRIVATE_KEY`

The local `bridge-relayer.env` file is ignored by Git.

## Deploy Bridge To OP EVM #2

The deployer account must have native gas on OP EVM #2.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\liteverse\drivechain\Deploy-LiteVerseBridge.ps1 `
  -DeployerPrivateKey 0x... `
  -OperatorAddress 0x... `
  -EvmChainId 713318 `
  -UpdateConfig
```

This writes `bridge-deployment.local.json` and can update
`bridge-relayer.env`. Both local files are ignored by Git.

## Start Relayer

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\liteverse\drivechain\Start-LiteVerseDrivechainRelayer.ps1 -Replace
```

The wrapper delegates to `drivechain-evm\scripts\Start-EvmBridgeRelayer.ps1`,
but uses OP EVM #2 endpoints from this checkout's config.

## Security Boundary

This adds Drivechain bridge capability to the OP Stack execution runtime. It
does not make OP Stack itself enforce Litecoin peg-outs. Without an activated
Litecoin Drivechain/LIP005 soft fork, real LTC peg-outs remain
federation/operator-secured.
