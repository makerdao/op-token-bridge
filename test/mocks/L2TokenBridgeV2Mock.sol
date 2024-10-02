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

import { UUPSUpgradeable, ERC1967Utils } from "src/L2TokenBridge.sol";

contract L2TokenBridgeV2Mock is UUPSUpgradeable {
    mapping(address => uint256) public wards;
    mapping(address => address) public l1ToL2Token;
    mapping(address => uint256) public maxWithdraws;
    uint256 public isOpen;

    string public constant version = "2";

    event UpgradedTo(string version);

    modifier auth {
        require(wards[msg.sender] == 1, "L2TokenBridge/not-authorized");
        _;
    }

    constructor() {
        _disableInitializers(); // Avoid initializing in the context of the implementation
    }

    function reinitialize() reinitializer(2) external {
        emit UpgradedTo(version);
    }

    function _authorizeUpgrade(address newImplementation) internal override auth {}

    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
