// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OApp, MessagingFee, Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract CrossSender is OApp {
    using SafeERC20 for IERC20;
    address public treasuryWallet;
    uint256 public mainDecimals;
    uint256 public payTokendecimals;
    string public data = "Nothing received yet.";
    address public payToken;

    constructor(
        address _endpoint,
        address _owner,
        address _payToken
    ) OApp(_endpoint, _owner) Ownable(_owner) {
        treasuryWallet =_owner;
        mainDecimals = 6;
        payTokendecimals = 18;
        payToken = _payToken;
    }

    function quote(
        uint32 _dstEid,
        uint256 _tokenAmount,
        uint256 _poolId,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory _payload = abi.encode(_tokenAmount, _poolId, msg.sender);
        fee = _quote(_dstEid, _payload, _options, _payInLzToken);
    }

    function _lzReceive(
        Origin calldata,
        bytes32,
        bytes calldata payload,
        address,
        bytes calldata
    ) internal override {
        data = abi.decode(payload, (string));
    }

    function buyTokens(
        uint32 _dstEid,
        uint256 _tokenAmount,
        uint256 _poolId,
        bytes calldata _options
    ) external payable {
        transferCurrency(payToken, msg.sender, treasuryWallet, _tokenAmount);

        uint256 amount = (_tokenAmount / 10**payTokendecimals) *
            10**mainDecimals;
        bytes memory _payload = abi.encode(amount, _poolId, msg.sender);
        _lzSend(
            _dstEid,
            _payload,
            _options,
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
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
}
