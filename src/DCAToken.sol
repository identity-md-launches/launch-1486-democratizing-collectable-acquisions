// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Democratizing Collectable Acquisions
/// @notice Fixed-supply, 18-decimal ERC-20. The deploying account receives the entire supply.
/// @dev When deployed by the launch factory, the factory is msg.sender and receives the tokens.
/// There are no external mint, burn, administrative, or upgrade entry points.
contract DCAToken is ERC20 {
    /// @notice One billion DCA expressed in the token's smallest unit (10^18 units per DCA).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Democratizing Collectable Acquisions", "DCA") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
