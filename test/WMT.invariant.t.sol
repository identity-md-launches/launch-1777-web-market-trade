// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
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

    function transfer(uint256 senderSeed, uint256 recipientSeed, uint256 amountSeed, bool valid) external {
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
        }
        _assertModel();
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount;
        if (mode % 3 == 0) amount = 0;
        else if (mode % 3 == 1) amount = bound(amountSeed, 0, SUPPLY);
        else amount = type(uint256).max;

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
        }
        _assertModel();
    }

    function _assertModel() internal view {
        assertEq(token.totalSupply(), SUPPLY);
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            assertEq(token.balanceOf(actor), expectedBalance[actor], "balance differs from model");
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

contract WMTInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    WMTHandler internal handler;
    WMT internal token;

    function setUp() public {
        handler = new WMTHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = WMTHandler.transfer.selector;
        selectors[1] = WMTHandler.approve.selector;
        selectors[2] = WMTHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyIsFixedAndAllBalancesAreAccountedFor() public view {
        assertEq(token.totalSupply(), SUPPLY);
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
}
