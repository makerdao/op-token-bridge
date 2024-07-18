// SPDX-FileCopyrightText: © 2024 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

pragma solidity >=0.8.0;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { L1TokenBridgeInstance } from "./L1TokenBridgeInstance.sol";
import { L2TokenBridgeInstance } from "./L2TokenBridgeInstance.sol";
import { L2TokenBridgeSpell } from "./L2TokenBridgeSpell.sol";
import { L1GovernanceRelay } from "src/L1GovernanceRelay.sol";
import { L2GovernanceRelay } from "src/L2GovernanceRelay.sol";
import { Escrow } from "src/Escrow.sol";
import { L1TokenBridge } from "src/L1TokenBridge.sol";
import { L2TokenBridge } from "src/L2TokenBridge.sol";

library TokenBridgeDeploy {
    function deployL1Bridge(
        address deployer,
        address owner,
        address l2GovRelay,
        address l2Bridge,
        address l1Messenger
    ) internal returns (L1TokenBridgeInstance memory l1BridgeInstance) {
        l1BridgeInstance.govRelay = address(new L1GovernanceRelay(l2GovRelay, l1Messenger));
        l1BridgeInstance.escrow = address(new Escrow());
        l1BridgeInstance.bridge = address(new L1TokenBridge(l2Bridge, l1BridgeInstance.escrow, l1Messenger));
        ScriptTools.switchOwner(l1BridgeInstance.govRelay, deployer, owner);
        ScriptTools.switchOwner(l1BridgeInstance.escrow, deployer, owner);
        ScriptTools.switchOwner(l1BridgeInstance.bridge, deployer, owner);
    }

    function deployL2Bridge(
        address deployer,
        address l1GovRelay,
        address l1Bridge,
        address l2Messenger
    ) internal returns (L2TokenBridgeInstance memory l2BridgeInstance) {
        l2BridgeInstance.govRelay = address(new L2GovernanceRelay(l1GovRelay, l2Messenger));
        l2BridgeInstance.bridge = address(new L2TokenBridge(l1Bridge, l2Messenger));
        l2BridgeInstance.spell = address(new L2TokenBridgeSpell(l2BridgeInstance.bridge));
        ScriptTools.switchOwner(l2BridgeInstance.bridge, deployer, l2BridgeInstance.govRelay);
    }
}
