// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {SafeProtocolManager} from "@safe/SafeProtocolManager.sol";
import {ISafe} from "@safe/interfaces/Accounts.sol";
import {SafeProtocolRegistry} from "@safe/SafeProtocolRegistry.sol";
import {SafeTransaction, SafeProtocolAction} from "@safe/DataTypes.sol";
import {Safe} from "@safe/Safe.sol";
import {SafeProxy} from "@safe/proxies/SafeProxy.sol";
import {TokenCallbackHandler} from "@safe/handler/TokenCallbackHandler.sol";
import {Plugin} from "../src/Plugin.sol";
import {Enum} from "@safe/common/Enum.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {SafeTxConfig} from "../script/utils/SafeTxConfig.s.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {ISafeProtocolManager} from "@safe/interfaces/Manager.sol";

/**
 * @title Foundry Test Setup for Safe Plugin
 * @author @willschiller
 * @notice This Test contract sets up an entirely fresh Safe{Core} Protocol instance with plugin and handles all the regitration.
 * (Deploys Safe, Manager, Registery & Plugin). This allows you to test locally without forking or sending testnet transaction.
 * @dev set the following environment variables in .env:
 *  SAFE_ADDRESS (The address of your safe),
 *  SAFE_OWNER_ADDRESS (An EOA that is an owner of your safe),
 *  SAFE_OWNER_PRIVATE_KEY (The EOA key) In production, you should not keep your private key in the env.
 * @dev One test is included to check that the plugin is enabled for the safe correctly.
 * @dev Extend with your own tests.
 */

contract PluginTest is Test {
    address private constant ARBITRUM_GOERLI_ROUTER = 0x88E492127709447A5ABEFdaB8788a15B4567589E;
    address private constant ARBITRUM_GOERLI_LINK = 0xB7C5a28bE43543eccE023A63d69b88d441cB6a28;
    address private constant ARBITRUM_GOERLI_AAVE_POOL = 0xccEa5C65f6d4F465B71501418b88FBe4e7071283;
    address private constant POLYGON_MUMBAI_ROUTER = 0x70499c328e1E2a3c41108bd3730F6670a44595D1;
    address private constant POLYGON_MUMBAI_LINK = 0xaB9F0568d5C6CE1437ba07E6efE529A2A9b82665;
    address private constant POLYGON_MUMBAI_AAVE_POOL = 0xcC6114B983E4Ed2737E9BD3961c9924e6216c704;

    address owner = vm.envAddress("SAFE_OWNER_ADDRESS");
    Safe singleton;
    SafeProxy proxy;
    Safe safe;
    TokenCallbackHandler handler;
    Plugin arbitrumPlugin;
    Plugin polyPlugin;
    SafeProtocolManager arbitrumManager;
    SafeProtocolRegistry arbitrumRegistry;
    SafeProtocolManager polyManager;
    SafeProtocolRegistry polyRegistry;
    SafeTxConfig safeTxConfig = new SafeTxConfig();
    SafeTxConfig.Config config = safeTxConfig.run();

    error SafeTxFailure(bytes reason);

    function getTransactionHash(address _to, bytes memory _data) public view returns (bytes32) {
        return safe.getTransactionHash(
            _to,
            config.value,
            _data,
            config.operation,
            config.safeTxGas,
            config.baseGas,
            config.gasPrice,
            config.gasToken,
            config.refundReceiver,
            safe.nonce()
        );
    }

    function sendSafeTx(address _to, bytes memory _data, bytes memory sig) public {
        try safe.execTransaction(
            _to,
            config.value,
            _data,
            config.operation,
            config.safeTxGas,
            config.baseGas,
            config.gasPrice,
            config.gasToken,
            config.refundReceiver,
            sig //sig
        ) {} catch (bytes memory reason) {
            revert SafeTxFailure(reason);
        }
    }

    function setUp() public {
        vm.startPrank(owner);
        IRouterClient[2] memory routers = [IRouterClient(ARBITRUM_GOERLI_ROUTER), IRouterClient(POLYGON_MUMBAI_ROUTER)];
        vm.selectFork(vm.createFork(vm.envString("ARBITRUM_GOERLI_RPC")));
        vm.deal(owner, 10 ether);
        arbitrumRegistry = new SafeProtocolRegistry(owner);
        arbitrumManager = new SafeProtocolManager(owner, address(arbitrumRegistry));

        vm.selectFork(vm.createFork(vm.envString("POLYGON_MUMBAI_RPC")));
        vm.deal(owner, 10 ether);
        polyRegistry = new SafeProtocolRegistry(owner);
        polyManager = new SafeProtocolManager(owner, address(polyRegistry));
        ISafeProtocolManager[2] memory _managers =
            [ISafeProtocolManager(arbitrumManager), ISafeProtocolManager(polyManager)];

        polyPlugin =
            new Plugin(POLYGON_MUMBAI_ROUTER, POLYGON_MUMBAI_LINK, routers, _managers, Plugin.Network.POLYGON_MUMBAI);

        safe = makeSafe();
        polyRegistry.addIntegration(address(polyPlugin), Enum.IntegrationType.Plugin);

        bytes32 txHash =
            getTransactionHash(address(safe), abi.encodeWithSignature("enableModule(address)", address(polyManager)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("SAFE_OWNER_PRIVATE_KEY"), txHash);
        sendSafeTx(
            address(safe),
            abi.encodeWithSignature("enableModule(address)", address(polyManager)),
            abi.encodePacked(r, s, v)
        );

        txHash = getTransactionHash(
            address(polyManager), abi.encodeWithSignature("enablePlugin(address,bool)", address(polyPlugin), false)
        );
        (v, r, s) = vm.sign(vm.envUint("SAFE_OWNER_PRIVATE_KEY"), txHash);
        sendSafeTx(
            address(polyManager),
            abi.encodeWithSignature("enablePlugin(address,bool)", address(polyPlugin), false),
            abi.encodePacked(r, s, v)
        );
        polyPlugin.setWhitelistedRecipient(
            address(polyPlugin), address(arbitrumPlugin), Plugin.Network.POLYGON_MUMBAI, true
        );
        polyPlugin.setWhitelistedRecipient(
            address(arbitrumPlugin), address(polyPlugin), Plugin.Network.POLYGON_MUMBAI, true
        );
        vm.stopPrank();
    }

    function makeSafe() public returns (Safe) {
        singleton = new Safe();
        proxy = new SafeProxy(address(singleton));
        handler = new TokenCallbackHandler();
        safe = Safe(payable(address(proxy)));
        address[] memory owners = new address[](1);
        owners[0] = owner;
        safe.setup(owners, 1, address(0), bytes(""), address(handler), address(0), 0, payable(address(owner)));
        return safe;
    }

    function testisPluginEnabled() public {
        assertEq(true, polyManager.isPluginEnabled(address(safe), address(polyPlugin)));
        assertEq(true, arbitrumManager.isPluginEnabled(address(safe), address(polyPlugin)));
    }

    function testRequestFunds() public {
        /* polyPlugin.requestCollateral( 
            _to,
            _from,
            Network network,
            uint64 destinationChainSelector,
            uint256 _amount
        ); */
    }
}
