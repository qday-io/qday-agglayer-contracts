/* eslint-disable no-console */
import path = require("path");
import * as dotenv from "dotenv";
dotenv.config({path: path.resolve(__dirname, "../.env")});
import {ethers} from "hardhat";

const deployParams = require(path.join(__dirname, "deploy_parameters.json"));
const createRollupParams = require(path.join(__dirname, "create_rollup_parameters.json"));
const ETH_FUND = ethers.parseEther("1000");
const POL_FUND = ethers.parseEther("100000");

async function main() {
    const currentProvider = ethers.provider;

    const deployer = deployParams.deployerPvtKey
        ? new ethers.Wallet(deployParams.deployerPvtKey, currentProvider)
        : ethers.HDNodeWallet.fromMnemonic(
              ethers.Mnemonic.fromPhrase(process.env.MNEMONIC || ""),
              "m/44'/60'/0'/0/0"
          ).connect(currentProvider);

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
