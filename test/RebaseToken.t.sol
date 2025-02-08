// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/RebaseToken.sol";
import "../src/Vault.sol";
import "../src/interfaces/IRebaseToken.sol"; 

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    function setup() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        bool success = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function testDepositLinear() public {
        // 1. deposit
        vm.startPrank(user);
        uint256 amount = bound(1e18, 1e18 * 5, type(uint256).max);
        vm.deal(user, amount); 
        payable(address(vault)).call{value: amount}("");
        // 2. check our rebase token balance
        // 3. warp the time and check the balance again
        // 4. warp the time again by the same amount and check the balance again
        vm.stopPrank();
    }

}