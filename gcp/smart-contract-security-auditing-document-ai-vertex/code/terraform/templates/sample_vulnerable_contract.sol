// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract VulnerableBank {
    mapping(address => uint256) public balances;
    mapping(address => bool) public isAdmin;
    
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    
    constructor() {
        isAdmin[msg.sender] = true;
    }
    
    // Vulnerability: Missing access control
    function setAdmin(address _admin) public {
        isAdmin[_admin] = true;
    }
    
    function deposit() public payable {
        require(msg.value > 0, "Must deposit positive amount");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    
    // Vulnerability: Reentrancy attack vector
    function withdraw(uint256 _amount) public {
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        
        // External call before state change - reentrancy vulnerability
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success, "Transfer failed");
        
        balances[msg.sender] -= _amount;
        emit Withdrawal(msg.sender, _amount);
    }
    
    // Vulnerability: Integer overflow in older Solidity versions
    function unsafeAdd(uint256 a, uint256 b) public pure returns (uint256) {
        return a + b; // Could overflow in Solidity < 0.8.0
    }
    
    // Vulnerability: Timestamp dependence
    function isLuckyTime() public view returns (bool) {
        return block.timestamp % 2 == 0;
    }
    
    // Admin function with proper access control
    function emergencyWithdraw() public {
        require(isAdmin[msg.sender], "Only admin");
        payable(msg.sender).transfer(address(this).balance);
    }
    
    function getBalance() public view returns (uint256) {
        return balances[msg.sender];
    }
}