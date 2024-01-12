# Puppet

A puppet is a contract that when called, acts like an empty account,
it doesn't do anything and it has no API.
The only exception is that if it's called by the address that deployed it,
it delegates the call to the address passed to it in calldata.
This gives the deployer the ability to execute any logic they want in the context of the puppet.

The puppet's logic doesn't need to be ever upgraded, to change its behavior the deployer needs to
change the address it passes to the puppet to delegate to, or the calldata it passes for delegation.
The entire fleet of puppets deployed by a single contract can be upgraded
by upgrading the contract that deployed them, without using beacons.
A nice trick is that the deployer can make the puppet delegate to the address
holding the deployer's own logic, so the puppet's logic is encapsulated in the deployer's.

Deploying a new puppet is almost as cheap as deploying a new clone proxy.
Its whole deployed bytecode is 66 bytes, and its creation code is 62 bytes.
Just like clone proxy, it can be deployed using just the scratch space in memory.
The cost to deploy a puppet is 45K gas, only 4K more than a clone.
Because the bytecode is not compiled, it can be reliably deployed
under a predictable CREATE2 address regardless of the compiler version.
The bytecode doesn't use `PUSH0`, because many chains don't support it yet.
The bytecode is made to resemble clone proxy's wherever it makes sense to simplify auditing.

Because the puppet can be deployed under a predictable address despite
having no fixed logic, in some cases it can be used as a CREATE3 alternative.
It can be also used as a full replacement of the CREATE3 factory by using
a puppet deployed using CREATE2 to deploy arbitrary code using plain CREATE.

# Usage

## Test

```shell
forge test
```

## Format

```shell
forge fmt
```
