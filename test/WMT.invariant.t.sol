// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WMT} from "../src/WMT.sol";

/// @dev Exercises valid and invalid calls against a separate accounting model.
contract WMTHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    WMT public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new WMT();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder-", vm.toString(i)));
            expectedBalance[actors[i]] = SUPPLY / actors.length;
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
        }
    }

    function transfer(uint256 senderSeed, uint256 recipientSeed, uint256 amountSeed, bool valid) public {
        address sender = actors[senderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[sender];
        uint256 amount = valid ? bound(amountSeed, 0, balance) : balance + 1;

        vm.prank(sender);
        (bool success, bytes memory data) = address(token).call(abi.encodeCall(token.transfer, (recipient, amount)));
        assertEq(success, valid, "transfer result differs from model");
        if (success) {
            assertTrue(abi.decode(data, (bool)));
            expectedBalance[sender] -= amount;
            expectedBalance[recipient] += amount;
        } else {
            assertEq(
                data,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, sender, balance, amount),
                "transfer failed for an unexpected reason"
            );
        }
        _assertModel();
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount;
        if (mode % 5 == 0) amount = 0;
        else if (mode % 5 == 1) amount = bound(amountSeed, 0, SUPPLY);
        else if (mode % 5 == 2) amount = type(uint256).max;
        else if (mode % 5 == 3) amount = type(uint256).max - 1;
        else amount = amountSeed;

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        _assertModel();
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 recipientSeed, uint256 amountSeed, bool valid)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address owner = actors[ownerSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = balance < approved ? balance : approved;
        uint256 amount = valid ? bound(amountSeed, 0, available) : available + 1;

        vm.prank(spender);
        (bool success, bytes memory data) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, recipient, amount)));
        assertEq(success, valid, "transferFrom result differs from model");
        if (success) {
            assertTrue(abi.decode(data, (bool)));
            expectedBalance[owner] -= amount;
            expectedBalance[recipient] += amount;
            if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        } else {
            bytes memory expectedError = approved < amount
                ? abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
                : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
            assertEq(data, expectedError, "transferFrom failed for an unexpected reason");
        }
        _assertModel();
    }

    /// @dev Reach empty and full balances deliberately, including self-transfers.
    function transferAll(uint256 senderSeed, uint256 recipientSeed) external {
        address sender = actors[senderSeed % actors.length];
        transfer(senderSeed, recipientSeed, expectedBalance[sender], true);
    }

    /// @dev Invalid calls must leave every modeled balance and approval intact.
    /// The delegated amount is within allowance, so a bad recipient is reached.
    function invalidAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 operation) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        bytes memory callData;
        bytes memory expectedError;
        address caller = owner;
        if (operation % 3 == 0) {
            callData = abi.encodeCall(token.transfer, (address(0), bound(amountSeed, 0, expectedBalance[owner])));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else if (operation % 3 == 1) {
            callData = abi.encodeCall(token.approve, (address(0), amountSeed));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        } else {
            uint256 limit = expectedBalance[owner] < expectedAllowance[owner][spender]
                ? expectedBalance[owner]
                : expectedAllowance[owner][spender];
            callData = abi.encodeCall(token.transferFrom, (owner, address(0), bound(amountSeed, 0, limit)));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
            caller = spender;
        }
        vm.prank(caller);
        (bool success, bytes memory data) = address(token).call(callData);
        assertFalse(success, "zero address mutation succeeded");
        assertEq(data, expectedError, "invalid address failed for an unexpected reason");
        _assertModel();
    }

    /// @dev A round trip restores both holders and cannot create fees or tokens.
    function transferRoundTrip(uint256 senderSeed, uint256 recipientSeed, uint256 amountSeed) external {
        address sender = actors[senderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 senderBefore = expectedBalance[sender];
        uint256 recipientBefore = expectedBalance[recipient];
        uint256 amount = bound(amountSeed, 0, senderBefore);
        transfer(senderSeed, recipientSeed, amount, true);
        transfer(recipientSeed, senderSeed, amount, true);
        assertEq(token.balanceOf(sender), senderBefore, "round trip changed sender balance");
        assertEq(token.balanceOf(recipient), recipientBefore, "round trip changed recipient balance");
    }

    function _assertModel() internal view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            assertEq(token.balanceOf(actor), expectedBalance[actor], "balance differs from model");
            assertEq(token.allowance(actor, address(0)), 0);
            assertEq(token.allowance(address(0), actor), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actor, actors[j]),
                    expectedAllowance[actor][actors[j]],
                    "allowance differs from model"
                );
            }
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract WMTInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    WMTHandler internal handler;
    WMT internal token;

    function setUp() public {
        handler = new WMTHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = WMTHandler.transfer.selector;
        selectors[1] = WMTHandler.approve.selector;
        selectors[2] = WMTHandler.transferFrom.selector;
        selectors[3] = WMTHandler.transferAll.selector;
        selectors[4] = WMTHandler.invalidAddress.selector;
        selectors[5] = WMTHandler.transferRoundTrip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyIsFixedAndAllBalancesAreAccountedFor() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.name(), "Web Market Trade");
        assertEq(token.symbol(), "WMT");
        assertEq(token.decimals(), 18);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_balancesAndAllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor));
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
    }

    /// @dev Conservation alone would miss a frozen token. After every campaign,
    /// collect and move the whole supply while continuing to check all allowances.
    function afterInvariant() public {
        for (uint256 i = 1; i < 4; ++i) {
            handler.transferAll(i, 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        handler.transferAll(0, 1);
        assertEq(token.balanceOf(handler.actors(0)), 0);
        assertEq(token.balanceOf(handler.actors(1)), SUPPLY);
        handler.transferAll(1, 0);
        invariant_supplyIsFixedAndAllBalancesAreAccountedFor();
        invariant_balancesAndAllowancesMatchModel();
    }

    /// @dev Pin nonzero delegated spending and both failure branches, so those
    /// paths do not depend solely on random approval/transfer ordering.
    function test_handlerSequenceReachesAllowanceAndBalanceBoundaries() public {
        handler.approve(0, 1, 0, 2);
        handler.transferFrom(1, 0, 2, SUPPLY / 4, true);
        handler.transferFrom(1, 0, 2, 1, false);
        handler.transfer(2, 0, SUPPLY / 4, true);
        handler.approve(0, 1, 7, 1);
        handler.invalidAddress(0, 1, 7, 2);
        handler.transferFrom(1, 0, 0, 7, true);
        handler.transferFrom(1, 0, 2, 1, false);
        handler.approve(0, 1, 0, 3);
        handler.transferFrom(1, 0, 1, 1, true);
        handler.approve(0, 1, 0, 0);
        handler.transferFrom(1, 0, 2, 1, false);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 0);
        afterInvariant();
    }
}
