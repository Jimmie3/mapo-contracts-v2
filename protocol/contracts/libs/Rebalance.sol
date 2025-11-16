// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Rebalance {
    int256 constant MAX_RATE_UNIT = 1_000_000;

    int256 constant MAX_BALANCE_CHANGE = 600000;         // 60%
    int256 constant MIN_BALANCE_CHANGE = -600000;        // -60%

    struct BalanceInfo {
        int256 a;
        int256 vt;
        int256 wt;
        int256 vx;
        int256 wx;
        int256 vy;
        int256 wy;
    }

    struct BalanceFeeRate {
        uint32 balanceThreshold;    // balance fee calculation threshold

        int32 fixedFromBalance;    // a fixed balance fee for source chain transfer, mostly is zero
        int32 fixedToBalance;      // the fixed balance fee for target chain transfer
        int32 minBalance;          // the min balance fee, it might be a negative value
        int32 maxBalance;          // the max balance fee, it might be a negative value

        uint96 reserved;            // reserved for future use
    }

    // for deposit mint
    // ΔS = Wₓ × (r'ₓ² - rₓ²)
    // rₓ = Vₓ/(Wₓ×Vₜ) - 1 = (Vₓ - Wₓ×Vₜ) / (Wₓ×Vₜ)
    // r'ₓ = (Vₓ + a)/(Wₓ×(Vₜ + a)) - 1 = (Vₓ + a - Wₓ×(Vₜ + a)) / (Wₓ×(Vₜ + a))

    // for burn withdraw
    // ΔS = Wᵧ × (r'ᵧ² - rᵧ²)
    // rᵧ = Vᵧ/(Wᵧ×Vₜ) - 1 = (Vᵧ - Wᵧ×Vₜ) / (Wᵧ×Vₜ)
    // r'ᵧ = (Vᵧ - a)/(Wᵧ×(Vₜ - a)) - 1 = (Vᵧ - a - Wᵧ×(Vₜ - a)) / (Wᵧ×(Vₜ - a))
    function calcRelayBalanceChange(BalanceInfo memory info, bool transferIn) internal pure returns (int256 deltaS) {
        int256 r0;
        int256 r1;

        int256 w;
        int256 v;
        if (transferIn) {
            w = info.wx;
            v = info.vx;
            // r = Vₓ/(Wₓ×Vₜ) - 1 = (Vₓ - Wₓ×Vₜ) / (Wₓ×Vₜ)
            r0 = MAX_RATE_UNIT * (v * info.wt - w * info.vt) / (w * info.vt);
            // r'ₓ = (Vₓ + a)/(Wₓ×(Vₜ + a)) - 1 = ((Vₓ + a) - Wₓ×(Vₜ + a)) / (Wₓ×(Vₜ + a))
            r1 = MAX_RATE_UNIT * ((v + info.a) * info.wt - w * (info.vt + info.a)) / (w * (info.vt + info.a));
        } else {
            w = info.wy;
            v = info.vy;

            r0 = MAX_RATE_UNIT * (v * info.wt - w * info.vt) / (w * info.vt);
            // r'ᵧ = (Vᵧ - a)/(Wᵧ×(Vₜ - a)) - 1 = ((Vᵧ - a) - Wᵧ×(Vₜ - a)) / (Wᵧ×(Vₜ - a))
            r1 = MAX_RATE_UNIT * ((v - info.a) * info.wt - w * (info.vt - info.a)) / (w * (info.vt - info.a));
        }

        return w * (r1 * r1 - r0 * r0) / (info.wt * MAX_RATE_UNIT) ;
    }

    // from chain x -> chain y
    // ΔS = Wₓ × (r'ₓ² - rₓ²) + Wᵧ × (r'ᵧ² - rᵧ²)
    //    = [2a(vₓ×wᵧ - vᵧ×wₓ) + a²(wₓ + wᵧ)] / (wₓ×wᵧ×Tᵥ²)
    //    = [2avₓ×wᵧ + a²(wₓ + wᵧ) - 2avᵧ×wₓ ] / (wₓ×wᵧ×Tᵥ²)
    function calcBridgeBalanceChange(BalanceInfo memory info) internal pure returns (int256 deltaS) {
        // 2avₓ×wᵧ + a²(wₓ + wᵧ)
        int256 s1 = 2 * info.a * info.vx * info.wy + info.a * info.a * (info.wx + info.wy);
        // 2avᵧ×wₓ
        int256 s2 = 2 * info.a * info.vy * info.wx;

        return MAX_RATE_UNIT * info.wt * (s1 - s2) / (info.wx * info.wy * info.vt * info.vt);
    }

    function calcBalanceRate(BalanceInfo memory info, BalanceFeeRate memory balanceFeeRate, int256 deltaSMax) internal pure returns (int24) {
        int256 deltaS;
        if (info.wy == 0) {
            deltaS = calcRelayBalanceChange(info, true);
        } else if (info.wx == 0) {
            deltaS = calcRelayBalanceChange(info, false);
        } else {
            deltaS = calcBridgeBalanceChange(info);
        }

        int256 deltaPercent = MAX_RATE_UNIT * deltaS * info.vt / (deltaSMax * info.a);

        int256 rate;
        if (deltaPercent >= MAX_BALANCE_CHANGE) {
            rate = balanceFeeRate.maxBalance;
        } else if (deltaPercent <= MIN_BALANCE_CHANGE) {
            rate = balanceFeeRate.minBalance;
        } else {
            int256 maxDelta = balanceFeeRate.maxBalance - balanceFeeRate.minBalance;
            int256 maxChange = MAX_BALANCE_CHANGE - MIN_BALANCE_CHANGE;
            rate = MAX_RATE_UNIT * deltaPercent * maxChange / maxDelta + balanceFeeRate.minBalance;
        }

        return int24(rate);
    }


    function getBalanceFeeRate(BalanceInfo memory info, BalanceFeeRate memory balanceFeeRate, int256 deltaSMax, bool isSwapIn, bool isSwapOut)
    internal
    pure
    returns (int32)
    {
        int32 rate;

        if (isSwapIn) {
            // get a fix swapIn balance fee
            rate = balanceFeeRate.fixedFromBalance;
        } else if (isSwapOut) {
            // get a fix swapOut balance fee
            rate = balanceFeeRate.fixedToBalance;
        } else {
            if (info.wt == 0) {
                // not set chain weight, will collect fix balance fee
                rate = balanceFeeRate.fixedFromBalance + balanceFeeRate.fixedToBalance;
            } else {
                // To save gas, when the cross-chain amount is less than a certain threshold (e.g., 0.1% of total vault),
                // instead of directly calculating balance fee/incentive, charge a fixed fee
                if (info.a * MAX_RATE_UNIT <= info.vt * int256(int32(balanceFeeRate.balanceThreshold))) {
                    rate = balanceFeeRate.fixedFromBalance + balanceFeeRate.fixedToBalance;
                } else {
                    rate = calcBalanceRate(info, balanceFeeRate, deltaSMax);
                }
            }
        }

        return rate;
    }
}
