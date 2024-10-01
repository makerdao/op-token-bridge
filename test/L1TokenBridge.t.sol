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
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { L1TokenBridge, UUPSUpgradeable, ERC1967Utils, Initializable } from "src/L1TokenBridge.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { MessengerMock } from "test/mocks/MessengerMock.sol";
import { L1TokenBridgeV2Mock } from "test/mocks/L1TokenBridgeV2Mock.sol";

contract L1TokenBridgeTest is DssTest {

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
    event UpgradedTo(string version);

    GemMock l1Token;
    address l2Token = address(0x222);
    L1TokenBridge bridge;
    address escrow = address(0xeee);
    address otherBridge = address(0xccc);
    MessengerMock messenger;
    bool validate;

    function setUp() public {
        validate = vm.envOr("VALIDATE", false);

        messenger = new MessengerMock();
        messenger.setXDomainMessageSender(otherBridge);

        L1TokenBridge imp = new L1TokenBridge(otherBridge, address(messenger));
        assertEq(imp.otherBridge(), otherBridge);
        assertEq(address(imp.messenger()), address(messenger));

        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        bridge = L1TokenBridge(address(new ERC1967Proxy(address(imp), abi.encodeCall(L1TokenBridge.initialize, ()))));
        assertEq(bridge.getImplementation(), address(imp));
        assertEq(bridge.wards(address(this)), 1);
        assertEq(bridge.isOpen(), 1);
        assertEq(bridge.otherBridge(), otherBridge);
        assertEq(address(bridge.messenger()), address(messenger));

        bridge.file("escrow", escrow);
        l1Token = new GemMock(1_000_000 ether);
        l1Token.transfer(address(0xe0a), 500_000 ether);
        vm.prank(escrow); l1Token.approve(address(bridge), type(uint256).max);
        bridge.registerToken(address(l1Token), l2Token);
    }

    function testAuth() public {
        checkAuth(address(bridge), "L1TokenBridge");
    }

    function testAuthModifiers() public virtual {
        bridge.deny(address(this));

        checkModifier(address(bridge), string(abi.encodePacked("L1TokenBridge", "/not-authorized")), [
            bridge.close.selector,
            bridge.registerToken.selector
        ]);
    }

    function testFileAddress() public {
        checkFileAddress(address(bridge), "L1TokenBridge", ["escrow"]);
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

        l1Token.approve(address(bridge), type(uint256).max);
        bridge.bridgeERC20To(address(l1Token), l2Token, address(0xb0b), 100 ether, 1_000_000, "");

        vm.prank(address(messenger)); bridge.finalizeBridgeERC20(address(l1Token), l2Token, address(this), address(this), 1 ether, "");

        vm.expectEmit(true, true, true, true);
        emit Closed();
        bridge.close();

        assertEq(bridge.isOpen(), 0);
        vm.expectRevert("L1TokenBridge/closed");
        bridge.bridgeERC20To(address(l1Token), l2Token, address(0xb0b), 100 ether, 1_000_000, "");

        // finalizing a transfer should still be possible
        vm.prank(address(messenger)); bridge.finalizeBridgeERC20(address(l1Token), l2Token, address(this), address(this), 1 ether, "");
    }

    function testBridgeERC20() public {
        vm.expectRevert("L1TokenBridge/sender-not-eoa");
        bridge.bridgeERC20(address(l1Token), l2Token, 100 ether, 1_000_000, "");

        vm.expectRevert("L1TokenBridge/invalid-token");
        vm.prank(address(0xe0a)); bridge.bridgeERC20(address(l1Token), address(0xbad), 100 ether, 1_000_000, "");

        vm.expectRevert("L1TokenBridge/invalid-token");
        vm.prank(address(0xe0a)); bridge.bridgeERC20(address(0xbad), address(0), 100 ether, 1_000_000, "");

        uint256 eoaBefore = l1Token.balanceOf(address(0xe0a));
        vm.prank(address(0xe0a)); l1Token.approve(address(bridge), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit SentMessage(
            otherBridge,
            address(bridge),
            abi.encodeCall(L1TokenBridge.finalizeBridgeERC20, (l2Token, address(l1Token), address(0xe0a), address(0xe0a), 100 ether, "abc")), 
            0, 
            1_000_000
        );
        vm.expectEmit(true, true, true, true);
        emit ERC20BridgeInitiated(address(l1Token), l2Token, address(0xe0a), address(0xe0a), 100 ether, "abc");
        vm.prank(address(0xe0a)); bridge.bridgeERC20(address(l1Token), l2Token, 100 ether, 1_000_000, "abc");

        assertEq(l1Token.balanceOf(address(0xe0a)), eoaBefore - 100 ether);
        assertEq(l1Token.balanceOf(escrow), 100 ether);

        uint256 thisBefore = l1Token.balanceOf(address(this));
        l1Token.approve(address(bridge), type(uint256).max);

        vm.expectEmit(true, true, true, true);
        emit SentMessage(
            otherBridge,
            address(bridge),
            abi.encodeCall(L1TokenBridge.finalizeBridgeERC20, (l2Token, address(l1Token), address(this), address(0xb0b), 100 ether, "def")), 
            0, 
            1_000_000
        );
        vm.expectEmit(true, true, true, true);
        emit ERC20BridgeInitiated(address(l1Token), l2Token, address(this), address(0xb0b), 100 ether, "def");
        bridge.bridgeERC20To(address(l1Token), l2Token, address(0xb0b), 100 ether, 1_000_000, "def");

        assertEq(l1Token.balanceOf(address(this)), thisBefore - 100 ether);
        assertEq(l1Token.balanceOf(escrow), 200 ether);
    }

    function testFinalizeBridgeERC20() public {
        vm.expectRevert("L1TokenBridge/not-from-other-bridge");
        bridge.finalizeBridgeERC20(address(l1Token), l2Token, address(0xb0b), address(0xced), 100 ether, "abc");

        messenger.setXDomainMessageSender(address(0));

        vm.expectRevert("L1TokenBridge/not-from-other-bridge");
        vm.prank(address(messenger)); bridge.finalizeBridgeERC20(address(l1Token), l2Token, address(0xb0b), address(0xced), 100 ether, "abc");

        messenger.setXDomainMessageSender(otherBridge);
        deal(address(l1Token), escrow, 100 ether, true);

        vm.expectEmit(true, true, true, true);
        emit ERC20BridgeFinalized(address(l1Token), l2Token, address(0xb0b), address(0xced), 100 ether, "abc");
        vm.prank(address(messenger)); bridge.finalizeBridgeERC20(address(l1Token), l2Token, address(0xb0b), address(0xced), 100 ether, "abc");

        assertEq(l1Token.balanceOf(escrow), 0);
        assertEq(l1Token.balanceOf(address(0xced)), 100 ether);
    }

    function testDeployWithUpgradesLib() public {
        Options memory opts;
        if (!validate) {
            opts.unsafeSkipAllChecks = true;
        } else {
            opts.unsafeAllow = 'state-variable-immutable,constructor';
        }
        opts.constructorData = abi.encode(otherBridge, address(messenger));

        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        address proxy = Upgrades.deployUUPSProxy(
            "out/L1TokenBridge.sol/L1TokenBridge.json",
            abi.encodeCall(L1TokenBridge.initialize, ()),
            opts
        );
        assertEq(L1TokenBridge(proxy).version(), "1");
        assertEq(L1TokenBridge(proxy).wards(address(this)), 1);
    }

    function testUpgrade() public {
        address newImpl = address(new L1TokenBridgeV2Mock());
        vm.expectEmit(true, true, true, true);
        emit UpgradedTo("2");
        bridge.upgradeToAndCall(newImpl, abi.encodeCall(L1TokenBridgeV2Mock.reinitialize, ()));

        assertEq(bridge.getImplementation(), newImpl);
        assertEq(bridge.version(), "2");
        assertEq(bridge.wards(address(this)), 1); // still a ward
    }

    function testUpgradeWithUpgradesLib() public {
        address implementation1 = bridge.getImplementation();

        Options memory opts;
        if (!validate) {
            opts.unsafeSkipAllChecks = true;
        } else {
            opts.referenceContract = "out/L1TokenBridge.sol/L1TokenBridge.json";
            opts.unsafeAllow = 'constructor';
        }

        vm.expectEmit(true, true, true, true);
        emit UpgradedTo("2");
        Upgrades.upgradeProxy(
            address(bridge),
            "out/L1TokenBridgeV2Mock.sol/L1TokenBridgeV2Mock.json",
            abi.encodeCall(L1TokenBridgeV2Mock.reinitialize, ()),
            opts
        );

        address implementation2 = bridge.getImplementation();
        assertTrue(implementation1 != implementation2);
        assertEq(bridge.version(), "2");
        assertEq(bridge.wards(address(this)), 1); // still a ward
    }

    function testUpgradeUnauthed() public {
        address newImpl = address(new L1TokenBridgeV2Mock());
        vm.expectRevert("L1TokenBridge/not-authorized");
        vm.prank(address(0x123)); bridge.upgradeToAndCall(newImpl, abi.encodeCall(L1TokenBridgeV2Mock.reinitialize, ()));
    }

    function testInitializeAgain() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        bridge.initialize();
    }

    function testInitializeDirectly() public {
        address implementation = bridge.getImplementation();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        L1TokenBridge(implementation).initialize();
    }
}
