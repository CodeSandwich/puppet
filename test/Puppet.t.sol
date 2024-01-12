// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Puppet} from "src/Puppet.sol";

contract Logic {
    string public constant ERROR = "Failure called";

    fallback(bytes calldata data) external returns (bytes memory) {
        return abi.encode(data);
    }

    function success(uint256 arg) external payable returns (address, uint256, uint256) {
        return (address(this), arg, msg.value);
    }

    function failure() external pure {
        revert(ERROR);
    }
}

contract PuppetTest is Test {
    address puppet = Puppet.deploy();
    address logic = address(new Logic());

    function logicFailurePayload() internal view returns (bytes memory) {
        return Puppet.delegationCalldata(logic, abi.encodeWithSelector(Logic.failure.selector));
    }

    function call(address target, bytes memory data) internal returns (bytes memory) {
        return call(target, data, 0);
    }

    function call(address target, bytes memory data, uint256 value)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returned) = target.call{value: value}(data);
        require(success, "Unexpected revert");
        return returned;
    }

    function testDeployDeterministic() public {
        bytes32 salt = keccak256("Puppet");
        address newPuppet = Puppet.deployDeterministic(salt);
        assertEq(
            newPuppet, Puppet.predictDeterministicAddress(salt, address(this)), "Invalid address"
        );
        assertEq(
            newPuppet, Puppet.predictDeterministicAddress(salt), "Invalid address when no deployer"
        );
        assertEq(newPuppet.code, puppet.code, "Invalid code");
    }

    function testPuppetSizeBenchmark() public {
        emit log_named_bytes("Puppet bytecode", puppet.code);
        emit log_named_uint("Puppet size in bytes", puppet.code.length);
        uint256 gas = gasleft();
        Puppet.deploy();
        gas -= gasleft();
        emit log_named_uint("Gas cost to deploy the puppet", gas);
    }

    function testPuppetDelegates() public {
        uint256 arg = 1234;
        bytes memory data = abi.encodeWithSelector(Logic.success.selector, arg);
        bytes memory payload = Puppet.delegationCalldata(logic, data);
        uint256 value = 5678;

        bytes memory returned = call(puppet, payload, value);

        (address thisAddr, uint256 receivedArg, uint256 receivedValue) =
            abi.decode(returned, (address, uint256, uint256));
        assertEq(thisAddr, puppet, "Invalid delegation context");
        assertEq(receivedArg, arg, "Invalid argument");
        assertEq(receivedValue, value, "Invalid value");
    }

    function testPuppetDelegatesWithEmptyCalldata() public {
        bytes memory payload = Puppet.delegationCalldata(logic, "");
        bytes memory returned = call(puppet, payload);
        bytes memory data = abi.decode(returned, (bytes));
        assertEq(data.length, 0, "Delegated with non-empty calldata");
    }

    function testPuppetBubblesRevertPayload() public {
        vm.expectRevert(bytes(Logic(logic).ERROR()));
        call(puppet, logicFailurePayload());
    }

    function testPuppetDoesNothingForNonDeployer() public {
        vm.prank(address(1234));
        call(puppet, logicFailurePayload());
    }

    function testCallingWithCalldataShorterThan32BytesDoesNothing() public {
        address delegateTo = address(uint160(1234) << 8);
        bytes memory payload = abi.encodePacked(bytes31(bytes32(uint256(uint160(delegateTo)))));
        vm.mockCallRevert(delegateTo, "", "Logic called");
        call(puppet, payload);
    }

    function testCallingWithDelegationAddressOver20BytesDoesNothing() public {
        bytes memory payload = logicFailurePayload();
        payload[11] = 0x01;
        call(puppet, payload);
    }

    function testCallingPuppetDoesNothing() public {
        // Forge the calldata, so if puppet uses it to delegate, it will run `Logic.failure`
        uint256 forged = uint256(uint160(address(this))) << 32;
        forged |= uint32(Logic.failure.selector);
        bytes memory payload = abi.encodeWithSignature("abc(uint)", forged);
        call(puppet, payload);
    }

    function testTransferFromDeployerToPuppet() public {
        uint256 amt = 123;
        payable(puppet).transfer(amt);
        assertEq(puppet.balance, amt, "Invalid balance");
    }

    function testTransferToPuppet() public {
        uint256 amt = 123;
        address sender = address(456);
        payable(sender).transfer(amt);
        vm.prank(sender);
        payable(puppet).transfer(amt);
        assertEq(puppet.balance, amt, "Invalid balance");
    }
}
