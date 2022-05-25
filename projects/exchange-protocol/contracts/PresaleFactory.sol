// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IOrbitalRouter02.sol";
import "./interfaces/IOrbitalFactory.sol";
import "./TokenTimelock.sol";

contract PresaleFactory is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    enum PresaleStatuses { Started, Canceled, Finished }

    uint constant public TOKEN_PRICE = 5454 * 10 ** 5;
    uint constant public TOKEN_LISTING_PRICE = 5000 * 10 ** 5;
    uint constant public LIQUIDITY_PERCENT = 51;
    uint constant public HARD_CAP = 4 ether;
    uint constant public SOFT_CAP = 2 ether;
    uint constant public CONTRIBUTION_MIN = 0.01 ether;
    uint constant public CONTRIBUTION_MAX = 1 ether;
    
    address public wBNB;
    address public LPTokenTimeLock;
    uint public fundersCounter;
    uint public totalSold;
    uint public tokenReminder;
    uint immutable public startTime;
    uint immutable public endTime;
    uint immutable public LPTokenLockUpTime;
    PresaleStatuses public status;

    mapping (address => uint) public funders;

    IOrbitalRouter02 public orbitalRouter;
    IOrbitalFactory private orbitalFactory;
    IERC20 public presaleToken;

    event Contribute(address funder, uint amount);

    constructor(
        uint _startTime,
        uint _endTime,
        uint _LPTokenLockUpTime,
        IERC20 _presaleToken,
        address _orbitalRouter,
        address _wBNB
    )
    {
        startTime = _startTime;
        endTime = _endTime;
        LPTokenLockUpTime = _LPTokenLockUpTime;
        presaleToken = _presaleToken;
        orbitalRouter = IOrbitalRouter02(_orbitalRouter);
        address orbitalFactoryAddress = orbitalRouter.factory();
        orbitalFactory = IOrbitalFactory(orbitalFactoryAddress);
        wBNB = _wBNB;
    }

    function contribute() public payable nonReentrant
    {
        require(msg.value >= CONTRIBUTION_MIN, "TokenSale: Contribution amount is too low!");
        require(msg.value < CONTRIBUTION_MAX, "TokenSale: Contribution amount is too high!");
        require(block.timestamp > startTime, "TokenSale: Presale is not started yet!");
        require(block.timestamp < endTime, "TokenSale: Presale is over!");
        require(address(this).balance <= HARD_CAP, "TokenSale: Hard cap was reached!");
        require(
            status != PresaleStatuses.Finished &&
            status != PresaleStatuses.Canceled,
            "TokenSale: Presale is over!"
        );

        if (funders[_msgSender()] == 0) {
            fundersCounter += 1;
        }
        require(
            funders[_msgSender()] + msg.value <= CONTRIBUTION_MAX,
            "TokenSale: Contribution amount is too high, you was reached contribution maximum!"
        );
        funders[_msgSender()] += msg.value;
        
        totalSold += msg.value * TOKEN_PRICE / 10 ** 18;
        emit Contribute(_msgSender(), msg.value);
    }

    function closePresale() public nonReentrant onlyOwner
    {
        require(status == PresaleStatuses.Started, "TokenSale: already closed");
        _setPresaleStatus(PresaleStatuses.Canceled);

        if (address(this).balance >= SOFT_CAP) {
            _addLiquidityOnOrbital();
            _lockLPTokens();
            _setPresaleStatus(PresaleStatuses.Finished);
        }
    }

    function withdraw() public payable nonReentrant
    {
        require(status != PresaleStatuses.Started, "Launchpad: Presale is not finished");

        if (_msgSender() == owner()){
            if (status == PresaleStatuses.Finished) {
                _safeTransfer(presaleToken, owner(), tokenReminder);
                _safeTransferBNB(owner(), address(this).balance);
            } else if (status == PresaleStatuses.Canceled) {
                _safeTransfer(presaleToken, owner(), presaleToken.balanceOf(address(this)));
            }
        } else {
            require(funders[_msgSender()] != 0, "Launchpad: You are not a funder!");
            if (status == PresaleStatuses.Finished) {
                uint amount = funders[_msgSender()] * TOKEN_PRICE / 10 ** 18;
                funders[_msgSender()] = 0;
                _safeTransfer(presaleToken, _msgSender(), amount);
            } else if (status == PresaleStatuses.Canceled) {
                uint amount = funders[_msgSender()];
                funders[_msgSender()] = 0;
                _safeTransferBNB(_msgSender(), amount);
            }
        }
    }

    receive() external payable {
        _safeTransferBNB(owner(), msg.value);
    }
    
    function _addLiquidityOnOrbital() private returns(uint amountA, uint amountB, uint liquidity)
    {
        uint amountTokenDesired = address(this).balance * TOKEN_LISTING_PRICE * LIQUIDITY_PERCENT / 100 / 10 ** 18;
        presaleToken.approve(address(orbitalRouter), amountTokenDesired);
        tokenReminder = presaleToken.balanceOf(address(this)) - amountTokenDesired - totalSold;

        uint amountBNB = address(this).balance * LIQUIDITY_PERCENT / 100;

        (amountA, amountB, liquidity) = orbitalRouter.addLiquidityETH{value: amountBNB}(
            address(presaleToken),
            amountTokenDesired,
            0,
            0,
            address(this),
            2**255
        );
    }

    function _lockLPTokens() private
    {
        address pair = orbitalFactory.getPair(address(presaleToken), wBNB);
        IERC20 LPToken = IERC20(pair);
        TokenTimelock contractInstance = new TokenTimelock(
            LPToken,
            owner(),
            LPTokenLockUpTime
        );

        LPTokenTimeLock = address(contractInstance);

        _safeTransfer(
            LPToken,
            LPTokenTimeLock,
            LPToken.balanceOf(address(this))
        );
    }

    function _setPresaleStatus(PresaleStatuses _status) private
    {
        status = _status;
    }

    function _safeTransferBNB(address _to, uint _value) internal {
        (bool success,) = _to.call{value:_value}(new bytes(0));
        require(success, 'TransferHelper: BNB_TRANSFER_FAILED');
    }

    function _safeTransfer(IERC20 _token, address _to, uint _amount) private
    {
        _token.safeTransfer(_to, _amount);
    }
}