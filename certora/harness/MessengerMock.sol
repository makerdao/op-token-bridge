// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.21;

interface GovernanceRelayLike {
    function relay(address, bytes calldata) external;
}

interface BridgeLike {
    function finalizeBridgeERC20(address, address, address, address, uint256, bytes calldata) external;
}

contract MessengerMock {
    address public xDomainMessageSender;
    address public lastTarget;
    bytes32 public lastMessageHash;
    uint32  public lastMinGasLimit;

    function getGovMessageHash(address target, bytes calldata targetData) public pure returns (bytes32) {
        return keccak256(abi.encodeCall(GovernanceRelayLike.relay, (target, targetData)));
    }

    function getBridgeMessageHash(address token1, address token2, address sender, address to, uint256 amount, bytes calldata extraData) public pure returns (bytes32) {
        return keccak256(abi.encodeCall(BridgeLike.finalizeBridgeERC20, (
            token1,
            token2,
            sender,
            to,
            amount,
            extraData
        )));
    }

    function sendMessage(address target, bytes calldata message, uint32 minGasLimit) public {
        lastTarget = target;
        lastMessageHash = keccak256(message);
        lastMinGasLimit = minGasLimit;
    }

}
