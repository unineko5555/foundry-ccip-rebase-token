//SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.24;

import { IRebaseToken } from "./interfaces/IRebaseToken.sol";

contract vault {
    // we need to pass the token adress to the construtor
    // create a deposit function that mint tokens to the user equal to the amount of ETH the user has sent
    // create redeem function that burns the user's tokens and sends them the ETH
    // create a function that allows the owner to set the interest rate
    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);
    
    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable{}

    /**
    * @notice Allows users to deposit ETH into the vault and mint rebase tokens in-return
     */
    function deposit() external payable {
        // we need to use the amount of ETH the user has sent to mint tokens to the user
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
    * @notice Allows users to redeem their rebase tokens for ETH
    * @param _amount the amount of rebase tokens the user wants to redeem
     */
    function redeem(uint256 _amount) external {
        // 1. burn the tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. we need to send the user ETH
        // payable(msg.sender).transfer(_amount);
        (bool success,) = payable(msg.sender).call{value: _amount}(""); // low level call
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
    * @notice Get the address of the rebase token
    * @return the address of the rebase token
     */
    function getrebaseToken() external view returns (address) {
        return address(i_rebaseToken);
    }
}