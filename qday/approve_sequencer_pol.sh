#!/bin/bash
# ============================================
# Sequencer POL approve to rollup contract
#
# Usage:
#   ./qday/approve_sequencer_pol.sh [sepolia|mainnet]
#   ./qday/approve_sequencer_pol.sh              # default: sepolia
#   ./qday/approve_sequencer_pol.sh sepolia
#   ./qday/approve_sequencer_pol.sh mainnet
#
# Meaning:
#   Wrapper around approve_sequencer_pol.ts. As Sequencer, calls
#   POL.approve(rollupProxy, MaxUint256) so the rollup contract can
#   pull POL for sequencing / bonding.
#
#   Approve target is the rollup proxy (create_rollup_output.json →
#   rollupAddress), NOT RollupManager.
#
# When to use:
#   - Automatically run by deploy.sh STEP 9 after a successful deploy
#   - Re-run manually if STEP 9 failed, or allowance was reset
#   - Requires qday/output/deploy_output.json and create_rollup_output.json
#
# Signer:
#   SEQ_PVT_KEY from .env, or MNEMONIC index 0 if SEQ_PVT_KEY is empty
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
