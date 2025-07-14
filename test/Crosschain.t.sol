// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {IERC20} from "ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

contract CrosschainTest is Test {
    RebaseToken sepoliaRebaseToken;
    RebaseToken arbSepoliaRebaseToken;
    Vault sepoliaVault;
    Vault arbSepoliaVault;

    RebaseTokenPool sepoliaRebaseTokenPool;
    RebaseTokenPool arbSepoliaRebaseTokenPool;

    uint256 public sepoliaFork;
    uint256 public arbSepoliaFork;

    address public OWNER = makeAddr("OWNER");

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    Register.NetworkDetails public sepoliaNetworkDetails;
    Register.NetworkDetails public arbSepoliaNetworkDetails;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia");
        arbSepoliaFork = vm.createSelectFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Deployment and Config on Sepolia
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(sepoliaFork);

        vm.selectFork(sepoliaFork);
        vm.startPrank(OWNER);
        sepoliaRebaseToken = new RebaseToken();
        sepoliaVault = new Vault(address(sepoliaRebaseToken));

        sepoliaRebaseTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaRebaseToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        sepoliaRebaseToken.grantMintAndBurnRole(address(sepoliaVault));
        sepoliaRebaseToken.grantMintAndBurnRole(address(sepoliaRebaseTokenPool));

        vm.stopPrank();

        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(arbSepoliaFork);
        // Deployment and Config on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(OWNER);
        arbSepoliaRebaseToken = new RebaseToken();
        arbSepoliaVault = new Vault(address(arbSepoliaRebaseToken));

        arbSepoliaRebaseTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaRebaseToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        arbSepoliaRebaseToken.grantMintAndBurnRole(address(arbSepoliaVault));
        arbSepoliaRebaseToken.grantMintAndBurnRole(address(arbSepoliaRebaseTokenPool));
        vm.stopPrank();
    }
}
