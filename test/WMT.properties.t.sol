// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WMT} from "src/WMT.sol";

/// @dev Exercises allowance lifecycles and properties spanning several transactions.
/// forge-config: default.fuzz.runs = 1000
contract WMTPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WMT internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        alice = makeAddr("property-alice");
        bob = makeAddr("property-bob");
        spender = makeAddr("property-spender");
        token = new WMT();
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedAllowanceCanBeReducedAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 1);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_returningTokensDoesNotRestoreSpentAllowance() public {
        assertTrue(token.transfer(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 10));
        vm.prank(bob);
        assertTrue(token.transfer(alice, 10));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_approvalDoesNotReserveBalanceAndSurvivesDirectTransfers() public {
        assertTrue(token.transfer(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10));
        assertEq(token.allowance(alice, spender), 10);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10));
        vm.prank(spender);
        token.transferFrom(alice, spender, 10);
        assertEq(token.allowance(alice, spender), 10);
        vm.prank(bob);
        assertTrue(token.transfer(alice, 10));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 10));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 10);
    }

    function test_approvalGivenBeforeFundingWorksAfterFailureAndFunding() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, SUPPLY));
        vm.prank(spender);
        token.transferFrom(alice, bob, SUPPLY);
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, SUPPLY));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unapprovedSpenderCannotUseAnotherSpendersAllowance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferFromCannotExceedBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    function test_zeroDelegatedTransferEmitsEventWithoutApproval() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroApprovalToZeroSpenderDoesNotDisturbExistingApproval() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_paidMutationsRevertWithoutChangingState() public {
        vm.deal(address(this), 3);
        assertTrue(token.approve(address(this), 1));
        bytes[3] memory calls = [
            abi.encodeCall(token.transfer, (alice, 1)),
            abi.encodeCall(token.approve, (spender, 1)),
            abi.encodeCall(token.transferFrom, (address(this), alice, 1))
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertFalse(success, "ERC20 mutation accepted native value");
        }
        assertEq(address(token).balance, 0);
        assertEq(address(this).balance, 3);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), address(this)), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedBalanceSpendCanBeRetried(uint256 rawBalance, uint256 rawShortfall, bool unlimited) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 shortfall = bound(rawShortfall, 1, SUPPLY - balance);
        uint256 amount = balance + shortfall;
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), approved);

        assertTrue(token.transfer(alice, shortfall));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_invalidRecipientDoesNotConsumeApproval(uint256 rawAmount, bool unlimited) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), approved);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), unlimited ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_reapprovalReplacesPartiallySpentAllowance(
        uint256 rawInitial,
        uint256 rawSpent,
        uint256 rawReplacement
    ) public {
        uint256 initial = bound(rawInitial, 1, SUPPLY - 1);
        uint256 spent = bound(rawSpent, 1, initial);
        uint256 replacement = bound(rawReplacement, 0, SUPPLY - spent - 1);
        assertTrue(token.approve(spender, initial));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, replacement, replacement + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, replacement + 1);
        assertEq(token.allowance(address(this), spender), replacement);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, replacement));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), spent + replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent - replacement);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Splitting a spend must have the same final effect as one whole spend,
    /// including allowances larger than the entire supply and unlimited approval.
    function testFuzz_splitDelegatedTransfersMatchSingleSpend(uint256 approved, uint256 rawAmount, uint256 rawFirst)
        public
    {
        WMT split = new WMT();
        uint256 limit = approved < SUPPLY ? approved : SUPPLY;
        uint256 amount = bound(rawAmount, 0, limit);
        uint256 first = bound(rawFirst, 0, amount);
        assertTrue(token.approve(spender, approved));
        assertTrue(split.approve(spender, approved));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertTrue(split.transferFrom(address(this), alice, first));
        assertTrue(split.transferFrom(address(this), alice, amount - first));
        vm.stopPrank();
        assertEq(split.balanceOf(alice), amount);
        assertEq(split.balanceOf(alice), token.balanceOf(alice));
        assertEq(split.balanceOf(address(this)), SUPPLY - amount);
        assertEq(split.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(split.allowance(address(this), spender), token.allowance(address(this), spender));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(split.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresExistingBalances(
        uint256 rawAliceBalance,
        uint256 rawBobBalance,
        uint256 rawAmount
    ) public {
        uint256 aliceBefore = bound(rawAliceBalance, 0, SUPPLY);
        uint256 bobBefore = bound(rawBobBalance, 0, SUPPLY - aliceBefore);
        uint256 amount = bound(rawAmount, 0, aliceBefore);
        assertTrue(token.transfer(alice, aliceBefore));
        assertTrue(token.transfer(bob, bobBefore));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), aliceBefore - amount);
        assertEq(token.balanceOf(bob), bobBefore + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), aliceBefore);
        assertEq(token.balanceOf(bob), bobBefore);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBefore - bobBefore);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
