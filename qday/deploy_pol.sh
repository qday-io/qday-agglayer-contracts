#!/bin/bash
# ============================================
# Standalone POL token deployment and funding script
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NETWORK="${1:-sepolia}"

if [ "$NETWORK" != "sepolia" ] && [ "$NETWORK" != "mainnet" ]; then
    echo "Usage: ./deploy_pol.sh <network>"
    echo "  sepolia  - Deploy test POL on Sepolia"
    echo "  mainnet  - Mainnet already has POL, use this to just fund Sequencer"
    exit 1
fi

echo "========================================"
echo "  POL Token Deployment & Sequencer Funding"
echo "  Network: $NETWORK"
echo "========================================"

if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo "[ERROR] .env file not found. Run: cp qday/.env.example .env and fill in the values"
    exit 1
fi

# Compile
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

if [ "$NETWORK" = "mainnet" ]; then
    POL_ADDR=$(cd "$SCRIPT_DIR" && node -e "console.log(require('./deploy_parameters.json').polTokenAddress)" 2>/dev/null || echo "")

    if [ -z "$POL_ADDR" ] || [ "$POL_ADDR" = "" ]; then
        echo "[ERROR] polTokenAddress is required in qday/deploy_parameters.json"
        exit 1
    fi

    echo "[STEP 3] Funding Sequencer with 100,000 POL from $POL_ADDR..."
    npx hardhat run "$PROJECT_ROOT/deployment/testnet/prepareTestnet.ts" --network mainnet
else
    echo "[STEP 3] Deploying test POL token + funding Sequencer with POL..."
    npx hardhat run deployment/testnet/prepareTestnet.ts --network sepolia
fi

echo ""
echo "========================================"
echo "  Done!"
echo "  Check qday/deploy_parameters.json for polTokenAddress"
echo "========================================"
