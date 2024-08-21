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

import "forge-std/Script.sol";

import { ScriptTools } from "dss-test/ScriptTools.sol";
import { Domain } from "dss-test/domains/Domain.sol";
import { TokenBridgeDeploy, L1TokenBridgeInstance, L2TokenBridgeInstance } from "deploy/TokenBridgeDeploy.sol";
import { ChainLog } from "deploy/mocks/ChainLog.sol";
import { GemMock } from "test/mocks/GemMock.sol";

// TODO: Add to dss-test/ScriptTools.sol
library ScriptToolsExtended {
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));
    function exportContracts(string memory name, string memory label, address[] memory addr) internal {
        name = vm.envOr("FOUNDRY_EXPORTS_NAME", name);
        string memory json = vm.serializeAddress(string(abi.encodePacked(ScriptTools.EXPORT_JSON_KEY, "_", name)), label, addr);
        ScriptTools._doExport(name, json);
    }
}

// TODO: Add to dss-test/domains/Domain.sol
library DomainExtended {
    using stdJson for string;
    function hasConfigKey(Domain domain, string memory key) internal view returns (bool) {
        bytes memory raw = domain.config().parseRaw(string.concat(".domains.", domain.details().chainAlias, ".", key));
        return raw.length > 0;
    }
    function readConfigAddresses(Domain domain, string memory key) internal view returns (address[] memory) {
        return domain.config().readAddressArray(string.concat(".domains.", domain.details().chainAlias, ".", key));
    }
}

contract Deploy is Script {
    using DomainExtended for Domain;

    address constant LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    uint256 l1PrivKey = vm.envUint("L1_PRIVATE_KEY");
    uint256 l2PrivKey = vm.envUint("L2_PRIVATE_KEY");
    address l1Deployer = vm.addr(l1PrivKey);
    address l2Deployer = vm.addr(l2PrivKey);

    Domain l1Domain;
    Domain l2Domain;

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        StdChains.Chain memory l2Chain = getChain(string(vm.envOr("L2", string("base"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        l1Domain = new Domain(config, l1Chain);
        l2Domain = new Domain(config, l2Chain);

        address l1Messenger = l2Domain.readConfigAddress("l1Messenger");
        address l2Messenger = l2Domain.readConfigAddress("l2Messenger");

        l2Domain.selectFork();
        address l2GovRelay = vm.computeCreateAddress(l2Deployer, vm.getNonce(l2Deployer));
        address l2Bridge = vm.computeCreateAddress(l2Deployer, vm.getNonce(l2Deployer) + 1);

        // Deploy chainlog, L1 gov relay, escrow and L1 bridge

        l1Domain.selectFork();
        ChainLog chainlog;
        address owner;
        if (LOG.code.length > 0) {
            chainlog = ChainLog(LOG);
            owner = chainlog.getAddress("MCD_PAUSE_PROXY");
        } else {
            vm.startBroadcast(l1PrivKey);
            chainlog = new ChainLog();
            vm.stopBroadcast();
            owner = l1Deployer;
        }

        vm.startBroadcast(l1PrivKey);
        L1TokenBridgeInstance memory l1BridgeInstance = TokenBridgeDeploy.deployL1(l1Deployer, owner, l2GovRelay, l2Bridge, l1Messenger);
        vm.stopBroadcast();

        address l1GovRelay = l1BridgeInstance.govRelay;
        address l1Bridge = l1BridgeInstance.bridge;

        // Deploy L2 gov relay, L2 bridge and L2 spell

        l2Domain.selectFork();
        vm.startBroadcast(l2PrivKey);
        L2TokenBridgeInstance memory l2BridgeInstance = TokenBridgeDeploy.deployL2(l2Deployer, l1GovRelay, l1Bridge, l2Messenger);
        vm.stopBroadcast();

        require(l2BridgeInstance.govRelay == l2GovRelay, "l2GovRelay address mismatch");
        require(l2BridgeInstance.bridge == l2Bridge, "l2Bridge address mismatch");

        // Deploy mock tokens

        address[] memory l1Tokens;
        address[] memory l2Tokens;
        if (LOG.code.length > 0) {
            l1Tokens = l1Domain.readConfigAddresses("tokens");
            l2Tokens = l2Domain.readConfigAddresses("tokens");
        } else {
            l1Domain.selectFork();
            vm.startBroadcast(l1PrivKey);
            if (l1Domain.hasConfigKey("tokens")) {
                l1Tokens = l1Domain.readConfigAddresses("tokens");
            } else {
                uint256 count = l2Domain.hasConfigKey("tokens") ? l2Domain.readConfigAddresses("tokens").length : 2;
                l1Tokens = new address[](count);
                for (uint256 i; i < count; ++i) {
                    l1Tokens[i] = address(new GemMock(1_000_000_000 ether));
                }
            }
            vm.stopBroadcast();

            l2Domain.selectFork();
            vm.startBroadcast(l2PrivKey);
            if (l2Domain.hasConfigKey("tokens")) {
                l2Tokens = l2Domain.readConfigAddresses("tokens");
            } else {
                uint256 count = l1Domain.hasConfigKey("tokens") ? l1Domain.readConfigAddresses("tokens").length : 2;
                l2Tokens = new address[](count);
                for (uint256 i; i < count; ++i) {
                    l2Tokens[i] = address(new GemMock(0));
                    GemMock(l2Tokens[i]).rely(l2GovRelay);
                    GemMock(l2Tokens[i]).deny(l2Deployer);
                }
            }
            vm.stopBroadcast();
        }

        // Export contract addresses

        ScriptTools.exportContract("deployed", "chainlog", address(chainlog));
        ScriptTools.exportContract("deployed", "owner", owner);
        ScriptTools.exportContract("deployed", "l1Messenger", l1Messenger);
        ScriptTools.exportContract("deployed", "l2Messenger", l2Messenger);
        ScriptTools.exportContract("deployed", "escrow", l1BridgeInstance.escrow);
        ScriptTools.exportContract("deployed", "l1GovRelay", l1GovRelay);
        ScriptTools.exportContract("deployed", "l2GovRelay", l2GovRelay);
        ScriptTools.exportContract("deployed", "l1Bridge", l1Bridge);
        ScriptTools.exportContract("deployed", "l2Bridge", l2Bridge);
        ScriptTools.exportContract("deployed", "l2BridgeSpell", l2BridgeInstance.spell);
        ScriptToolsExtended.exportContracts("deployed", "l1Tokens", l1Tokens);
        ScriptToolsExtended.exportContracts("deployed", "l2Tokens", l2Tokens);
    }
}
