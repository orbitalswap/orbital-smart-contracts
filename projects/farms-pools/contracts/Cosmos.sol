// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "bsc-library/contracts/BEP20.sol";
import "./OrbitalToken.sol";

// Cosmos with Governance.
contract Cosmos is BEP20("Cosmos Token", "COSMOS") {
    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public onlyOwner {
        _burn(_from, _amount);
    }

    // The ORB TOKEN!
    OrbToken public orb;

    constructor(OrbToken _orb) public {
        orb = _orb;
    }

    // Safe orb transfer function, just in case if rounding error causes pool to not have enough ORBs.
    function safeOrbTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 orbBal = orb.balanceOf(address(this));
        if (_amount > orbBal) {
            orb.transfer(_to, orbBal);
        } else {
            orb.transfer(_to, _amount);
        }
    }
}
