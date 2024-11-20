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

import "dss-test/DssTest.sol";

import { L1GovernanceRelay } from "src/L1GovernanceRelay.sol";
import { L2GovernanceRelay } from "src/L2GovernanceRelay.sol";
import { MessengerMock } from "test/mocks/MessengerMock.sol";

contract L1GovernanceRelayTest is DssTest {

    L1GovernanceRelay relay;
    address l2GovRelay = address(0x222);
    address messenger;

    event SentMessage(
        address indexed target,
        address sender,
        bytes message,
        uint256 messageNonce,
        uint256 gasLimit
    );

    function setUp() public {
        messenger = address(new MessengerMock());
        relay = new L1GovernanceRelay(l2GovRelay, messenger);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        L1GovernanceRelay r = new L1GovernanceRelay(address(111), address(222));

        assertEq(r.l2GovernanceRelay(), address(111));
        assertEq(address(r.messenger()), address(222));
        assertEq(r.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(relay), "L1GovernanceRelay");
    }

    function testAuthModifiers() public virtual {
        relay.deny(address(this));

        checkModifier(address(relay), string(abi.encodePacked("L1GovernanceRelay", "/not-authorized")), [
            relay.relay.selector
        ]);
    }

    function testRelay() public {
        address target = address(0x333);
        bytes memory targetData = "0xaabbccdd";
        uint32 minGasLimit = 1_234_567;

        vm.expectEmit(true, true, true, true);
        emit SentMessage(
            l2GovRelay, 
            address(relay), 
            abi.encodeCall(L2GovernanceRelay.relay, (target, targetData)), 
            0, 
            minGasLimit
        );
        relay.relay(target, targetData, minGasLimit);
    }
}
