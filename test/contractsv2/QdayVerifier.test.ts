import {expect} from "chai";
import {ethers} from "hardhat";
import {QdayVerifier} from "../../typechain-types";

const RFIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

describe("QdayVerifier", () => {
    async function deploy() {
        const [, aggregator, other] = await ethers.getSigners();
        const verifier = (await ethers.deployContract("QdayVerifier", [aggregator.address])) as unknown as QdayVerifier;
        return {aggregator, other, verifier};
    }

    function snarkInput(caller: string) {
        return ethers.solidityPacked(
            ["address", "bytes32", "bytes32", "uint64", "uint64", "uint64", "bytes32", "bytes32", "bytes32", "uint64"],
            [
                caller,
                ethers.id("old-root"),
                ethers.id("old-acc"),
                0n,
                44005n,
                12n,
                ethers.id("new-root"),
                ethers.id("new-acc"),
                ethers.id("ler"),
                1n,
            ]
        );
    }

    function inputSnark(verifyData: string) {
        return BigInt(ethers.sha256(verifyData)) % RFIELD;
    }

    async function signedProof(
        signer: {signMessage: (message: Uint8Array) => Promise<string>},
        verifyData: string,
        result = 1n
    ) {
        const padded = ethers.zeroPadBytes(verifyData, 224);
        const words: string[] = [];
        for (let i = 0; i < 7; i++) {
            words.push(ethers.dataSlice(padded, i * 32, (i + 1) * 32));
        }
        words.push(ethers.toBeHex(result, 32));
        const inner = ethers.keccak256(ethers.concat([verifyData, words[7]]));
        const signature = ethers.Signature.from(await signer.signMessage(ethers.getBytes(inner)));
        words.push(signature.r, signature.s, ethers.toBeHex(signature.v, 32));
        while (words.length < 24) {
            words.push(ethers.ZeroHash);
        }
        return words;
    }

    it("accepts a proof signed by the aggregator deployed into the contract", async () => {
        const {aggregator, verifier} = await deploy();
        const verifyData = snarkInput(aggregator.address);
        expect(ethers.dataLength(verifyData)).to.equal(212);

        const proof = await signedProof(aggregator, verifyData);
        expect(await verifier.messageHash(proof)).to.equal(
            ethers.keccak256(ethers.concat([verifyData, ethers.toBeHex(1n, 32)]))
        );
        expect(await verifier.verifyProof(proof, [inputSnark(verifyData)])).to.equal(true);
    });

    it("rejects a signature from any other address", async () => {
        const {aggregator, other, verifier} = await deploy();
        const verifyData = snarkInput(aggregator.address);
        const proof = await signedProof(other, verifyData);

        expect(await verifier.verifyProof(proof, [inputSnark(verifyData)])).to.equal(false);
    });

    it("rejects a failed verification result", async () => {
        const {aggregator, verifier} = await deploy();
        const verifyData = snarkInput(aggregator.address);
        const proof = await signedProof(aggregator, verifyData, 0n);

        expect(await verifier.verifyProof(proof, [inputSnark(verifyData)])).to.equal(false);
    });

    it("rejects verify data that does not hash to the public input", async () => {
        const {aggregator, verifier} = await deploy();
        const verifyData = snarkInput(aggregator.address);
        const proof = await signedProof(aggregator, verifyData);

        expect(await verifier.verifyProof(proof, [inputSnark(verifyData) + 1n])).to.equal(false);
    });

    it("rejects a non-zero unused tail", async () => {
        const {aggregator, verifier} = await deploy();
        const verifyData = snarkInput(aggregator.address);
        const proof = await signedProof(aggregator, verifyData);
        proof[11] = ethers.toBeHex(1n, 32);

        expect(await verifier.verifyProof(proof, [inputSnark(verifyData)])).to.equal(false);
    });

    it("reverts when the aggregator address is zero", async () => {
        const factory = await ethers.getContractFactory("QdayVerifier");
        await expect(ethers.deployContract("QdayVerifier", [ethers.ZeroAddress])).to.be.revertedWithCustomError(
            factory,
            "AggregatorAddressZero"
        );
    });
});
