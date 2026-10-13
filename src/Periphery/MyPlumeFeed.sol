// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { frxETH } from "../frxETH.sol";
import { IstPlumeRewards } from "../interfaces/IstPlumeRewards.sol";
import { IstPlumeMinter } from "../interfaces/IstPlumeMinter.sol";
import { IPlumeStaking } from "../interfaces/IPlumeStaking.sol";
import { PlumeStakingStorage } from "../interfaces/PlumeStakingStorage.sol";


// ====================================================================
// |                      myPlume Periphery Feed                        |
// ====================================================================

/// @title MyPlumeFeed - Periphery contract for myPlume
/// @notice Handles all periphery view functions for myPlume
contract MyPlumeFeed is Initializable{
    
    frxETH public myPlume; // 10%
    IstPlumeRewards public stPlumeRewards;
    IstPlumeMinter public stPlumeMinter;
    IPlumeStaking public plumeStaking;
    address public nativeToken;
    
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _myPlume,
        address _stPlumeMinter,
        address _stPlumeRewards,
        address _plumeStaking
    ) public initializer{
        myPlume = frxETH(_myPlume);
        stPlumeMinter = IstPlumeMinter(_stPlumeMinter);
        stPlumeRewards = IstPlumeRewards(_stPlumeRewards);
        plumeStaking = IPlumeStaking(_plumeStaking);
        nativeToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    }
    
    function getMyPlumeTvl() external view returns (uint256) {
        return myPlume.totalSupply();
    }

    function getTotalDeposits() public view returns (uint256) {
        return getPlumeStakedAmount() + stPlumeMinter.currentWithheldETH() - stPlumeMinter.totalInstantUnstaked() - getMyPlumeRewards();
    }
    
    /// @notice myPLUME/PLUME solvency ratio, 1e18-scaled (== 1e18 when fully backed, < 1e18 on a shortfall).
    /// @dev myPLUME is minted/redeemed 1:1 for PLUME principal and rewards are claimed separately
    ///      (Synthetix-style, in stPlumeRewards), so this is a backing-per-token *solvency* figure,
    ///      not an appreciating exchange rate — the repo's own fork test asserts it stays ~1e18.
    function getMyPlumePrice() public view returns (uint256) {
        return getTotalDeposits() * 1e18 / myPlume.totalSupply();
    }

    function getPlumeStakedAmount() public view returns (uint256) {
        return plumeStaking.stakeInfo(address(stPlumeMinter)).staked;
    }

    /// @notice Total non-principal PLUME held by the system: the surplus of total backing over the
    ///         1:1 principal owed to myPLUME holders (accrued rewards + protocol fees sitting in the pool).
    /// @dev Previously this multiplied the Synthetix *cumulative* `stPlumeRewards.rewardPerToken()`
    ///      index (monotonically increasing since genesis) by the current `totalSupply()`. That does
    ///      NOT equal the rewards accrued across holders — the true sum is
    ///      `sum_i balance_i * (rewardPerToken() - userRewardPerTokenPaid_i)`, which is not derivable
    ///      from a single cumulative index — so the old term grew without bound, drifting
    ///      {getMyPlumePrice} and eventually underflow-reverting {getTotalDeposits}.
    ///
    ///      Since myPLUME redeems 1:1 for principal, any backing above `totalSupply()` is by definition
    ///      non-principal (reward/fee) surplus. Computing it directly makes {getTotalDeposits} equal the
    ///      principal backing (capped at supply) and {getMyPlumePrice} a bounded solvency ratio.
    function getMyPlumeRewards() public view returns (uint256) {
        uint256 backing =
            getPlumeStakedAmount() + stPlumeMinter.currentWithheldETH() - stPlumeMinter.totalInstantUnstaked();
        uint256 supply = myPlume.totalSupply();
        return backing > supply ? backing - supply : 0;
    }

    function getMinterStats() public view returns (PlumeStakingStorage.StakeInfo memory) {
        return plumeStaking.stakeInfo(address(stPlumeMinter));
    }

    function getRedemptionFees() external view returns (uint256 standard, uint256 instant) {
        standard = stPlumeMinter.REDEMPTION_FEE();
        instant = stPlumeMinter.INSTANT_REDEMPTION_FEE();
    }

    // Liquidity and capacity metrics
    function getCurrentWithheldETH() external view returns (uint256) {
        return stPlumeMinter.currentWithheldETH();
    }

    function getTotalInstantUnstaked() external view returns (uint256) {
        return stPlumeMinter.totalInstantUnstaked();
    }

    function getLiquidityRatio() external view returns (uint256) {
        uint256 liquid = stPlumeMinter.currentWithheldETH();
        uint256 total = getTotalDeposits();
        return total > 0 ? liquid * 1e18 / total : 0;
    }

    function getEffectiveYield() external view returns (uint256) {
        return stPlumeRewards.getYield();
    }

    function totalRewards() public view returns (uint256) {
        uint256 reward = plumeStaking.getClaimableReward(address(stPlumeMinter), nativeToken);
        uint256 yieldAmount = (reward * stPlumeRewards.YIELD_FEE()) / stPlumeRewards.RATIO_PRECISION();
        uint256 netReward = reward - yieldAmount;
        return getMyPlumeRewards() + netReward;
    }
}