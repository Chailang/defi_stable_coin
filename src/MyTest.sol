// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
contract MyTest{

    uint256 public showAlaysBeZero = 0;
    uint256 public hiddenValue = 0;
    mapping(address => uint256) public balances;
    function doStuff(uint256 data) public {
      //  if (data == 2){
      //     showAlaysBeZero = 1;
      //  }
      //  if (hiddenValue == 7){
      //     showAlaysBeZero = 1;
      //  }
       hiddenValue = data;
    }
   

    function deposit(uint256 amount) public {
        balances[msg.sender] += amount;
    }
    function withdraw(uint256 amount) public {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
    }
}