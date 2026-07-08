/* eslint-disable no-console */
import path = require("path");
import fs = require("fs");
import * as dotenv from "dotenv";
dotenv.config({path: path.resolve(__dirname, "../.env")});
import {ethers} from "hardhat";

const deployOutput = require(path.join(__dirname, "output", "deploy_output.json"));
const createRollupOutput = require(path.join(__dirname, "output", "create_rollup_output.json"));
const createRollupParams = require(path.join(__dirname, "create_rollup_parameters.json"));

async function main() {
    const currentProvider = ethers.provider;

    // Sequencer: use SEQ_PVT_KEY from env, then try MNEMONIC index 0
    let sequencer;
    if (process.env.SEQ_PVT_KEY && process.env.SEQ_PVT_KEY !== "") {
        sequencer = new ethers.Wallet(process.env.SEQ_PVT_KEY, currentProvider);
    } else {
        sequencer = ethers.HDNodeWallet.fromMnemonic(
            ethers.Mnemonic.fromPhrase(process.env.MNEMONIC || ""),
            "m/44'/60'/0'/0/0"
        ).connect(currentProvider);
    }
    console.log(`Sequencer address: ${sequencer.address}`);

    const polAddr = deployOutput.polTokenAddress;
    const rollupAddr = createRollupOutput.rollupAddress;

    if (!rollupAddr || !ethers.isAddress(rollupAddr)) {
        throw new Error(`Invalid rollup address: ${rollupAddr}`);
    }
    if (!polAddr || !ethers.isAddress(polAddr)) {
        throw new Error(`Invalid POL address: ${polAddr}`);
    }

    console.log(`POL token:    ${polAddr}`);
    console.log(`Rollup proxy: ${rollupAddr}`);

    // Check if already approved
    const pol = await ethers.getContractAt(
        [
            "function allowance(address,address) view returns (uint256)",
            "function approve(address,uint256) returns (bool)"
        ],
        polAddr,
        sequencer
    );
    const allowance: bigint = await pol.allowance(sequencer.address, rollupAddr);
    if (allowance > 0n) {
        console.log(`Already approved: ${ethers.formatEther(allowance)} POL`);
        return;
    }

    const maxApproval = ethers.MaxUint256;
    console.log(`Approving max (${ethers.formatEther(maxApproval)} POL)...`);
    const tx = await pol.approve(rollupAddr, maxApproval);
    await tx.wait();

    console.log("Approval complete.");
    console.log(`Tx: ${tx.hash}`);
}

main().catch((e) => {
    console.error("[ERROR]", e.message);
    process.exit(1);
});
