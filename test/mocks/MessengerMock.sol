// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.21;

contract MessengerMock {
    address public xDomainMessageSender;
    address public lastTarget;
    bytes32 public lastMessageHash;
    uint32  public lastMinGasLimit;

    event SentMessage(address indexed target, address sender, bytes message, uint256 messageNonce, uint256 gasLimit);

    function setXDomainMessageSender(address xDomainMessageSender_) external {
        xDomainMessageSender = xDomainMessageSender_;
    }

    function sendMessage(address target, bytes calldata message, uint32 minGasLimit) external payable {
        lastTarget = target;
        lastMessageHash = keccak256(message);
        lastMinGasLimit = minGasLimit;
        emit SentMessage(target, msg.sender, message, 0, minGasLimit);
    }
}
