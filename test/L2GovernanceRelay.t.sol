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

import { L2GovernanceRelay } from "src/L2GovernanceRelay.sol";
import { MessengerMock } from "test/mocks/MessengerMock.sol";

contract L2SpellMock {
    function exec() external {}
    function revt() pure external { revert("L2SpellMock/revt"); }
}

contract L2GovernanceRelayTest is DssTest {

    L2GovernanceRelay relay;
    address l1GovRelay = address(0x111);
    MessengerMock messenger;
    address spell;

    function setUp() public {
        messenger = new MessengerMock();
        messenger.setXDomainMessageSender(l1GovRelay);
        relay = new L2GovernanceRelay(l1GovRelay, address(messenger));
        spell = address(new L2SpellMock());
    }

    function testConstructor() public {
        L2GovernanceRelay r = new L2GovernanceRelay(address(111), address(222));

        assertEq(r.l1GovernanceRelay(), address(111));
        assertEq(address(r.messenger()), address(222));
    }

    function testRelay() public {
        vm.expectRevert("L2GovernanceRelay/not-from-l1-gov-relay");
        relay.relay(spell, abi.encodeCall(L2SpellMock.exec, ()));

        messenger.setXDomainMessageSender(address(0));

        vm.expectRevert("L2GovernanceRelay/not-from-l1-gov-relay");
        vm.prank(address(messenger)); relay.relay(spell, abi.encodeCall(L2SpellMock.exec, ()));

        messenger.setXDomainMessageSender(l1GovRelay);

        vm.expectRevert("L2GovernanceRelay/delegatecall-error");
        vm.prank(address(messenger)); relay.relay(spell, abi.encodeWithSignature("bad()"));

        vm.expectRevert("L2SpellMock/revt");
        vm.prank(address(messenger)); relay.relay(spell, abi.encodeCall(L2SpellMock.revt, ()));

        vm.prank(address(messenger)); relay.relay(spell, abi.encodeCall(L2SpellMock.exec, ()));
    }
}
