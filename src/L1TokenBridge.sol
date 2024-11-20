// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2024 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.21;

import { UUPSUpgradeable, ERC1967Utils } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface TokenLike {
    function transferFrom(address, address, uint256) external;
}

interface CrossDomainMessengerLike {
    function xDomainMessageSender() external view returns (address);
    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable;
}

contract L1TokenBridge is UUPSUpgradeable {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(address => address) public l1ToL2Token;
    uint256 public isOpen;
    address public escrow;

    // --- immutables and const ---

    address public immutable otherBridge;
    CrossDomainMessengerLike public immutable messenger;
    string public constant version = "1";

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Closed();
    event TokenSet(address indexed l1Token, address indexed l2Token);
    event ERC20BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );
    event ERC20BridgeFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "L1TokenBridge/not-authorized");
        _;
    }

    modifier onlyOtherBridge() {
        require(
            msg.sender == address(messenger) && messenger.xDomainMessageSender() == otherBridge,
            "L1TokenBridge/not-from-other-bridge"
        );
        _;
    }

    // --- constructor ---

    constructor(
        address _otherBridge,
        address _messenger
    ) {
        _disableInitializers(); // Avoid initializing in the context of the implementation

        otherBridge = _otherBridge;
        messenger = CrossDomainMessengerLike(_messenger);
    }

    // --- upgradability ---

    function initialize() initializer external {
        __UUPSUpgradeable_init();

        isOpen = 1;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal override auth {}

    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    // --- administration ---

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "escrow") {
            escrow = data;
        } else revert("L1TokenBridge/file-unrecognized-param");
        emit File(what, data);
    }

    function close() external auth {
        isOpen = 0;
        emit Closed();
    }

    function registerToken(address l1Token, address l2Token) external auth {
        l1ToL2Token[l1Token] = l2Token;
        emit TokenSet(l1Token, l2Token);
    }

    // -- bridging --

    function _initiateBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    ) internal {
        require(isOpen == 1, "L1TokenBridge/closed"); // do not allow initiating new xchain messages if bridge is closed
        require(_remoteToken != address(0) && l1ToL2Token[_localToken] == _remoteToken, "L1TokenBridge/invalid-token");

        TokenLike(_localToken).transferFrom(msg.sender, escrow, _amount);

        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeCall(this.finalizeBridgeERC20, (
                // Because this call will be executed on the remote chain, we reverse the order of
                // the remote and local token addresses relative to their order in the
                // finalizeBridgeERC20 function.
                _remoteToken,
                _localToken,
                msg.sender,
                _to,
                _amount,
                _extraData
            )),
            _minGasLimit: _minGasLimit
        });

        emit ERC20BridgeInitiated(_localToken, _remoteToken, msg.sender, _to, _amount, _extraData);
    }

    /// @notice Sends ERC20 tokens to the sender's address on L2.
    /// @param _localToken  Address of the ERC20 on L1.
    /// @param _remoteToken Address of the corresponding token on L2.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeERC20(
        address _localToken,
        address _remoteToken,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external {
        require(msg.sender.code.length == 0, "L1TokenBridge/sender-not-eoa");
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @notice Sends ERC20 tokens to a receiver's address on L2.
    /// @param _localToken  Address of the ERC20 on L1.
    /// @param _remoteToken Address of the corresponding token on L2.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external {
        _initiateBridgeERC20(_localToken, _remoteToken, _to, _amount, _minGasLimit, _extraData);
    }

    /// @notice Finalizes an ERC20 bridge on L1. Can only be triggered by the L2TokenBridge.
    /// @param _localToken  Address of the ERC20 on L1.
    /// @param _remoteToken Address of the corresponding token on L2.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 being bridged.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function finalizeBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        external
        onlyOtherBridge
    {
        TokenLike(_localToken).transferFrom(escrow, _to, _amount);

        emit ERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }
}
