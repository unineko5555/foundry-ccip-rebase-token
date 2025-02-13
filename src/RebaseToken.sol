// SPDX-MIT-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
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


contract RebaseToken is ERC20, Ownable, AccessControl {
    error  RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18; //1e18 → 1e27
    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // 10^(-8) = 1 / 10^8 = 0.00000001
    mapping (address => uint256) private s_userInterestRate;
    mapping (address => uint256) private s_lastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) AccessControl() {
        // _mint(msg.sender, 1000000 * 10 ** decimals());
        // _setRoleAdmin(DEFAULT_ADMIN_ROLE, msg.sender);
        // _setRoleAdmin(MINT_AND_BURN_ROLE, msg.sender);
    }

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }
    /*
    * @Deposits tokens into the vault and mints the user tokens
    * @param _newInterestRate The new interest rate to set
    * @dev The interest rate can only decrease
    */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Set the interest rate
        if (_newInterestRate < s_interestRate) { //> でない？？
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /*
    * @notice Get the principale balance of the user. This is the number of tokens that have actually been minted to the user, not including any interest that has accrued since the last user interected with the protocol.
    * @param _user The user to get the balance for
    * @return The principale balance of the user
    */
    function principalebalanceOf(address _user) public view returns (uint256) {
        return super.balanceOf(_user);
    }
    /*
    * @notice Mint the user tokens when they deposit into the vault
    * @param _to The user to mint the tokens to
    * @param _amount The amount of tokens to mint
    */
    function mint(address _to, uint256 _amount, uint256 _userInterfaceRate) external onlyRole(MINT_AND_BURN_ROLE){ //ここでsuperを使わない理由は？
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterfaceRate;
        _mint(_to, _amount);
    }

    /*
    * @notice Burn the user tokens when they withdraw from the vault
    * @param _from The user to burn the tokens from
    * @param _amount The amount of tokens to burn
    */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) { //AAVEv3で使用されている
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
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
    * @notice Transfer tokens from one user to another
    * @param _recipient The recipient of the tokens
    * @param _amount The amount of tokens to transfer
    * @return True if the transfer was successful
    */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        //tokenを持っていない場合のみ新しいいinterest rateを設定する、すでに持っている場合はinterest rateを変更しない(変更するとinterest  rateを意図的に下げることができるため)
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_interestRate;
        }
        return super.transfer(_recipient, _amount); //ERC20を継承しているのでsuperを使う
    }

    /*
    * @notice Transfer tokens from one user to another
    * @param _sender The sender of the tokens
    * @param _recipient The recipient of the tokens
    * @param _amount The amount of tokens to transfer
    * @return True if the transfer was successful
    */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        //tokenを持っていない場合のみ新しいinterest rateを設定する、すでに持っている場合はinterest rateを変更しない(変更するとinterest  rateを意図的に下げることができるため)
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_interestRate;
        }
        return super.transferFrom(_sender, _recipient, _amount); //ERC20を継承しているのでsuperを使う
    }

    /*
    * @notice Calculate the interest that has accumulated since the last update
    * @param _user The user to calculate the interest for
    * @return The linearinterest that has accumulated in the time since the balance was last updated.
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
        uint256 timeElapsed = block.timestamp - s_lastUpdatedTimestamp[_user];
        linearInterest = (PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed));    
    }

    /*
    * @notice Mint the accrued interest to the user since the last time they intereacted with the protocol (e.g. burn, mint, transfer)
    * @param _user The user to mint the accrued interest to
    */
    function _mintAccruedInterest(address _user) internal { //view??
        // (1) find their current balance of rebase tokens that have been minted to the user -> principal
        uint256 previousPrincipalBalance = super.balanceOf(_user); //ERC20を継承しているのでsuperを使う
        // (2) calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // caluculate the number of tokens that have been minted to the user -> (2) - (1) interest
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;
        // call _mint to mint the tokens to the user 
        _mint(_user, balanceIncrease); //Interaction of CEI
        // set the user's last updated timestamp 
        s_lastUpdatedTimestamp[_user] = block.timestamp;
    }

    /*
    * @notice Get the interest rate that is currently set for the smart contract.Any future deposits will receive this interest rate
    * @return The interest rate
    */
    function getInterestRate() public view returns (uint256) {
        return s_interestRate;
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