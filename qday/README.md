# QDAY zkRollup Contract Deployment

Deploy zkRollup (`PolygonZkEVMEtrog` fork12) contracts to an existing L1 node (Sepolia/Mainnet).

## Quick Start

```bash
# 1. Install & configure
npm install
cp qday/env.example .env        # fill in SEQ_PVT_KEY, SEPOLIA_PROVIDER / MAINNET_PROVIDER
vim qday/deploy_parameters.json  # fill in deployerPvtKey + admin/aggregator addresses
vim qday/create_rollup_parameters.json  # fill in deployerPvtKey + sequencer/chain info

# 2. Deploy to Sepolia
./qday/deploy.sh sepolia

# or Mainnet
./qday/deploy.sh mainnet
```

## Directory Structure

| File | Purpose |
|------|---------|
| `env.example` | Environment variable template |
| `deploy_parameters.json` | L1 core contract parameters (salt, admin addresses, POL, verifier) |
| `create_rollup_parameters.json` | Rollup creation parameters (sequencer, chainID, forkID) |
| `validate_deployer_keys.js` | Fail-fast check: both JSON files have the same `deployerPvtKey` |
| `deploy.sh` | Full deployment script (compile → fund → deploy L1 contracts → create rollup) |
| `deploy_pol.sh` | Standalone POL token deployment + Sequencer funding |
| `pre_deploy_check.ts` | Balance check + fund Sequencer/Aggregator (1000 ETH each) |
| `approve_sequencer_pol.ts` | Authorize rollup contract to spend Sequencer's POL |
| `usage.md` | Detailed deployment guide |
| `output/` | Generated after deployment — genesis + contract addresses for zkEVM node |

## Deployment Flow

```
deploy.sh:
  STEP 0  Compile contracts
  STEP 1  Copy parameter files
  STEP 2  Check deployer balance → fund Sequencer (1000 ETH) + Aggregator (1000 ETH)
  STEP 3  Deploy test POL token (Sepolia only)
  STEP 4  Generate genesis.json
  STEP 5  Deploy PolygonZkEVMDeployer
  STEP 6  Deploy L1 core contracts
         (Bridge, GlobalExitRoot, AggLayerGateway, RollupManager, Timelock)
  STEP 7  Create zkRollup
  STEP 8  Collect output to qday/output/
  STEP 9  Clean up intermediate files
  STEP 10 Approve rollup contract to spend Sequencer's POL
```

## Deployer Address

QDAY is private-key only. Fill `deployerPvtKey` in **both**:
1. `deploy_parameters.json` → `deployerPvtKey`
2. `create_rollup_parameters.json` → `deployerPvtKey`

The two keys must be the same (same address). Deployment exits if either is missing or they differ.

The deployer account must hold enough ETH for gas + funding.

## Output Files

After deployment, `qday/output/` contains:

| File | Used By |
|------|---------|
| `genesis.json` | **zkEVM node** — bootstraps L2 chain state |
| `deploy_output.json` | **zkEVM node** — L1 contract addresses |
| `create_rollup_output.json` | **Sequencer** — rollup address + first batch data |

## Contracts Deployed

| Contract | Role |
|----------|------|
| `PolygonZkEVMDeployer` | Create2 deterministic deployment factory |
| `PolygonZkEVMTimelock` | Timelock for admin operations |
| `PolygonZkEVMBridgeV2` | L1 ↔ L2 bridge |
| `PolygonZkEVMGlobalExitRootV2` | Global exit root manager |
| `AggLayerGateway` | AggLayer verification key gateway |
| `PolygonRollupManager` | Rollup manager (central hub) |
| `Verifier` | ZK proof verifier (SP1VerifierPlonk) |
| `PolygonZkEVMEtrog` | zkRollup consensus contract |

## Standalone POL Deployment

```bash
# Deploy POL token + fund Sequencer only
./qday/deploy_pol.sh sepolia
```

## Sequencer POL Approval

After deployment, the Sequencer must approve the **rollup proxy contract** (not RollupManager) to spend its POL. This is handled automatically by `deploy.sh` STEP 10, or run manually:

```bash
# Requires SEQ_PVT_KEY in .env (must match trustedSequencer)
./qday/approve_sequencer_pol.sh sepolia
```

Or with `cast`:
```bash
cast send <POL_ADDR> "approve(address,uint256)" <ROLLUP_ADDR> 115792089237316195423570985008687907853269984665640564039457584007913129639935
```
