/* eslint-disable no-console */
import path = require("path");
import * as dotenv from "dotenv";
dotenv.config({path: path.resolve(__dirname, "../.env")});
import {ethers} from "hardhat";

const deployOutput = require(path.join(__dirname, "output", "deploy_output.json"));
const createRollupOutput = require(path.join(__dirname, "output", "create_rollup_output.json"));
const createRollupParams = require(path.join(__dirname, "create_rollup_parameters.json"));

async function main() {
    const currentProvider = ethers.provider;

    if (!process.env.SEQ_PVT_KEY || process.env.SEQ_PVT_KEY.trim() === "") {
        throw new Error(".env → SEQ_PVT_KEY is missing. Set the Sequencer private key.");
    }

    let sequencer;
    try {
        sequencer = new ethers.Wallet(process.env.SEQ_PVT_KEY.trim(), currentProvider);
    } catch (_e) {
        throw new Error(".env → SEQ_PVT_KEY is not a valid private key.");
    }

    const expectedSeq = createRollupParams.trustedSequencer;
    if (!expectedSeq || !ethers.isAddress(expectedSeq)) {
        throw new Error("trustedSequencer address is invalid or missing in create_rollup_parameters.json");
    }
    if (sequencer.address.toLowerCase() !== expectedSeq.toLowerCase()) {
        throw new Error(
            `SEQ_PVT_KEY address ${sequencer.address} does not match ` +
                `create_rollup_parameters.json → trustedSequencer ${expectedSeq}`
        );
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
