// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { E2eSwapTest, E2eTestState, SwapLimits } from "@balancer-labs/v3-vault/test/foundry/E2eSwap.t.sol";

import { GyroEclpPoolDeployer } from "./utils/GyroEclpPoolDeployer.sol";

contract E2eSwapECLPTest is E2eSwapTest, GyroEclpPoolDeployer {
    using FixedPoint for uint256;

    function setUp() public override {
        E2eSwapTest.setUp();
    }

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by E2eSwapTest tests.
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address, bytes memory) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createGyroEclpPool(tokens, rateProviders, label, vault, lp);
    }

    function setUpVariables(E2eTestState memory state) internal view override returns (E2eTestState memory) {
        state.sender = lp;
        state.poolCreator = lp;

        // 0.0001% min swap fee.
        state.minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        state.maxPoolSwapFeePercentage = 10e16;

        return state;
    }

    function computeSwapLimits() internal view virtual override returns (SwapLimits memory swapLimits) {
        uint256 rateTokenA = getRate(tokenA);
        uint256 rateTokenB = getRate(tokenB);

        // The vault does not allow trade amounts (amountGivenScaled18 or amountCalculatedScaled18) to be less than
        // MIN_TRADE_AMOUNT. For "linear pools" (PoolMock), amountGivenScaled18 and amountCalculatedScaled18 are
        // the same. So, minAmountGivenScaled18 > MIN_TRADE_AMOUNT. To derive the formula below, note that
        // `amountGivenRaw = amountGivenScaled18/(rateToken * scalingFactor)`. There's an adjustment for stable math
        // in the following steps.
        uint256 tokenAMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT.divUp(rateTokenA).mulUp(10 ** decimalsTokenA);
        uint256 tokenBMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT.divUp(rateTokenB).mulUp(10 ** decimalsTokenB);

        // Also, since we undo the operation (reverse swap with the output of the first swap), amountCalculatedRaw
        // cannot be 0. Considering that amountCalculated is tokenB, and amountGiven is tokenA:
        // 1) amountCalculatedRaw > 0
        // 2) amountCalculatedRaw = amountCalculatedScaled18 * 10^(decimalsB) / (rateB * 10^18)
        // 3) amountCalculatedScaled18 = amountGivenScaled18 // Linear math, there's a factor to stable math
        // 4) amountGivenScaled18 = amountGivenRaw * rateA * 10^18 / 10^(decimalsA)
        // Using the four formulas above, we determine that:
        // amountCalculatedRaw > rateB * 10^(decimalsA) / (rateA * 10^(decimalsB))
        uint256 tokenACalculatedNotZero = (rateTokenB * (10 ** decimalsTokenA)) / (rateTokenA * (10 ** decimalsTokenB));
        uint256 tokenBCalculatedNotZero = (rateTokenA * (10 ** decimalsTokenB)) / (rateTokenB * (10 ** decimalsTokenA));

        // Use the larger of the two values above to calculate the minSwapAmount. Also, multiply by 10 to account for
        // swap fees and compensate for rate rounding issues.
        uint256 mathFactor = 10;
        swapLimits.minTokenA = (
            tokenAMinTradeAmount > tokenACalculatedNotZero
                ? mathFactor * tokenAMinTradeAmount
                : mathFactor * tokenACalculatedNotZero
        );
        swapLimits.minTokenB = (
            tokenBMinTradeAmount > tokenBCalculatedNotZero
                ? mathFactor * tokenBMinTradeAmount
                : mathFactor * tokenBCalculatedNotZero
        );

        // 50% of pool init amount to make sure LP has enough tokens to pay for the swap in case of EXACT_OUT.
        swapLimits.maxTokenA = poolInitAmountTokenA.mulDown(50e16);
        swapLimits.maxTokenB = poolInitAmountTokenB.mulDown(50e16);
    }
}
