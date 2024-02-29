# Uniswap V2 Area

Code from [Uniswap V2](https://github.com/Uniswap/uniswap-v2-core/tree/27f6354bae6685612c182c3bc7577e61bc8717e3/contracts) with the following modifications.

1. Change contract version to 0.8.13 and do the necessary patching.
   - Change negation of `uint256` to `type(uint256).max - d + 1` in `FullMath.sol`.
   - Change `uint(-1)` to `type(uint).max` or `uint(MAX_VALUE)`.
2. Add `migrator` member in `UniswapV2Factory` which can be set by `feeToSetter`.
3. Allow `migrator` to specify the amount of `liquidity` during the first mint. Disallow first mint if migrator is set.
