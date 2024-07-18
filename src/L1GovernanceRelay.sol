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

interface CrossDomainMessengerLike {
    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable;
}

interface L2GovernanceRelayLike {
    function relay(address target, bytes calldata targetData) external;
}

// Relay a message from L1 to L2GovernanceRelay
contract L1GovernanceRelay {
    // --- storage variables ---

    mapping(address => uint256) public wards;

    // --- immutables ---

    address public immutable l2GovernanceRelay;
    CrossDomainMessengerLike public immutable messenger;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "L1GovernanceRelay/not-authorized");
        _;
    }

    // --- constructor ---

    constructor(
        address _l2GovernanceRelay,
        address _l1Messenger 
    ) {
        l2GovernanceRelay = _l2GovernanceRelay;
        messenger = CrossDomainMessengerLike(_l1Messenger);
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

    // --- relay ---

    function relay(address target, bytes calldata targetData, uint32 minGasLimit) external auth {
        messenger.sendMessage({
            _target: l2GovernanceRelay,
            _message: abi.encodeCall(L2GovernanceRelayLike.relay, (target, targetData)),
            _minGasLimit: minGasLimit
        });
    }
}
