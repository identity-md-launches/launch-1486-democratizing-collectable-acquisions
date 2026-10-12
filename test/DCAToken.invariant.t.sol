// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {DCAToken} from "../src/DCAToken.sol";

/// @dev A bounded set of holders lets the invariant account for every token after arbitrary actions.
contract DCAHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
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
        modelBalance[actors[0]] = SUPPLY;
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
        // Reach allowance exhaustion regularly, rather than almost always approving more than the supply.
        amount = unlimited ? type(uint256).max : bound(amount, 0, SUPPLY);
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

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, spender, 1);
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

    /// @dev Always moves a nonzero full balance to a different actor, including previously emptied accounts.
    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = _fundedActor(fromSeed);
        uint256 toIndex = toSeed % actors.length;
        if (actors[toIndex] == from) toIndex = (toIndex + 1) % actors.length;
        address to = actors[toIndex];
        uint256 amount = modelBalance[from];

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        modelBalance[from] = 0;
        modelBalance[to] += amount;
    }

    // Failed calls must leave the ghost ledger unchanged. The invariants compare every tracked
    // balance and owner/spender pair after each action, so partial writes cannot pass unnoticed.
    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = modelBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectTransferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amount,
        bool unlimited
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = modelBalance[owner];
        // Keep the finite branch below MAX so it attempts an allowance write before reverting.
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        modelAllowance[owner][spender] = approved;

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectTransferFromAboveAllowance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 approved,
        uint256 amount
    ) external {
        // Sufficient balance isolates the authorization failure from insufficient funds.
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = modelBalance[owner];
        approved = bound(approved, 0, balance - 1);
        amount = bound(amount, approved + 1, balance);
        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        modelAllowance[owner][spender] = approved;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = modelBalance[owner];
        if (delegated && modelAllowance[owner][spender] < limit) limit = modelAllowance[owner][spender];
        amount = bound(amount, 0, limit);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _fundedActor(uint256 seed) internal view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[(start + i) % actors.length];
            if (modelBalance[actor] > 0) return actor;
        }
        revert("the fixed supply must belong to a tracked actor");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract DCATokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    DCAToken internal token;
    DCAHandler internal handler;

    function setUp() public {
        token = new DCAToken();
        handler = new DCAHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = DCAHandler.transfer.selector;
        selectors[1] = DCAHandler.approve.selector;
        selectors[2] = DCAHandler.revoke.selector;
        selectors[3] = DCAHandler.transferFrom.selector;
        selectors[4] = DCAHandler.transferFullBalance.selector;
        selectors[5] = DCAHandler.rejectTransferAboveBalance.selector;
        selectors[6] = DCAHandler.rejectTransferFromAboveBalance.selector;
        selectors[7] = DCAHandler.rejectTransferFromAboveAllowance.selector;
        selectors[8] = DCAHandler.rejectZeroRecipient.selector;
        selectors[9] = DCAHandler.rejectZeroSpender.selector;
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
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.modelAllowance(owner, spender));
            }
        }
    }

    function invariant_MetadataRemainsUnchanged() public view {
        assertEq(token.name(), "Democratizing Collectable Acquisions");
        assertEq(token.symbol(), "DCA");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// @dev After each random sequence, every holder can still move its full balance and get it back.
    /// Exact checks on both legs prevent a fee, freeze, or phantom balance from hiding in the round trip.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            address from = handler.actors(i);
            address to = handler.actors((i + 1) % 4);
            uint256 amount = handler.modelBalance(from);
            uint256 recipientBefore = handler.modelBalance(to);

            vm.prank(from);
            assertTrue(token.transfer(to, amount));
            assertEq(token.balanceOf(from), 0);
            assertEq(token.balanceOf(to), recipientBefore + amount);

            vm.prank(to);
            assertTrue(token.transfer(from, amount));
            assertEq(token.balanceOf(from), amount);
            assertEq(token.balanceOf(to), recipientBefore);
        }
        invariant_SupplyIsFixedAndTokensAreConserved();
        invariant_BalancesAndAllowancesMatchModel();
        invariant_MetadataRemainsUnchanged();
    }

    function test_SequenceSpendsNonzeroAmountsAndRecoversAfterRejections() public {
        handler.transferFullBalance(0, 1);
        handler.approve(1, 2, 9, false);
        handler.transferFrom(1, 2, 3, 4);
        assertEq(token.balanceOf(handler.actors(3)), 4);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 5);

        handler.rejectTransferAboveBalance(1, 1, type(uint256).max);
        invariant_BalancesAndAllowancesMatchModel();
        handler.rejectTransferFromAboveBalance(1, 2, 3, type(uint256).max - 1, false);
        invariant_BalancesAndAllowancesMatchModel();
        handler.rejectZeroRecipient(1, 2, 1, true);
        invariant_BalancesAndAllowancesMatchModel();
        handler.rejectZeroSpender(1, type(uint256).max);
        invariant_BalancesAndAllowancesMatchModel();
        handler.rejectTransferFromAboveAllowance(1, 2, 3, 0, 1);
        invariant_BalancesAndAllowancesMatchModel();
        handler.revoke(1, 2);

        handler.approve(1, 2, 1, false);
        handler.transferFrom(1, 2, 0, 1);
        assertEq(token.balanceOf(handler.actors(0)), 1);
        assertEq(token.balanceOf(handler.actors(1)), SUPPLY - 5);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 0);
        afterInvariant();
    }
}
