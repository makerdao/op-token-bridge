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
import { MCD, DssInstance } from "dss-test/MCD.sol";
import { TokenBridgeInit, BridgesConfig } from "deploy/TokenBridgeInit.sol";
import { L1TokenBridgeInstance } from "deploy/L1TokenBridgeInstance.sol";
import { L2TokenBridgeInstance } from "deploy/L2TokenBridgeInstance.sol";
import { L2TokenBridgeSpell } from "deploy/L2TokenBridgeSpell.sol";
import { L2GovernanceRelay } from "src/L2GovernanceRelay.sol";


contract Init is Script {
    using stdJson for string;

    uint256 l1PrivKey = vm.envUint("L1_PRIVATE_KEY");

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        StdChains.Chain memory l2Chain = getChain(string(vm.envOr("L2", string("base"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        string memory deps   = ScriptTools.loadDependencies();
        Domain l1Domain = new Domain(config, l1Chain);
        Domain l2Domain = new Domain(config, l2Chain);
        l1Domain.selectFork();

        DssInstance memory dss = MCD.loadFromChainlog(deps.readAddress(".chainlog"));

        BridgesConfig memory cfg; 
        cfg.l1Messenger   = deps.readAddress(".l1Messenger");
        cfg.l2Messenger   = deps.readAddress(".l2Messenger");
        cfg.l1Tokens      = deps.readAddressArray(".l1Tokens");
        cfg.l2Tokens      = deps.readAddressArray(".l2Tokens");
        cfg.minGasLimit   = 100_000;
        cfg.govRelayCLKey = l2Domain.readConfigBytes32FromString("govRelayCLKey");
        cfg.escrowCLKey   = l2Domain.readConfigBytes32FromString("escrowCLKey");
        cfg.l1BridgeCLKey = l2Domain.readConfigBytes32FromString("l1BridgeCLKey");

        L1TokenBridgeInstance memory l1BridgeInstance = L1TokenBridgeInstance({
            govRelay: deps.readAddress(".l1GovRelay"),
            escrow:   deps.readAddress(".escrow"),
            bridge:   deps.readAddress(".l1Bridge")
        });
        L2TokenBridgeInstance memory l2BridgeInstance = L2TokenBridgeInstance({
            govRelay: deps.readAddress(".l2GovRelay"),
            spell:    deps.readAddress(".l2BridgeSpell"),
            bridge:   deps.readAddress(".l2Bridge")
        });

        vm.startBroadcast(l1PrivKey);
        TokenBridgeInit.initBridges(dss, l1BridgeInstance, l2BridgeInstance, cfg);
        vm.stopBroadcast();
    }
}
