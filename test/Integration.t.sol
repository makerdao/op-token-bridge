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

import { Domain } from "dss-test/domains/Domain.sol";
import { OptimismDomain } from "dss-test/domains/OptimismDomain.sol";
import { TokenBridgeDeploy } from "deploy/TokenBridgeDeploy.sol";
import { L2TokenBridgeSpell } from "deploy/L2TokenBridgeSpell.sol";
import { L1TokenBridgeInstance } from "deploy/L1TokenBridgeInstance.sol";
import { L2TokenBridgeInstance } from "deploy/L2TokenBridgeInstance.sol";
import { TokenBridgeInit, BridgesConfig } from "deploy/TokenBridgeInit.sol";
import { L1TokenBridge } from "src/L1TokenBridge.sol";
import { L2TokenBridge } from "src/L2TokenBridge.sol";
import { GemMock } from "test/mocks/GemMock.sol";

contract IntegrationTest is DssTest {

    Domain l1Domain;
    OptimismDomain l2Domain;

    // L1-side
    DssInstance dss;
    address PAUSE_PROXY;
    address L1_MESSENGER;
    address l1GovRelay;
    address escrow;
    L1TokenBridge l1Bridge;
    GemMock l1Token;

    // L2-side
    address l2GovRelay;
    GemMock l2Token;
    L2TokenBridge l2Bridge;
    address L2_MESSENGER;

    function setUp() public {} // TODO: setUp seems to cause a foundry bug whereby l2Domain is not actually persistent and incorrectly resets its log index

    function _setUp() internal {
        vm.setEnv("FOUNDRY_ROOT_CHAINID", "1"); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");

        l1Domain = new Domain(config, getChain("mainnet"));
        l1Domain.selectFork();
        l1Domain.loadDssFromChainlog();
        dss = l1Domain.dss();
        PAUSE_PROXY = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
        vm.label(address(PAUSE_PROXY),  "PAUSE_PROXY");

        l2Domain = new OptimismDomain(config, getChain("base"), l1Domain);
        L1_MESSENGER = l2Domain.readConfigAddress("l1Messenger");
        L2_MESSENGER = l2Domain.readConfigAddress("l2Messenger");
        vm.label(L1_MESSENGER, "L1_MESSENGER");
        vm.label(L2_MESSENGER, "L2_MESSENGER");

        address l1GovRelay_ = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3); // foundry increments a global nonce across domains
        address l1Bridge_ = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 5); // foundry increments a global nonce across domains
        l2Domain.selectFork();
        L2TokenBridgeInstance memory l2BridgeInstance = TokenBridgeDeploy.deployL2Bridge({
            deployer:    address(this),
            l1GovRelay:  l1GovRelay_,
            l1Bridge:    l1Bridge_, 
            l2Messenger: L2_MESSENGER
        });
        l2GovRelay = l2BridgeInstance.govRelay;
        l2Bridge = L2TokenBridge(l2BridgeInstance.bridge);
        assertEq(address(L2TokenBridgeSpell(l2BridgeInstance.spell).l2Bridge()), address(l2Bridge));

        l1Domain.selectFork();
        L1TokenBridgeInstance memory l1BridgeInstance = TokenBridgeDeploy.deployL1Bridge({
            deployer:    address(this),
            owner:       PAUSE_PROXY,
            l2GovRelay:  l2BridgeInstance.govRelay,
            l2Bridge:    address(l2Bridge), 
            l1Messenger: L1_MESSENGER
        });
        l1GovRelay = l1BridgeInstance.govRelay;
        escrow = l1BridgeInstance.escrow;
        l1Bridge = L1TokenBridge(l1BridgeInstance.bridge);
        assertEq(l1GovRelay, l1GovRelay_);
        assertEq(address(l1Bridge), l1Bridge_);

        l1Token = new GemMock(100 ether);
        vm.label(address(l1Token), "l1Token");

        l2Domain.selectFork();
        l2Token = new GemMock(0);
        l2Token.rely(l2GovRelay);
        l2Token.deny(address(this));
        vm.label(address(l2Token), "l2Token");

        address[] memory l1Tokens = new address[](1);
        l1Tokens[0] = address(l1Token);
        address[] memory l2Tokens = new address[](1);
        l2Tokens[0] = address(l2Token);
        BridgesConfig memory cfg = BridgesConfig({
            l1Messenger:   L1_MESSENGER,
            l2Messenger:   L2_MESSENGER,
            l1Tokens:      l1Tokens,
            l2Tokens:      l2Tokens,
            minGasLimit:   1_000_000,
            govRelayCLKey: "BASE_GOV_RELAY",
            escrowCLKey:   "BASE_ESCROW",
            l1BridgeCLKey: "BASE_TOKEN_BRIDGE"
        });

        l1Domain.selectFork();
        vm.startPrank(PAUSE_PROXY);
        TokenBridgeInit.initBridges(dss, l1BridgeInstance, l2BridgeInstance, cfg);
        vm.stopPrank();

        // test L1 side of initBridges
        assertEq(l1Token.allowance(escrow, l1Bridge_), type(uint256).max);
        assertEq(l1Bridge.l1ToL2Token(address(l1Token)), address(l2Token));
        assertEq(dss.chainlog.getAddress("BASE_GOV_RELAY"),    l1GovRelay);
        assertEq(dss.chainlog.getAddress("BASE_ESCROW"),       escrow);
        assertEq(dss.chainlog.getAddress("BASE_TOKEN_BRIDGE"), l1Bridge_);

        l2Domain.relayFromHost(true);

        // test L2 side of initBridges
        assertEq(l2Bridge.l1ToL2Token(address(l1Token)), address(l2Token));
        assertEq(l2Token.wards(address(l2Bridge)), 1);
    }

    function testDeposit() public {
        _setUp();

        l1Domain.selectFork();
        l1Token.approve(address(l1Bridge), 100 ether);
        uint256 escrowBefore = l1Token.balanceOf(escrow);

        L1TokenBridge(l1Bridge).bridgeERC20To(
            address(l1Token),
            address(l2Token),
            address(0xb0b),
            100 ether,
            1_000_000,
            ""
        );

        assertEq(l1Token.balanceOf(escrow), escrowBefore + 100 ether);
        
        l2Domain.relayFromHost(true);

        assertEq(l2Token.balanceOf(address(0xb0b)), 100 ether);
    }


    function testWithdraw() public {
        testDeposit();

        vm.startPrank(address(0xb0b));
        l2Token.approve(address(l2Bridge), 100 ether);
        L2TokenBridge(l2Bridge).bridgeERC20To(
            address(l2Token),
            address(l1Token),
            address(0xced),
            100 ether,
            1_000_000,
            ""
        );
        vm.stopPrank();

        assertEq(l2Token.balanceOf(address(0xb0b)), 0);
        l2Domain.relayToHost(true);

        assertEq(l1Token.balanceOf(address(0xced)), 100 ether);
    }
}
