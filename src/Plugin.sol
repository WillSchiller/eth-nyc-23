// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

//CCIP
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
//SAFE
import {BasePluginWithEventMetadata, PluginMetadata} from "./Base.sol";
import {ISafe} from "@safe/interfaces/Accounts.sol";
import {ISafeProtocolManager} from "@safe/interfaces/Manager.sol";
import {SafeTransaction, SafeProtocolAction} from "@safe/DataTypes.sol";
import {IPool} from "@aave/interfaces/IPool.sol";

contract Plugin is BasePluginWithEventMetadata, OwnerIsCreator {

    enum Network {
        ARBITRUM_GOERLI,
        AVALANCHE_FUJI,
        BASE_GOERLI,
        POLYGON_MUMBAI
    }

    bool private isPool; // true is pool false is child
    mapping(Network network => mapping(address to => mapping(address from => bool locked))) threadLocked; // Prevent duplication
    mapping(address from => mapping(Network network => mapping(address to => bool isWhitelisted))) private
        whitelistedRecipient; //should be gas optimised
    address private pool; // pool address

    //CCIP
    IRouterClient router;
    LinkTokenInterface linkToken;

    event MessageSent( // The unique ID of the CCIP message.
        // The chain selector of the destination chain.
        // The address of the receiver on the destination chain.
        // The text being sent.
        // the token address used to pay CCIP fees.
        // The fees paid for sending the CCIP message.
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        string text,
        address feeToken,
        uint256 fees
    );

    error ThreadLocked();
    error RecipientNotWhitelisted();
    error AaveHealthFactorTooHigh();
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.

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

    constructor(address _pool, address _router, address _link)
        BasePluginWithEventMetadata(
            PluginMetadata({
                name: "Fillable.xyz",
                version: "1.0.0",
                requiresRootAccess: false,
                iconUrl: "Fillable.xyz",
                appUrl: ""
            })
        )
    {
        pool = _pool;
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
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
