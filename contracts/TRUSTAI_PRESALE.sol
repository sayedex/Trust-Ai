// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OApp, MessagingFee, Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TRUSTAI_PRESALE is OApp, ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public token;
    address public treasuryWallet;
    uint256 public PRESALE_START = 0;
    uint256 public PRESALE_ENDTIME = 0;
    uint256 public totalSold;
    uint256 public totalRaised;

    struct Presale {
        uint256 tokenPrice;
        uint256 tokensSold;
        uint256 initialReleasePercentage;
        address paytokenaddress;
        uint256 payTokendecimals;
        uint256 lockPeriod;
        uint256 monthlyReleasePercentage;
    }

    struct Purchase {
        uint256 amount;
        uint256 remainingAmount;
        uint256 lastClaimTimestamp;
    }

    mapping(uint256 => Presale) public presalePool;
    mapping(address => mapping(uint256 => mapping(uint256 => Purchase)))
        public purchases;
    mapping(address => mapping(uint256 => uint256)) public userNonces;

    event TokensPurchased(
        address indexed buyer,
        uint256 amount,
        uint256 initialReleaseAmount,
        uint256 presaleOptionId,
        uint256 nonce,
        uint256 lastClaimTimestamp,
        uint256 nextClaimTimestamp
    );
    event TokensClaimed(
        address indexed claimer,
        uint256 presaleOptionId,
        uint256 amount,
        uint256 nonce,
        uint256 lastClaimTimestamp,
        uint256 nextClaimTimestamp
    );

    constructor(
        address _endpoint,
        address _owner,
        uint256[] memory price,
        address _token,
        address _payToken
    ) OApp(_endpoint, _owner) Ownable(_owner) {
        initializePresaleOptions(price, _payToken, 6);
        token = _token;
        treasuryWallet = _owner;
        PRESALE_START = block.timestamp;
        PRESALE_ENDTIME = block.timestamp + 10 days;
    }

    modifier onlyDuringPresale() {
        require(
            block.timestamp >= PRESALE_START,
            "Presale has not started yet"
        );
        require(block.timestamp <= PRESALE_ENDTIME, "Presale has ended");
        _;
    }

    function initializePresaleOptions(
        uint256[] memory price,
        address _payToken,
        uint256 _payTokendecimals
    ) internal {
        presalePool[0] = Presale({
            tokenPrice: price[0],
            tokensSold: 0,
            initialReleasePercentage: 33,
            paytokenaddress: _payToken,
            payTokendecimals: _payTokendecimals,
            lockPeriod: 30 days,
            monthlyReleasePercentage: 33
        });
        presalePool[1] = Presale({
            tokenPrice: price[1],
            tokensSold: 0,
            initialReleasePercentage: 10,
            paytokenaddress: _payToken,
            payTokendecimals: _payTokendecimals,
            lockPeriod: 30 days,
            monthlyReleasePercentage: 10
        });

        presalePool[2] = Presale({
            tokenPrice: price[2],
            tokensSold: 0,
            initialReleasePercentage: 100,
            paytokenaddress: _payToken,
            payTokendecimals: _payTokendecimals,
            lockPeriod: 0,
            monthlyReleasePercentage: 0
        });
    }

    function buyTokens(uint256 _tokenAmount, uint256 _poolId)
        external
        nonReentrant
    {
        Presale memory presale = presalePool[_poolId];
        require(presale.tokenPrice > 0, "Invalid presale option");

        transferCurrency(
            presale.paytokenaddress,
            msg.sender,
            treasuryWallet,
            _tokenAmount
        );
        _processPayment(msg.sender, _poolId, _tokenAmount);
    }

    function _processPayment(
        address _buyer,
        uint256 _poolId,
        uint256 _tokenAmount
    ) internal onlyDuringPresale {
        Presale memory presale = presalePool[_poolId];
        uint256 userNonce = userNonces[_buyer][_poolId];

        uint256 amountTokens = (presale.tokenPrice * _tokenAmount) /
            10**presale.payTokendecimals;

        uint256 initialReleaseAmount = (amountTokens *
            presale.initialReleasePercentage) / 100;
        uint256 remainingAmount = amountTokens - initialReleaseAmount;

        if (remainingAmount > 0) {
            purchases[_buyer][_poolId][userNonce] = Purchase({
                amount: amountTokens,
                remainingAmount: remainingAmount,
                lastClaimTimestamp: block.timestamp
            });
            transferCurrency(
                token,
                treasuryWallet,
                address(this),
                amountTokens
            );
            transferCurrency(
                token,
                address(this),
                _buyer,
                initialReleaseAmount
            );
        } else {
            transferCurrency(token, treasuryWallet, _buyer, amountTokens);
        }

        totalSold += amountTokens;
        totalRaised += _tokenAmount;
        presale.tokensSold += amountTokens;
        emit TokensPurchased(
            _buyer,
            amountTokens,
            initialReleaseAmount,
            _poolId,
            userNonce,
            block.timestamp,
            block.timestamp + presale.lockPeriod
        );

        userNonces[_buyer][_poolId]++;
    }

    function claimTokens(uint256 presaleOptionId, uint256 nonce)
        external
        nonReentrant
    {
        Presale memory presale = presalePool[presaleOptionId];
        uint256 claimableAmount = getClaimableTokens(
            msg.sender,
            presaleOptionId,
            nonce
        );
        require(claimableAmount > 0, "No tokens to claim at this time");

        Purchase storage purchase = purchases[msg.sender][presaleOptionId][
            nonce
        ];
        purchase.remainingAmount -= claimableAmount;
        purchase.lastClaimTimestamp = block.timestamp;

        transferCurrency(token, address(this), msg.sender, claimableAmount);
        emit TokensClaimed(
            msg.sender,
            presaleOptionId,
            claimableAmount,
            nonce,
            block.timestamp,
            block.timestamp + presale.lockPeriod
        );
    }

    function getClaimableTokens(
        address user,
        uint256 presaleOptionId,
        uint256 nonce
    ) public view returns (uint256) {
        Purchase memory purchase = purchases[user][presaleOptionId][nonce];
        if (purchase.remainingAmount == 0) {
            return 0;
        }

        Presale memory presale = presalePool[presaleOptionId];
        if (
            block.timestamp < purchase.lastClaimTimestamp + presale.lockPeriod
        ) {
            return 0;
        }

        uint256 monthsPassed = (block.timestamp - purchase.lastClaimTimestamp) /
            30 days;
        uint256 claimableAmount = (purchase.amount *
            presale.monthlyReleasePercentage *
            monthsPassed) / 100;
        if (claimableAmount > purchase.remainingAmount) {
            claimableAmount = purchase.remainingAmount;
        }

        return claimableAmount;
    }

    function transferCurrency(
        address _currency,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_amount == 0) {
            return;
        }
        safeTransferERC20(_currency, _from, _to, _amount);
    }

    function safeTransferERC20(
        address _currency,
        address _from,
        address _to,
        uint256 _amount
    ) internal {
        if (_from == _to) {
            return;
        }

        if (_from == address(this)) {
            IERC20(_currency).safeTransfer(_to, _amount);
        } else {
            IERC20(_currency).safeTransferFrom(_from, _to, _amount);
        }
    }

    function setTreasuryWallet(address _newTreasuryWallet) external onlyOwner {
        require(
            _newTreasuryWallet != address(0),
            "Invalid treasury wallet address"
        );
        treasuryWallet = _newTreasuryWallet;
    }

    function setPresaleEndTime(uint256 _PRESALE_ENDTIME) external onlyOwner {
        require(
            block.timestamp < _PRESALE_ENDTIME,
            "end time must be in the future"
        );
        PRESALE_ENDTIME = _PRESALE_ENDTIME;
    }

    function setPresaleStartTime(uint256 _PRESALE_START) external onlyOwner {
        require(
            block.timestamp < _PRESALE_START,
            "start time must be in the future"
        );
        PRESALE_START = _PRESALE_START;
    }

    function updatePresalePrice(uint256 presaleOptionId, uint256 newPrice)
        external
        onlyOwner
    {
        require(
            presalePool[presaleOptionId].tokenPrice > 0,
            "Invalid presale option"
        );
        require(newPrice > 0, "New price must be greater than 0");

        presalePool[presaleOptionId].tokenPrice = newPrice;
    }

    function getTokenPrice(uint256 presaleOptionId)
        external
        view
        returns (uint256)
    {
        return presalePool[presaleOptionId].tokenPrice;
    }

    function _lzReceive(
        Origin calldata,
        bytes32,
        bytes calldata payload,
        address,
        bytes calldata
    ) internal override {
        (uint256 _amount, uint256 _pool, address _user) = abi.decode(
            payload,
            (uint256, uint256, address)
        );
        _processPayment(_user, _pool, _amount);
    }
}
