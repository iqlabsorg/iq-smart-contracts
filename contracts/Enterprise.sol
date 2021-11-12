// SPDX-License-Identifier: MIT

// IQ Protocol. Risk-free collateral-less utility renting
// https://iq.space/docs/iq-yellow-paper.pdf
// (C) Blockvis & PARSIQ
// 🖖 Stake strong!

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./token/ERC20.sol";
import "./interfaces/IStakeToken.sol";
import "./interfaces/IRentalToken.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IPowerToken.sol";
import "./interfaces/IEnterprise.sol";
import "./EnterpriseStorage.sol";

contract Enterprise is EnterpriseStorage, IEnterprise {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    enum StakeOperation {
        Reward,
        Stake,
        Unstake,
        Increase,
        Decrease
    }

    event StakeChanged(
        uint256 indexed stakeTokenId,
        address indexed staker,
        StakeOperation indexed operation,
        uint256 amountDelta,
        uint256 amount,
        uint256 sharesDelta,
        uint256 shares,
        uint256 totalShares,
        uint256 totalReserve,
        uint256 totalUsedReserve
    );

    event ServiceRegistered(address indexed powerToken);

    event Rented(
        uint256 indexed rentalTokenId,
        address indexed renter,
        address indexed powerToken,
        address paymentToken,
        uint112 rentalAmount,
        uint112 poolFee,
        uint112 serviceFee,
        uint112 gcFee,
        uint32 startTime,
        uint32 endTime,
        uint32 renterOnlyReturnTime,
        uint32 enterpriseOnlyCollectionTime,
        uint256 totalReserve,
        uint256 totalUsedReserve
    );

    event RentalPeriodExtended(
        uint256 indexed rentalTokenId,
        address indexed renter,
        address paymentToken,
        uint112 poolFee,
        uint112 serviceFee,
        uint32 endTime,
        uint32 renterOnlyReturnTime,
        uint32 enterpriseOnlyCollectionTime
    );

    event RentalReturned(
        uint256 indexed rentalTokenId,
        address indexed returner,
        address indexed powerToken,
        uint112 rentalAmount,
        uint112 gcRewardAmount,
        address gcRewardToken,
        uint256 totalReserve,
        uint256 totalUsedReserve
    );

    function registerService(
        string memory serviceName,
        string memory serviceSymbol,
        uint32 energyGapHalvingPeriod,
        uint112 baseRate,
        address baseToken,
        uint16 serviceFeePercent,
        uint32 minRentalPeriod,
        uint32 maxRentalPeriod,
        uint96 minGCFee,
        bool swappingEnabledForever
    ) external onlyOwner whenNotShutdown {
        require(address(baseToken) != address(0), Errors.E_INVALID_BASE_TOKEN_ADDRESS);
        require(_powerTokens.length < type(uint16).max, Errors.E_SERVICE_LIMIT_REACHED);

        // Deploy new power token.
        IPowerToken powerToken = _factory.deployService(getProxyAdmin());
        {
            string memory tokenSymbol = _enterpriseToken.symbol();
            string memory powerTokenSymbol = string(abi.encodePacked(tokenSymbol, " ", serviceSymbol));
            ERC20(address(powerToken)).initialize(serviceName, powerTokenSymbol, _enterpriseToken.decimals());
        }

        // Configure service parameters.
        powerToken.initialize(
            this,
            IERC20Metadata(baseToken),
            baseRate,
            minGCFee,
            serviceFeePercent,
            energyGapHalvingPeriod,
            uint16(_powerTokens.length),
            minRentalPeriod,
            maxRentalPeriod,
            swappingEnabledForever
        );

        // Complete service registration.
        _powerTokens.push(powerToken);
        _registeredPowerTokens[address(powerToken)] = true;

        emit ServiceRegistered(address(powerToken));
    }

    function rent(
        address powerToken,
        address paymentToken,
        uint112 rentalAmount,
        uint32 rentalPeriod,
        uint256 maxPayment
    ) external whenNotShutdown {
        require(rentalAmount > 0, Errors.E_INVALID_RENTAL_AMOUNT);
        require(_registeredPowerTokens[powerToken], Errors.UNREGISTERED_POWER_TOKEN);
        require(rentalAmount <= getAvailableReserve(), Errors.E_INSUFFICIENT_LIQUIDITY);

        // Estimate rental fee.
        (uint112 poolFee, uint112 serviceFee, uint112 gcFee) = IPowerToken(powerToken).estimateRentalFee(
            paymentToken,
            rentalAmount,
            rentalPeriod
        );
        {
            // Ensure no rental fee payment slippage.
            // GC fee does not go to the pool but must be accounted for slippage calculation.
            require(poolFee + serviceFee + gcFee <= maxPayment, Errors.E_RENTAL_PAYMENT_SLIPPAGE);

            // Handle rental fee transfer and distribution.
            handleRentalPayment(IERC20(paymentToken), serviceFee, poolFee);

            // Transfer GC fee to the rental token contract.
            IERC20(paymentToken).safeTransferFrom(msg.sender, address(_rentalToken), gcFee);

            // Update used reserve.
            _usedReserve += rentalAmount;
        }

        // Calculate rental agreement timestamps.
        uint32 endTime = uint32(block.timestamp) + rentalPeriod;
        uint32 renterOnlyReturnTime = endTime + _renterOnlyReturnPeriod;
        uint32 enterpriseOnlyCollectionTime = endTime + _enterpriseOnlyCollectionPeriod;

        // Precalculate rental token ID to associate rental agreement.
        uint256 rentalTokenId = _rentalToken.getNextTokenId();

        _rentalAgreements[rentalTokenId] = RentalAgreement(
            rentalAmount,
            IPowerToken(powerToken).getIndex(),
            uint32(block.timestamp),
            endTime,
            renterOnlyReturnTime,
            enterpriseOnlyCollectionTime,
            gcFee,
            uint16(getPaymentTokenIndex(paymentToken))
        );

        // Mint rental token to the renter address.
        // This also mints corresponding amount of PowerTokens.
        assert(_rentalToken.mint(msg.sender) == rentalTokenId);

        // Notify power token contract about new rental.
        IPowerToken(powerToken).notifyNewRental(rentalTokenId);

        emit Rented(
            rentalTokenId,
            msg.sender,
            powerToken,
            paymentToken,
            rentalAmount,
            poolFee,
            serviceFee,
            gcFee,
            uint32(block.timestamp),
            endTime,
            renterOnlyReturnTime,
            enterpriseOnlyCollectionTime,
            getReserve(),
            _usedReserve
        );
    }

    function extendRentalPeriod(
        uint256 rentalTokenId,
        address paymentToken,
        uint32 rentalPeriod,
        uint256 maxPayment
    ) external whenNotShutdown {
        RentalAgreement storage rentalAgreement = _rentalAgreements[rentalTokenId];
        require(rentalAgreement.rentalAmount > 0, Errors.E_INVALID_RENTAL_TOKEN_ID);
        IPowerToken powerToken = _powerTokens[rentalAgreement.powerTokenIndex];
        require(rentalAgreement.endTime + rentalPeriod >= block.timestamp, Errors.E_INVALID_RENTAL_PERIOD);

        // Simulate rental return to ensure correct reserves during new rental fee calculation.
        uint256 usedReserve = _usedReserve;
        _usedReserve = usedReserve - rentalAgreement.rentalAmount;
        // Estimate new rental fee.
        (uint112 poolFee, uint112 serviceFee, ) = powerToken.estimateRentalFee(
            paymentToken,
            rentalAgreement.rentalAmount,
            rentalPeriod
        );

        // Simulate renting.
        _usedReserve = usedReserve;

        // Ensure no rental fee payment slippage.
        require(poolFee + serviceFee <= maxPayment, Errors.E_RENTAL_PAYMENT_SLIPPAGE);

        // Handle rental payment transfer and distribution.
        handleRentalPayment(IERC20(paymentToken), serviceFee, poolFee);

        // Calculate new rental agreement timestamps.
        uint32 newEndTime = rentalAgreement.endTime + rentalPeriod;
        uint32 newRenterOnlyReturnTime = newEndTime + _renterOnlyReturnPeriod;
        uint32 newEnterpriseOnlyCollectionTime = newEndTime + _enterpriseOnlyCollectionPeriod;

        // Update rental agreement.
        rentalAgreement.endTime = newEndTime;
        rentalAgreement.renterOnlyReturnTime = newRenterOnlyReturnTime;
        rentalAgreement.enterpriseOnlyCollectionTime = newEnterpriseOnlyCollectionTime;

        // Notify power token contract about new rental.
        powerToken.notifyNewRental(rentalTokenId);

        emit RentalPeriodExtended(
            rentalTokenId,
            msg.sender,
            paymentToken,
            poolFee,
            serviceFee,
            newEndTime,
            newRenterOnlyReturnTime,
            newEnterpriseOnlyCollectionTime
        );
    }

    function handleRentalPayment(
        IERC20 paymentToken,
        uint256 serviceFee,
        uint112 poolFee
    ) internal {
        uint256 rentalFee;
        unchecked {
            rentalFee = serviceFee + poolFee;
        }
        // Transfer base rental fee to the enterprise.
        paymentToken.safeTransferFrom(msg.sender, address(this), rentalFee);
        IERC20 enterpriseToken = _enterpriseToken;

        // Initially assume rental fee payment is made in enterprise tokens.
        uint256 serviceFeeInEnterpriseTokens = serviceFee;
        uint112 poolFeeInEnterpriseTokens = poolFee;

        // Should the rental fee payment be made in tokens other than enterprise tokens,
        // the payment amount gets converted to enterprise tokens automatically.
        if (address(paymentToken) != address(enterpriseToken)) {
            paymentToken.approve(address(_converter), rentalFee);
            uint256 rentalFeeInEnterpriseTokens = _converter.convert(paymentToken, rentalFee, enterpriseToken);
            serviceFeeInEnterpriseTokens = (serviceFee * rentalFeeInEnterpriseTokens) / rentalFee;
            poolFeeInEnterpriseTokens = uint112(rentalFeeInEnterpriseTokens - serviceFeeInEnterpriseTokens);
        }

        // Transfer service fee (enterprise tokens) to the enterprise wallet.
        enterpriseToken.safeTransfer(_enterpriseWallet, serviceFeeInEnterpriseTokens);
        // Update streaming target.
        _increaseStreamingReserveTarget(poolFeeInEnterpriseTokens);
    }

    function returnRental(uint256 rentalTokenId) external {
        RentalAgreement memory rentalAgreement = _rentalAgreements[rentalTokenId];
        require(rentalAgreement.rentalAmount > 0, Errors.E_INVALID_RENTAL_TOKEN_ID);

        address renter = _rentalToken.ownerOf(rentalTokenId);
        uint32 timestamp = uint32(block.timestamp);

        require(
            rentalAgreement.renterOnlyReturnTime < timestamp || msg.sender == renter,
            Errors.E_INVALID_CALLER_WITHIN_RENTER_ONLY_RETURN_PERIOD
        );
        require(
            rentalAgreement.enterpriseOnlyCollectionTime < timestamp ||
                msg.sender == renter ||
                msg.sender == _enterpriseCollector,
            Errors.E_INVALID_CALLER_WITHIN_ENTERPRISE_ONLY_COLLECTION_PERIOD
        );

        if (!_enterpriseShutdown) {
            // When enterprise is shut down, usedReserve equals zero.
            _usedReserve -= rentalAgreement.rentalAmount;
        }

        emit RentalReturned(
            rentalTokenId,
            msg.sender,
            address(_powerTokens[rentalAgreement.powerTokenIndex]),
            rentalAgreement.rentalAmount,
            rentalAgreement.gcRewardAmount,
            _paymentTokens[rentalAgreement.gcRewardTokenIndex],
            getReserve(),
            _usedReserve
        );

        // Burn rental token and delete associated rental agreement.
        // This also burns corresponding amount of PowerTokens and transfers GC fee to the transaction sender address.
        _rentalToken.burn(rentalTokenId, msg.sender);
        delete _rentalAgreements[rentalTokenId];
    }

    /**
     * One must approve sufficient amount of enterprise tokens to
     * Enterprise address before calling this function
     */
    function stake(uint256 stakeAmount) external whenNotShutdown {
        // Transfer enterprise tokens to the enterprise.
        _enterpriseToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        // Calculate number of new shares to be issued.
        uint256 reserve = getReserve();
        uint256 stakeShares = (_totalShares == 0 ? stakeAmount : _liquidityToShares(stakeAmount, reserve));

        // Increase total reserves & shares.
        _increaseReserveAndShares(stakeAmount, stakeShares);

        // Mint new stake token and associate stake information.
        uint256 stakeTokenId = _stakeToken.mint(msg.sender);
        _stakes[stakeTokenId] = Stake(stakeAmount, stakeShares, block.number);

        emit StakeChanged(
            stakeTokenId,
            msg.sender,
            StakeOperation.Stake,
            stakeAmount,
            stakeAmount,
            stakeShares,
            stakeShares,
            _totalShares,
            reserve + stakeAmount,
            _usedReserve
        );
    }

    function claimStakingReward(uint256 stakeTokenId) external onlyStakeTokenOwner(stakeTokenId) {
        Stake storage stakeInfo = _stakes[stakeTokenId];

        uint256 stakeAmount = stakeInfo.amount;
        uint256 stakeShares = stakeInfo.shares;
        uint256 reserve = getReserve();

        // Calculate reward & check if reserves are sufficient to fulfill withdrawal request.
        uint256 rewardAmount = _calculateStakingReward(stakeShares, stakeAmount, reserve);
        require(rewardAmount <= _getAvailableReserve(reserve), Errors.E_INSUFFICIENT_LIQUIDITY);

        // Transfer reward to the stake token owner.
        _enterpriseToken.safeTransfer(msg.sender, rewardAmount);

        // Recalculate the remaining number of shares after reward withdrawal.
        uint256 remainingStakeShares = _liquidityToShares(stakeAmount, reserve);
        uint256 stakeSharesDelta = stakeShares - remainingStakeShares;

        // Decrease total reserves & shares.
        _decreaseReserveAndShares(rewardAmount, stakeSharesDelta);

        // Update stake information.
        stakeInfo.shares = remainingStakeShares;

        emit StakeChanged(
            stakeTokenId,
            msg.sender,
            StakeOperation.Reward,
            rewardAmount,
            stakeAmount,
            stakeSharesDelta,
            remainingStakeShares,
            _totalShares,
            reserve - rewardAmount,
            _usedReserve
        );
    }

    function unstake(uint256 stakeTokenId) external onlyStakeTokenOwner(stakeTokenId) {
        Stake storage stakeInfo = _stakes[stakeTokenId];
        require(stakeInfo.block < block.number, Errors.E_FLASH_LIQUIDITY_REMOVAL);

        // Calculate owing enterprise token amount including accrued reward.
        uint256 stakeShares = stakeInfo.shares;
        uint256 reserve = getReserve();
        uint256 stakeAmountWithReward = _sharesToLiquidity(stakeShares, reserve);
        require(stakeAmountWithReward <= _getAvailableReserve(reserve), Errors.E_INSUFFICIENT_LIQUIDITY);

        // Transfer enterprise tokens to the stake token owner.
        _enterpriseToken.safeTransfer(msg.sender, stakeAmountWithReward);

        // Decrease total reserves & shares.
        _decreaseReserveAndShares(stakeAmountWithReward, stakeShares);

        // Burn stake token and delete associated stake information.
        _stakeToken.burn(stakeTokenId);
        delete _stakes[stakeTokenId];

        emit StakeChanged(
            stakeTokenId,
            msg.sender,
            StakeOperation.Unstake,
            stakeAmountWithReward,
            0,
            stakeShares,
            0,
            _totalShares,
            reserve - stakeAmountWithReward,
            _usedReserve
        );
    }

    function decreaseStake(uint256 stakeTokenId, uint256 stakeAmountDelta) external onlyStakeTokenOwner(stakeTokenId) {
        Stake memory stakeInfo = _stakes[stakeTokenId];
        require(stakeInfo.block < block.number, Errors.E_FLASH_LIQUIDITY_REMOVAL);
        require(stakeInfo.amount >= stakeAmountDelta, Errors.E_INSUFFICIENT_LIQUIDITY);
        uint256 reserve = getReserve();
        require(stakeAmountDelta <= _getAvailableReserve(reserve), Errors.E_INSUFFICIENT_LIQUIDITY);

        // Transfer enterprise tokens to the stake token owner.
        _enterpriseToken.safeTransfer(msg.sender, stakeAmountDelta);

        // Calculate number of shares to be destroyed.
        uint256 stakeSharesDelta = _liquidityToShares(stakeAmountDelta, reserve);
        if (stakeSharesDelta > stakeInfo.shares) {
            stakeSharesDelta = stakeInfo.shares;
        }

        // Decrease total reserves & shares.
        _decreaseReserveAndShares(stakeAmountDelta, stakeSharesDelta);

        // Update stake information.
        unchecked {
            stakeInfo.shares -= stakeSharesDelta;
            stakeInfo.amount -= stakeAmountDelta;
        }
        _stakes[stakeTokenId].shares = stakeInfo.shares;
        _stakes[stakeTokenId].amount = stakeInfo.amount;

        emit StakeChanged(
            stakeTokenId,
            msg.sender,
            StakeOperation.Decrease,
            stakeAmountDelta,
            stakeInfo.amount,
            stakeSharesDelta,
            stakeInfo.shares,
            _totalShares,
            reserve - stakeAmountDelta,
            _usedReserve
        );
    }

    function increaseStake(uint256 stakeTokenId, uint256 stakeAmountDelta)
        external
        whenNotShutdown
        onlyStakeTokenOwner(stakeTokenId)
    {
        // Transfer enterprise tokens to the enterprise.
        _enterpriseToken.safeTransferFrom(msg.sender, address(this), stakeAmountDelta);

        // Calculate number of new shares to be issued.
        uint256 reserve = getReserve();
        uint256 stakeSharesDelta = (
            _totalShares == 0 ? stakeAmountDelta : _liquidityToShares(stakeAmountDelta, reserve)
        );

        // Increase total reserves & shares.
        _increaseReserveAndShares(stakeAmountDelta, stakeSharesDelta);

        // Update stake information.
        Stake storage stakeInfo = _stakes[stakeTokenId];
        uint256 stakeAmount = stakeInfo.amount + stakeAmountDelta;
        uint256 stakeShares = stakeInfo.shares + stakeSharesDelta;
        stakeInfo.amount = stakeAmount;
        stakeInfo.shares = stakeShares;
        stakeInfo.block = block.number;

        emit StakeChanged(
            stakeTokenId,
            msg.sender,
            StakeOperation.Increase,
            stakeAmountDelta,
            stakeAmount,
            stakeSharesDelta,
            stakeShares,
            _totalShares,
            reserve + stakeAmountDelta,
            _usedReserve
        );
    }

    function estimateRentalFee(
        address powerToken,
        address paymentToken,
        uint112 rentalAmount,
        uint32 rentalPeriod
    ) external view whenNotShutdown returns (uint256) {
        require(_registeredPowerTokens[powerToken], Errors.UNREGISTERED_POWER_TOKEN);
        (uint112 poolFee, uint112 serviceFee, uint112 gcFee) = IPowerToken(powerToken).estimateRentalFee(
            paymentToken,
            rentalAmount,
            rentalPeriod
        );

        return poolFee + serviceFee + gcFee;
    }

    function _increaseReserveAndShares(uint256 reserveDelta, uint256 sharesDelta) internal {
        _totalShares += sharesDelta;
        uint256 fixedReserve = _fixedReserve + reserveDelta;
        _fixedReserve = fixedReserve;
        emit FixedReserveChanged(fixedReserve);
    }

    function _decreaseReserveAndShares(uint256 reserveDelta, uint256 sharesDelta) internal {
        uint256 fixedReserve = _fixedReserve;
        _totalShares -= sharesDelta;
        if (fixedReserve >= reserveDelta) {
            unchecked {
                fixedReserve -= reserveDelta;
            }
        } else {
            uint256 streamingReserve = _flushStreamingReserve();
            fixedReserve = (fixedReserve + streamingReserve) - reserveDelta;
        }
        _fixedReserve = fixedReserve;
        emit FixedReserveChanged(fixedReserve);
    }

    function _liquidityToShares(uint256 liquidityAmount, uint256 reserve) internal view returns (uint256) {
        return (_totalShares * liquidityAmount) / reserve;
    }

    function _sharesToLiquidity(uint256 shares, uint256 reserve) internal view returns (uint256) {
        return (reserve * shares) / _totalShares;
    }

    function transferRental(
        address from,
        address to,
        uint256 rentalTokenId
    ) external override onlyRentalToken {
        RentalAgreement memory rentalAgreement = _rentalAgreements[rentalTokenId];

        require(rentalAgreement.rentalAmount > 0, Errors.E_INVALID_RENTAL_TOKEN_ID);

        bool isExpiredRentalAgreement = (block.timestamp > rentalAgreement.endTime);
        bool isMinting = (from == address(0));
        bool isBurning = (to == address(0));
        IPowerToken powerToken = _powerTokens[rentalAgreement.powerTokenIndex];

        if (isBurning) {
            powerToken.burnFrom(from, rentalAgreement.rentalAmount);
        } else if (isMinting) {
            powerToken.mint(to, rentalAgreement.rentalAmount);
        } else if (!isExpiredRentalAgreement) {
            powerToken.forceTransfer(from, to, rentalAgreement.rentalAmount);
        } else {
            revert(Errors.E_RENTAL_TRANSFER_NOT_ALLOWED);
        }
    }

    function getStakingReward(uint256 stakeTokenId) public view returns (uint256) {
        Stake storage stakeInfo = _stakes[stakeTokenId];
        return _calculateStakingReward(stakeInfo.shares, stakeInfo.amount, getReserve());
    }

    function _calculateStakingReward(
        uint256 stakeShares,
        uint256 stakeAmount,
        uint256 reserve
    ) internal view returns (uint256) {
        uint256 liquidity = _sharesToLiquidity(stakeShares, reserve);
        // Due to rounding errors calculated liquidity could be insignificantly less than provided liquidity
        return liquidity <= stakeAmount ? 0 : liquidity - stakeAmount;
    }

    /**
     * @dev Shuts down Enterprise.
     *  * Unlocks all reserves, stakers can withdraw their tokens
     *  * Disables staking
     *  * Disables renting
     *  * Disables swapping
     *
     * !!! Cannot be undone !!!
     */
    function shutdownEnterpriseForever() external whenNotShutdown onlyOwner {
        _enterpriseShutdown = true;
        _usedReserve = 0;
        _streamingReserve = _streamingReserveTarget;

        emit EnterpriseShutdown();
    }
}
