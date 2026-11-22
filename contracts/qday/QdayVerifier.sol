// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.28;

import "../interfaces/IVerifierRollup.sol";
import {ECDSA} from "@openzeppelin/contracts52/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts52/utils/cryptography/MessageHashUtils.sol";

/**
 * @title QdayVerifier
 * @notice QDAY-only Etrog verifier. Same `IVerifierRollup` entry as `FflonkVerifier_12`,
 * but the proof is an aggregator attestation instead of a Fflonk proof.
 *
 * `PolygonRollupManager` calls `verifyProof(proof, [inputSnark])`, where
 * `inputSnark = uint256(sha256(verifyData)) % _RFIELD` and `verifyData` is the
 * 212-byte payload built in `_getInputSnarkBytes`.
 *
 * `proof` (`bytes32[24]`) layout:
 * - `[0..5]` and the high 20 bytes of `[6]`: `verifyData` (212 bytes). Low 12 bytes of `[6]` must be 0.
 * - `[7]`: verification result. `1` means the aggregator accepts this transition.
 * - `[8]`: ECDSA `r`
 * - `[9]`: ECDSA `s`
 * - `[10]`: ECDSA `v` (`27` or `28`)
 * - `[11..23]`: must be zero
 *
 * The configured aggregator signs `messageHash(proof)` with EIP-191 `personal_sign`.
 * That address is fixed in the constructor.
 *
 * `verifyData` byte layout, matching `PolygonRollupManager._getInputSnarkBytes`:
 * - `address` caller (20)
 * - `bytes32` oldStateRoot
 * - `bytes32` oldAccInputHash
 * - `uint64` initNumBatch
 * - `uint64` chainID
 * - `uint64` forkID
 * - `bytes32` newStateRoot
 * - `bytes32` newAccInputHash
 * - `bytes32` newLocalExitRoot
 * - `uint64` finalNewBatch
 */
contract QdayVerifier is IVerifierRollup {
    /// @notice zkSNARK scalar field, same modulus `PolygonRollupManager` uses for `inputSnark`.
    uint256 internal constant _RFIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    uint256 private constant _RESULT_WORD = 7;
    uint256 private constant _SIG_R_WORD = 8;
    uint256 private constant _SIG_S_WORD = 9;
    uint256 private constant _SIG_V_WORD = 10;
    bytes32 private constant _RESULT_OK = bytes32(uint256(1));

    /// @notice Aggregator address accepted as the ECDSA signer. Set at deployment.
    address public immutable aggregator;

    error AggregatorAddressZero();

    /**
     * @param aggregatorAddress Signer that must attest every accepted proof.
     */
    constructor(address aggregatorAddress) {
        if (aggregatorAddress == address(0)) {
            revert AggregatorAddressZero();
        }
        aggregator = aggregatorAddress;
    }

    /**
     * @notice Inner hash the aggregator must `personal_sign`.
     * @dev Signature words are not part of the hash. `proof[7]` is.
     */
    function messageHash(
        bytes32[24] calldata proof
    ) external pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(_verifyData(proof), proof[_RESULT_WORD])
            );
    }

    /**
     * @inheritdoc IVerifierRollup
     * @dev Returns false for a bad shape, a rejected result, a public input that
     * does not match `verifyData`, or a signature from any address other than `aggregator`.
     */
    function verifyProof(
        bytes32[24] calldata proof,
        uint256[1] calldata pubSignals
    ) external view returns (bool) {
        if (!_proofShapeIsValid(proof)) {
            return false;
        }

        bytes memory verifyData = _verifyData(proof);
        if (uint256(sha256(verifyData)) % _RFIELD != pubSignals[0]) {
            return false;
        }

        bytes32 digest = MessageHashUtils.toEthSignedMessageHash(
            keccak256(abi.encodePacked(verifyData, proof[_RESULT_WORD]))
        );
        (address signer, ECDSA.RecoverError err, ) = ECDSA.tryRecover(
            digest,
            uint8(uint256(proof[_SIG_V_WORD])),
            proof[_SIG_R_WORD],
            proof[_SIG_S_WORD]
        );
        return err == ECDSA.RecoverError.NoError && signer == aggregator;
    }

    function _proofShapeIsValid(
        bytes32[24] calldata proof
    ) private pure returns (bool) {
        if (proof[_RESULT_WORD] != _RESULT_OK) {
            return false;
        }
        // Last verify-data word holds 20 bytes. The low 12 bytes stay unused.
        if (uint96(uint256(proof[6])) != 0) {
            return false;
        }
        uint256 vWord = uint256(proof[_SIG_V_WORD]);
        if (vWord != 27 && vWord != 28) {
            return false;
        }
        for (uint256 i = 11; i < 24; ) {
            if (proof[i] != bytes32(0)) {
                return false;
            }
            unchecked {
                ++i;
            }
        }
        return true;
    }

    /// @dev 6 full words plus the high 20 bytes of word 6. Total 212 bytes.
    function _verifyData(
        bytes32[24] calldata proof
    ) private pure returns (bytes memory) {
        return
            abi.encodePacked(
                proof[0],
                proof[1],
                proof[2],
                proof[3],
                proof[4],
                proof[5],
                bytes20(proof[6])
            );
    }
}
