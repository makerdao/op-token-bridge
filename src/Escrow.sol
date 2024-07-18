// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2024 Dai Foundation
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

interface GemLike {
    function approve(address, uint256) external;
}

// Escrow funds on L1, manage approval rights

contract Escrow {
    // --- storage variables ---

    mapping(address => uint256) public wards;

    // --- events ---

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Approve(address indexed token, address indexed spender, uint256 value);

    // --- modifiers ---

    modifier auth() {
        require(wards[msg.sender] == 1, "Escrow/not-authorized");
        _;
    }

    // --- constructor ---

    constructor() {
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

    // --- approve ---

    function approve(address token, address spender, uint256 value) external auth {
        emit Approve(token, spender, value);
        GemLike(token).approve(spender, value);
    }
}
