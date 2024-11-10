// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MultiSigWallet is Ownable {
    using Address for address;
    using SafeERC20 for IERC20;

    address[] public signers;
    mapping(address => bool) public isSigner;
    uint256 public numConfirmationsRequired;

    struct Transaction {
        address token;
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 numConfirmations;
    }

    Transaction[] public transactions;
    // mapping from tx index => signer => bool
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    event SubmitTransaction(
        address indexed signer,
        uint256 indexed txIndex,
        address indexed token,
        address indexed to,
        uint256 value,
        bytes data
    );
    event ConfirmTransaction(address indexed signer, uint256 indexed txIndex);
    event RevokeConfirmation(address indexed signer, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed signer, uint256 indexed txIndex);

    modifier onlySigner() {
        require(isSigner[msg.sender], "MultiSigWallet: Not signer");
        _;
    }

    modifier txExists(uint256 _txIndex) {
        require(_txIndex < transactions.length, "MultiSigWallet: Invalid tx");
        _;
    }

    modifier notExecuted(uint256 _txIndex) {
        require(!transactions[_txIndex].executed, "MultiSigWallet: Tx already executed");
        _;
    }

    modifier notConfirmed(uint256 _txIndex) {
        require(!isConfirmed[_txIndex][msg.sender], "MultiSigWallet: Tx already confirmed");
        _;
    }

    constructor(address[] memory _signers) {
        require(_signers.length > 0, "MultiSigWallet: Signers required");

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            require(signer != address(0) || !isSigner[signer], "MultiSigWallet: Invalid signer");

            isSigner[signer] = true;
            signers.push(signer);
        }

        numConfirmationsRequired = _signers.length;
    }

    function submitTransaction(
        address _token,
        address _to,
        uint256 _value,
        bytes memory _data
    ) public onlySigner {
        uint256 amount;
        if (_token == address(0)) {
            amount = address(this).balance;
        } else {
            amount = IERC20(_token).balanceOf(address(this));
        }
        require(amount >= _value, "MultiSigWallet: Tx can't be submited!");
        require(_to != address(0), "MultiSigWallet: Invalid recipient");

        uint256 txIndex = transactions.length;

        transactions.push(
            Transaction({
                token: _token,
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                numConfirmations: 0
            })
        );

        emit SubmitTransaction(msg.sender, txIndex, _token, _to, _value, _data);
    }

    function confirmTransaction(
        uint256 _txIndex
    )
        public
        onlySigner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;

        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function executeTransaction(
        uint256 _txIndex
    ) public onlySigner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];

        require(
            transaction.numConfirmations >= numConfirmationsRequired,
            "MultiSigWallet: Tx can't be execute!"
        );

        transaction.executed = true;
        if(transaction.token == address(0)) {
            (bool success, ) = address(transaction.to).call{value: transaction.value}("");
        } else {
            IERC20(transaction.token).safeTransfer(transaction.to, transaction.value);
        }

        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function revokeConfirmation(
        uint256 _txIndex
    ) public onlySigner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];

        require(isConfirmed[_txIndex][msg.sender], "MultiSigWallet: Tx not confirmed");

        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function getSigners() public view returns (address[] memory) {
        return signers;
    }

    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }

    function getTransaction(
        uint256 _txIndex
    ) public view returns (Transaction memory) {
        Transaction storage transaction = transactions[_txIndex];

        return transaction;
    }
}
