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

Gas for deployment comes from the **deployer address**. The source is determined by the following priority:

| Priority | Source | Description |
|----------|--------|-------------|
| 1 | `qday/deploy_parameters.json` → `deployerPvtKey` | If a private key is provided, this becomes the deployer |
| 2 | `.env` → `MNEMONIC`, first account | Derivation path `m/44'/60'/0'/0/0` |
| 3 | Hardhat default Signer | Local hardhat network only |

**Verify the deployer address**:

```bash
source .env 2>/dev/null
npx hardhat console --network sepolia <<< "
const w = ethers.HDNodeWallet.fromMnemonic(
  ethers.Mnemonic.fromPhrase(process.env.MNEMONIC),
  'm/44'/60'/0'/0/0'
);
console.log('Deployer:', w.address);
"
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
MNEMONIC="your twelve word mnemonic phrase here"
INFURA_PROJECT_ID="your-infura-project-id"
ETHERSCAN_API_KEY="your-etherscan-api-key"
```

---

## 5. Parameter Configuration

### 5.1 deploy_parameters.json

```bash
vim qday/deploy_parameters.json
```

| Field | Sepolia | Mainnet | Description |
|-------|---------|---------|-------------|
| `salt` | Custom | Custom | Create2 salt |
| `polTokenAddress` | **Leave empty** | **Required** | Deployed automatically on Sepolia; must be filled manually on Mainnet |
| `initialZkEVMDeployerOwner` | Fill in | Fill in | Deployer factory owner |
| `admin` | Fill in | Fill in | Super admin |
| `trustedAggregator` | Fill in | Fill in | Trusted aggregator |
| `emergencyCouncilAddress` | Fill in | Fill in | Emergency council |
| `timelockAdminAddress` | Fill in | Fill in | Timelock admin (multisig recommended) |
| `realVerifier` | `true` | `true` | Use real verifier for production |
| `ppVKey` | Fill in | Fill in | Pessimistic proof verification key |
| `ppVKeySelector` | `0x00000001` | `0x00000001` | Pessimistic proof selector |

### 5.2 create_rollup_parameters.json

```bash
vim qday/create_rollup_parameters.json
```

| Field | Description |
|-------|-------------|
| `trustedSequencerURL` | Sequencer RPC URL |
| `networkName` | L2 network name |
| `trustedSequencer` | Trusted sequencer address |
| `chainID` | L2 chain ID (must be unique) |
| `adminZkEVM` | L2 admin |
| `forkID` | `12` (do not modify) |
| `gasTokenAddress` | Gas token address (`""` = ETH) |

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

# Step 4: Generate Genesis
npx ts-node deployment/v2/1_createGenesis.ts

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
