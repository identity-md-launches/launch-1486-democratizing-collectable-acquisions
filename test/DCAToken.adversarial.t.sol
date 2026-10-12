// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {DCAToken} from "src/DCAToken.sol";

/// @dev A real intermediate caller to distinguish msg.sender authorization from tx.origin.
contract DCASpendingRelay {
    function spend(DCAToken token, address owner, address recipient, uint256 amount) external returns (bool) {
        return token.transferFrom(owner, recipient, amount);
    }
}

/// @dev Complements the original suite with integer boundaries, repeated operations and rollback properties.
/// forge-config: default.fuzz.runs = 1000
contract DCATokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 internal constant MAX = type(uint256).max;

    DCAToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new DCAToken();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_OneWeiCanMoveDirectlyAndByAllowance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);

        vm.prank(bob);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferCannotWrapBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, MAX)
        );
        token.transfer(alice, MAX);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferFromCannotSpendBeyondSupplyWithUnlimitedApproval() public {
        assertTrue(token.approve(spender, MAX));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, MAX)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, MAX);

        assertEq(token.allowance(address(this), spender), MAX);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceIsConsumedAndFailedSpendDoesNotConsumeIt() public {
        assertTrue(token.approve(spender, MAX - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 1));
        assertEq(token.allowance(address(this), spender), MAX - 2);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        uint256 remaining = MAX - 2 - SUPPLY;
        assertEq(token.allowance(address(this), spender), remaining);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), remaining);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalBeforeFundingSurvivesFailureButCannotBeReusedAfterExhaustion() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 7));
        vm.prank(spender);
        token.transferFrom(alice, bob, 7);
        assertEq(token.allowance(alice, spender), 7);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.transfer(alice, 7));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 7));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 7);

        assertTrue(token.transfer(alice, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 7);
        assertEq(token.balanceOf(bob), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY - 14);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SpenderCannotDelegateTheOwnersAllowanceToAnotherSpender() public {
        assertTrue(token.transfer(alice, 5));
        vm.prank(alice);
        assertTrue(token.approve(spender, 5));
        vm.prank(spender);
        assertTrue(token.approve(bob, MAX));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 5));
        vm.prank(bob);
        token.transferFrom(alice, bob, 5);
        assertEq(token.allowance(alice, spender), 5);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.allowance(spender, bob), MAX);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_TransferFromByOwnerStillRequiresSelfApproval() public {
        assertTrue(token.transfer(alice, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.balanceOf(alice), 9);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_ZeroDelegatedTransfersPreserveFiniteAndInfiniteAllowances() public {
        uint256[4] memory approvals = [uint256(0), 1, MAX - 1, MAX];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(alice);
            assertTrue(token.approve(spender, approvals[i]));

            vm.expectEmit(true, true, false, true, address(token));
            emit Transfer(alice, bob, 0);
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, bob, 0));
            vm.expectEmit(true, true, false, true, address(token));
            emit Transfer(alice, alice, 0);
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, alice, 0));

            assertEq(token.allowance(alice, spender), approvals[i]);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_ZeroSpenderIsRejectedForZeroAndMaximumApprovals() public {
        uint256[3] memory approvals = [uint256(0), 1, MAX];
        for (uint256 i; i < approvals.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), approvals[i]);
            assertEq(token.allowance(address(this), address(0)), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_ZeroRecipientRestoresLargestFiniteAndInfiniteApprovals() public {
        uint256[2] memory approvals = [MAX - 1, MAX];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 1);
            assertEq(token.allowance(address(this), spender), approvals[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_TransferFromAuthorizesImmediateCallerInsteadOfTransactionOrigin() public {
        DCASpendingRelay relay = new DCASpendingRelay();
        assertTrue(token.approve(spender, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(relay), 0, 1));
        vm.prank(spender, spender);
        relay.spend(token, address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.allowance(address(this), address(relay)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);

        assertTrue(token.approve(address(relay), 1));
        vm.prank(spender, spender);
        assertTrue(relay.spend(token, address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.allowance(address(this), address(relay)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RoundTripRestoresBalancesWithoutChangingApprovals(
        uint256 aliceBalance,
        uint256 bobBalance,
        uint256 amount,
        uint256 approved
    ) public {
        aliceBalance = bound(aliceBalance, 0, SUPPLY);
        bobBalance = bound(bobBalance, 0, SUPPLY - aliceBalance);
        amount = bound(amount, 0, aliceBalance);
        assertTrue(token.transfer(alice, aliceBalance));
        assertTrue(token.transfer(bob, bobBalance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), aliceBalance - amount);
        assertEq(token.balanceOf(bob), bobBalance + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));

        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedSpendsMatchOneSpend(uint256 amount, uint256 first, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        uint256 approved = unlimited ? MAX : amount;
        DCAToken singleSpend = new DCAToken();
        assertTrue(token.approve(spender, approved));
        assertTrue(singleSpend.approve(spender, approved));

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.balanceOf(alice), first);
        assertEq(token.allowance(address(this), spender), unlimited ? MAX : amount - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount - first));
        vm.prank(spender);
        assertTrue(singleSpend.transferFrom(address(this), alice, amount));

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(alice), singleSpend.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(address(this)), singleSpend.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), unlimited ? MAX : 0);
        assertEq(token.allowance(address(this), spender), singleSpend.allowance(address(this), spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleSpend.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedDelegatedSpendPreservesEntireApproval(uint256 balance, uint256 requested, uint256 approved)
        public
    {
        balance = bound(balance, 0, SUPPLY);
        requested = bound(requested, balance + 1, MAX);
        approved = bound(approved, requested, MAX);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, requested)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReplacementAndRevocationAffectOnlyChosenSpender(
        uint256 previous,
        uint256 replacement,
        uint256 amount,
        uint256 otherApproval
    ) public {
        replacement = bound(replacement, 0, SUPPLY);
        amount = bound(amount, 0, replacement);
        assertTrue(token.approve(bob, otherApproval));
        assertTrue(token.approve(spender, previous));
        assertTrue(token.approve(spender, replacement));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), bob), otherApproval);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), replacement - amount);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);

        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), bob), otherApproval);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferConsumesAllowanceWithoutMovingFunds(
        uint256 amount,
        uint256 approved,
        bool unlimited
    ) public {
        amount = bound(amount, 0, SUPPLY);
        approved = unlimited ? MAX : bound(approved, amount, MAX - 1);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), amount));

        assertEq(token.allowance(address(this), spender), unlimited ? MAX : approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
