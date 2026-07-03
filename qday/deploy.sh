#!/bin/bash
# ============================================
# QDAY zkRollup contract deployment script
# Targets: Sepolia testnet / Ethereum mainnet
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
    echo "[ERROR] .env file not found. Run: cp qday/.env.example .env and fill in the values"
    exit 1
fi

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

# Generate Genesis
echo "[STEP 4] Generating Genesis..."
npx ts-node "$PROJECT_ROOT/deployment/v2/1_createGenesis.ts"

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
    cp "$PROJECT_ROOT/deployment/v2/create_rollup_output_"*.json "$OUTPUT_DIR/create_rollup_output.json"
fi
[ -f "$PROJECT_ROOT/deployment/v2/genesis_sovereign.json" ] && cp "$PROJECT_ROOT/deployment/v2/genesis_sovereign.json" "$OUTPUT_DIR/"

# Save deployment snapshot
if [ "$NETWORK" = "sepolia" ]; then
    npm run saveDeployment:sepolia 2>/dev/null || true
elif [ "$NETWORK" = "mainnet" ]; then
    npm run saveDeployment:mainnet 2>/dev/null || true
fi

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
