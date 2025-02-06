// SPDX-MIT-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/*
* @title RebaseToken
* @author unineko
* @notice This is a cross-chain rebase token that incentivises users to deposit into vault
* @notice The interest rate in the smart contract can only decrease
* @notice Each will user will have their own interest rate that is the global interest rate at the time of depositing
* @dev A simple ERC20 token with a name, symbol, and 18 decimals.
*/

/*
* @dev The interest rate can only decrease

*/


contract RebaseToken is ERC20 {
    error  RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = 5e10;
    mapping (address => uint256) private s_userInterestRate;
    mapping (address => uint256) private s_lastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
    /*
    * @Deposits tokens into the vault and mints the user tokens
    * @param _newInterestRate The new interest rate to set
    * @dev The interest rate can only decrease
    */
    function setInterestRate(uint256 _newInterestRate) external {
        // Set the interest rate
        if (_newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }
    /*
    * @notice Mint the user tokens when they deposit into the vault
    * @param _to The user to mint the tokens to
    * @param _amount The amount of tokens to mint
    */
    function mint(address _to, uint256 _amount) external { //ここでsuperを使わない理由は？
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /*
    * @notice Calculate the interest that has accumulated since the last update
    * (principale balance ) + some interest that has accreud
    * @param _user The user to calculate the balance for
    * @return The balance of the user including the interest that has accumulated in the time since the balance was last updated.
    */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current balance of the user(the number of token that have actually been minted to the user)
        // multiply the principle balance by the interest that has accumulated in the time since the balance was last updated
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /*
    * @notice Calculate the interest that has accumulated since the last update
    * @param _user The user to calculate the interest for
    * @return The interest that has accumulated in the time since the balance was last updated.
    */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) { //ERC20ではviewを使う
        // we need to calcurate the interest that has accumulated the time since the last update
        // this is going to be linear growth with time
        //1. calculate the time since the last update
        //2. calculate the amount of linear growth
        // principal amount(1 + (user interest rate * time elapsed))
        // deposit: 10 tokens
        // interest rate 0.5 tokens per second
        // 10 + (10 * 0.5 * 2)
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = (PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed));    
    }

    function _mintAccruedInterest(address _user) internal view { //view??
        // (1) find their current balance of rebase tokens that have been minted to the user -> principal
        // (2) calculate their current balance including any interest -> balanceOf
        // caluculate the number of tokens that have been minted to the user -> (2) - (1) interest
        // call _mint to mint the tokens to the user 
        // set the user's last updated timestamp 
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }

    /*
    * @noitice Get the interest rate for a user
    * @param _user The user to get the interest rate for
    * @return The interest rate for the user
    */
    function getUserInterestRate(address _user) public view returns (uint256) {
        return s_userInterestRate[_user];
    }
}