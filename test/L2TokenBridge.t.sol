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

import { L2TokenBridge } from "src/L2TokenBridge.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { MessengerMock } from "test/mocks/MessengerMock.sol";

contract L2TokenBridgeTest is DssTest {

    event TokenSet(address indexed l1Address, address indexed l2Address);
    event Closed();
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
    event SentMessage(
        address indexed target,
        address sender,
        bytes message,
        uint256 messageNonce,
        uint256 gasLimit
    );

    GemMock l2Token;
    address l1Token = address(0x111);
    L2TokenBridge bridge;
    address otherBridge = address(0xccc);
    address l2Router = address(0xbbb);
    MessengerMock messenger;

    function setUp() public {
        messenger = new MessengerMock();
        messenger.setXDomainMessageSender(otherBridge);
        bridge = new L2TokenBridge(otherBridge, address(messenger));
        l2Token = new GemMock(1_000_000 ether);
        l2Token.transfer(address(0xe0a), 500_000 ether);
        l2Token.rely(address(bridge));
        bridge.registerToken(l1Token, address(l2Token));
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        L2TokenBridge b = new L2TokenBridge(address(111), address(222));

        assertEq(b.isOpen(), 1);
        assertEq(b.otherBridge(), address(111));
        assertEq(address(b.messenger()), address(222));
        assertEq(b.wards(address(this)), 1);
    }

    function testAuth() public {
        checkAuth(address(bridge), "L2TokenBridge");
    }

    function testAuthModifiers() public virtual {
        bridge.deny(address(this));

        checkModifier(address(bridge), string(abi.encodePacked("L2TokenBridge", "/not-authorized")), [
            bridge.close.selector,
            bridge.registerToken.selector
        ]);
    }

    function testTokenRegistration() public {
        assertEq(bridge.l1ToL2Token(address(11)), address(0));

        vm.expectEmit(true, true, true, true);
        emit TokenSet(address(11), address(22));
        bridge.registerToken(address(11), address(22));

        assertEq(bridge.l1ToL2Token(address(11)), address(22));
    }

    function testClose() public {
        assertEq(bridge.isOpen(), 1);

        l2Token.approve(address(bridge), type(uint256).max);
        bridge.bridgeERC20To(address(l2Token), l1Token, address(0xb0b), 100 ether, 1_000_000, "");

        vm.prank(address(messenger)); bridge.finalizeBridgeERC20(address(l2Token), l1Token, address(this), address(this), 1 ether, "");

        vm.expectEmit(true, true, true, true);
        emit Closed();
        bridge.close();

        assertEq(bridge.isOpen(), 0);
        vm.expectRevert("L2TokenBridge/closed");
        bridge.bridgeERC20To(address(l2Token), l1Token, address(0xb0b), 100 ether, 1_000_000, "");

        // finalizing a transfer should still be possible
        vm.prank(address(messenger)); bridge.finalizeBridgeERC20(address(l2Token), l1Token, address(this), address(this), 1 ether, "");
    }

    function testBridgeERC20() public {
        vm.expectRevert("L2TokenBridge/sender-not-eoa");
        bridge.bridgeERC20(address(l2Token), l1Token, 100 ether, 1_000_000, "");

        vm.expectRevert("L2TokenBridge/invalid-token");
        vm.prank(address(0xe0a)); bridge.bridgeERC20(address(l1Token), address(0xbad), 100 ether, 1_000_000, "");

        vm.expectRevert("L2TokenBridge/invalid-token");
        vm.prank(address(0xe0a)); bridge.bridgeERC20(address(0xbad), address(0), 100 ether, 1_000_000, "");

        uint256 supplyBefore = l2Token.totalSupply();
        uint256 eoaBefore = l2Token.balanceOf(address(this));
        vm.prank(address(0xe0a)); l2Token.approve(address(bridge), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit SentMessage(
            otherBridge,
            address(bridge),
            abi.encodeCall(L2TokenBridge.finalizeBridgeERC20, (l1Token, address(l2Token), address(0xe0a), address(0xe0a), 100 ether, "abc")), 
            0, 
            1_000_000
        );
        vm.expectEmit(true, true, true, true);
        emit ERC20BridgeInitiated(address(l2Token), l1Token, address(0xe0a), address(0xe0a), 100 ether, "abc");
        vm.prank(address(0xe0a)); bridge.bridgeERC20(address(l2Token), l1Token, 100 ether, 1_000_000, "abc");

        assertEq(l2Token.totalSupply(), supplyBefore - 100 ether);
        assertEq(l2Token.balanceOf(address(0xe0a)), eoaBefore - 100 ether);

        uint256 thisBefore = l2Token.balanceOf(address(this));
        l2Token.approve(address(bridge), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit SentMessage(
            otherBridge,
            address(bridge),
            abi.encodeCall(L2TokenBridge.finalizeBridgeERC20, (l1Token, address(l2Token), address(this), address(0xb0b), 100 ether, "def")), 
            0, 
            1_000_000
        );
        vm.expectEmit(true, true, true, true);
        emit ERC20BridgeInitiated(address(l2Token), l1Token, address(this), address(0xb0b), 100 ether, "def");
        bridge.bridgeERC20To(address(l2Token), l1Token, address(0xb0b), 100 ether, 1_000_000, "def");

        assertEq(l2Token.totalSupply(), supplyBefore - 200 ether);
        assertEq(l2Token.balanceOf(address(this)), thisBefore - 100 ether);
    }

    function testFinalizeBridgeERC20() public {
        vm.expectRevert("L2TokenBridge/not-from-other-bridge");
        bridge.finalizeBridgeERC20(address(l2Token), l1Token, address(0xb0b), address(0xced), 100 ether, "abc");
        
        messenger.setXDomainMessageSender(address(0));

        vm.expectRevert("L2TokenBridge/not-from-other-bridge");
        vm.prank(address(messenger)); bridge.finalizeBridgeERC20(address(l2Token), l1Token, address(0xb0b), address(0xced), 100 ether, "abc");

        messenger.setXDomainMessageSender(otherBridge);
        uint256 balanceBefore = l2Token.balanceOf(address(0xced));
        uint256 supplyBefore = l2Token.totalSupply();

        vm.expectEmit(true, true, true, true);
        emit ERC20BridgeFinalized(address(l2Token), l1Token, address(0xb0b), address(0xced), 100 ether, "abc");
        vm.prank(address(messenger)); bridge.finalizeBridgeERC20(address(l2Token), l1Token, address(0xb0b), address(0xced), 100 ether, "abc");

        assertEq(l2Token.balanceOf(address(0xced)), balanceBefore + 100 ether);
        assertEq(l2Token.totalSupply(), supplyBefore + 100 ether);
    }
}
