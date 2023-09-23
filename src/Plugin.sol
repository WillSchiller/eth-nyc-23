// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BasePluginWithEventMetadata, PluginMetadata} from "./Base.sol";
import {ISafe} from "@safe/interfaces/Accounts.sol";
import {ISafeProtocolManager} from "@safe/interfaces/Manager.sol";
import {SafeTransaction, SafeProtocolAction} from "@safe/DataTypes.sol";
import {Ipool} from "@aave/interfaces/IPool.sol";

contract Plugin is BasePluginWithEventMetadata {
    constructor(
        address poolAddress,
        string network
    )
        BasePluginWithEventMetadata(
            PluginMetadata({
                name: "Fillable.xyz",
                version: "1.0.0",
                requiresRootAccess: false,
                iconUrl: "",
                appUrl: ""
            })
        )
    {
        poolAddress[0] = poolAddress;
        poolAddress[1] = poolAddress;
    }

    enum Network {
        polygonMumbai,
        AvalancheFuji
    }

    bool private isPool; // true is pool false is child
    mapping(Network network => bool locked) locked;

    mapping(address msgSender => mapping(Network network => mapping(address to => bool isAllowed)))
        private _allowed;
    mapping(Network network => address poolAddress) private poolAddress; // pool address

    function getAaveUserHealth(
        address userAddress
    ) public view returns (uint256) {
        return
            Ipool(poolAddress[0]).getUserAccountData(userAddress).healthFactor;
    }
}
