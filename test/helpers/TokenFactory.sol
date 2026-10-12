// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DCAToken} from "../../src/DCAToken.sol";

/// @dev Test-only factory; models the constructor caller and later token distributions.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (DCAToken) {
        return new DCAToken{salt: salt}();
    }

    function move(DCAToken token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}
