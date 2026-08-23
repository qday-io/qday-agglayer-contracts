/**
 * QDAY pre-deployment check & funding script.
 *
 * Usage:
 *   npx hardhat run qday/pre_deploy_check.ts --network sepolia
 *   npx hardhat run qday/pre_deploy_check.ts --network mainnet
 *
 * Called automatically by deploy.sh STEP 2. Can also be run standalone.
 *
 * Prerequisites:
 *   - deployerPvtKey in BOTH deploy_parameters.json and create_rollup_parameters.json
 *     (same key, filled in manually)
 *   - SEPOLIA_PROVIDER / MAINNET_PROVIDER for the target network
 *
 * Steps:
 *   1. Resolve deployer from deployerPvtKey (both files must match)
 *
 *   2. Validate addresses
 *      - trustedSequencer from create_rollup_parameters.json
 *      - trustedAggregator from deploy_parameters.json
 *
 *   3. Check deployer ETH balance
 *      - Require >= 2000 ETH (1000 Sequencer + 1000 Aggregator)
 *      - Does not include gas overhead for later deploy steps
 *
 *   4. Check deployer POL balance (only if polTokenAddress is set)
 *      - Mainnet: require >= 100,000 POL
 *      - Sepolia: usually empty; POL is deployed later by prepareTestnet
 *
 *   5. Fund accounts
 *      - Sequencer: 1000 ETH
 *      - Aggregator: 1000 ETH
 *      - Sequencer: 100,000 POL (only when polTokenAddress is set)
 */

/* eslint-disable no-console */
import path = require("path");
import * as dotenv from "dotenv";
dotenv.config({path: path.resolve(__dirname, "../.env")});
import {ethers} from "hardhat";

const deployParams = require(path.join(__dirname, "deploy_parameters.json"));
const createRollupParams = require(path.join(__dirname, "create_rollup_parameters.json"));
const ETH_FUND = ethers.parseEther("1000");
const POL_FUND = ethers.parseEther("100000");

function walletFromKey(key: unknown, file: string) {
    if (key === undefined || key === null || String(key).trim() === "") {
        throw new Error(`${file} → deployerPvtKey is missing. Fill it in manually.`);
    }
    try {
        return new ethers.Wallet(String(key).trim());
    } catch (_e) {
        throw new Error(`${file} → deployerPvtKey is not a valid private key.`);
    }
}

async function main() {
    const currentProvider = ethers.provider;

    const deployWallet = walletFromKey(deployParams.deployerPvtKey, "qday/deploy_parameters.json");
    const createWallet = walletFromKey(
        createRollupParams.deployerPvtKey,
        "qday/create_rollup_parameters.json"
    );
    if (deployWallet.address.toLowerCase() !== createWallet.address.toLowerCase()) {
        throw new Error(
            "deployerPvtKey addresses differ: " +
                `deploy_parameters.json → ${deployWallet.address}, ` +
                `create_rollup_parameters.json → ${createWallet.address}. ` +
                "Both files must use the same Deployer key."
        );
    }

    const deployer = deployWallet.connect(currentProvider);

    const deployerAddr = deployer.address;
    console.log(`[CHECK] Deployer: ${deployerAddr}`);

    // ---- Validate addresses ----
    const seqAddr = createRollupParams.trustedSequencer;
    const aggrAddr = deployParams.trustedAggregator;
    if (!seqAddr || !ethers.isAddress(seqAddr)) {
        throw new Error("trustedSequencer address is invalid or missing in create_rollup_parameters.json");
    }
    if (!aggrAddr || !ethers.isAddress(aggrAddr)) {
        throw new Error("trustedAggregator address is invalid or missing in deploy_parameters.json");
    }
    console.log(`[CHECK] Sequencer: ${seqAddr}`);
    console.log(`[CHECK] Aggregator: ${aggrAddr}`);

    // ---- Check ETH balance ----
    const ethBalance = await currentProvider.getBalance(deployerAddr);
    console.log(`[CHECK] Deployer ETH balance: ${ethers.formatEther(ethBalance)} ETH`);

    const minEth = ETH_FUND * 2n; // 1000 + 1000
    if (ethBalance < minEth) {
        throw new Error(
            `Deployer ETH balance too low. Need >= ${ethers.formatEther(minEth)} ETH ` +
            `(1000 for Sequencer + 1000 for Aggregator), have ${ethers.formatEther(ethBalance)} ETH`
        );
    }

    // ---- Check POL balance (Mainnet only; Sepolia POL is deployed later) ----
    const hasPol = deployParams.polTokenAddress && deployParams.polTokenAddress !== "";
    if (hasPol) {
        const pol = await ethers.getContractAt(
            ["function balanceOf(address) view returns (uint256)"],
            deployParams.polTokenAddress,
            deployer
        );
        const polBalance: bigint = await pol.balanceOf(deployerAddr);
        console.log(`[CHECK] Deployer POL balance: ${ethers.formatEther(polBalance)} POL`);

        if (polBalance < POL_FUND) {
            throw new Error(
                `Deployer POL balance too low. Need >= ${ethers.formatEther(POL_FUND)} POL, ` +
                `have ${ethers.formatEther(polBalance)} POL`
            );
        }
    } else {
        console.log("[CHECK] POL token not yet deployed (will be deployed by prepareTestnet).");
    }

    console.log("[CHECK] All checks passed.\n");

    // ---- Fund Sequencer: 1000 ETH ----
    console.log(`[FUND] Sending 1000 ETH to Sequencer: ${seqAddr}`);
    await (await deployer.sendTransaction({to: seqAddr, value: ETH_FUND})).wait();
    console.log("[FUND] Sequencer ETH funded.");

    // ---- Fund Aggregator: 1000 ETH ----
    console.log(`[FUND] Sending 1000 ETH to Aggregator: ${aggrAddr}`);
    await (await deployer.sendTransaction({to: aggrAddr, value: ETH_FUND})).wait();
    console.log("[FUND] Aggregator ETH funded.");

    // ---- Fund Sequencer: 100,000 POL (Mainnet only) ----
    if (hasPol) {
        const pol = await ethers.getContractAt(
            ["function transfer(address,uint256) returns (bool)"],
            deployParams.polTokenAddress,
            deployer
        );
        console.log(`[FUND] Sending 100,000 POL to Sequencer: ${seqAddr}`);
        await (await pol.transfer(seqAddr, POL_FUND)).wait();
        console.log("[FUND] Sequencer POL funded.\n");
    } else {
        console.log("[FUND] Skipping POL transfer (will be handled by prepareTestnet).\n");
    }
}

main().catch((e) => {
    console.error("[ERROR]", e.message);
    process.exit(1);
});
