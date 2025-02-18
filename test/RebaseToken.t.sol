// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        // (bool success,) = payable(address(vault)).call{value: 1e18}(""); // なぜ？？
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardsAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardsAmount}("");
        require(success, "Failed to add rewards");
    }

    function testDepositLinear(uint256 amount) public {
        vm.assume(amount > 1e5);
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // (bool success,) = address(vault).call{value: amount}("");
        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        assertEq(startBalance, amount);
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        // 4. warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1); // assertEq → assertApproxEqAbs

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        // 2. redeem
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    // Note:エラー未解決
    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max); // this is a crazy number of years - 2^96 seconds is a lot
        depositAmount = bound(depositAmount, 1e5, type(uint96).max); // this is an Ether value of max 2^78 which is crazy

        // 1.deposit
        vm.deal(user, depositAmount);
        vm.prank(user); //startPrank → prank, dealと位置も逆にするなぜ？
        vault.deposit{value: depositAmount}();

        // 2.warp the time
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        // 2(b) Add rewards to the vault
        vm.deal(owner, balanceAfterSomeTime - depositAmount);
        vm.prank(user);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);
        // 3.redeem
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;

        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    // function testCannotCallMint() public {
    //     // Deposit funds
    //     vm.startPrank(user);
    //     uint256 interestRate = rebaseToken.getInterestRate();
    //     vm.expectRevert();
    //     rebaseToken.mint(user, SEND_VALUE, interestRate);
    //     vm.stopPrank();
    // }

    // IAccessControl.AccessControlUnauthorizedAccountエラー
    // function testCannotCallMintAndBurn() public {
    //     // Deposit funds
    //     vm.prank(user);
    //     vm.expecPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
    //     rebaseToken.mint(user, 100, rebaseToken.getInterestRate());
    //     vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
    //     rebaseToken.burn(user, 100);
    // }

    // function testCannotWithdrawMoreThanBalance() public {
    //     // Deposit funds
    //     vm.startPrank(user);
    //     vm.deal(user, SEND_VALUE);
    //     vault.deposit{value: SEND_VALUE}();
    //     vm.expectRevert();
    //     vault.redeem(SEND_VALUE + 1);
    //     vm.stopPrank();
    // }

    // function testDeposit(uint256 amount) public {
    //     amount = bound(amount, 1e3, type(uint96).max);
    //     vm.deal(user, amount);
    //     vm.prank(user);
    //     vault.deposit{value: amount}();
    // }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address userTwo = makeAddr("userTwo");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 userTwoBalance = rebaseToken.balanceOf(userTwo);
        assertEq(userBalance, amount);
        assertEq(userTwoBalance, 0);

        // Update the interest rate so we can check the user interest rates are different after transferring.
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // Send half the balance to another user
        vm.prank(user);
        rebaseToken.transfer(userTwo, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 userTwoBalancAfterTransfer = rebaseToken.balanceOf(userTwo);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(userTwoBalancAfterTransfer, userTwoBalance + amountToSend);
        // After some time has passed, check the balance of the two users has increased
        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterWarp = rebaseToken.balanceOf(user);
        uint256 userTwoBalanceAfterWarp = rebaseToken.balanceOf(userTwo);
        // check their interest rates are as expected
        // since user two hadn't minted before, their interest rate should be the same as in the contract
        uint256 userTwoInterestRate = rebaseToken.getUserInterestRate(userTwo);
        assertEq(userTwoInterestRate, 5e10);
        // since user had minted before, their interest rate should be the previous interest rate
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        assertEq(userInterestRate, 5e10);

        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(userTwoBalanceAfterWarp, userTwoBalancAfterTransfer);
    }

    // function testSetInterestRate(uint256 newInterestRate) public {
    //     // bound the interest rate to be less than the current interest rate
    //     newInterestRate = bound(newInterestRate, 0, rebaseToken.getInterestRate() - 1);
    //     // Update the interest rate
    //     vm.startPrank(owner);
    //     rebaseToken.setInterestRate(newInterestRate);
    //     uint256 interestRate = rebaseToken.getInterestRate();
    //     assertEq(interestRate, newInterestRate);
    //     vm.stopPrank();

    //     // check that if someone deposits, this is their new interest rate
    //     vm.startPrank(user);
    //     vm.deal(user, SEND_VALUE);
    //     vault.deposit{value: SEND_VALUE}();
    //     uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
    //     vm.stopPrank();
    //     assertEq(userInterestRate, newInterestRate);
    // }

    // function testCannotSetInterestRate(uint256 newInterestRate) public {
    //     // Update the interest rate
    //     vm.startPrank(user);
    //     vm.expectRevert();
    //     rebaseToken.setInterestRate(newInterestRate);
    //     vm.stopPrank();
    // }

    // function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
    //     uint256 initialInterestRate = rebaseToken.getInterestRate();
    //     newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
    //     vm.prank(owner);
    //     vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
    //     rebaseToken.setInterestRate(newInterestRate);
    //     assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    // }

    // function testGetPrincipleAmount() public {
    //     uint256 amount = 1e5;
    //     vm.deal(user, amount);
    //     vm.prank(user);
    //     vault.deposit{value: amount}();
    //     uint256 principleAmount = rebaseToken.principalBalanceOf(user);
    //     assertEq(principleAmount, amount);

    //     // check that the principle amount is the same after some time has passed
    //     vm.warp(block.timestamp + 1 days);
    //     uint256 principleAmountAfterWarp = rebaseToken.principalBalanceOf(user);
    //     assertEq(principleAmountAfterWarp, amount);
    // }
}
