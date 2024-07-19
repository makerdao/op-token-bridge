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
    function xDomainMessageSender() external view returns (address);
}

// Receive xchain message from L1GovernanceRelay and execute given spell
contract L2GovernanceRelay {

    // --- immutables ---

    address public immutable l1GovernanceRelay;
    CrossDomainMessengerLike public immutable messenger;

    // --- modifiers ---

    modifier onlyL1GovRelay() {
        require(
            msg.sender == address(messenger) && messenger.xDomainMessageSender() == l1GovernanceRelay,
            "L2GovernanceRelay/not-from-l1-gov-relay"
        );
        _;
    }

    // --- constructor ---

    constructor(
        address _l1GovernanceRelay, 
        address _l2Messenger
    ) {
        l1GovernanceRelay = _l1GovernanceRelay;
        messenger = CrossDomainMessengerLike(_l2Messenger);
    }

    // --- relay ---

    function relay(address target, bytes calldata targetData) external onlyL1GovRelay {
        (bool success, bytes memory result) = target.delegatecall(targetData);
        if (!success) {
            // Next 3 lines are based on https://ethereum.stackexchange.com/a/83577
            if (result.length < 68) revert("L2GovernanceRelay/delegatecall-error");
            assembly { result := add(result, 0x04) }
            revert(abi.decode(result, (string)));
        }
    }
}
