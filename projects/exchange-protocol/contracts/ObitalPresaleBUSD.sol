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

    uint256 public constant TOKEN_PRICE = 3333 * 10**5;
    uint256 public constant HARD_CAP = 10000 ether;
    uint256 public constant SOFT_CAP = 5000 ether;
    uint256 public constant CONTRIBUTION_MIN = 1 ether;
    uint256 public constant CONTRIBUTION_MAX = 3000 ether;
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
        uint256 claimed_amount;
        uint256 first_claim_time;
        FunderStatus status;
    }

    mapping(address => ContributeData) public funders;
    uint256 public fundersCounter;
    uint256 public FIRST_CLAIM_PERCENT = 40;
    uint256 public PERIOD_CLAIM_PERCENT = 5;
    uint256 public CLAIM_PERIOD = 7 * 24 * 3600; // one week

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
        require(IERC20(BUSD).balanceOf(address(this)) <= HARD_CAP, "TokenSale: Hard cap was reached!");
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
        ContributeData storage funder = funders[_msgSender()];
        require(
            funder.amount > 0 &&
                funder.amount > funder.claimed_amount &&
                (funder.status == FunderStatus.Invested || funder.status == FunderStatus.Claimed),
            "Launchpad: You are not a funder!"
        );

        if (status == PresaleStatuses.Finished) {
            if (funder.status == FunderStatus.Invested) {
                // First claim - 40%
                uint256 amount = (FIRST_CLAIM_PERCENT * funder.amount * TOKEN_PRICE) / 100 / 1e18;
                funder.claimed_amount += amount;
                funder.first_claim_time = block.timestamp;
                funder.status = FunderStatus.Claimed;
                _safeTransfer(presaleToken, _msgSender(), amount);
                emit Claimed(_msgSender(), amount);
            } else if (funder.status == FunderStatus.Claimed) {
                // Can claim 5% every week
                require(
                    funder.first_claim_time + CLAIM_PERIOD > block.timestamp,
                    "Can claim after week of first claimed"
                );
                uint256 period_claim_count = (block.timestamp - funder.first_claim_time) / CLAIM_PERIOD;
                uint256 amount = (PERIOD_CLAIM_PERCENT * period_claim_count * funder.amount * TOKEN_PRICE) / 100 / 1e18;
                funder.claimed_amount += amount;

                _safeTransfer(presaleToken, _msgSender(), amount);
                emit Claimed(_msgSender(), amount);
            }
        } else if (status == PresaleStatuses.Canceled) {
            uint256 amount = funder.amount;
            funder.amount = 0;
            funder.status = FunderStatus.Refunded;
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
