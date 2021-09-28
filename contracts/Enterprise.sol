// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/IInterestToken.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IPowerToken.sol";
import "./EnterpriseStorage.sol";

contract Enterprise is EnterpriseStorage {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    enum LiquidityChangeType {
        WithdrawInterest,
        Add,
        Remove,
        Increase,
        Decrease
    }

    event LiquidityChanged(
        uint256 indexed interestTokenId,
        address indexed liquidityProvider,
        LiquidityChangeType indexed changeType,
        uint256 amount,
        uint256 totalShares,
        uint256 reserve,
        uint256 usedReserve
    );

    event ServiceRegistered(address indexed powerToken);

    event Borrowed(
        uint256 indexed borrowTokenId,
        address indexed borrower,
        address indexed powerToken,
        address paymentToken,
        uint112 amount,
        uint112 interest,
        uint112 serviceFee,
        uint112 gcFee,
        uint32 borrowingTime,
        uint32 maturityTime,
        uint32 borrowerReturnGraceTime,
        uint32 enterpriseCollectGraceTime,
        uint256 reserve,
        uint256 usedReserve
    );

    event LoanExtended(
        uint256 indexed borrowTokenId,
        address indexed borrower,
        address paymentToken,
        uint112 interest,
        uint112 serviceFee,
        uint32 maturityTime,
        uint32 borrowerReturnGraceTime,
        uint32 enterpriseCollectGraceTime
    );

    event LoanReturned(
        uint256 indexed borrowTokenId,
        address indexed returner,
        address indexed powerToken,
        uint112 amount,
        uint112 gcFee,
        address gcFeeToken,
        uint256 reserve,
        uint256 usedReserve
    );

    function registerService(
        string memory serviceName,
        string memory symbol,
        uint32 gapHalvingPeriod,
        uint112 baseRate,
        IERC20Metadata baseToken,
        uint16 serviceFeePercent,
        uint32 minLoanDuration,
        uint32 maxLoanDuration,
        uint96 minGCFee,
        bool allowsPerpetualTokensForever
    ) external onlyOwner notShutdown {
        require(address(baseToken) != address(0), Errors.E_INVALID_BASE_TOKEN_ADDRESS);
        require(_powerTokens.length < type(uint16).max, Errors.E_SERVICE_LIMIT_REACHED);

        // Deploy new power token.
        PowerToken powerToken = _factory.deployService(getProxyAdmin());
        {
            string memory tokenSymbol = _liquidityToken.symbol();
            string memory powerTokenSymbol = string(abi.encodePacked(tokenSymbol, " ", symbol));
            powerToken.initialize(serviceName, powerTokenSymbol, _liquidityToken.decimals());
        }
        // Configure service parameters.
        powerToken.initialize(
            this,
            baseRate,
            minGCFee,
            gapHalvingPeriod,
            uint16(_powerTokens.length),
            baseToken,
            minLoanDuration,
            maxLoanDuration,
            serviceFeePercent,
            allowsPerpetualTokensForever
        );

        // Complete service registration.
        _powerTokens.push(powerToken);
        _registeredPowerTokens[powerToken] = true;

        emit ServiceRegistered(address(powerToken));
    }

    function borrow(
        PowerToken powerToken,
        IERC20 paymentToken,
        uint112 loanAmount,
        uint32 duration,
        uint256 maxPayment
    ) external notShutdown {
        require(_registeredPowerTokens[powerToken], Errors.UNREGISTERED_POWER_TOKEN);
        require(isSupportedPaymentToken(paymentToken), Errors.E_UNSUPPORTED_INTEREST_PAYMENT_TOKEN);
        require(powerToken.isAllowedLoanDuration(duration), Errors.E_LOAN_DURATION_OUT_OF_RANGE);
        require(loanAmount > 0, Errors.E_INVALID_LOAN_AMOUNT);
        require(loanAmount <= getAvailableReserve(), Errors.E_INSUFFICIENT_LIQUIDITY);

        // Estimate loan cost.
        (uint112 interest, uint112 serviceFee, uint112 gcFee) = powerToken.estimateLoanDetailed(
            paymentToken,
            loanAmount,
            duration
        );
        {
            // Ensure no loan payment slippage.
            // GC fee does not go to the pool but must be accounted for slippage calculation.
            uint256 loanCost = interest + serviceFee;
            require(loanCost + gcFee <= maxPayment, Errors.E_LOAN_COST_SLIPPAGE);

            // Handle loan payment transfer and distribution.
            handleLoanPayment(paymentToken, loanCost, serviceFee, interest);

            // Transfer GC fee to the borrow token contract.
            paymentToken.safeTransferFrom(msg.sender, address(_borrowToken), gcFee);

            // Update used reserve.
            _usedReserve += loanAmount;
        }

        // Calculate loan timestamps.
        uint32 borrowingTime = uint32(block.timestamp);
        uint32 maturityTime = borrowingTime + duration;
        uint32 borrowerReturnGraceTime = maturityTime + _borrowerLoanReturnGracePeriod;
        uint32 enterpriseCollectGraceTime = maturityTime + _enterpriseLoanCollectGracePeriod;

        // Precalculate borrow token ID to associate loan information.
        uint256 borrowTokenId = _borrowToken.getNextTokenId();
        _loanInfo[borrowTokenId] = LoanInfo(
            loanAmount,
            powerToken.getIndex(),
            borrowingTime,
            maturityTime,
            borrowerReturnGraceTime,
            enterpriseCollectGraceTime,
            gcFee,
            uint16(getPaymentTokenIndex(paymentToken))
        );

        // Mint borrow token to the borrower address.
        // This also mints corresponding amount of PowerTokens.
        assert(_borrowToken.mint(msg.sender) == borrowTokenId);

        // Notify power token contract about new loan.
        powerToken.notifyNewLoan(borrowTokenId);

        emit Borrowed(
            borrowTokenId,
            msg.sender,
            address(powerToken),
            address(paymentToken),
            loanAmount,
            interest,
            serviceFee,
            gcFee,
            borrowingTime,
            maturityTime,
            borrowerReturnGraceTime,
            enterpriseCollectGraceTime,
            getReserve(),
            _usedReserve
        );
    }

    function reborrow(
        uint256 borrowTokenId,
        IERC20 paymentToken,
        uint32 duration,
        uint256 maxPayment
    ) external notShutdown {
        require(isSupportedPaymentToken(paymentToken), Errors.E_UNSUPPORTED_INTEREST_PAYMENT_TOKEN);
        LoanInfo storage loan = _loanInfo[borrowTokenId];
        require(loan.amount > 0, Errors.E_INVALID_LOAN_TOKEN_ID);
        PowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(powerToken.isAllowedLoanDuration(duration), Errors.E_LOAN_DURATION_OUT_OF_RANGE);
        require(loan.maturityTime + duration >= block.timestamp, Errors.E_INVALID_LOAN_DURATION);

        // Emulate loan return to ensure correct reserves during new loan estimation.
        _usedReserve -= loan.amount;
        // Estimate new loan cost.
        (uint112 interest, uint112 serviceFee, ) = powerToken.estimateLoanDetailed(paymentToken, loan.amount, duration);
        // Emulate borrowing.
        unchecked {
            // Safe since used reserve value was successfully decreased earlier.
            _usedReserve += loan.amount;
        }

        // Ensure no loan payment slippage.
        uint256 loanCost = interest + serviceFee;
        require(loanCost <= maxPayment, Errors.E_LOAN_COST_SLIPPAGE);

        // Handle loan payment transfer and distribution.
        handleLoanPayment(paymentToken, loanCost, serviceFee, interest);

        // Calculate new loan timestamps.
        uint32 newMaturityTime = loan.maturityTime + duration;
        uint32 newBorrowerReturnGraceTime = newMaturityTime + _borrowerLoanReturnGracePeriod;
        uint32 newEnterpriseCollectGraceTime = newMaturityTime + _enterpriseLoanCollectGracePeriod;

        // Update loan details.
        loan.maturityTime = newMaturityTime;
        loan.borrowerReturnGraceTime = newBorrowerReturnGraceTime;
        loan.enterpriseCollectGraceTime = newEnterpriseCollectGraceTime;

        // Notify power token contract about new loan.
        powerToken.notifyNewLoan(borrowTokenId);

        emit LoanExtended(
            borrowTokenId,
            msg.sender,
            address(paymentToken),
            interest,
            serviceFee,
            newMaturityTime,
            newBorrowerReturnGraceTime,
            newEnterpriseCollectGraceTime
        );
    }

    function handleLoanPayment(
        IERC20 paymentToken,
        uint256 loanCost,
        uint256 serviceFee,
        uint112 interest
    ) internal {
        // Transfer loan payment to the enterprise.
        paymentToken.safeTransferFrom(msg.sender, address(this), loanCost);

        // Initially assume loan cost payment is made in liquidity tokens.
        uint256 loanCostInLiquidityTokens = loanCost;
        uint256 serviceFeeInLiquidityTokens = serviceFee;
        uint112 interestInLiquidityTokens = interest;

        // Should the loan cost payment be made in tokens other than liquidity tokens,
        // the payment amount gets converted to liquidity tokens automatically.
        if (address(paymentToken) != address(_liquidityToken)) {
            paymentToken.approve(address(_converter), loanCost);
            loanCostInLiquidityTokens = _converter.convert(paymentToken, loanCost, _liquidityToken);
            serviceFeeInLiquidityTokens = (serviceFee * loanCostInLiquidityTokens) / loanCost;
            interestInLiquidityTokens = uint112(loanCostInLiquidityTokens - serviceFeeInLiquidityTokens);
        }

        // Transfer service fee (liquidity tokens) to the enterprise vault.
        _liquidityToken.safeTransfer(_enterpriseVault, serviceFeeInLiquidityTokens);
        // Update streaming target.
        _increaseStreamingReserveTarget(interestInLiquidityTokens);
    }

    function returnLoan(uint256 borrowTokenId) external {
        LoanInfo memory loan = _loanInfo[borrowTokenId];
        require(loan.amount > 0, Errors.E_INVALID_LOAN_TOKEN_ID);
        address borrower = _borrowToken.ownerOf(borrowTokenId);
        uint32 timestamp = uint32(block.timestamp);

        require(
            loan.borrowerReturnGraceTime < timestamp || msg.sender == borrower,
            Errors.E_INVALID_CALLER_WITHIN_BORROWER_GRACE_PERIOD
        );
        require(
            loan.enterpriseCollectGraceTime < timestamp || msg.sender == borrower || msg.sender == _enterpriseCollector,
            Errors.E_INVALID_CALLER_WITHIN_ENTERPRISE_GRACE_PERIOD
        );

        if (!_enterpriseShutdown) {
            // When enterprise is shut down, usedReserve equals zero.
            _usedReserve -= loan.amount;
        }

        emit LoanReturned(
            borrowTokenId,
            msg.sender,
            address(_powerTokens[loan.powerTokenIndex]),
            loan.amount,
            loan.gcFee,
            _paymentTokens[loan.gcFeeTokenIndex],
            getReserve(),
            _usedReserve
        );

        // Burn borrow token and delete associated loan information.
        // This also burns corresponding amount of PowerTokens and transfers GC fee to the transaction sender address.
        _borrowToken.burn(borrowTokenId, msg.sender);
        delete _loanInfo[borrowTokenId];
    }

    /**
     * One must approve sufficient amount of liquidity tokens to
     * Enterprise address before calling this function
     */
    function addLiquidity(uint256 amount) external notShutdown {
        // Transfer liquidity tokens to the enterprise.
        _liquidityToken.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate number of new shares to be issued.
        uint256 reserve = getReserve();
        uint256 newShares = (_totalShares == 0 ? amount : _liquidityToShares(amount, reserve));

        // Increase total reserves & shares.
        _increaseReserveAndShares(amount, newShares);

        // Mint new interest token and associate liquidity information.
        uint256 interestTokenId = _interestToken.mint(msg.sender);
        _liquidityInfo[interestTokenId] = LiquidityInfo(amount, newShares, block.number);

        emit LiquidityChanged(
            interestTokenId,
            msg.sender,
            LiquidityChangeType.Add,
            amount,
            _totalShares,
            reserve + amount,
            _usedReserve
        );
    }

    function withdrawInterest(uint256 interestTokenId) external onlyInterestTokenOwner(interestTokenId) {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[interestTokenId];

        // Calculate accrued interest & check if reserves are sufficient to fulfill withdrawal request.
        uint256 accruedInterest = getAccruedInterest(interestTokenId);
        require(accruedInterest <= getAvailableReserve(), Errors.E_INSUFFICIENT_LIQUIDITY);

        // Transfer liquidity tokens to the interest token owner.
        _liquidityToken.safeTransfer(msg.sender, accruedInterest);

        // Recalculate the remaining number of shares after interest withdrawal.
        uint256 reserve = getReserve();
        uint256 remainingShares = _liquidityToShares(liquidityInfo.amount, reserve);

        // Decrease total reserves & shares.
        _decreaseReserveAndShares(accruedInterest, liquidityInfo.shares - remainingShares);

        // Update interest token liquidity information.
        liquidityInfo.shares = remainingShares;

        emit LiquidityChanged(
            interestTokenId,
            msg.sender,
            LiquidityChangeType.WithdrawInterest,
            accruedInterest,
            _totalShares,
            reserve - accruedInterest,
            _usedReserve
        );
    }

    function removeLiquidity(uint256 interestTokenId) external onlyInterestTokenOwner(interestTokenId) {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[interestTokenId];
        require(liquidityInfo.block < block.number, Errors.E_FLASH_LIQUIDITY_REMOVAL);

        // Calculate owing liquidity amount including accrued interest.
        uint256 shares = liquidityInfo.shares;
        uint256 reserve = getReserve();
        uint256 liquidityWithInterest = _sharesToLiquidity(shares, reserve);
        require(liquidityWithInterest <= getAvailableReserve(), Errors.E_INSUFFICIENT_LIQUIDITY);

        // Transfer liquidity tokens to the interest token owner.
        _liquidityToken.safeTransfer(msg.sender, liquidityWithInterest);

        // Decrease total reserves & shares.
        _decreaseReserveAndShares(liquidityWithInterest, shares);

        // Burn interest token and delete associated liquidity information.
        _interestToken.burn(interestTokenId);
        delete _liquidityInfo[interestTokenId];

        emit LiquidityChanged(
            interestTokenId,
            msg.sender,
            LiquidityChangeType.Remove,
            liquidityWithInterest,
            _totalShares,
            reserve - liquidityWithInterest,
            _usedReserve
        );
    }

    function decreaseLiquidity(uint256 interestTokenId, uint256 amount)
        external
        onlyInterestTokenOwner(interestTokenId)
    {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[interestTokenId];
        require(liquidityInfo.block < block.number, Errors.E_FLASH_LIQUIDITY_REMOVAL);
        require(liquidityInfo.amount >= amount, Errors.E_INSUFFICIENT_LIQUIDITY);
        require(amount <= getAvailableReserve(), Errors.E_INSUFFICIENT_LIQUIDITY);

        // Transfer liquidity tokens to the interest token owner.
        _liquidityToken.safeTransfer(msg.sender, amount);

        // Calculate number of shares to be destroyed.
        uint256 reserve = getReserve();
        uint256 shares = _liquidityToShares(amount, reserve);
        if (shares > liquidityInfo.shares) {
            shares = liquidityInfo.shares;
        }

        // Decrease total reserves & shares.
        _decreaseReserveAndShares(amount, shares);

        // Update interest token liquidity information.
        unchecked {
            liquidityInfo.shares -= shares;
            liquidityInfo.amount -= amount;
        }

        emit LiquidityChanged(
            interestTokenId,
            msg.sender,
            LiquidityChangeType.Decrease,
            amount,
            _totalShares,
            reserve - amount,
            _usedReserve
        );
    }

    function increaseLiquidity(uint256 interestTokenId, uint256 amount)
        external
        notShutdown
        onlyInterestTokenOwner(interestTokenId)
    {
        // Transfer liquidity tokens to the enterprise.
        _liquidityToken.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate number of new shares to be issued.
        uint256 reserve = getReserve();
        uint256 newShares = (_totalShares == 0 ? amount : _liquidityToShares(amount, reserve));

        // Increase total reserves & shares.
        _increaseReserveAndShares(amount, newShares);

        // Update interest token liquidity information.
        LiquidityInfo storage liquidityInfo = _liquidityInfo[interestTokenId];
        liquidityInfo.amount += amount;
        liquidityInfo.shares += newShares;
        liquidityInfo.block = block.number;

        emit LiquidityChanged(
            interestTokenId,
            msg.sender,
            LiquidityChangeType.Increase,
            amount,
            _totalShares,
            reserve + amount,
            _usedReserve
        );
    }

    function estimateLoan(
        PowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration
    ) external view notShutdown returns (uint256) {
        require(_registeredPowerTokens[powerToken], Errors.UNREGISTERED_POWER_TOKEN);

        return powerToken.estimateLoan(paymentToken, amount, duration);
    }

    function _increaseReserveAndShares(uint256 reserveDelta, uint256 sharesDelta) internal {
        _totalShares += sharesDelta;
        _fixedReserve += reserveDelta;
        emit FixedReserveChanged(_fixedReserve);
    }

    function _decreaseReserveAndShares(uint256 reserveDelta, uint256 sharesDelta) internal {
        _totalShares -= sharesDelta;
        if (_fixedReserve >= reserveDelta) {
            unchecked {
                _fixedReserve -= reserveDelta;
            }
        } else {
            uint256 streamingReserve = _flushStreamingReserve();
            _fixedReserve = _fixedReserve + streamingReserve - reserveDelta;
        }
        emit FixedReserveChanged(_fixedReserve);
    }

    function _liquidityToShares(uint256 amount, uint256 reserve) internal view returns (uint256) {
        return (_totalShares * amount) / reserve;
    }

    function _sharesToLiquidity(uint256 shares, uint256 reserve) internal view returns (uint256) {
        return (reserve * shares) / _totalShares;
    }

    function loanTransfer(
        address from,
        address to,
        uint256 borrowTokenId
    ) external onlyBorrowToken {
        uint112 amount = _loanInfo[borrowTokenId].amount;
        require(amount > 0, Errors.E_INVALID_LOAN_TOKEN_ID);

        bool isExpiredBorrow = (block.timestamp > _loanInfo[borrowTokenId].maturityTime);
        bool isMinting = (from == address(0));
        bool isBurning = (to == address(0));
        PowerToken powerToken = _powerTokens[_loanInfo[borrowTokenId].powerTokenIndex];

        if (isBurning) {
            powerToken.burnFrom(from, amount);
        } else if (isMinting) {
            powerToken.mint(to, amount);
        } else if (!isExpiredBorrow) {
            powerToken.forceTransfer(from, to, amount);
        } else {
            revert(Errors.E_LOAN_TRANSFER_NOT_ALLOWED);
        }
    }

    function getAccruedInterest(uint256 interestTokenId) public view returns (uint256) {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[interestTokenId];

        uint256 liquidity = _sharesToLiquidity(liquidityInfo.shares, getReserve());
        // Due to rounding errors calculated liquidity could be insignificantly
        // less than provided liquidity
        return liquidity <= liquidityInfo.amount ? 0 : liquidity - liquidityInfo.amount;
    }

    /**
     * @dev Shuts down Enterprise.
     *  * Unlocks all reserves, LPs can withdraw their tokens
     *  * Disables adding liquidity
     *  * Disables borrowing
     *  * Disables wrapping
     *
     * !!! Cannot be undone !!!
     */
    function shutdownEnterpriseForever() external notShutdown onlyOwner {
        _enterpriseShutdown = true;
        _usedReserve = 0;
        _streamingReserve = _streamingReserveTarget;

        emit EnterpriseShutdown();
    }
}
