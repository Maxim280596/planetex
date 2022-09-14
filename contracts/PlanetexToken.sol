// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title A PlanetexToken, symbol TPTX
contract PlanetexToken is ERC20, Ownable {
    constructor(uint256 totalSupply) ERC20("PlanetexToken", "TPTX") {
        _mint(owner(), totalSupply);
    }
}
