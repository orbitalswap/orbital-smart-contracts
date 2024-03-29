// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "bsc-library/contracts/BEP20.sol";

// OrbitalToken with Governance.
contract OrbitalToken is BEP20("OrbitalSwap Token", "ORB") {
    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
