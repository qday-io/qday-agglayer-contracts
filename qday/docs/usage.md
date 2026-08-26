# QDAY zkRollup Contract Deployment Guide

## Table of Contents

1. [Overview](#1-overview)
2. [POL Token](#2-pol-token)
3. [Deployer Address (Important)](#3-deployer-address-important)
4. [Prerequisites](#4-prerequisites)
5. [Parameter Configuration](#5-parameter-configuration)
6. [Deployment](#6-deployment)
7. [Post-Deployment Checks](#7-post-deployment-checks)
8. [Contract Verification](#8-contract-verification)
9. [Manual Step-by-Step Deployment](#9-manual-step-by-step-deployment)
10. [FAQ](#10-faq)

---

## 1. Overview

Deploy zkRollup (PolygonZkEVMEtrog fork12) contracts to an existing L1 network.

### Deployed Contracts

| Contract | Description |
|----------|-------------|
| PolygonZkEVMDeployer | Create2 deterministic deployment factory |
| PolygonZkEVMTimelock | Timelock controller |
| PolygonZkEVMBridgeV2 | L1↔L2 bridge |
| PolygonZkEVMGlobalExitRootV2 | Global exit root manager |
| AggLayerGateway | AggLayer verification key gateway |
| PolygonRollupManager | Rollup manager |
| Verifier | ZK proof verifier |
| PolygonZkEVMEtrog | zkRollup consensus contract |

### Key Scripts

| Script | Description |
|--------|-------------|
| `qday/deploy.sh` | One-click deployment (all steps) |
| `qday/pre_deploy_check.ts` | Pre-deployment checks: validate addresses, check balances, fund Sequencer/Aggregator with 1000 ETH each, fund Sequencer with 100,000 POL |
| `qday/approve_sequencer_pol.sh` | Sequencer POL approval to Rollup contract (wrapper) |
| `qday/approve_sequencer_pol.ts` | Sequencer calls `POL.approve(rollupAddr, MaxUint256)` |

### Deployment Flow

```
Compile → Check balances + fund Sequencer/Aggregator 1000 ETH each → Deploy POL + fund Sequencer 100,000 POL → Generate Genesis → Deploy Deployer → Deploy L1 core contracts → Create Rollup → Sequencer approves POL to Rollup → Clean up intermediate files
```

---

## 2. POL Token

POL is the native token of the Polygon ecosystem. `polTokenAddress` must be specified when deploying RollupManager.

### Sepolia Testnet

**No need to manually provide a POL address**. `deploy.sh` will automatically:

1. Check deployer ETH balance, and once confirmed sufficient:
   - Transfer **1000 ETH** to **Sequencer**
   - Transfer **1000 ETH** to **Aggregator**
2. Deploy a test POL token (ERC20PermitMock)
3. Transfer **100,000 POL** to **Sequencer**
4. Auto-write the POL address into `deploy_parameters.json`

### Ethereum Mainnet

The mainnet POL address is known and must be **filled in manually** in `qday/deploy_parameters.json`:

```json
// Ethereum mainnet POL token address:
"polTokenAddress": "0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6"
```

On mainnet, Sequencer/Aggregator must be **prepared in advance**:
- Sufficient ETH for gas fees
- Sufficient POL for rollup bond

---

## 3. Deployer Address (Important)

QDAY is private-key only. Gas for deployment comes from the **deployer address** derived from `deployerPvtKey`. Fill the **same** key in both files (manually; the scripts do not copy one into the other):

| File | Field |
|------|--------|
| `qday/deploy_parameters.json` | `deployerPvtKey` |
| `qday/create_rollup_parameters.json` | `deployerPvtKey` |

`deploy.sh` / `deploy_pol.sh` / `pre_deploy_check.ts` verify both keys are present, parseable, and derive the same address. Any failure exits immediately.

**Verify the deployer address**:

```bash
node -e "console.log(new (require('ethers').Wallet)('<deployerPvtKey>').address)"
```

> :warning: **Confirm before deployment**: the deployer address must have sufficient ETH on the target network to cover gas fees. All L1 contract deployments, POL token deployments, and account funding operations will originate from this address.

---

## 4. Prerequisites

### 4.1 System Requirements

- Node.js >= 18.x, npm >= 9.x
- Dependencies installed: `npm install`

### 4.2 Environment Variables

```bash
cp qday/env.example .env
```

Edit `.env`:

```env
# [REQUIRED] Sequencer private key (must match trustedSequencer)
SEQ_PVT_KEY=""

# [REQUIRED] L1 RPC URLs
SEPOLIA_PROVIDER="https://sepolia.infura.io/v3/xxx"
MAINNET_PROVIDER="https://mainnet.infura.io/v3/xxx"

# [OPTIONAL] Fallback when SEPOLIA_PROVIDER / MAINNET_PROVIDER are unset
INFURA_PROJECT_ID=""

# [OPTIONAL] Only needed for contract verification
ETHERSCAN_API_KEY=""
```

Also fill `deployerPvtKey` in **both** `qday/deploy_parameters.json` and `qday/create_rollup_parameters.json` (same key).

> `INFURA_PROJECT_ID` is only used as a fallback RPC URL builder in Hardhat when `SEPOLIA_PROVIDER` / `MAINNET_PROVIDER` are empty. `ETHERSCAN_API_KEY` is only required if you run contract verification.

---

## 5. Parameter Configuration

How to fill the tables below:

| Fill | Meaning |
|------|---------|
| **Manual** | Write before `deploy.sh`. Scripts do not generate this value. |
| **Auto** | Leave empty. The deploy script writes it. |
| **Pre-set** | Already in the QDAY template. Do not change unless you know why. |

### 5.1 deploy_parameters.json

```bash
vim qday/deploy_parameters.json
```

| Field | Sepolia | Mainnet | Description |
|-------|---------|---------|-------------|
| `deployerPvtKey` | **Manual** | **Manual** | Deployer private key (must match `create_rollup_parameters.json`) |
| `salt` | **Manual** | **Manual** | Create2 salt |
| `polTokenAddress` | **Auto** (leave empty) | **Manual** | Sepolia: `prepareTestnet` deploys POL and writes the address. Mainnet: set the real POL token. |
| `zkEVMDeployerAddress` | **Auto** (leave empty) | **Auto** (leave empty) | Written after `PolygonZkEVMDeployer` is deployed |
| `initialZkEVMDeployerOwner` | **Manual** | **Manual** | Deployer factory owner |
| `admin` | **Manual** | **Manual** | Super admin |
| `trustedAggregator` | **Manual** | **Manual** | Trusted aggregator address (funded with 1000 ETH) |
| `emergencyCouncilAddress` | **Manual** | **Manual** | Emergency council |
| `timelockAdminAddress` | **Manual** | **Manual** | Timelock admin (multisig recommended) |
| `realVerifier` | **Manual** (`true` in production) | **Manual** (`true`) | Use real verifier for production |
| `ppVKey` | **Pre-set** `0xac51…959f` | **Pre-set** `0xac51…959f` | AggLayerGateway pessimistic VKey. QDAY Etrog does not use pessimistic proofs; keep the template default. Must not be `0x00…00` (Gateway `initialize` rejects zero). |
| `ppVKeySelector` | **Pre-set** `0x00000001` | **Pre-set** `0x00000001` | 4-byte route id for `ppVKey`. Keep `0x00000001`. Must not be `0x00000000`. |

QDAY does not run AggLayer pessimistic. `ppVKey` / `ppVKeySelector` are still required to deploy `AggLayerGateway`, but they are unused by Etrog sequencing. Use the template defaults:

```text
ppVKey:         0xac51a6a2e513d02e4f39ea51d4d133cec200b940805f1054eabbb6d6412c959f
ppVKeySelector: 0x00000001
```

If you later attach a real pessimistic route, replace these with the official VKey. Do not leave them empty.

### 5.2 create_rollup_parameters.json

```bash
vim qday/create_rollup_parameters.json
```

| Field | Sepolia | Mainnet | Description |
|-------|---------|---------|-------------|
| `deployerPvtKey` | **Manual** | **Manual** | Deployer private key (must match `deploy_parameters.json`) |
| `trustedSequencerURL` | **Manual** | **Manual** | Sequencer RPC URL (written on-chain; not generated) |
| `networkName` | **Manual** | **Manual** | L2 network name |
| `description` | **Manual** | **Manual** | Rollup type description |
| `trustedSequencer` | **Manual** | **Manual** | Trusted sequencer address (`SEQ_PVT_KEY` must match this; funded with 1000 ETH) |
| `chainID` | **Manual** | **Manual** | L2 chain ID (must be unique) |
| `adminZkEVM` | **Manual** | **Manual** | L2 admin |
| `forkID` | **Pre-set** `12` | **Pre-set** `12` | Etrog fork ID |
| `consensusContract` | **Pre-set** `PolygonZkEVMEtrog` | **Pre-set** `PolygonZkEVMEtrog` | Consensus contract name |
| `gasTokenAddress` | **Manual** (leave empty = ETH) | **Manual** (leave empty = ETH) | Not auto-filled unless set to `"deploy"` (deploys a test ERC20) |
| `realVerifier` | **Manual** (`true` in production) | **Manual** (`true`) | Use real verifier for production |
| `programVKey` | **Pre-set** `0x00…00` | **Pre-set** `0x00…00` | Rollup-type ZK program hash (SP1 / pessimistic). For `PolygonZkEVMEtrog` it **must** be `bytes32(0)`. A non-zero value fails create-rollup with `programVKey should be 0x for PolygonZkEVMEtrog`. |

QDAY is Etrog-only. Keep `programVKey` as the template default (do not change):

```text
0x0000000000000000000000000000000000000000000000000000000000000000
```

This is a different key from `ppVKey`. `programVKey` is registered on this rollup type in RollupManager; `ppVKey` is only the Gateway placeholder described in 5.1.

---

## 6. Deployment

### Sepolia Testnet

```bash
./qday/deploy.sh sepolia
```

### Ethereum Mainnet

```bash
# Fill in polTokenAddress first
vim qday/deploy_parameters.json

./qday/deploy.sh mainnet
```

Script steps:

| Sepolia | Mainnet |
|---------|---------|
| Compile | Compile |
| Copy parameter files | Copy parameter files |
| **Check balance + fund Sequencer 1000 ETH + Aggregator 1000 ETH** | Same |
| **Deploy POL + fund Sequencer 100,000 POL** | Validate polTokenAddress is not empty |
| Generate Genesis | Generate Genesis |
| Deploy ZkEVMDeployer | Deploy ZkEVMDeployer |
| Deploy L1 core contracts | Deploy L1 core contracts |
| Create Rollup | Create Rollup |
| Collect output → `qday/output/` | Collect output → `qday/output/` |
| **Sequencer approves POL to Rollup** | Same |
| Clean up intermediate files | Clean up intermediate files |

---

## 7. Post-Deployment Checks

```bash
# List output files
ls -la qday/output/

# L1 contract addresses
cat qday/output/deploy_output.json | python3 -m json.tool

# Rollup details
cat qday/output/create_rollup_output.json | python3 -m json.tool
```

| File | Description | Usage |
|------|-------------|-------|
| `genesis.json` | L2 genesis config (state root, pre-deployed contracts) | **Required for zkEVM node startup**, initializes L2 chain state |
| `deploy_output.json` | All L1 contract addresses | Configure zkEVM node to point to correct L1 contracts |
| `create_rollup_output.json` | Rollup address + initial batch data | Configure Sequencer sync starting point |

---

## 8. Contract Verification

Requires `ETHERSCAN_API_KEY` in `.env`.

```bash
# Sepolia
npm run verify:v2:sepolia

# Mainnet
npm run verify:ZkEVM:mainnet
```

---

## 9. Manual Step-by-Step Deployment

For step-by-step debugging, run each step individually:

```bash
# Step 0: Compile
npx hardhat compile

# Step 1: Copy parameters
cp qday/deploy_parameters.json deployment/v2/deploy_parameters.json
cp qday/create_rollup_parameters.json deployment/v2/create_rollup_parameters.json

# Step 2: Check balance + fund Sequencer/Aggregator 1000 ETH each
npx hardhat run qday/pre_deploy_check.ts --network sepolia

# Step 3: Prepare testnet (deploy POL + fund Sequencer 100,000 POL)
npx hardhat run deployment/testnet/prepareTestnet.ts --network sepolia

# Step 4: Generate Genesis (in-memory Hardhat; --test uses the default mnemonic)
npx ts-node deployment/v2/1_createGenesis.ts --test

# Step 5: Deploy ZkEVMDeployer
npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network sepolia

# Step 6: Deploy L1 core contracts
npx hardhat run deployment/v2/3_deployContracts.ts --network sepolia

# Step 7: Create Rollup
npx hardhat run deployment/v2/4_createRollup.ts --network sepolia

# Step 8: Collect output
mkdir -p qday/output
cp deployment/v2/deploy_output.json qday/output/
cp deployment/v2/genesis.json qday/output/
cp deployment/v2/create_rollup_output_*.json qday/output/create_rollup_output.json

# Step 9: Sequencer approves POL to Rollup contract
npx hardhat run qday/approve_sequencer_pol.ts --network sepolia
```

---

## 10. FAQ

### 10.1 Insufficient Sequencer/Aggregator funds?

`deploy.sh` automatically checks and funds:

```
Sequencer: 1000 ETH + 100,000 POL
Aggregator: 1000 ETH
```

The deployer address must hold at least 2000 ETH (1000 for Sequencer + 1000 for Aggregator), otherwise deployment will fail at [STEP 2].

On mainnet, ensure sufficient balances manually.

### 10.2 How to retry a failed deployment?

```bash
rm -f deployment/v2/deploy_ongoing.json .openzeppelin/sepolia.json
./qday/deploy.sh sepolia
```

### 10.3 How to redeploy with a different salt?

Modify `salt` in `qday/deploy_parameters.json`. **The same salt produces the same Create2 address and cannot be redeployed.**

### 10.4 "zkEVM deployer contract is not deployed"

On Sepolia, run Step 4 first. Mainnet Deployer is already deployed at: `0xCB19eDdE626906eB1EE52357a27F62dd519608C2`.

### 10.5 Mainnet deployment notes

- `polTokenAddress` must be filled in
- `realVerifier` must be `true`
- `test` must be `false`
- Deployer account must have sufficient balance for gas
- Sequencer / Aggregator must have ETH + POL prepared in advance
