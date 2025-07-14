// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    ////////////////////////
    // Errors
    ////////////////////////
    error Vault_WithdrawFailed();

    ////////////////////////
    // State Variables
    ////////////////////////

    IRebaseToken public immutable i_rebaseToken;

    ////////////////////////
    // Events
    ////////////////////////

    event Vault_Deposit(address indexed sender, uint256 amount);
    event Vault_Withdraw(address indexed sender, uint256 amount);

    ////////////////////////
    // Constructor
    ////////////////////////

    constructor(address _rebaseToken) {
        i_rebaseToken = IRebaseToken(_rebaseToken);
    }

    receive() external payable {}

    ////////////////////////
    // External Functions
    ////////////////////////

    /**
     * @notice Deposit ETH into the vault.
     * @dev The amount of rebase tokens minted is equal to the amount of ETH deposited.
     */
    function deposit() external payable {
        uint256 amountReceived = msg.value;
        address sender = msg.sender;

        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(sender, amountReceived, interestRate);

        emit Vault_Deposit(sender, amountReceived);
    }

    /**
     * @notice Withdraw ETH from the vault.
     * @dev The amount of rebase tokens burned is equal to the amount of ETH withdrawn.
     * @dev If the amount is the max value, the entire balance (principal and accrued interest) will be burned. This is to avoid dust tokens.
     */
    function withdraw(uint256 _amount) external {
        address sender = msg.sender;

        // If the amount is the max value, burn the entire balance (principal and accrued interest)
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(sender);
        }

        i_rebaseToken.burn(sender, _amount);

        (bool success,) = payable(sender).call{value: _amount}("");
        if (!success) revert Vault_WithdrawFailed();

        emit Vault_Withdraw(sender, _amount);
    }

    ////////////////////////
    // View Functions
    ////////////////////////

    /**
     * @notice Get the address of the rebase token.
     * @return The address of the rebase token.
     */
    function getRebaseToken() public view returns (address) {
        return address(i_rebaseToken);
    }
}
