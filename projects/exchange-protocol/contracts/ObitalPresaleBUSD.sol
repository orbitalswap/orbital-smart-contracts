// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// import "./interfaces/IOrbitalRouter02.sol";
// import "./interfaces/IOrbitalFactory.sol";
import "./TokenTimelock.sol";

contract ObitalPresaleBUSD is ReentrancyGuard, Ownable {
    using SafeERC20 for ERC20;

    bool initialized = false;

    address public presaleToken;
    // ERC20 public BUSD = ERC20(0xe9e7cea3dedca5984780bafc599bd69add087d56); // BSC Mainnet
    address public BUSD = 0x37be299867CBE501140d95D4FD5d1a4c55969b7B; // BSC Testnet

    // address public wBNB;
    // address public pair;

    enum PresaleStatus {
        Started,
        Canceled,
        Finished
    }
    struct PresaleConfig {
        address token;
        uint256 price;
        // uint256 listing_price;
        // uint256 liquidity_percent;
        uint256 hardcap;
        uint256 softcap;
        uint256 min_contribution;
        uint256 max_contribution;
        uint256 startTime;
        uint256 endTime;
        // uint256 liquidity_lockup_time;
    }
    PresaleConfig public presaleConfig;

    address public liquidityTimeLock;
    uint256 public totalSold;
    // uint256 public tokenReminder;
    PresaleStatus public status;

    uint256 private totalPaid;

    enum FunderStatus {
        None,
        Invested,
        EmergencyWithdrawn,
        Refunded,
        Claimed
    }
    struct Funder {
        uint256 amount; // BUSD contribute balance
        uint256 claimed_amount; // Presale token claim Balance
        uint256 first_claim_time;
        FunderStatus status;
    }

    mapping(address => Funder) public funders;
    uint256 public funderCounter;
    uint256 FIRST_CLAIM_PERCENT = 40;
    uint256 PERIOD_CLAIM_PERCENT = 5;
    uint256 CLAIM_PERIOD = 7 * 24 * 3600; // one week

    // IOrbitalFactory private orbitalFactory;
    // IOrbitalRouter02 public orbitalRouter;

    // address public treasury;
    // uint256 public ethFee = 0;
    // uint256 public tokenFee = 0;
    uint256 public emergencyFee = 200;

    event Contribute(address funder, uint256 amount);
    event Claimed(address funder, uint256 amount);
    event Withdrawn(address funder, uint256 amount);
    event EmergencyWithdrawn(address funder, uint256 amount);

    event PresaleClosed();

    // event LiquidityAdded(address token, uint256 amount);
    // event TimeLockCreated(address lock, address token, uint256 amount, uint256 lockTime);

    constructor() {}

    function initialize(
        PresaleConfig memory _config,
        // address _orbitalRouter,
        address _owner,
        // address _treasury,
        // uint256 _ethFee,
        // uint256 _tokenFee
        uint256 _emergencyFee
    ) external {
        require(!initialized, "already initialized");
        require(owner() == address(0x0) || _msgSender() == owner(), "not allowed");

        initialized = true;

        presaleToken = _config.token;
        presaleConfig = _config;

        // orbitalRouter = IOrbitalRouter02(_orbitalRouter);
        // address orbitalFactoryAddress = orbitalRouter.factory();
        // orbitalFactory = IOrbitalFactory(orbitalFactoryAddress);

        // wBNB = orbitalRouter.WETH();
        // pair = orbitalFactory.getPair(address(presaleToken), wBNB);
        // if (pair == address(0x0)) {
        //     pair = orbitalFactory.createPair(address(presaleToken), wBNB);
        // }

        // treasury = _treasury;
        emergencyFee = _emergencyFee;
        // ethFee = _ethFee;
        // tokenFee = _tokenFee;

        _transferOwnership(_owner);
    }

    function contribute(uint256 _amount) external nonReentrant {
        require(IERC20(BUSD).balanceOf(_msgSender()) >= _amount, "TokenSale: Don't have enough token balance");
        require(_amount >= presaleConfig.min_contribution, "TokenSale: Contribution amount is too low!");
        require(_amount <= presaleConfig.max_contribution, "TokenSale: Contribution amount is too high!");
        require(block.timestamp > presaleConfig.startTime, "TokenSale: Presale is not started yet!");
        require(block.timestamp < presaleConfig.endTime, "TokenSale: Presale is over!");
        require(IERC20(BUSD).balanceOf(address(this)) <= presaleConfig.hardcap, "TokenSale: Hard cap was reached!");
        require(status == PresaleStatus.Started, "TokenSale: Presale is over!");

        Funder storage funder = funders[_msgSender()];
        require(
            funder.amount + _amount <= presaleConfig.max_contribution,
            "TokenSale: Contribution amount is too high, you was reached contribution maximum!"
        );

        ERC20(BUSD).safeTransferFrom(_msgSender(), address(this), _amount);

        if (funder.amount == 0 && funder.status == FunderStatus.None) {
            funderCounter++;
        }

        funder.amount = funder.amount + _amount;
        funder.status = FunderStatus.Invested;

        totalSold += (_amount * presaleConfig.price) / 1e18;
        emit Contribute(_msgSender(), _amount);
    }

    function withdraw() external nonReentrant {
        require(status != PresaleStatus.Started, "TokenSale: Presale is not finished");

        if (_msgSender() == owner()) {
            if (status == PresaleStatus.Finished) {
                // _safeTransfer(presaleToken, owner(), tokenReminder);
                _safeTransferBUSD(owner(), IERC20(BUSD).balanceOf(address(this)));
            } else if (status == PresaleStatus.Canceled) {
                _safeTransfer(presaleToken, owner(), IERC20(presaleToken).balanceOf(address(this)));
            }
        } else {
            Funder storage funder = funders[_msgSender()];

            require(
                funder.amount > 0 && (funder.status == FunderStatus.Invested || funder.status == FunderStatus.Invested),
                "TokenSale: You are not a funder!"
            );
            if (status == PresaleStatus.Finished) {
                if (funder.status == FunderStatus.Invested) {
                    // First claim - 40%
                    uint256 amount = (FIRST_CLAIM_PERCENT * funder.amount * presaleConfig.price) / 100 / 1e18;
                    funder.claimed_amount = amount;
                    funder.first_claim_time = block.timestamp;
                    funder.status = FunderStatus.Claimed;
                    _safeTransfer(presaleToken, _msgSender(), amount);
                    emit Claimed(_msgSender(), amount);
                } else if (funder.status == FunderStatus.Claimed) {
                    // Can claim 5% every week
                    require(
                        funder.first_claim_time + CLAIM_PERIOD > block.timestamp,
                        "Can claim after week first claimed"
                    );
                    uint256 period_claim_count = (block.timestamp - funder.first_claim_time) / CLAIM_PERIOD;
                    uint256 amount = (PERIOD_CLAIM_PERCENT * period_claim_count * funder.amount * presaleConfig.price) /
                        100 /
                        1e18;
                    funder.claimed_amount = amount;

                    funder.status = FunderStatus.Claimed;
                    _safeTransfer(presaleToken, _msgSender(), amount);
                    emit Claimed(_msgSender(), amount);
                }
            } else if (status == PresaleStatus.Canceled) {
                uint256 amount = funder.amount;
                funder.amount = 0;
                funder.status = FunderStatus.Refunded;
                _safeTransferBUSD(_msgSender(), amount);
                emit Withdrawn(_msgSender(), amount);
            }
        }
    }

    function emergencyWithdraw() external nonReentrant {
        require(status == PresaleStatus.Started, "TokenSale: Presale is over!");
        require(block.timestamp < presaleConfig.endTime, "TokenSale: Presale is over!");

        Funder storage funder = funders[_msgSender()];
        require(
            funder.amount > 0 && (funder.status == FunderStatus.Invested || funder.status == FunderStatus.Invested),
            "TokenSale: You are not a funder!"
        );

        uint256 amount = funder.amount;

        funder.amount = 0;
        funder.status = FunderStatus.EmergencyWithdrawn;

        totalSold = totalSold - (funder.amount * presaleConfig.price) / 1e18;
        emit EmergencyWithdrawn(_msgSender(), amount);

        if (emergencyFee > 0) {
            uint256 fee = (amount * emergencyFee) / 10000;
            _safeTransferBUSD(_msgSender(), fee);

            amount = amount - fee;
        }
        _safeTransferBUSD(_msgSender(), amount);
    }

    function closePresale() external nonReentrant onlyOwner {
        require(status == PresaleStatus.Started, "TokenSale: already closed");
        _setPresaleStatus(PresaleStatus.Canceled);

        totalPaid = IERC20(BUSD).balanceOf(address(this));
        if (totalPaid >= presaleConfig.softcap) {
            //     _addLiquidityOnOrbital();
            //     _lockLPTokens();
            _setPresaleStatus(PresaleStatus.Finished);
        }

        emit PresaleClosed();
    }

    function totalRaised() external view returns (uint256) {
        if (totalPaid > 0) return totalPaid;
        return IERC20(BUSD).balanceOf(address(this));
    }

    // receive() external payable {
    //     _safeTransferBUSD(treasury, msg.value);
    // }

    // function _addLiquidityOnOrbital()
    //     internal
    //     returns (
    //         uint256 amountA,
    //         uint256 amountB,
    //         uint256 liquidity
    //     )
    // {
    //     uint256 amountTokenDesired = (totalPaid * presaleConfig.listing_price * presaleConfig.liquidity_percent) /
    //         100 /
    //         1e18;
    //     presaleToken.approve(address(orbitalRouter), amountTokenDesired);
    //     tokenReminder = presaleToken.balanceOf(address(this)) - amountTokenDesired - totalSold;

    //     uint256 amountBNB = (totalPaid * presaleConfig.liquidity_percent) / 100;
    //     (amountA, amountB, liquidity) = orbitalRouter.addLiquidityETH{value: amountBNB}(
    //         address(presaleToken),
    //         amountTokenDesired,
    //         0,
    //         0,
    //         address(this),
    //         2**255
    //     );

    //     emit LiquidityAdded(pair, liquidity);

    //     _transferFee(totalPaid);
    // }

    // function _lockLPTokens() internal {
    //     ERC20 LPToken = ERC20(pair);
    //     TokenTimelock contractInstance = new TokenTimelock(
    //         LPToken,
    //         owner(),
    //         presaleConfig.liquidity_lockup_time + block.timestamp
    //     );
    //     liquidityTimeLock = address(contractInstance);

    //     uint256 amount = LPToken.balanceOf(address(this));
    //     _safeTransfer(LPToken, liquidityTimeLock, amount);

    //     emit TimeLockCreated(liquidityTimeLock, pair, amount, presaleConfig.liquidity_lockup_time);
    // }

    function _setPresaleStatus(PresaleStatus _status) internal {
        status = _status;
    }

    // function _transferFee(uint256 _amount) internal {
    //     _safeTransferBUSD(treasury, (_amount * ethFee) / 10000);
    //     _safeTransfer(presaleToken, treasury, (_amount * presaleConfig.price * tokenFee) / 10000);
    // }

    function _safeTransferBUSD(address _to, uint256 _value) internal {
        require(_value > 0);
        ERC20(BUSD).safeTransfer(_to, _value);
        // (bool success, ) = _to.call{value: _value}(new bytes(0));
        // require(success, "TransferHelper: BNB_TRANSFER_FAILED");
    }

    function _safeTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        ERC20(_token).safeTransfer(_to, _amount);
    }

    function adminWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        ERC20(_token).safeTransfer(_to, _amount);
    }
}