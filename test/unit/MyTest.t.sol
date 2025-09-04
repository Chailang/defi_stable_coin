// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {MyTest} from "../../src/MyTest.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
contract MyTestTest is StdInvariant,Test{
    MyTest myTest;
    function setUp() public {
        myTest = new MyTest();
        //目标合约，允许随机调用 MyTest 的所有公共和外部函数
        // 以检查不变量是否保持不变
        targetContract(address(myTest));

    }
    // function testIsAlwaysBeZero() public {     
    //     myTest.doStuff(0);
    //     assertEq(myTest.showAlaysBeZero(),0);
    // }
    // //模糊测试
    // function testFuzz_IsAlwaysBeZero(uint256 x) public {     
    //     myTest.doStuff(x);
    //     assertEq(myTest.showAlaysBeZero(),0);
    // }

    // // 模糊测试 withdraw 
    // function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawAmount) public {
    //     vm.assume(depositAmount <= 1e18);  // 限制输入范围
    //     vm.assume(withdrawAmount <= 1e18);

    //     myTest.deposit(depositAmount);

    //     if (withdrawAmount <= depositAmount) {
    //         myTest.withdraw(withdrawAmount);
    //         assertEq(myTest.balances(address(this)), depositAmount - withdrawAmount);
    //     } else {
    //         // 应该 revert
    //         vm.expectRevert("Insufficient balance");
    //         myTest.withdraw(withdrawAmount);
    //     }
    // }

      //不变量测试
    function invariant_IsAlwaysBeZero() public view {     
        assertEq(myTest.showAlaysBeZero(),0);
    }

    // //符号执行
    // function testSymbolicExecution_IsAlwaysBeZero() public {     
    //     for (uint256 i = 0; i < 10; i++) {
    //         myTest.doStuff(i);
    //     }
    //     assertEq(myTest.showAlaysBeZero(),0);   
    // }

}

/**
 * 
 * Fuzz/invariant Testing
 * Sybolic Execution/ Formal Verification
 * 
*/