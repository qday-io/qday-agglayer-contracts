#!/bin/bash
# ============================================
# Sequencer POL approve to rollup contract
# ============================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NETWORK="${1:-sepolia}"

if [ "$NETWORK" != "sepolia" ] && [ "$NETWORK" != "mainnet" ]; then
    echo "Usage: ./approve_sequencer_pol.sh <network>"
    echo "  sepolia | mainnet"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/output/deploy_output.json" ] || [ ! -f "$SCRIPT_DIR/output/create_rollup_output.json" ]; then
    echo "[ERROR] Output files not found. Run deploy.sh first."
    exit 1
fi

cd "$PROJECT_ROOT"
npx hardhat run "$SCRIPT_DIR/approve_sequencer_pol.ts" --network "$NETWORK"
