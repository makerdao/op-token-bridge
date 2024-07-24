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

interface GemLike {
    function approve(address, uint256) external;
}

interface BridgeLike {
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

// Test deployment in config.json
contract Deposit is Script {
    using stdJson for string;

    uint256 l1PrivKey = vm.envUint("L1_PRIVATE_KEY");
    uint256 l2PrivKey = vm.envUint("L2_PRIVATE_KEY");
    address l2Deployer = vm.addr(l2PrivKey);

    function run() external {
        StdChains.Chain memory l1Chain = getChain(string(vm.envOr("L1", string("mainnet"))));
        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(l1Chain.chainId)); // used by ScriptTools to determine config path
        string memory config = ScriptTools.loadConfig("config");
        string memory deps   = ScriptTools.loadDependencies();
        Domain l1Domain = new Domain(config, l1Chain);
        l1Domain.selectFork();
       
        address l1Bridge = deps.readAddress(".l1Bridge");
        address l1Token = deps.readAddressArray(".l1Tokens")[0];
        address l2Token = deps.readAddressArray(".l2Tokens")[0];
        uint256 amount = 1 ether;

        vm.startBroadcast(l1PrivKey);
        GemLike(l1Token).approve(l1Bridge, type(uint256).max);
        BridgeLike(l1Bridge).bridgeERC20To({
            _localToken:  l1Token, 
            _remoteToken: l2Token,
            _to:          l2Deployer,
            _amount:      amount, 
            _minGasLimit: 100_000, 
            _extraData: ""
        });
        vm.stopBroadcast();
    }
}
