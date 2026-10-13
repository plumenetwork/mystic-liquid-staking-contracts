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
    
    /// @notice myPLUME/PLUME share price, 1e18-scaled.
    /// @dev WARNING: not safe to consume as an external price oracle. It depends on
    ///      {getMyPlumeRewards}, which is malformed (see below): the value does not track the
    ///      actual accrued/claimable rewards, so this price can drift from the real backing and,
    ///      as `getMyPlumeRewards` grows past the staked+withheld total, {getTotalDeposits} can
    ///      underflow and revert. Any integrating lending market / collateral oracle MUST NOT rely
    ///      on it until {getMyPlumeRewards} is corrected to the protocol's intended rewards figure.
    function getMyPlumePrice() public view returns (uint256) {
        return getTotalDeposits() * 1e18 / myPlume.totalSupply();
    }

    function getPlumeStakedAmount() public view returns (uint256) {
        return plumeStaking.stakeInfo(address(stPlumeMinter)).staked;
    }

    /// @dev KNOWN-INCORRECT: `rewardPerToken()` is the Synthetix *cumulative* reward-per-token
    ///      index (monotonically increasing since genesis), not a current rewards figure.
    ///      Multiplying it by the current `totalSupply()` does NOT equal the total accrued rewards
    ///      across holders — that sum is `Σ balance_i * (rewardPerToken() - userRewardPerTokenPaid_i)`,
    ///      which cannot be derived globally from a single cumulative index. As written this term
    ///      grows without bound, corrupting {getTotalDeposits}/{getMyPlumePrice}. The intended
    ///      semantics (pending-cycle rewards? net undistributed rewards? exclude entirely for an
    ///      auto-compounding LST?) must be confirmed by the maintainers before fixing — this is
    ///      flagged rather than silently "corrected" because it feeds a price function.
    function getMyPlumeRewards() public view returns (uint256) {
        return (stPlumeRewards.rewardPerToken() * myPlume.totalSupply()) / 1e18;
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