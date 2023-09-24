// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BasePluginWithEventMetadata, PluginMetadata} from "./Base.sol";
import {ISafe} from "@safe/interfaces/Accounts.sol";
import {Safe} from "@safe/Safe.sol";
import {ISafeProtocolManager} from "@safe/interfaces/Manager.sol";
import {SafeTransaction, SafeProtocolAction} from "@safe/DataTypes.sol";
import {IPool} from "@aave/interfaces/IPool.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts-ccip/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract Plugin is BasePluginWithEventMetadata, OwnerIsCreator, CCIPReceiver {
    enum Network {
        ARBITRUM_GOERLI,
        AVALANCHE_FUJI,
        BASE_GOERLI,
        POLYGON_MUMBAI
    }

    mapping(bytes32 RouteKey => bool) private threadLocked;
    bool private isPool; // true is pool false is child
    mapping(address from => mapping(Network network => mapping(address to => bool isWhitelisted))) private
        whitelistedRecipient; //should be gas optimised
    address private aavePool; // pool address

    //CCIP
    address private receiver;
    IRouterClient[4] private routers; // See network Enum for index
    LinkTokenInterface private linkToken;
    bytes32 private lastReceivedMessageId; // Store the last received messageId.
    string private lastReceivedText; // Store the last received text.

    // The chain selector of the destination chain.
    // The address of the receiver on the destination chain.
    // The text being sent.
    // the token address used to pay CCIP fees.
    // The fees paid for sending the CCIP message.
    event MessageSent( // The unique ID of the CCIP message.
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address _to,
        address _from,
        uint256 _amount,
        address feeToken,
        uint256 fees
    );

    event MessageReceived( // The unique ID of the message.
        // The chain selector of the source chain.
        // The address of the sender from the source chain.
        // The text that was received.
    bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, string text);

    error ThreadLocked();
    error RecipientNotWhitelisted();
    error AaveHealthFactorTooHigh();
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error FeePaymentFailure(bytes data);

    modifier guard(address _to, address _from, Network network) {
        if (threadLocked(getRouteKey())) revert ThreadLocked();
        if (!whitelistedRecipient[_from][network][_to]) {
            revert RecipientNotWhitelisted();
        }
        if (getAaveUserHealth(_to) > 1100000000000000000) {
            revert AaveHealthFactorTooHigh();
        }
        _;
    }

    constructor(address _aavePool, address _link, IRouterClient[4] memory _routers, Network _thisNetwork)
        BasePluginWithEventMetadata(
            PluginMetadata({name: "Fillable.xyz", version: "1.0.0", requiresRootAccess: false, iconUrl: "", appUrl: ""})
        )
        CCIPReceiver(address(_routers[uint256(_thisNetwork)]))
    {
        aavePool = _aavePool;
        routers = _routers;
        linkToken = LinkTokenInterface(_link);
    }

    function getRouteKey(address _to, address _from, Network _network) internal pure returns (bytes32) {
        return keccak256(abi.encode(address, address, uint256(_network)));
    }

    function getAaveUserHealth(address userAddress) public view returns (uint256) {
        (,,,,, uint256 heathFactor) = IPool(aavePool).getUserAccountData(userAddress);
        return heathFactor;
    }

    function requestCollateral(
        address _to,
        address _from,
        Network network,
        uint64 destinationChainSelector,
        uint256 _amount
    ) external guard(_to, _from, network) returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: abi.encode(_to, _from, _amount), // ABI-encoded string
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: 200_000})
                ),
            // Set the feeToken  address, indicating LINK will be used for fees
            feeToken: address(linkToken)
        });

        uint256 fees = routers[uint256(network)].getFee(destinationChainSelector, evm2AnyMessage);

        if (fees > linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);
        }

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        linkToken.approve(address(routers[uint256(network)]), fees);

        // Send the message through the router and store the returned message ID
        messageId = routers[uint256(network)].ccipSend(destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(messageId, destinationChainSelector, receiver, _to, _from, _amount, address(linkToken), fees);

        // Return the message ID
        return messageId;
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        lastReceivedText = abi.decode(any2EvmMessage.data, (string)); // abi-decoding of the sent text

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            abi.decode(any2EvmMessage.data, (string))
        );

        (address _to, address _from, uint256 _amount) = abi.decode(any2EvmMessage.data, (address, address, uint256));
        processMessage(_to, _from, _amount);
    }

    function processMesage(address from, address to, uint256 amount) internal {
        ISafe iSafe = ISafe(from);
        Safe safe = Safe(payable(from));
        SafeProtocolAction[] memory actions = new SafeProtocolAction[](1);
        actions[0].to = payable(to);
        actions[0].value = amount;
        actions[0].data = ""; // TODO: abi.encodeWithSignature("PayAave(address,uint256)", _address, amount, data etc etc);

        // Note: Metadata format has not been proposed
        SafeTransaction memory safeTx =
            SafeTransaction({actions: actions, nonce: safe.nonce(), metadataHash: bytes32(0)});
        try ISafeProtocolManager(safe, manager()).executeTransaction(iSafe, safeTx) returns (bytes[] memory) {}
        catch (bytes memory reason) {
            revert FeePaymentFailure(reason);
        }
    }

    function postCollateralToAave() external {
        //TODO 
    }
}
