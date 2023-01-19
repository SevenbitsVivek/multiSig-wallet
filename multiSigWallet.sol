// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "hardhat/console.sol";

contract MultiSigWallet is Pausable, ERC20 {
    uint256 private _totalSupply;
    event Deposit(address indexed sender, uint amount, uint balance);
    event SubmitTransaction(
        address indexed owner,
        uint indexed txIndex,
        address indexed to,
        uint amount,
        string message
    );
    event ConfirmTransaction(address indexed owner, uint indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint indexed txIndex);
    event TokenMint(address indexed to, uint256 indexed amount);
    event TokenTransfered(
        address token,
        address from,
        address to,
        uint256 indexed amount
    );

    address[] private owners;
    uint public numConfirmationsRequired;
    Transaction[] private transactions;
    mapping(address => bool) private isOwner;
    mapping(uint => mapping(address => bool)) private isConfirmed;

    struct Transaction {
        address from;
        address to;
        uint amount;
        string message;
        bool executed;
        uint numConfirmations;
    }

    modifier onlyOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txExists(uint _txIndex) {
        require(_txIndex < transactions.length, "tx does not exist");
        _;
    }

    modifier notExecuted(uint _txIndex) {
        require(!transactions[_txIndex].executed, "tx already executed");
        _;
    }

    modifier notConfirmed(uint _txIndex) {
        require(!isConfirmed[_txIndex][msg.sender], "tx already confirmed");
        _;
    }

    constructor(address[] memory _owners, uint _numConfirmationsRequired, string memory name, string memory symbol) ERC20(name, symbol) {
        require(_owners.length > 0, "owners required");
        require(
            _numConfirmationsRequired > 0 &&
                _numConfirmationsRequired <= _owners.length,
            "invalid number of required confirmations"
        );
        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");
            isOwner[owner] = true;
            owners.push(owner);
            isOwner[_owners[i]] = true;
        }
        numConfirmationsRequired = _numConfirmationsRequired;
    }

    function submitTransaction(
        address _to,
        uint _amount,
        string memory _message
    ) public onlyOwner whenNotPaused {
        uint txIndex = transactions.length;
        transactions.push(
            Transaction({
                from: msg.sender,
                to: _to,
                amount: _amount,
                message: _message,
                executed: false,
                numConfirmations: 0
            })
        );
        emit TokenMint(address(this), _amount);
        _mint(address(this), _amount);
        _totalSupply += _amount;
        emit SubmitTransaction(msg.sender, txIndex, _to, _amount, _message);
    }

    function confirmTransaction(
        uint _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) notConfirmed(_txIndex) whenNotPaused {
        Transaction storage transaction = transactions[_txIndex];
        // require(transaction.from != msg.sender, "The owner who submit the transaction cannot call this function");
        transaction.numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;
        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function executeTransaction(
        uint _txIndex, address _to, uint256 _amount
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) whenNotPaused {
        Transaction storage transaction = transactions[_txIndex];
        require(transaction.to == _to && transaction.amount == _amount, "Invalid input");
        require(_amount != 0, "Insufficient amount");
        require(
            transaction.numConfirmations >= numConfirmationsRequired,
            "cannot execute tx"
        );
        emit ExecuteTransaction(msg.sender, _txIndex);
        transaction.executed = true;   
        emit TokenTransfered(address(this), msg.sender, _to, _amount);
        _totalSupply = totalSupply() - _amount;
        _transfer(address(this), _to, _amount);
    }

    function revokeConfirmation(
        uint _txIndex
    ) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) whenNotPaused {
        Transaction storage transaction = transactions[_txIndex];
        require(isConfirmed[_txIndex][msg.sender], "tx not confirmed");
        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;
        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount() public view returns (uint) {
        return transactions.length;
    }

    function getTransaction(
        uint _txIndex
    )
        public
        view
        returns (
            address from,
            address to,
            uint amount,
            string memory message,
            bool executed,
            uint numConfirmations
        )
    {
        Transaction storage transaction = transactions[_txIndex];
        return (
            transaction.from,
            transaction.to,
            transaction.amount,
            transaction.message,
            transaction.executed,
            transaction.numConfirmations
        );
    }

    function addOwners(address newOwners) external onlyOwner whenNotPaused {
        require(newOwners != address(0), "Address cannot be 0");
        require(!isOwner[newOwners], "Owners already exists");
        owners.push(newOwners);
        isOwner[newOwners] = true;
    }

    function removeOwners(address oldOwners) public onlyOwner whenNotPaused { 
        require(oldOwners != msg.sender, "Another owner can call this function");
        require(oldOwners != address(0), "Address cannot be 0");
        require(isOwner[oldOwners], "Owners already removed");
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == oldOwners) {
                delete owners[i];       
                isOwner[oldOwners] = false;
            }
        }
    }

    function pause() public {
        _pause();
    }

    function unpause() public {
        _unpause();
    }

    function changeNumConfirmationsRequired(uint _txIndex, uint256 _numConfirmationsRequired) public whenNotPaused onlyOwner notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];
        require(transaction.from == msg.sender, "Owner who submitted the transaction can only call this function");
        require(numConfirmationsRequired != _numConfirmationsRequired, "Numbers of required confirmations is already same");
        numConfirmationsRequired = _numConfirmationsRequired;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
}
