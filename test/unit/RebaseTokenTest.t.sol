// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RebaseToken} from "../../src/RebaseToken.sol";
import {Vault} from "../../src/Vault.sol";
import {console} from "forge-std/console.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public OWNER = makeAddr("OWNER");
    address public USER = makeAddr("USER");

    uint256 public constant INITIAL_VAULT_DEPOSIT = 100 ether;

    function addRewardsToVault(uint256 amount) public {
        // send some rewards to the vault using the receive function
        payable(address(vault)).call{value: amount}("");
    }

    function setUp() public {
        vm.startPrank(OWNER);
        rebaseToken = new RebaseToken();
        vault = new Vault(address(rebaseToken));

        rebaseToken.grantMintAndBurnRole(address(vault));

        vm.deal(address(vault), INITIAL_VAULT_DEPOSIT);

        vm.stopPrank();
    }

    ////////////////////////
    // setInterestRate Tests ////
    ////////////////////////

    function test_setInterestRate_reverts_when_interestRateIsGreaterThanCurrent(uint256 _interestRate) public {
        vm.assume(_interestRate > 5e10);
        _interestRate = bound(_interestRate, 5e10, type(uint96).max);

        vm.startPrank(OWNER);
        vm.expectRevert(RebaseToken.RebaseToken__InterestRateMustBeLessThanTheCurrent.selector);
        rebaseToken.setInterestRate(_interestRate);
        vm.stopPrank();
    }

    ////////////////////////
    // Ownership Tests ////
    ////////////////////////

    function test_setInterestRate_reverts_when_notOwner() public {
        vm.startPrank(USER);
        vm.expectRevert();
        rebaseToken.setInterestRate(1e10);
        vm.stopPrank();
    }

    function test_mint_reverts_when_notMintAndBurnRole() public {
        vm.startPrank(USER);
        vm.expectRevert();
        rebaseToken.mint(USER, 1e10);
        vm.stopPrank();
    }

    function test_burn_reverts_when_notMintAndBurnRole() public {
        vm.startPrank(USER);
        vm.expectRevert();
        rebaseToken.burn(USER, 1e10);
        vm.stopPrank();
    }

    ////////////////////////
    // Interest Rate Tests ////
    ////////////////////////

    /**
     * @notice Test the interest rate of the rebase token is linear.
     * @param amount The amount of ETH to deposit. For fuzzing, we assume the amount is greater than 1e5.
     */
    function test_depositLiner(uint256 amount) public {
        // This will discard the fuzzer from testing smaller `_amount` values than 1e5.
        vm.assume(amount > 1e5);
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(USER);
        vm.deal(USER, amount);

        // 1. Deposit ETH into the vault.
        vault.deposit{value: amount}();

        // 2. Get the initial balance of the rebase token.
        uint256 initialBalance = rebaseToken.balanceOf(USER);
        console.log("initialBalance", initialBalance);
        assertEq(initialBalance, amount);

        // 3. Wait for 1 hour.
        vm.warp(block.timestamp + 1 hours);

        // 4. Get the balance of the rebase token after 1 hour.
        uint256 balanceAfter1Hour = rebaseToken.balanceOf(USER);
        console.log("balanceAfter1Hour", balanceAfter1Hour);
        assertGt(balanceAfter1Hour, initialBalance);

        // 5. Wait for additional 1 hour.
        vm.warp(block.timestamp + 1 hours);

        // 6. Get the balance of the rebase token after 2 hours.
        uint256 balanceAfter2Hours = rebaseToken.balanceOf(USER);
        console.log("balanceAfter2Hours", balanceAfter2Hours);
        assertGt(balanceAfter2Hours, balanceAfter1Hour);

        // 7. Check the difference of the balance of the rebase token after 2 hours and 1 hour.
        uint256 differenceBetween2HoursAnd1Hour = balanceAfter2Hours - balanceAfter1Hour;
        console.log("differenceBetween2HoursAnd1Hour", differenceBetween2HoursAnd1Hour);
        uint256 differenceBetween1HourAndInitialBalance = balanceAfter1Hour - initialBalance;
        console.log("differenceBetween1HourAndInitialBalance", differenceBetween1HourAndInitialBalance);

        assertApproxEqAbs(differenceBetween2HoursAnd1Hour, differenceBetween1HourAndInitialBalance, 1);

        vm.stopPrank();
    }

    /**
     * @notice Test the interest rate of the rebase token is transferred to the user B when the user A transfer the rebase token to the user B.
     * @param balanceOfUserA The balance of the user A. For fuzzing, we assume the balance is greater than 1e5.
     * @param amountToSend The amount of rebase token to send. For fuzzing, we assume the amount is greater than 1e5.
     */
    function test_TransferOfInterestRate_when_UserB_have_no_balance(uint256 balanceOfUserA, uint256 amountToSend)
        public
    {
        vm.assume(balanceOfUserA > 1e5);
        balanceOfUserA = bound(balanceOfUserA, 1e5 + 1e5, type(uint96).max);
        vm.assume(amountToSend > 1e5);
        amountToSend = bound(amountToSend, 1e5, balanceOfUserA - 1e5);

        address USERB = makeAddr("USERB");

        vm.startPrank(USER);
        vm.deal(USER, balanceOfUserA);
        vault.deposit{value: balanceOfUserA}();

        uint256 interestRateOfUserABeforeTransfer = rebaseToken.getUserInterestRate(USER);
        uint256 balanceOfUserBBeforeTransfer = rebaseToken.balanceOf(USERB);
        assertEq(balanceOfUserBBeforeTransfer, 0);

        rebaseToken.transfer(USERB, amountToSend);

        uint256 interestRateOfUserBAfterTransfer = rebaseToken.getUserInterestRate(USERB);

        assertEq(interestRateOfUserBAfterTransfer, interestRateOfUserABeforeTransfer);
    }

    /**
     * @notice Test the interest rate of the rebase token is NOT transferred to the user B when the user A transfer the rebase token to the user B.
     * @param balanceOfUserA The balance of the user A. For fuzzing, we assume the balance is greater than 1e5.
     * @param amountToSend The amount of rebase token to send. For fuzzing, we assume the amount is greater than 1e5.
     * @param userBBalance The balance of the user B. For fuzzing, we assume the balance is greater than 1e5.
     */
    function test_TransferOfInterestRate_when_UserB_have_balance(
        uint256 balanceOfUserA,
        uint256 amountToSend,
        uint256 userBBalance
    ) public {
        vm.assume(balanceOfUserA > 1e5);
        balanceOfUserA = bound(balanceOfUserA, 1e5 + 1e5, type(uint96).max);
        vm.assume(amountToSend > 1e5);
        amountToSend = bound(amountToSend, 1e5, balanceOfUserA - 1e5);
        vm.assume(userBBalance > 1e5);
        userBBalance = bound(userBBalance, 1e5, type(uint96).max);

        address USERB = makeAddr("USERB");

        vm.deal(USERB, userBBalance);
        vm.prank(USERB);
        vault.deposit{value: userBBalance}();

        vm.prank(OWNER);
        rebaseToken.setInterestRate(1e10);

        vm.startPrank(USER);
        vm.deal(USER, balanceOfUserA);
        vault.deposit{value: balanceOfUserA}();

        uint256 interestRateOfUserBBeforeTransfer = rebaseToken.getUserInterestRate(USERB);
        uint256 balanceOfUserBBeforeTransfer = rebaseToken.balanceOf(USERB);
        assertGt(balanceOfUserBBeforeTransfer, 0);

        rebaseToken.transfer(USERB, amountToSend);

        vm.stopPrank();

        uint256 interestRateOfUserBAfterTransfer = rebaseToken.getUserInterestRate(USERB);

        assertEq(interestRateOfUserBAfterTransfer, interestRateOfUserBBeforeTransfer);
    }

    ////////////////////////
    // Withdraw Tests ////
    ////////////////////////

    /**
     * @notice Test the amount withdraw is to the amount deposited when no time has passed.
     * @param amount The amount of ETH to deposit. For fuzzing, we assume the amount is greater than 1e5.
     */
    function test_withdrawStraightAway(uint256 amount) public {
        vm.assume(amount > 1e5);
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(USER);
        vm.deal(USER, amount);
        uint256 initialBalance = address(USER).balance;

        vault.deposit{value: amount}();

        vault.withdraw(type(uint256).max);

        uint256 balanceAfterWithdraw = address(USER).balance;

        assertEq(balanceAfterWithdraw, initialBalance);

        vm.stopPrank();
    }

    /**
     * @notice Test the amount withdraw is to the amount deposited when time has passed.
     * @param amount The amount of ETH to deposit. For fuzzing, we assume the amount is greater than 1e5.
     * @param time The amount of time to wait. For fuzzing, we assume the time is greater than 1 hour.
     */
    function test_withdrawAfterTimePassed(uint256 amount, uint256 time) public {
        vm.assume(amount > 1e5);
        amount = bound(amount, 1e5, type(uint96).max);
        vm.assume(time > 1 hours);
        time = bound(time, 1 hours, type(uint96).max);

        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();

        vm.warp(block.timestamp + time);

        uint256 balanceAfterTimePassed = rebaseToken.balanceOf(USER);

        vm.deal(OWNER, balanceAfterTimePassed - amount);
        vm.prank(OWNER);
        addRewardsToVault(balanceAfterTimePassed - amount);

        vm.prank(USER);
        vault.withdraw(type(uint256).max);

        uint256 ethBalance = address(USER).balance;

        assertEq(ethBalance, balanceAfterTimePassed);
    }

    ////////////////////////
    // Balance Tests ////
    ////////////////////////

    /**
     * @notice Test the balance of the user is the amount deposited.
     * @param amount The amount of ETH to deposit. For fuzzing, we assume the amount is greater than 1e5.
     */
    function test_balanceOf(uint256 amount) public {
        vm.assume(amount > 1e5);
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();

        uint256 balance = rebaseToken.balanceOf(USER);
        console.log("balance", balance);
        assertEq(balance, amount);
    }

    /**
     * @notice Test the principal amount of the user is the amount deposited.
     * @dev The principal amount is not affected by the interest rate till the user interact with the contract.
     * @param amount The amount of ETH to deposit. For fuzzing, we assume the amount is greater than 1e5.
     */
    function test_getPrincipalAmount(uint256 amount) public {
        vm.assume(amount > 1e5);
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();

        uint256 principalAmount = rebaseToken.principalBalanceOf(USER);
        assertEq(principalAmount, amount);

        vm.warp(block.timestamp + 1 hours);
        uint256 principalAmountAfterTimePassed = rebaseToken.principalBalanceOf(USER);
        assertEq(principalAmountAfterTimePassed, amount);
    }

    ////////////////////////
    // Transfer Tests ////
    ////////////////////////

    /**
     * @notice Test the transfer from user A to user B is successful when user A transfer the complete balance to user B after time has passed.
     * @param userABalance The balance of the user A. For fuzzing, we assume the balance is greater than 1e5.
     * @param userBBalance The balance of the user B. For fuzzing, we assume the balance is greater than 1e5.
     */
    function test_TransferFrom_when_UserATransferCompleteBalanceToUserB_after_time_passed(
        uint256 userABalance,
        uint256 userBBalance
    ) public {
        vm.assume(userABalance > 1e5);
        userABalance = bound(userABalance, 1e5, type(uint96).max);
        vm.assume(userBBalance > 1e5);
        userBBalance = bound(userBBalance, 1e5, type(uint96).max);

        address USERB = makeAddr("USERB");

        vm.deal(USERB, userBBalance);
        vm.prank(USERB);
        vault.deposit{value: userBBalance}();

        vm.deal(USER, userABalance);
        vm.prank(USER);
        vault.deposit{value: userABalance}();

        vm.warp(block.timestamp + 1 hours);

        uint256 balanceOfUserAAfterTimePassed = rebaseToken.balanceOf(USER);
        uint256 balanceOfUserBAfterTimePassed = rebaseToken.balanceOf(USERB);

        vm.startPrank(USER);
        rebaseToken.approve(USER, balanceOfUserAAfterTimePassed);
        rebaseToken.transferFrom(USER, USERB, balanceOfUserAAfterTimePassed);
        vm.stopPrank();

        uint256 balanceOfUserBAfterTransfer = rebaseToken.balanceOf(USERB);

        assertEq(balanceOfUserBAfterTransfer, balanceOfUserAAfterTimePassed + balanceOfUserBAfterTimePassed);
    }

    function test_getInterestRate() public {
        vm.prank(OWNER);
        rebaseToken.setInterestRate(1e10);

        uint256 interestRate = rebaseToken.getInterestRate();
        assertEq(interestRate, 1e10);
    }
}
