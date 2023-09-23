// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BasePluginWithEventMetadata, PluginMetadata} from "./Base.sol";
import {ISafe} from "@safe/interfaces/Accounts.sol";
import {ISafeProtocolManager} from "@safe/interfaces/Manager.sol";
import {SafeTransaction, SafeProtocolAction} from "@safe/DataTypes.sol";
import {Ipool} from "@aave/interfaces/IPool.sol";

contract Plugin is BasePluginWithEventMetadata {
    constructor(
        address poolAddress
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
        pool = poolAddress;
    }

    enum Network {
        ARBITRUM_GOERLI,
        AVALANCHE_FUJI,
        BASE_GOERLI,
        POLYGON_MUMBAI
    }

    bool private isPool; // true is pool false is child
    mapping(Network network => bool locked) locked;
    mapping(address msgSender => mapping(Network network => mapping(address to => bool isWhitelisted)))
        private whitelistedRecipient; //should be gas optimised
    address private pool; // pool address

    function getAaveUserHealth(
        address userAddress,
        Network network
    ) public view returns (uint256) {
        return Ipool(pool).getUserAccountData(userAddress).healthFactor;
    }
}
