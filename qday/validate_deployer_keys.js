/* eslint-disable no-console */
/**
 * Fail-fast check: both parameter files must contain the same Deployer key.
 * Used by deploy.sh / deploy_pol.sh before compile. Does not write any file.
 */
const {Wallet} = require("ethers");
const path = require("path");

const deploy = require(path.join(__dirname, "deploy_parameters.json"));
const create = require(path.join(__dirname, "create_rollup_parameters.json"));

function walletFrom(key, file) {
    if (key === undefined || key === null || String(key).trim() === "") {
        console.error(`[ERROR] ${file} → deployerPvtKey is missing. Fill it in manually.`);
        process.exit(1);
    }
    try {
        return new Wallet(String(key).trim());
    } catch (_e) {
        console.error(`[ERROR] ${file} → deployerPvtKey is not a valid private key.`);
        process.exit(1);
    }
}

const deployWallet = walletFrom(deploy.deployerPvtKey, "qday/deploy_parameters.json");
const createWallet = walletFrom(create.deployerPvtKey, "qday/create_rollup_parameters.json");
if (deployWallet.address.toLowerCase() !== createWallet.address.toLowerCase()) {
    console.error("[ERROR] deployerPvtKey addresses differ:");
    console.error(`        qday/deploy_parameters.json        → ${deployWallet.address}`);
    console.error(`        qday/create_rollup_parameters.json → ${createWallet.address}`);
    console.error("        Both files must use the same Deployer key.");
    process.exit(1);
}
console.log(`[CHECK] Deployer keys match: ${deployWallet.address}`);
