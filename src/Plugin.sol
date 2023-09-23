// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BasePluginWithEventMetadata, PluginMetadata} from "./Base.sol";
import {ISafe} from "@safe/interfaces/Accounts.sol";
import {ISafeProtocolManager} from "@safe/interfaces/Manager.sol";
import {SafeTransaction, SafeProtocolAction} from "@safe/DataTypes.sol";
import {IPool} from "@aave/interfaces/IPool.sol";

contract Plugin is BasePluginWithEventMetadata {
    constructor(address poolAddress)
        BasePluginWithEventMetadata(
            PluginMetadata({name: "Fillable.xyz", version: "1.0.0", requiresRootAccess: false, iconUrl: "", appUrl: ""})
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

    error ThreadLocked();
    error RecipientNotWhitelisted();
    error AaveHealthFactorTooHigh();

    bool private isPool; // true is pool false is child
    mapping(Network network => mapping(address to => mapping(address from => bool locked))) threadLocked; // Prevent duplication
    mapping(address from => mapping(Network network => mapping(address to => bool isWhitelisted))) private
        whitelistedRecipient; //should be gas optimised
    address private pool; // pool address

    modifier guard(address _to, address _from, Network network) {
        if (threadLocked[network][_to][_from]) revert ThreadLocked();
        if (!whitelistedRecipient[_from][network][_to]) {
            revert RecipientNotWhitelisted();
        }
        if (getAaveUserHealth(_to) > 1100000000000000000) {
            revert AaveHealthFactorTooHigh();
        }
        _;
    }

    function getAaveUserHealth(address userAddress) public view returns (uint256) {
        (,,,,, uint256 heathFactor) = IPool(pool).getUserAccountData(userAddress);
        return heathFactor;
    }

    function sendFunds(address _to, address _from, Network network) internal guard(_to, _from, network) {
        //then request data
        //lock the channel
    }

    function receiveFunds() internal {
        // on return of msg post to aave
    }
}
