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

    event ServiceRegistered(address indexed powerToken, uint32 gapHalvingPeriod, uint112 factor);
    event Borrowed(address indexed powerToken, uint256 tokenId, uint32 from, uint32 to);

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

        PowerToken powerToken = _factory.deployService(getProxyAdmin());
        {
            string memory tokenSymbol = _liquidityToken.symbol();
            string memory powerTokenSymbol = string(abi.encodePacked(tokenSymbol, " ", symbol));
            powerToken.initialize(serviceName, powerTokenSymbol);
        }
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
        _powerTokens.push(powerToken);
        _registeredPowerTokens[powerToken] = true;

        emit ServiceRegistered(address(powerToken), gapHalvingPeriod, baseRate);
    }

    function borrow(
        PowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration,
        uint256 maxPayment
    ) external notShutdown {
        require(_registeredPowerTokens[powerToken], Errors.UNREGISTERED_POWER_TOKEN);
        require(isSupportedPaymentToken(paymentToken), Errors.E_UNSUPPORTED_INTEREST_PAYMENT_TOKEN);
        require(powerToken.isAllowedLoanDuration(duration), Errors.E_LOAN_DURATION_OUT_OF_RANGE);
        require(amount > 0, Errors.E_INVALID_LOAN_AMOUNT);
        require(amount <= getAvailableReserve(), Errors.E_INSUFFICIENT_LIQUIDITY);

        uint112 gcFee;
        {
            // scope to avoid stack too deep errors
            (uint112 interest, uint112 serviceFee, uint112 gcFeeAmount) =
                powerToken.estimateLoanDetailed(paymentToken, amount, duration);
            gcFee = gcFeeAmount;

            uint256 loanCost = interest + serviceFee;
            require(loanCost + gcFee <= maxPayment, Errors.E_LOAN_COST_SLIPPAGE);

            paymentToken.safeTransferFrom(msg.sender, address(this), loanCost);

            uint256 convertedLiquidityTokens = loanCost;

            if (address(paymentToken) != address(powerToken.getBaseToken())) {
                paymentToken.approve(address(_converter), loanCost);
                convertedLiquidityTokens = _converter.convert(paymentToken, loanCost, _liquidityToken);
            }

            uint256 serviceLiquidity = (serviceFee * convertedLiquidityTokens) / loanCost;
            _liquidityToken.safeTransfer(_enterpriseVault, serviceLiquidity);

            _usedReserve += amount;

            uint112 poolInterest = uint112(convertedLiquidityTokens - serviceLiquidity);
            _increaseStreamingReserveTarget(poolInterest);
        }
        paymentToken.safeTransferFrom(msg.sender, address(_borrowToken), gcFee);
        uint32 borrowingTime = uint32(block.timestamp);
        uint32 maturityTime = borrowingTime + duration;
        uint256 tokenId = _borrowToken.getNextTokenId();
        _loanInfo[tokenId] = LoanInfo(
            amount,
            powerToken.getIndex(),
            borrowingTime,
            maturityTime,
            maturityTime + _borrowerLoanReturnGracePeriod,
            maturityTime + _enterpriseLoanCollectGracePeriod,
            gcFee,
            uint16(paymentTokenIndex(paymentToken))
        );

        assert(_borrowToken.mint(msg.sender) == tokenId); // also mints PowerTokens

        powerToken.notifyNewLoan(tokenId);

        emit Borrowed(address(powerToken), tokenId, borrowingTime, maturityTime);
    }

    function reborrow(
        uint256 tokenId,
        IERC20 paymentToken,
        uint32 duration,
        uint256 maxPayment
    ) external notShutdown {
        require(isSupportedPaymentToken(paymentToken), Errors.E_UNSUPPORTED_INTEREST_PAYMENT_TOKEN);
        LoanInfo storage loan = _loanInfo[tokenId];
        require(loan.amount > 0, Errors.E_INVALID_LOAN_TOKEN_ID);
        PowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(powerToken.isAllowedLoanDuration(duration), Errors.E_LOAN_DURATION_OUT_OF_RANGE);
        require(loan.maturityTime + duration >= block.timestamp, Errors.E_INVALID_LOAN_DURATION);

        // emulating here loan return
        _usedReserve -= loan.amount;

        (uint112 interest, uint112 serviceFee, ) = powerToken.estimateLoanDetailed(paymentToken, loan.amount, duration);

        // emulating here borrow
        unchecked {_usedReserve += loan.amount;} // safe, because previously we successfully decreased it
        uint256 loanCost = interest + serviceFee;

        require(loanCost <= maxPayment, Errors.E_LOAN_COST_SLIPPAGE);

        paymentToken.safeTransferFrom(msg.sender, address(this), loanCost);
        uint256 convertedLiquidityTokens = loanCost;
        if (address(paymentToken) != address(powerToken.getBaseToken())) {
            paymentToken.approve(address(_converter), loanCost);
            convertedLiquidityTokens = _converter.convert(paymentToken, loanCost, _liquidityToken);
        }

        uint256 serviceLiquidity = (serviceFee * convertedLiquidityTokens) / loanCost;
        _liquidityToken.safeTransfer(_enterpriseVault, serviceLiquidity);

        uint112 poolInterest = uint112(convertedLiquidityTokens - serviceLiquidity);
        _increaseStreamingReserveTarget(poolInterest);

        uint32 borrowingTime = loan.maturityTime;
        loan.maturityTime = loan.maturityTime + duration;
        loan.borrowerReturnGraceTime = loan.maturityTime + _borrowerLoanReturnGracePeriod;
        loan.enterpriseCollectGraceTime = loan.maturityTime + _enterpriseLoanCollectGracePeriod;

        powerToken.notifyNewLoan(tokenId);

        emit Borrowed(address(powerToken), tokenId, borrowingTime, loan.maturityTime);
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

    function returnLoan(uint256 tokenId) public {
        LoanInfo storage loan = _loanInfo[tokenId];
        require(loan.amount > 0, Errors.E_INVALID_LOAN_TOKEN_ID);
        address borrower = _borrowToken.ownerOf(tokenId);
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
            _usedReserve -= loan.amount;
        }

        _borrowToken.burn(tokenId, msg.sender); // burns PowerTokens, returns gc fee

        delete _loanInfo[tokenId];
    }

    /**
     * One must approve sufficient amount of liquidity tokens to
     * Enterprise address before calling this function
     */
    function addLiquidity(uint256 liquidityAmount) external notShutdown {
        _liquidityToken.safeTransferFrom(msg.sender, address(this), liquidityAmount);

        uint256 newShares = (_totalShares == 0 ? liquidityAmount : _liquidityToShares(liquidityAmount));

        _fixedReserve += liquidityAmount;

        uint256 tokenId = _interestToken.mint(msg.sender);

        _liquidityInfo[tokenId] = LiquidityInfo(liquidityAmount, newShares, block.number);

        _totalShares += newShares;
    }

    function withdrawInterest(uint256 tokenId) external onlyInterestTokenOwner(tokenId) {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];
        uint256 shares = liquidityInfo.shares;

        uint256 interest = getOwedInterest(tokenId);
        require(interest <= getAvailableReserve(), Errors.E_INSUFFICIENT_LIQUIDITY);

        _liquidityToken.safeTransfer(msg.sender, interest);

        uint256 newShares = _liquidityToShares(liquidityInfo.amount);
        liquidityInfo.shares = newShares;
        _totalShares -= (shares - newShares);

        _decreaseReserve(interest);
    }

    function removeLiquidity(uint256 tokenId) external onlyInterestTokenOwner(tokenId) {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];
        require(liquidityInfo.block < block.number, Errors.E_FLASH_LIQUIDITY_REMOVAL);
        uint256 shares = liquidityInfo.shares;

        uint256 liquidityWithInterest = _sharesToLiquidity(shares);
        require(liquidityWithInterest <= getAvailableReserve(), Errors.E_INSUFFICIENT_LIQUIDITY);

        _interestToken.burn(tokenId);
        _liquidityToken.safeTransfer(msg.sender, liquidityWithInterest);
        _totalShares -= shares;

        _decreaseReserve(liquidityWithInterest);
        delete _liquidityInfo[tokenId];
    }

    function decreaseLiquidity(uint256 tokenId, uint256 amount) external onlyInterestTokenOwner(tokenId) {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];
        require(liquidityInfo.block < block.number, Errors.E_FLASH_LIQUIDITY_REMOVAL);
        require(liquidityInfo.amount >= amount, Errors.E_INSUFFICIENT_LIQUIDITY);
        require(amount <= getAvailableReserve(), Errors.E_INSUFFICIENT_LIQUIDITY);
        _liquidityToken.safeTransfer(msg.sender, amount);

        uint256 shares = _liquidityToShares(amount);
        if (shares > liquidityInfo.shares) {
            shares = liquidityInfo.shares;
        }
        unchecked {
            liquidityInfo.shares -= shares;
            liquidityInfo.amount -= amount;
            _totalShares -= shares;
        }
        _decreaseReserve(amount);
    }

    function increaseLiquidity(uint256 tokenId, uint256 amount) external notShutdown onlyInterestTokenOwner(tokenId) {
        _liquidityToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 newShares = (_totalShares == 0 ? amount : _liquidityToShares(amount));

        _fixedReserve += amount;
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];
        liquidityInfo.amount += amount;
        liquidityInfo.shares += newShares;
        liquidityInfo.block = block.number;
        _totalShares += newShares;
    }

    function _decreaseReserve(uint256 delta) internal {
        if (_fixedReserve >= delta) {
            unchecked {_fixedReserve -= delta;}
        } else {
            uint256 streamingReserve = _flushStreamingReserve();

            _fixedReserve = _fixedReserve + streamingReserve - delta;
        }
    }

    function _liquidityToShares(uint256 amount) internal view returns (uint256) {
        return (_totalShares * amount) / getReserve();
    }

    function _sharesToLiquidity(uint256 shares) internal view returns (uint256) {
        return (getReserve() * shares) / _totalShares;
    }

    function loanTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external onlyBorrowToken {
        uint112 amount = _loanInfo[tokenId].amount;
        require(amount > 0, Errors.E_INVALID_LOAN_TOKEN_ID);

        bool isExpiredBorrow = (block.timestamp > _loanInfo[tokenId].maturityTime);
        bool isMinting = (from == address(0));
        bool isBurning = (to == address(0));
        PowerToken powerToken = _powerTokens[_loanInfo[tokenId].powerTokenIndex];

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

    function getOwedInterest(uint256 tokenId) public view returns (uint256) {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];

        uint256 liquidity = _sharesToLiquidity(liquidityInfo.shares);
        // Due to rounding errors calculated liquidity could be insignificantly
        // less than provided liquidity
        return liquidity <= liquidityInfo.amount ? 0 : liquidity - liquidityInfo.amount;
    }

    /**
     * @dev Shuts down Enterprise.
     *  * Unlocks all reverves, LPs can withdraw their tokens
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
    }
}
