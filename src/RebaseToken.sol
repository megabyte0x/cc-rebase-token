// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author @megabyte0x
 * @notice This is a cross-chain rebase token that incentivize users to deposit assets into the vault.
 * @notice The interest rate can only decrease.
 * @notice Each user will have their own interest rate depending on the time they deposit into the vault.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    ////////////////////////
    /// State Variables ////
    ////////////////////////
    error RebaseToken__InterestRateMustBeLessThanTheCurrent();

    ////////////////////////
    /// State Variables ////
    ////////////////////////
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // interest rate per second
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    mapping(address user => uint256 userInterestRate) private s_userInterestRate;
    mapping(address user => uint256 lastUpdated) private s_lastUpdated;

    ////////////////////////
    /// Events ////////////
    ////////////////////////

    event RebaseToken__InterestRateSet(uint256 indexed _interestRate);

    ////////////////////////
    /// Constructor ///////
    ////////////////////////
    constructor() ERC20("RebaseToken", "REB") Ownable(msg.sender) {}

    /**
     * @notice Grant the mint and burn role to an account.
     * @param _account The address to grant the mint and burn role to.
     */
    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate for the rebase token.
     * @param _interestRate The new interest rate.
     * @dev The interest rate can only decrease.
     */
    function setInterestRate(uint256 _interestRate) external onlyOwner {
        if (_interestRate > s_interestRate) {
            revert RebaseToken__InterestRateMustBeLessThanTheCurrent();
        }

        s_interestRate = _interestRate;
        emit RebaseToken__InterestRateSet(_interestRate);
    }

    /**
     * @notice Mint tokens to the user.
     * @param _to The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // Mint the accrued interest to the user
        _mintAccruedInterest(_to);
        // Set the user's interest rate to the current interest rate
        s_userInterestRate[_to] = s_interestRate;
        // Mint the tokens to the user
        _mint(_to, _amount);
    }

    /**
     * @notice Burn tokens from the user.
     * @param _from The address to burn tokens from.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // Mint the accrued interest to the user
        _mintAccruedInterest(_from);

        // Burn the tokens from the user
        _burn(_from, _amount);
    }

    /**
     * @notice Get the principal balance of a user. This is the balance of user at the time of his last interaction with the contract.
     * @param _user The address of the user.
     * @return The principal balance of the user.
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Get the balance of a user with accrued interest.
     * @param _user The address of the user.
     * @return The balance of the user with accrued interest.
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // Get the current balance
        uint256 currentBalance = super.balanceOf(_user);

        // Get the interest accumulated since the last update
        uint256 interestAccumulated = _calculateInterestAccumulatedSinceLastUpdate(_user);

        // multiply the balance by the interest that has accrued since the last update
        // currentBalance * (1 + (interestRate * timeElapsed))
        // currentBalance + (currentBalance * interestRate * timeElapsed)
        return (currentBalance * interestAccumulated) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens to a recipient.
     * @param _recipient The address to transfer tokens to.
     * @param _amount The amount of tokens to transfer.
     * @notice This first mint the accrued interest to the sender and the recipient.
     * @dev If the amount is the max value, the entire balance (principal and accrued interest) will be transferred. This is to avoid dust tokens.
     * @dev If the recipient has no balance, set the interest rate to the sender's interest rate.
     * @dev If the recipient has a balance with lower interest rate, the amount will be transferred with the lower interest rate and vice versa.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        address sender = msg.sender;

        _mintAccruedInterest(sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[sender];
        }

        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from a sender to a recipient.
     * @param _sender The address to transfer tokens from.
     * @param _recipient The address to transfer tokens to.
     * @param _amount The amount of tokens to transfer.
     * @notice This first mint the accrued interest to the sender and the recipient.
     * @dev If the amount is the max value, the entire balance (principal and accrued interest) will be transferred. This is to avoid dust tokens.
     * @dev If the recipient has no balance, set the interest rate to the sender's interest rate.
     * @dev If the recipient has a balance with lower interest rate, the amount will be transferred with the lower interest rate and vice versa.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }

        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the interest that has accrued since the last update.
     * @param _user The address of the user.
     * @return The interest that has accrued since the last update.
     */
    function _calculateInterestAccumulatedSinceLastUpdate(address _user) internal view returns (uint256) {
        uint256 lastUpdated = s_lastUpdated[_user];
        uint256 interestRate = s_userInterestRate[_user];

        uint256 timeElapsed = block.timestamp - lastUpdated;

        // 1 + (interestRate * timeElapsed)
        return PRECISION_FACTOR + (interestRate * timeElapsed);
    }

    /**
     * @notice Mint the accrued interest to the user since the last update.
     * @param _user The address to mint the accrued interest to.
     */
    function _mintAccruedInterest(address _user) internal {
        // 1. Principal Balance since last update
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        // 2. Current Balance with accrued interest
        uint256 currentBalance = balanceOf(_user);
        // 3. Difference between the two
        uint256 difference = currentBalance - previousPrincipalBalance;
        // 4. Update the last updated timestamp
        s_lastUpdated[_user] = block.timestamp;
        // 5. Mint the difference
        _mint(_user, difference);
    }

    /**
     * @notice Get the interest rate for a user.
     * @param _user The address of the user.
     * @return The interest rate for the user.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Get the last updated timestamp for a user.
     * @param _user The address of the user.
     * @return The last updated timestamp for the user.
     */
    function getLastUpdated(address _user) external view returns (uint256) {
        return s_lastUpdated[_user];
    }

    /**
     * @notice Get the current interest rate.
     * @return The current interest rate.
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
