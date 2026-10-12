// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DCAToken} from "../src/DCAToken.sol";

/// @dev A bounded set of holders lets the invariant account for every token after arbitrary actions.
contract DCAHandler is Test {
    DCAToken public immutable token;
    address[4] public actors;
    mapping(address actor => uint256 balance) public modelBalance;
    mapping(address owner => mapping(address spender => uint256 amount)) public modelAllowance;

    constructor(DCAToken token_) {
        token = token_;
        actors[0] = makeAddr("invariant holder 0");
        actors[1] = makeAddr("invariant holder 1");
        actors[2] = makeAddr("invariant holder 2");
        actors[3] = makeAddr("invariant holder 3");
        modelBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, modelBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        modelBalance[from] -= amount;
        modelBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        if (unlimited) amount = type(uint256).max;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowance[owner][spender] = amount;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        modelAllowance[owner][spender] = 0;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = modelAllowance[owner][spender];
        uint256 balance = modelBalance[owner];
        amount = bound(amount, 0, approved < balance ? approved : balance);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        modelBalance[owner] -= amount;
        modelBalance[to] += amount;
        if (approved != type(uint256).max) modelAllowance[owner][spender] -= amount;
    }
}

contract DCATokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    DCAToken internal token;
    DCAHandler internal handler;

    function setUp() public {
        token = new DCAToken();
        handler = new DCAHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = DCAHandler.transfer.selector;
        selectors[1] = DCAHandler.approve.selector;
        selectors[2] = DCAHandler.revoke.selector;
        selectors[3] = DCAHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyIsFixedAndTokensAreConserved() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            balances += token.balanceOf(handler.actors(i));
        }
        assertEq(balances, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_BalancesAndAllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.modelBalance(owner));
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.modelAllowance(owner, spender));
            }
        }
    }
}
