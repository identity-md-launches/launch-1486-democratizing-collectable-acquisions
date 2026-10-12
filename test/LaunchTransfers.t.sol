// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DCAToken} from "../src/DCAToken.sol";
import {TokenFactory} from "./helpers/TokenFactory.sol";

/// @dev Exercises the token leg of the launch. It does not simulate Uniswap pricing or swaps.
contract LaunchTransfersTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    TokenFactory internal factory;
    DCAToken internal token;
    address internal distributor;
    address internal poolAccount;
    address internal requester;
    address internal claimant;
    address internal trader;

    function setUp() public {
        distributor = makeAddr("test distributor");
        poolAccount = makeAddr("test pool account");
        requester = makeAddr("test requester");
        claimant = makeAddr("test claimant");
        trader = makeAddr("test trader");
        factory = new TokenFactory();
        token = factory.deploy(keccak256("test launch"));
    }

    function test_LaunchDistributionAndClaimsArriveWhole() public {
        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 pool = SUPPLY * 7_500 / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        assertTrue(factory.move(token, distributor, swarm));
        assertTrue(factory.move(token, poolAccount, pool));
        assertTrue(factory.move(token, requester, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolAccount), pool);
        assertEq(token.balanceOf(requester), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_PoolTransfersToAndFromOrdinaryTraderArriveWhole() public {
        uint256 pool = SUPPLY * 7_500 / 10_000;
        uint256 traded = 123 ether;
        assertTrue(factory.move(token, poolAccount, pool));

        vm.prank(poolAccount);
        assertTrue(token.transfer(trader, traded));
        assertEq(token.balanceOf(trader), traded);
        assertEq(token.balanceOf(poolAccount), pool - traded);

        vm.prank(trader);
        assertTrue(token.transfer(poolAccount, traded));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolAccount), pool);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
