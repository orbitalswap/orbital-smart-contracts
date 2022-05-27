// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IOrbitalRouter02.sol";
import "./interfaces/IOrbitalFactory.sol";
import "./TokenTimelock.sol";

contract ObitalPresale is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    bool initialized = false;

    IERC20 public presaleToken;
    address public wBNB;
    address public pair;

    enum PresaleStatus { Started, Canceled, Finished }
    struct PresaleConfig {
        address token;
        uint256 price;
        uint256 listing_price;
        uint256 liquidity_percent;
        uint256 hardcap;
        uint256 softcap;
        uint256 min_contribution;
        uint256 max_contribution;
        uint256 startTime;
        uint256 endTime;
        uint256 liquidity_lockup_time;
    }
    PresaleConfig public presaleConfig;

    address public liquidityTimeLock;
    uint256 public totalSold;
    uint256 public tokenReminder;
    PresaleStatus public status;

    uint256 private totalPaid;

    enum FunderStatus { None, Invested, EmergencyWithdrawn, Refunded, Claimed }
    struct Funder {
        uint256 amount;
        uint256 claimed_amount;
        FunderStatus status;
    }

    mapping(address => Funder) public funders;
    uint256 public funderCounter;
    
    IOrbitalFactory private orbitalFactory;
    IOrbitalRouter02 public orbitalRouter;

    address public treasury;
    uint256 public ethFee = 0;
    uint256 public tokenFee = 0;
    uint256 public emergencyFee = 200;

    event Contribute(address funder, uint256 amount);
    event Claimed(address funder, uint256 amount);
    event Withdrawn(address funder, uint256 amount);
    event EmergencyWithdrawn(address funder, uint256 amount);

    event PresaleClosed();
    event LiquidityAdded(address token, uint256 amount);
    event TimeLockCreated(address lock, address token, uint256 amount, uint256 lockTime);

    constructor() { }

    function initialize(
        PresaleConfig memory _config,
        address _orbitalRouter, 
        address _owner,
        address _treasury,
        uint256 _emergencyFee,
        uint256 _ethFee, 
        uint256 _tokenFee
    ) external {
        require(!initialized, "already initialized");
        require(owner() == address(0x0) || _msgSender() == owner(), "not allowed");

        initialized = true;

        presaleToken = IERC20(_config.token);
        presaleConfig = _config;

        orbitalRouter = IOrbitalRouter02(_orbitalRouter);
        address orbitalFactoryAddress = orbitalRouter.factory();
        orbitalFactory = IOrbitalFactory(orbitalFactoryAddress);

        wBNB = orbitalRouter.WETH();        
        pair = orbitalFactory.getPair(address(presaleToken), wBNB);
        if(pair == address(0x0)) {
            pair = orbitalFactory.createPair(address(presaleToken), wBNB);
        }

        treasury = _treasury;
        emergencyFee = _emergencyFee;
        ethFee = _ethFee;
        tokenFee = _tokenFee;

        _transferOwnership(_owner);
    }

    function contribute() external payable nonReentrant {
        require(msg.value >= presaleConfig.min_contribution, "TokenSale: Contribution amount is too low!");
        require(msg.value <= presaleConfig.max_contribution, "TokenSale: Contribution amount is too high!");
        require(block.timestamp > presaleConfig.startTime, "TokenSale: Presale is not started yet!");
        require(block.timestamp < presaleConfig.endTime, "TokenSale: Presale is over!");
        require(address(this).balance <= presaleConfig.hardcap, "TokenSale: Hard cap was reached!");
        require(status == PresaleStatus.Started, "TokenSale: Presale is over!");

        Funder storage funder = funders[_msgSender()];
        require(
            funder.amount + msg.value <= presaleConfig.max_contribution,
            "TokenSale: Contribution amount is too high, you was reached contribution maximum!"
        );
        if(funder.amount == 0 && funder.status == FunderStatus.None) {
            funderCounter++;
        }

        funder.amount = funder.amount + msg.value;
        funder.status = FunderStatus.Invested;
        
        totalSold += msg.value * presaleConfig.price / 10 ** 18;
        emit Contribute(_msgSender(), msg.value);
    }

    function withdraw() external nonReentrant {
        require(status != PresaleStatus.Started, "TokenSale: Presale is not finished");

        if (_msgSender() == owner()){
            if (status == PresaleStatus.Finished) {
                _safeTransfer(presaleToken, owner(), tokenReminder);
                _safeTransferBNB(owner(), address(this).balance);
            } else if (status == PresaleStatus.Canceled) {
                _safeTransfer(presaleToken, owner(), presaleToken.balanceOf(address(this)));
            }
        } else {
            Funder storage funder = funders[_msgSender()];

            require(funder.amount > 0 && funder.status == FunderStatus.Invested, "TokenSale: You are not a funder!");
            if (status == PresaleStatus.Finished) {
                uint256 amount = funder.amount * presaleConfig.price / 10 ** 18;
                funder.claimed_amount = amount;
                funder.status = FunderStatus.Claimed;
                _safeTransfer(presaleToken, _msgSender(), amount);
                emit Claimed(_msgSender(), amount);
            } else if (status == PresaleStatus.Canceled) {
                uint256 amount = funder.amount;
                funder.amount = 0;
                funder.status = FunderStatus.Refunded;
                _safeTransferBNB(_msgSender(), amount);
                emit Withdrawn(_msgSender(), amount);
            }
        }
    }

    function emergencyWithdraw() external nonReentrant {
        require(status == PresaleStatus.Started, "TokenSale: Presale is over!");
        require(block.timestamp < presaleConfig.endTime, "TokenSale: Presale is over!");

        Funder storage funder = funders[_msgSender()];
        require(funder.amount > 0 && funder.status == FunderStatus.Invested, "TokenSale: You are not a funder!");
        
        uint256 amount = funder.amount;

        funder.amount = 0;
        funder.status = FunderStatus.EmergencyWithdrawn;

        totalSold = totalSold - funder.amount * presaleConfig.price / 10 ** 18;
        emit EmergencyWithdrawn(_msgSender(), amount);

        if(emergencyFee > 0) {
            uint256 fee = amount * emergencyFee / 10000;
            _safeTransferBNB(_msgSender(), fee);

            amount = amount - fee;
        }
        _safeTransferBNB(_msgSender(), amount);
    }

    function closePresale() external nonReentrant onlyOwner {
        require(status == PresaleStatus.Started, "TokenSale: already closed");
        _setPresaleStatus(PresaleStatus.Canceled);

        totalPaid = address(this).balance;
        if (address(this).balance >= presaleConfig.softcap) {
            _addLiquidityOnOrbital();
            _lockLPTokens();
            _setPresaleStatus(PresaleStatus.Finished);
        }

        emit PresaleClosed();
    }

    function totalRaised() external view returns (uint256) {
        if(totalPaid > 0) return totalPaid;
        return address(this).balance;
    }

    receive() external payable {
        _safeTransferBNB(treasury, msg.value);
    }
    
    function _addLiquidityOnOrbital() internal returns(uint256 amountA, uint256 amountB, uint256 liquidity) {
        uint256 amountTokenDesired = totalPaid * presaleConfig.listing_price * presaleConfig.liquidity_percent / 100 / 10 ** 18;
        presaleToken.approve(address(orbitalRouter), amountTokenDesired);
        tokenReminder = presaleToken.balanceOf(address(this)) - amountTokenDesired - totalSold;

        uint256 amountBNB = totalPaid * presaleConfig.liquidity_percent / 100;
        (amountA, amountB, liquidity) = orbitalRouter.addLiquidityETH{value: amountBNB}(
            address(presaleToken),
            amountTokenDesired,
            0,
            0,
            address(this),
            2**255
        );

        emit LiquidityAdded(pair, liquidity);

        _transferFee(totalPaid);
    }

    function _lockLPTokens() internal {
        IERC20 LPToken = IERC20(pair);
        TokenTimelock contractInstance = new TokenTimelock(
            LPToken,
            owner(),
            presaleConfig.liquidity_lockup_time + block.timestamp
        );
        liquidityTimeLock = address(contractInstance);

        uint256 amount = LPToken.balanceOf(address(this));
        _safeTransfer(LPToken, liquidityTimeLock, amount);

        emit TimeLockCreated(liquidityTimeLock, pair, amount, presaleConfig.liquidity_lockup_time);
    }

    function _setPresaleStatus(PresaleStatus _status) internal {
        status = _status;
    }

    function _transferFee(uint256 _amount) internal {
        _safeTransferBNB(treasury, _amount * ethFee / 10000);
        _safeTransfer(presaleToken, treasury, _amount * presaleConfig.price * tokenFee / 10000);
    }

    function _safeTransferBNB(address _to, uint256 _value) internal {
        (bool success,) = _to.call{value:_value}(new bytes(0));
        require(success, 'TransferHelper: BNB_TRANSFER_FAILED');
    }

    function _safeTransfer(IERC20 _token, address _to, uint256 _amount) internal {
        _token.safeTransfer(_to, _amount);
    }
}