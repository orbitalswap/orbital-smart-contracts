// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IOrbitalRouter02.sol";
import "./interfaces/IOrbitalFactory.sol";
import "./interfaces/IObitalPresale.sol";

contract PresaleFactory is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct FeeStruct {
        uint256 ethFee;
        uint256 tokenFee;
    }

    address public treasury;
    FeeStruct[] public gFees;
    uint256 public mintFee = 1 ether;
    uint256 public emergencyFee = 200;

    address public implementation;
    mapping(address => IObitalPresale.PresaleConfig) presales;

    event UpdateImplementation(address impl);
    event FeeAdded(uint256 id, uint256 ethFee, uint256 tokenFee);
    event FeeUpdated(uint256 id, uint256 ethFee, uint256 tokenFee);
    event SetMintFee(uint256 fee);

    event PresaleCreated(address presale, address owner, IObitalPresale.PresaleConfig config, uint256 emergencyFee, uint256 ethFee, uint256 tokenFee);

    constructor(address _implementation) {
        implementation = _implementation;
    }
    
    function createPresale(
        address _op, 
        address _uniRouter, 
        address _token,
        IObitalPresale.PresaleConfig memory _config,
        uint256 _feeType
    ) external payable returns (address presale) {
        require(msg.value >= mintFee, "not enough fee");
        require(gFees.length > _feeType, "Invalid fee type");
        payable(treasury).transfer(mintFee);
        
        uint256 tokenAmt = _config.hardcap * _config.price;
        uint256 feeAmt = tokenAmt * gFees[_feeType].tokenFee;
        tokenAmt = tokenAmt + tokenAmt * _config.liquidity_percent / 10000 + feeAmt;

        uint256 beforeAmt = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transferFrom(_msgSender(), address(this), tokenAmt);
        uint256 afterAmt = IERC20(_token).balanceOf(address(this));
        require(afterAmt - beforeAmt >= tokenAmt, "Fee is not excluded");

        bytes32 salt = keccak256(abi.encodePacked(_op, _token, _feeType, block.timestamp));
        presale = Clones.cloneDeterministic(implementation, salt);
        IObitalPresale(presale).initialize(
            _config, 
            _uniRouter, 
            _op, 
            treasury, 
            emergencyFee, 
            gFees[_feeType].ethFee, 
            gFees[_feeType].tokenFee
        );
        IERC20(_token).transfer(presale, tokenAmt);

        presales[presale] = _config;
        emit PresaleCreated(presale, _op, _config, emergencyFee, gFees[_feeType].ethFee, gFees[_feeType].tokenFee);
    }
    
    function setImplementation(address _implementation) external onlyOwner {
        require(_implementation != address(0x0), "invalid address");

        implementation = _implementation;
        emit UpdateImplementation(_implementation);
    }

    function addFee(uint256 _ethFee, uint256 _tokenFee) external onlyOwner {
        require(_ethFee < 1000, "ethFee is too high");
        require(_tokenFee < 1000, "tokenFee is too high");

        gFees.push();
        FeeStruct storage _fee = gFees[gFees.length - 1];
        _fee.ethFee = _ethFee;
        _fee.tokenFee = _tokenFee;

        emit FeeAdded(gFees.length - 1, _ethFee, _tokenFee);
    }

    function updateFee(uint256 id, uint256 _ethFee, uint256 _tokenFee) external onlyOwner {
        require(_ethFee < 1000, "ethFee is too high");
        require(_tokenFee < 1000, "tokenFee is too high");

        gFees.push();
        FeeStruct storage _fee = gFees[id];
        _fee.ethFee = _ethFee;
        _fee.tokenFee = _tokenFee;

        emit FeeUpdated(id, _ethFee, _tokenFee);
    }
    
    function setFee(uint256 _fee) external onlyOwner {
        mintFee = _fee;
        emit SetMintFee(_fee);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    receive() external payable {}
}