// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice This library is used to deploys puppets.
/// A puppet is a contract that when called, acts like an empty account, it doesn't do anything.
/// The only exception is that if it's called by the address that deployed it,
/// it can delegate the call to whatever address is passed to it in calldata.
///
/// To delegate, the deployer must prepend the calldata with an ABI-encoded address to delegate to.
/// All the data after the address will be passed verbatim as the delegation calldata.
/// If the calldata is shorter than 32 bytes, or it doesn't start with
/// an address left-padded with zeros, the puppet doesn't do anything.
/// This lets the deployer make a plain native tokens transfer to the puppet,
/// it will have an empty calldata, and the puppet will accept the transfer without delegating.
/// ABI-encoding the delegation address protects the deployer from being tricked by a 3rd party
/// into calling the puppet and making it delegate to an arbitrary address.
/// Such scenario would only be possible if the deployer called on the puppet a function with
/// the selector `0x00000000`, which as of now doesn't come from any reasonably named function.
library Puppet {
    // The creation code.
    // [code 1] and [code 2] are parts of the deployed code,
    // placed respectively before and after the deployer's address.
    // | Opcode used    | Hex value     | Stack content after executing
    // Code size and offset in memory
    // | PUSH1          | 60 42         | 66
    // | PUSH1          | 60 12         | 18 66
    // The code before the deployer's address and where it's stored in memory
    // | PUSH14         | 6D [code 1]   | [code 1] 18 66
    // | RETURNDATASIZE | 3D            | 0 [code 1] 18 66
    // The deployer's address and where it's stored in memory
    // | CALLER         | 33            | [deployer] 0 [code 1] 18 66
    // | PUSH1          | 60 14         | 20 [deployer] 0 [code 1] 18 66
    // The code after the deployer's address and where it's stored in memory
    // | PUSH32         | 7F [code 2]   | [code 2] 20 [deployer] 0 [code 1] 18 66
    // | PUSH1          | 60 34         | 52 [code 2] 20 [deployer] 0 [code 1] 18 66
    // Return the entire code
    // | MSTORE         | 52            | 20 [deployer] 0 [code 1] 18 66
    // | MSTORE         | 52            | 0 [code 1] 18 66
    // | MSTORE         | 52            | 18 66
    // | RETURN         | F3            |

    // The deployed code.
    // `deployer` is the deployer's address.
    // | Opcode used    | Hex value     | Stack content after executing
    // Push some constants
    // | PUSH1          | 60 20         | 32
    // | RETURNDATASIZE | 3D            | 0 32
    // | RETURNDATASIZE | 3D            | 0 0 32
    // Do not delegate if calldata shorter than 32 bytes
    // | CALLDATASIZE   | 36            | [calldata size] 0 0 32
    // | DUP4           | 83            | 32 [calldata size] 0 0 32
    // | GT             | 11            | [do not delegate] 0 0 32
    // Do not delegate if the first word of calldata is not a zero-padded address
    // | RETURNDATASIZE | 3D            | 0 [do not delegate] 0 0 32
    // | CALLDATALOAD   | 35            | [first word] [do not delegate] 0 0 32
    // | PUSH1          | 60 A0         | 160 [first word] [do not delegate] 0 0 32
    // | SHR            | 1C            | [first word upper bits] [do not delegate] 0 0 32
    // | OR             | 17            | [do not delegate] 0 0 32
    // Do not delegate if not called by the deployer
    // | PUSH20         | 73 [deployer] | [deployer] [do not delegate] 0 0 32
    // | CALLER         | 33            | [sender] [deployer] [do not delegate] 0 0 32
    // | XOR            | 18            | [sender not deployer] [do not delegate] 0 0 32
    // | OR             | 17            | [do not delegate] 0 0 32
    // Skip to the return if should not delegate
    // | PUSH1          | 60 40         | [success branch] [do not delegate] 0 0 32
    // | JUMPI          | 57            | 0 0 32
    // Calculate the payload size
    // | DUP3           | 82            | 32 0 0 32
    // | CALLDATASIZE   | 36            | [calldata size] 32 0 0 32
    // | SUB            | 03            | [payload size] 0 0 32
    // Copy the payload from calldata
    // | DUP1           | 80            | [payload size] [payload size] 0 0 32
    // | RETURNDATASIZE | 3D            | 0 [payload size] [payload size] 0 0 32
    // | SWAP5          | 94            | 32 [payload size] [payload size] 0 0 0
    // | RETURNDATASIZE | 3D            | 0 32 [payload size] [payload size] 0 0 0
    // | CALLDATACOPY   | 37            | [payload size] 0 0 0
    // Delegate call
    // | RETURNDATASIZE | 3D            | 0 [payload size] 0 0 0
    // | RETURNDATASIZE | 3D            | 0 0 [payload size] 0 0 0
    // | CALLDATALOAD   | 35            | [delegate to] 0 [payload size] 0 0 0
    // | GAS            | 5A            | [gas] [delegate to] 0 [payload size] 0 0 0
    // | DELEGATECALL   | F4            | [success] 0
    // Copy return data
    // | RETURNDATASIZE | 3D            | [return size] [success] 0
    // | DUP3           | 82            | 0 [return size] [success] 0
    // | DUP1           | 80            | 0 0 [return size] [success] 0
    // | RETURNDATACOPY | 3E            | [success] 0
    // Return
    // | SWAP1          | 90            | 0 [success]
    // | RETURNDATASIZE | 3D            | [return size] 0 [success]
    // | SWAP2          | 91            | [success] 0 [return size]
    // | PUSH1          | 60 40         | [success branch] [success] 0 [return size]
    // | JUMPI          | 57            | 0 [return size]
    // | REVERT         | FD            |
    // | JUMPDEST       | 5B            | 0 [return size]
    // | RETURN         | F3            |

    bytes internal constant CREATION_CODE =
        hex"604260126D60203D3D3683113D3560A01C17733D3360147F33181760405782"
        hex"3603803D943D373D3D355AF43D82803E903D91604057FD5BF36034525252F3";
    bytes32 internal constant CREATION_CODE_HASH = keccak256(CREATION_CODE);

    /// @notice Deploy a new puppet.
    /// @return instance The address of the puppet.
    function deploy() internal returns (address instance) {
        bytes memory creationCode = CREATION_CODE;
        assembly {
            instance := create(0, add(creationCode, 32), mload(creationCode))
        }
        require(instance != address(0), "Failed to deploy the puppet");
    }

    /// @notice Deploy a new puppet under a deterministic address.
    /// @param salt The salt to use for the deterministic deployment.
    /// @return instance The address of the puppet.
    function deployDeterministic(bytes32 salt) internal returns (address instance) {
        bytes memory creationCode = CREATION_CODE;
        assembly {
            instance := create2(0, add(creationCode, 32), mload(creationCode), salt)
        }
        require(instance != address(0), "Failed to deploy the puppet");
    }

    /// @notice Calculate the deterministic address for a puppet deployment made by this contract.
    /// @param salt The salt to use for the deterministic deployment.
    /// @return predicted The address of the puppet.
    function predictDeterministicAddress(bytes32 salt) internal view returns (address predicted) {
        return predictDeterministicAddress(salt, address(this));
    }

    /// @notice Calculate the deterministic address for a puppet deployment.
    /// @param salt The salt to use for the deterministic deployment.
    /// @param deployer The address of the deployer of the puppet.
    /// @return predicted The address of the puppet.
    function predictDeterministicAddress(bytes32 salt, address deployer)
        internal
        pure
        returns (address predicted)
    {
        bytes32 hash = keccak256(abi.encodePacked(hex"ff", deployer, salt, CREATION_CODE_HASH));
        return address(uint160(uint256(hash)));
    }

    function delegationCalldata(address delegateTo, bytes memory data)
        internal
        pure
        returns (bytes memory payload)
    {
        return abi.encodePacked(bytes32(uint256(uint160(delegateTo))), data);
    }
}
