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

interface TokenLike {
    function mint(address, uint256) external;
    function burn(address, uint256) external;
}

interface CrossDomainMessengerLike {
    function xDomainMessageSender() external view returns (address);
    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable;
}

contract L2TokenBridge {
    // --- storage variables ---

    mapping(address => uint256) public wards;
    mapping(address => address) public l1ToL2Token;
    mapping(address => uint256) public maxWithdraws;
    uint256 public isOpen = 1;

    // --- immutables ---

    address public immutable otherBridge;
    CrossDomainMessengerLike public immutable messenger;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Closed();
    event TokenSet(address indexed l1Token, address indexed l2Token);
    event MaxWithdrawSet(address indexed l2Token, uint256 maxWithdraw);
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
        require(wards[msg.sender] == 1, "L2TokenBridge/not-authorized");
        _;
    }

    modifier onlyOtherBridge() {
        require(
            msg.sender == address(messenger) && messenger.xDomainMessageSender() == otherBridge,
            "L2TokenBridge/not-from-other-bridge"
        );
        _;
    }

    // --- constructor ---

    constructor(
        address _otherBridge,
        address _messenger
    ) {
        otherBridge = _otherBridge;
        messenger = CrossDomainMessengerLike(_messenger);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
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

    function close() external auth {
        isOpen = 0;
        emit Closed();
    }

    function registerToken(address l1Token, address l2Token) external auth {
        l1ToL2Token[l1Token] = l2Token;
        emit TokenSet(l1Token, l2Token);
    }

    function setMaxWithdraw(address l2Token, uint256 maxWithdraw) external auth {
        maxWithdraws[l2Token] = maxWithdraw;
        emit MaxWithdrawSet(l2Token, maxWithdraw);
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
        require(isOpen == 1, "L2TokenBridge/closed"); // do not allow initiating new xchain messages if bridge is closed
        require(_localToken != address(0) && l1ToL2Token[_remoteToken] == _localToken, "L2TokenBridge/invalid-token");
        require(_amount <= maxWithdraws[_localToken], "L2TokenBridge/amount-too-large");

        TokenLike(_localToken).burn(msg.sender, _amount); // TODO: should l2Tokens allow authed burn?

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

    /// @notice Sends ERC20 tokens to the sender's address on L1.
    /// @param _localToken  Address of the ERC20 on L2.
    /// @param _remoteToken Address of the corresponding token on L1.
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
        require(msg.sender.code.length == 0, "L2TokenBridge/sender-not-eoa");
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @notice Sends ERC20 tokens to a receiver's address on L1.
    /// @param _localToken  Address of the ERC20 on L2.
    /// @param _remoteToken Address of the corresponding token on L1.
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

    /// @notice Finalizes an ERC20 bridge on L2. Can only be triggered by the L1TokenBridge.
    /// @param _localToken  Address of the ERC20 on L2.
    /// @param _remoteToken Address of the corresponding token on L1.
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
        TokenLike(_localToken).mint(_to, _amount);

        emit ERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }
}
