// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ObitalPresaleBUSD is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public presaleToken;
    // ERC20 public BUSD = IERC20(0xe9e7cea3dedca5984780bafc599bd69add087d56); // BSC Mainnet
    address public BUSD = 0x37be299867CBE501140d95D4FD5d1a4c55969b7B; // BSC Testnet

    enum PresaleStatuses {
        Started,
        Canceled,
        Finished
    }

    uint256 public constant TOKEN_PRICE = 25 * 10**16;
    uint256 public constant HARD_CAP = 100000 ether;
    uint256 public constant SOFT_CAP = 2000 ether;
    uint256 public constant CONTRIBUTION_MIN = 100 ether;
    uint256 public constant CONTRIBUTION_MAX = 50000 ether;
    uint256 public immutable startTime;
    uint256 public immutable endTime;

    uint256 public totalSold;

    PresaleStatuses public status;

    uint256 private totalPaid;

    enum FunderStatus {
        None,
        Invested,
        EmergencyWithdrawn,
        Refunded,
        Claimed
    }

    struct ContributeData {
        uint256 amount;
        uint256 totalClaimAmount;
        uint256 claimedAmount;
        uint256 claimedTime;
        FunderStatus status;
    }

    mapping(address => ContributeData) public funders;
    uint256 public fundersCounter;
    uint256 public FIRST_CLAIM_PERCENT = 40;
    uint256 public PERIOD_CLAIM_PERCENT = 5;
    uint256 public CLAIM_PERIOD = 300; // one week

    uint256 public emergencyFee = 200;

    event Contribute(address funder, uint256 amount);
    event Claimed(address funder, uint256 amount);
    event Withdrawn(address funder, uint256 amount);
    event EmergencyWithdrawn(address funder, uint256 amount);
    event PresaleClosed();

    constructor(
        uint256 _startTime,
        uint256 _endTime,
        IERC20 _presaleToken
    ) {
        startTime = _startTime;
        endTime = _endTime;
        presaleToken = _presaleToken;
    }

    function contribute(uint256 _amount) public nonReentrant {
        require(IERC20(BUSD).balanceOf(_msgSender()) >= _amount, "TokenSale: Don't have enough token balance");
        require(_amount >= CONTRIBUTION_MIN, "TokenSale: Contribution amount is too low!");
        require(_amount <= CONTRIBUTION_MAX, "TokenSale: Contribution amount is too high!");
        require(block.timestamp > startTime, "TokenSale: Presale is not started yet!");
        require(block.timestamp < endTime, "TokenSale: Presale is over!");
        require(IERC20(BUSD).balanceOf(address(this)) + _amount <= HARD_CAP, "TokenSale: Hard cap was reached!");
        require(status != PresaleStatuses.Finished, "TokenSale: Presale is over!");
        require(
            funders[_msgSender()].amount + _amount <= CONTRIBUTION_MAX,
            "TokenSale: Contribution amount is too high, you was reached contribution maximum!"
        );

        ContributeData storage funder = funders[_msgSender()];

        if (funder.amount == 0 && funder.status == FunderStatus.None) {
            fundersCounter += 1;
        }

        funder.amount += _amount;
        funder.totalClaimAmount += (_amount * TOKEN_PRICE) / 1e18;
        funder.status = FunderStatus.Invested;

        totalSold += (_amount * TOKEN_PRICE) / 10**18;
        IERC20(BUSD).safeTransferFrom(_msgSender(), address(this), _amount);
        emit Contribute(_msgSender(), _amount);
    }

    function withdraw() external nonReentrant {
        require(status != PresaleStatuses.Started, "Launchpad: Presale is not finished");

        // if (_msgSender() == owner()) {
        //     if (status == PresaleStatuses.Finished) {
        //         _safeTransferBUSD(owner(), IERC20(BUSD).balanceOf(address(this)));
        //     } else if (status == PresaleStatuses.Canceled) {
        //         _safeTransfer(presaleToken, owner(), presaleToken.balanceOf(address(this)));
        //     }
        // } else {

        require(funders[_msgSender()].amount > 0, "Launchpad: You are not a funder!");

        require(
            funders[_msgSender()].totalClaimAmount > funders[_msgSender()].claimedAmount &&
                (funders[_msgSender()].status == FunderStatus.Invested ||
                    funders[_msgSender()].status == FunderStatus.Claimed),
            "You already claimed total amount"
        );

        if (status == PresaleStatuses.Finished) {
            uint256 totalWithdrawableAmount = (funders[_msgSender()].amount * TOKEN_PRICE) / 1e18;
            if (funders[_msgSender()].status == FunderStatus.Invested) {
                // First claim - 40%
                uint256 amount = (FIRST_CLAIM_PERCENT * totalWithdrawableAmount) / 100;
                funders[_msgSender()].claimedAmount += amount;
                funders[_msgSender()].claimedTime = block.timestamp;
                funders[_msgSender()].status = FunderStatus.Claimed;
                _safeTransfer(presaleToken, _msgSender(), amount);
                emit Claimed(_msgSender(), amount);
            } else if (funders[_msgSender()].status == FunderStatus.Claimed) {
                // Can claim 5% every week
                require(totalWithdrawableAmount > funders[_msgSender()].claimedAmount, "Already claimed all");
                require(
                    funders[_msgSender()].claimedTime + CLAIM_PERIOD < block.timestamp,
                    "Can claim after week of first claimed"
                );
                uint256 periodClaimPercent = (block.timestamp - funders[_msgSender()].claimedTime) / CLAIM_PERIOD;
                if (periodClaimPercent > 100 - FIRST_CLAIM_PERCENT) periodClaimPercent = 100 - FIRST_CLAIM_PERCENT;
                uint256 amount = (PERIOD_CLAIM_PERCENT * periodClaimPercent * totalWithdrawableAmount) / 100;
                if (funders[_msgSender()].claimedAmount + amount > totalWithdrawableAmount)
                    amount = totalWithdrawableAmount - funders[_msgSender()].claimedAmount;
                funders[_msgSender()].claimedAmount += amount;
                funders[_msgSender()].claimedTime = block.timestamp;
                _safeTransfer(presaleToken, _msgSender(), amount);
                emit Claimed(_msgSender(), amount);
            }
        } else if (status == PresaleStatuses.Canceled) {
            uint256 amount = funders[_msgSender()].amount;
            funders[_msgSender()].amount = 0;
            funders[_msgSender()].status = FunderStatus.Refunded;
            _safeTransferBUSD(_msgSender(), amount);
            emit Withdrawn(_msgSender(), amount);
        }
        // }
    }

    function emergencyWithdraw() external nonReentrant {
        require(status == PresaleStatuses.Started, "TokenSale: Presale is over!");
        require(block.timestamp < endTime, "TokenSale: Presale is over!");

        ContributeData storage funder = funders[_msgSender()];
        require(
            funder.amount > 0 && (funder.status == FunderStatus.Invested || funder.status == FunderStatus.Claimed),
            "TokenSale: You are not a funder!"
        );

        uint256 amount = funder.amount;

        funder.amount = 0;
        funder.status = FunderStatus.EmergencyWithdrawn;

        totalSold = totalSold - (funder.amount * TOKEN_PRICE) / 1e18;

        if (emergencyFee > 0) {
            uint256 fee = (amount * emergencyFee) / 10000;
            _safeTransferBUSD(_msgSender(), fee);

            amount = amount - fee;
        }
        _safeTransferBUSD(_msgSender(), amount);
        emit EmergencyWithdrawn(_msgSender(), amount);
    }

    function closePresale() external nonReentrant onlyOwner {
        require(status == PresaleStatuses.Started, "TokenSale: already closed");
        _setPresaleStatus(PresaleStatuses.Canceled);

        totalPaid = IERC20(BUSD).balanceOf(address(this));

        if (totalPaid >= SOFT_CAP) {
            _setPresaleStatus(PresaleStatuses.Finished);
        }
        emit PresaleClosed();
    }

    function totalRaised() external view returns (uint256) {
        if (totalPaid > 0) return totalPaid;
        return IERC20(BUSD).balanceOf(address(this));
    }

    receive() external payable {}

    function _setPresaleStatus(PresaleStatuses _status) internal {
        status = _status;
    }

    function _safeTransferBUSD(address _to, uint256 _value) internal {
        require(_value > 0);
        IERC20(BUSD).safeTransfer(_to, _value);
    }

    function _safeTransfer(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) private {
        _token.safeTransfer(_to, _amount);
    }

    function adminWithdraw(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        _token.safeTransfer(_to, _amount);
    }
}
