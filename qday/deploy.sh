#!/bin/bash
# ============================================
# QDAY zkRollup contract deployment script
# Targets: Sepolia testnet / Ethereum mainnet
# Consensus: PolygonZkEVMEtrog (fork12)
#
# Usage:
#   ./qday/deploy.sh [sepolia|mainnet]
#   ./qday/deploy.sh              # default: sepolia
#   ./qday/deploy.sh sepolia      # Sepolia (auto-deploys test POL)
#   ./qday/deploy.sh mainnet      # Mainnet (polTokenAddress required)
#
# Prerequisites:
#   - Copy qday/env.example → .env and fill SEQ_PVT_KEY + RPC URLs
#   - Fill deployerPvtKey in BOTH qday/deploy_parameters.json and
#     qday/create_rollup_parameters.json (same Deployer key, manual)
#
# Steps:
#   0. Compile contracts
#   1. Copy parameter files into deployment/v2/
#   2. Check deployer balance + fund Sequencer/Aggregator (1000 ETH each)
#   3. Deploy test POL (Sepolia) or validate polTokenAddress (Mainnet)
#   4. Generate genesis.json
#   5. Deploy PolygonZkEVMDeployer
#   6. Deploy L1 core contracts (Bridge/GER/AggLayerGateway/RollupManager/Timelock)
#   7. Create zkRollup
#   8. Collect output → qday/output/
#   9. Approve rollup contract to spend Sequencer's POL
#  10. Clean up intermediate files in deployment/v2/
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NETWORK="${1:-sepolia}"

if [ "$NETWORK" != "sepolia" ] && [ "$NETWORK" != "mainnet" ]; then
    echo "Usage: ./deploy.sh <network>"
    echo "  sepolia  - Deploy to Sepolia testnet (auto-deploys test POL)"
    echo "  mainnet  - Deploy to Ethereum mainnet (polTokenAddress required)"
    exit 1
fi

echo "========================================"
echo "  QDAY zkRollup Contract Deployment"
echo "  Network: $NETWORK"
echo "  Consensus: PolygonZkEVMEtrog (fork12)"
echo "========================================"

# Check .env
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo "[ERROR] .env file not found. Run: cp qday/env.example .env and fill in the values"
    exit 1
fi

set -a
# shellcheck disable=SC1091
source "$PROJECT_ROOT/.env"
set +a

if [ -z "${SEQ_PVT_KEY:-}" ]; then
    echo "[ERROR] .env → SEQ_PVT_KEY is missing. Set the Sequencer private key."
    exit 1
fi

cd "$PROJECT_ROOT"
node "$SCRIPT_DIR/validate_deployer_keys.js"

# Compile contracts
echo "[STEP 0] Compiling contracts..."
cd "$PROJECT_ROOT"
npx hardhat compile

# Copy parameter files
echo "[STEP 1] Copying deployment parameters..."
cp "$SCRIPT_DIR/deploy_parameters.json" "$PROJECT_ROOT/deployment/v2/deploy_parameters.json"
cp "$SCRIPT_DIR/create_rollup_parameters.json" "$PROJECT_ROOT/deployment/v2/create_rollup_parameters.json"

# Pre-deployment checks: deployer balance + fund Sequencer/Aggregator
echo "[STEP 2] Checking deployer balance + funding Sequencer/Aggregator (1000 ETH each)..."
npx hardhat run "$SCRIPT_DIR/pre_deploy_check.ts" --network "$NETWORK"

# Prepare testnet: deploy POL
if [ "$NETWORK" = "sepolia" ]; then
    echo "[STEP 3] Preparing testnet: deploying POL token..."
    npx hardhat run deployment/testnet/prepareTestnet.ts --network sepolia
    echo ""
    echo "  POL deployed on Sepolia, address written back to deploy_parameters.json"
    echo ""
elif [ "$NETWORK" = "mainnet" ]; then
    POL_ADDR=$(cd "$SCRIPT_DIR" && node -e "console.log(require('./deploy_parameters.json').polTokenAddress)" 2>/dev/null || echo "")
    if [ -z "$POL_ADDR" ] || [ "$POL_ADDR" = "" ]; then
        echo "[ERROR] Mainnet deployment requires polTokenAddress"
        echo "        Edit qday/deploy_parameters.json and set the mainnet POL token address"
        exit 1
    fi
    echo "[STEP 3] Mainnet mode: POL token address = $POL_ADDR (skipping auto-deploy)"
fi

# Generate Genesis (in-memory Hardhat simulation — not L1).
# --test forces Hardhat's default mnemonic so genesis does not depend on .env MNEMONIC.
echo "[STEP 4] Generating Genesis..."
npx ts-node "$PROJECT_ROOT/deployment/v2/1_createGenesis.ts" --test

# Deploy ZkEVMDeployer
echo "[STEP 5] Deploying PolygonZkEVMDeployer..."
rm -f "$PROJECT_ROOT/.openzeppelin/${NETWORK}.json"
rm -f "$PROJECT_ROOT/deployment/v2/deploy_ongoing.json"
npx hardhat run "$PROJECT_ROOT/deployment/v2/2_deployPolygonZKEVMDeployer.ts" --network "$NETWORK"

# Deploy L1 core contracts
echo "[STEP 6] Deploying L1 core contracts (Bridge/GlobalExitRoot/AggLayerGateway/RollupManager/Timelock)..."
npx hardhat run "$PROJECT_ROOT/deployment/v2/3_deployContracts.ts" --network "$NETWORK"

# Create zkRollup
echo "[STEP 7] Creating zkRollup..."
npx hardhat run "$PROJECT_ROOT/deployment/v2/4_createRollup.ts" --network "$NETWORK"

# Collect deployment output
echo "[STEP 8] Collecting deployment output..."
OUTPUT_DIR="$SCRIPT_DIR/output"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cp "$PROJECT_ROOT/deployment/v2/deploy_output.json" "$OUTPUT_DIR/"
cp "$PROJECT_ROOT/deployment/v2/genesis.json" "$OUTPUT_DIR/"
if ls "$PROJECT_ROOT/deployment/v2/create_rollup_output_"*.json 1> /dev/null 2>&1; then
    # 4_createRollup.ts writes a new timestamped file each run, so the glob may
    # match several files. Pick the most recent one and copy it under a stable name.
    LATEST_ROLLUP_OUTPUT=$(ls -t "$PROJECT_ROOT/deployment/v2/create_rollup_output_"*.json 2>/dev/null | head -n 1)
    cp "$LATEST_ROLLUP_OUTPUT" "$OUTPUT_DIR/create_rollup_output.json"
fi
[ -f "$PROJECT_ROOT/deployment/v2/genesis_sovereign.json" ] && cp "$PROJECT_ROOT/deployment/v2/genesis_sovereign.json" "$OUTPUT_DIR/"

# Save deployment snapshot
if [ "$NETWORK" = "sepolia" ]; then
    npm run saveDeployment:sepolia || true
elif [ "$NETWORK" = "mainnet" ]; then
    npm run saveDeployment:mainnet || true
fi

# Approve rollup contract to spend Sequencer's POL
echo "[STEP 9] Approving rollup contract to spend POL (Sequencer → Rollup)..."
npx hardhat run "$SCRIPT_DIR/approve_sequencer_pol.ts" --network "$NETWORK"

# Clean up intermediate files generated under deployment/v2/ during this run.
# Outputs are already preserved in $OUTPUT_DIR and the deployments/<network>_<ts>/ snapshot,
# so the copies in deployment/v2/ are safe to remove. .example templates and source scripts are kept.
echo "[STEP 10] Cleaning up intermediate files in deployment/v2/..."
rm -f "$PROJECT_ROOT/deployment/v2/deploy_output.json" \
      "$PROJECT_ROOT/deployment/v2/deploy_parameters.json" \
      "$PROJECT_ROOT/deployment/v2/deploy_ongoing.json" \
      "$PROJECT_ROOT/deployment/v2/genesis.json" \
      "$PROJECT_ROOT/deployment/v2/genesis_sovereign.json" \
      "$PROJECT_ROOT/deployment/v2/create_rollup_parameters.json" \
      "$PROJECT_ROOT/deployment/v2/create_rollup_output_"*.json
echo "[STEP 10] Cleanup done."

echo ""
echo "========================================"
echo "  Deployment complete! ($NETWORK)"
echo "  Output dir: $OUTPUT_DIR/"
echo "========================================"
echo ""
echo "Output files:"
echo "  $OUTPUT_DIR/genesis.json              - L2 genesis config (required by zkEVM node)"
echo "  $OUTPUT_DIR/deploy_output.json        - All L1 contract addresses"
echo "  $OUTPUT_DIR/create_rollup_output.json - Rollup address + first batch data"
echo ""
echo "Next steps:"
echo "  1. Contract verification: npm run verify:v2:${NETWORK}"
echo "  2. Configure the output files in your zkEVM node setup"
