# NXD Protocol

The NXD cryptocurrency is designed to function as a store of value derivative capturing DXN Protocol’s earnings capabilities through compounding the yield created by the daily auction participants. The NXD cryptocurrency aims to function as the inverse of DXN providing a deflationary force to DXN’s disinflationary system tokenomics.

In its purest from, NXD Protocol is a compounding staking vault of which the shares are denominated in NXD. These shares are bought and burned from the ETH operational profits derived from staking DXN in the DBXEN Protocol earning yield from its daily auction participants.

The operating profits are supported by similarly re-buying & staking DXN tokens, effectively compounding DXN earnings, to increase ETH rewards required for the Protocol’s deflationary mechanisms.

## Contracts

- [NXDERC20](src/NXDERC20.sol): The NXD ERC20 token contract. This contract is used to create the NXD token and manage the token's supply and transfer functionality. Has a 10% sell tax.

- [NXDProtocol](src/NXDProtocol.sol): The NXD Protocol contract. This contract is used to manage the Capped Staking Period (CSP) and the deflationary mechanisms of the NXD Protocol.

- [NXDStakingVault](src/NXDStakingVault.sol): The NXD staking contract. This contract is used to stake NXD tokens and earn rewards. The rewards are paid in ETH and are derived from the DXN Protocol's daily auction participants. The rewards are compounded by re-buying and staking DXN tokens.

- [TaxRecipient](src/TaxRecipient.sol): The Tax Recipient contract. This contract is used to manage the tax distribution of the NXD token.

- [Vesting](src/Vesting.sol): The Vesting contract. This contract is used to manage the vesting of the NXD tokens issued at launch.

- [V2Oracle](src/V2Oracle.sol): Uniswap V2 Oracle contract. This contract is used to get the price of the NXD token from the NXD/DXN Uniswap V2 pool. The price is used to calculate the minimum amount received when swapping NXD/DXN tokens.

- [V3Oracle](src/V3Oracle.sol): Uniswap V3 Oracle contract. This contract is used to get the price of the DXN token from the DXN/ETH Uniswap V3 pool. The price is used to calculate the minimum amount received when swapping DXN/ETH.

## Live Contracts

Will be updated soon.

## Development

The NXD Protocol is developed using the Solidity programming language and the Foundry framework.

Build the contracts using the following command:

```bash
forge build
```

## Documentation

The NXD Protocol uses the NatSpec format for documentation. The documentation is written in the contract files and can be generated using the following command:

```bash
forge doc
```

## Testing

The NXD Protocol uses the Foundry framework for testing. The test are written in solidity and exist is the `test/` folder.

To run the tests, you can use the following command:

```bash
forge test
```

To run the tests with coverage, you can use the following command:

```bash
forge coverage
```

To run a specific test, you can use the following command:

```bash
forge test --mc <TestContractName>
```

To run a specific test function in a specific test, you can use the following command:

```bash
forge test --mt <testFunctionName>
```

## Deployment

The deployment script lives in `script/NXD.s.sol`. To deploy the contracts, you can use the following command:

```bash
forge script script/NXD.s.sol --rpc-url <YOUR_RPC_URL> --broadcast -vvvv
```

Read more about Fonudry scripts [here](https://book.getfoundry.sh/tutorials/solidity-scripting)

## Audit

Will be updated soon.
