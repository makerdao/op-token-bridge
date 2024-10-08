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
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { L2TokenBridge } from "src/L2TokenBridge.sol";
import { GemMock } from "test/mocks/GemMock.sol";
import { MessengerMock } from "test/mocks/MessengerMock.sol";
import { L2TokenBridgeV2Mock } from "test/mocks/L2TokenBridgeV2Mock.sol";

contract L2TokenBridgeTest is DssTest {

    event TokenSet(address indexed l1Address, address indexed l2Address);
    event MaxWithdrawSet(address indexed l2Token, uint256 maxWithdraw);
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

    GemMock l2Token;
    address l1Token = address(0x111);
    L2TokenBridge bridge;
    address otherBridge = address(0xccc);
    address l2Router = address(0xbbb);
    MessengerMock messenger;
    bool validate;

    function setUp() public {
        validate = vm.envOr("VALIDATE", false);

        messenger = new MessengerMock();
        messenger.setXDomainMessageSender(otherBridge);

        L2TokenBridge imp = new L2TokenBridge(otherBridge, address(messenger));
        assertEq(imp.otherBridge(), otherBridge);
        assertEq(address(imp.messenger()), address(messenger));

        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        bridge = L2TokenBridge(address(new ERC1967Proxy(address(imp), abi.encodeCall(L2TokenBridge.initialize, ()))));
        assertEq(bridge.getImplementation(), address(imp));
        assertEq(bridge.wards(address(this)), 1);
        assertEq(bridge.isOpen(), 1);
        assertEq(bridge.otherBridge(), otherBridge);
        assertEq(address(bridge.messenger()), address(messenger));

        l2Token = new GemMock(1_000_000 ether);
        l2Token.transfer(address(0xe0a), 500_000 ether);
        l2Token.rely(address(bridge));
        bridge.registerToken(l1Token, address(l2Token));
        bridge.setMaxWithdraw(address(l2Token), 1_000_000 ether);
    }

    function testAuth() public {
        checkAuth(address(bridge), "L2TokenBridge");
    }

    function testAuthModifiers() public virtual {
        bridge.deny(address(this));

        checkModifier(address(bridge), string(abi.encodePacked("L2TokenBridge", "/not-authorized")), [
            bridge.close.selector,
            bridge.registerToken.selector,
            bridge.setMaxWithdraw.selector,
            bridge.upgradeToAndCall.selector
        ]);
    }

    function testTokenRegistration() public {
        assertEq(bridge.l1ToL2Token(address(11)), address(0));

        vm.expectEmit(true, true, true, true);
        emit TokenSet(address(11), address(22));
        bridge.registerToken(address(11), address(22));

        assertEq(bridge.l1ToL2Token(address(11)), address(22));
    }

    function testSetmaxWithdraw() public {
        assertEq(bridge.maxWithdraws(address(22)), 0);

        vm.expectEmit(true, true, true, true);
        emit MaxWithdrawSet(address(22), 123);
        bridge.setMaxWithdraw(address(22), 123);

        assertEq(bridge.maxWithdraws(address(22)), 123);
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
        vm.prank(address(0xe0a)); bridge.bridgeERC20(address(0), address(0xbad), 100 ether, 1_000_000, "");

        vm.expectRevert("L2TokenBridge/amount-too-large");
        vm.prank(address(0xe0a)); bridge.bridgeERC20(address(l2Token), l1Token, 1_000_000 ether + 1, 1_000_000, "");

        uint256 supplyBefore = l2Token.totalSupply();
        uint256 eoaBefore = l2Token.balanceOf(address(0xe0a));
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
            "out/L2TokenBridge.sol/L2TokenBridge.json",
            abi.encodeCall(L2TokenBridge.initialize, ()),
            opts
        );
        assertEq(L2TokenBridge(proxy).version(), "1");
        assertEq(L2TokenBridge(proxy).wards(address(this)), 1);
    }

    function testUpgrade() public {
        address newImpl = address(new L2TokenBridgeV2Mock());
        vm.expectEmit(true, true, true, true);
        emit UpgradedTo("2");
        bridge.upgradeToAndCall(newImpl, abi.encodeCall(L2TokenBridgeV2Mock.reinitialize, ()));

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
            opts.referenceContract = "out/L2TokenBridge.sol/L2TokenBridge.json";
            opts.unsafeAllow = 'constructor';
        }

        vm.expectEmit(true, true, true, true);
        emit UpgradedTo("2");
        Upgrades.upgradeProxy(
            address(bridge),
            "out/L2TokenBridgeV2Mock.sol/L2TokenBridgeV2Mock.json",
            abi.encodeCall(L2TokenBridgeV2Mock.reinitialize, ()),
            opts
        );

        address implementation2 = bridge.getImplementation();
        assertTrue(implementation1 != implementation2);
        assertEq(bridge.version(), "2");
        assertEq(bridge.wards(address(this)), 1); // still a ward
    }

    function testInitializeAgain() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        bridge.initialize();
    }

    function testInitializeDirectly() public {
        address implementation = bridge.getImplementation();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        L2TokenBridge(implementation).initialize();
    }
}
