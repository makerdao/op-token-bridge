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

import { Escrow } from "src/Escrow.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract EscrowTest is DssTest {

    Escrow escrow;
    GemMock token;

    event Approve(address indexed token, address indexed spender, uint256 value);

    function setUp() public {
        escrow = new Escrow();
        token = new GemMock(0);
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        Escrow e = new Escrow();

        assertEq(e.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(escrow), "Escrow");
    }

    function testAuthModifiers() public virtual {
        escrow.deny(address(this));

        checkModifier(address(escrow), string(abi.encodePacked("Escrow", "/not-authorized")), [
            escrow.approve.selector
        ]);
    }

    function testApprove() public {
        address spender = address(0xb0b);
        uint256 value = 10 ether;

        vm.expectEmit(true, true, true, true);
        emit Approve(address(token), spender, value);
        escrow.approve(address(token), spender, value);

        assertEq(token.allowance(address(escrow), spender), value);
    }
}
