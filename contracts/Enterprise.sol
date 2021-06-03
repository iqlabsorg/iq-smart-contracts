// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./math/ExpMath.sol";
import "./interfaces/IInterestToken.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IEstimator.sol";
import "./PowerToken.sol";
import "./EnterpriseStorage.sol";

contract Enterprise is EnterpriseStorage {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;
    using Clones for address;

    event ServiceRegistered(address indexed powerToken, uint32 halfLife, uint112 factor);
    event Borrowed(address indexed powerToken, uint256 tokenId, uint32 from, uint32 to);

    modifier onlyBorrowToken() {
        require(msg.sender == address(_borrowToken), "Not BorrowToken");
        _;
    }

    function registerService(
        string memory serviceName,
        string memory symbol,
        uint32 halfLife,
        uint112 baseRate,
        IERC20Metadata baseToken,
        uint16 serviceFeePercent,
        uint32 minLoanDuration,
        uint32 maxLoanDuration,
        uint96 minGCFee,
        bool allowsPerpetualTokensForever
    ) external onlyOwner {
        require(address(baseToken) != address(0), "Invalid Base Token");
        require(_powerTokens.length < type(uint16).max, "Cannot register more services");
        require(minLoanDuration <= maxLoanDuration, "Invalid min and max periods");
        require(halfLife > 0, "Invalid half life");

        PowerToken powerToken = PowerToken(_powerTokenImpl.clone());
        string memory tokenSymbol = _liquidityToken.symbol();
        string memory powerTokenSymbol = string(abi.encodePacked(tokenSymbol, " ", symbol));
        powerToken.initialize(serviceName, powerTokenSymbol, this);

        ServiceConfig memory config =
            ServiceConfig(
                baseRate,
                minGCFee,
                halfLife,
                uint16(_powerTokens.length),
                baseToken,
                minLoanDuration,
                maxLoanDuration,
                serviceFeePercent,
                allowsPerpetualTokensForever
            );

        _serviceConfig[powerToken] = config;
        _powerTokens.push(powerToken);

        _estimator.initializeService(powerToken);
        emit ServiceRegistered(address(powerToken), halfLife, baseRate);
    }

    function borrow(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint256 maximumPayment,
        uint32 duration
    ) external registeredPowerToken(powerToken) {
        require(isSupportedPaymentToken(paymentToken), "Interest payment token is disabled or not supported");
        require(isServiceAllowedLoanDuration(powerToken, duration), "Duration is not allowed");
        require(amount <= getAvailableReserve(), "Insufficient reserves");

        uint112 gcFee;
        {
            // scope to avoid stack too deep errors
            (uint112 interest, uint112 serviceFee, uint112 gcFeeAmount) =
                _estimateLoan(powerToken, paymentToken, amount, duration);
            gcFee = gcFeeAmount;

            uint256 loanCost = interest + serviceFee;
            require(loanCost + gcFee <= maximumPayment, "Slippage is too big");

            paymentToken.safeTransferFrom(msg.sender, address(this), loanCost);

            uint256 convertedLiquidityTokens = _converter.convert(paymentToken, loanCost, _liquidityToken);

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
            _serviceConfig[powerToken].index,
            borrowingTime,
            maturityTime,
            maturityTime + _borrowerLoanReturnGracePeriod,
            maturityTime + _enterpriseLoanCollectGracePeriod,
            gcFee,
            uint16(paymentTokenIndex(paymentToken))
        );

        assert(_borrowToken.mint(msg.sender) == tokenId); // also mints PowerTokens

        _estimator.notifyNewLoan(tokenId);

        emit Borrowed(address(powerToken), tokenId, borrowingTime, maturityTime);
    }

    function estimateLoan(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration
    ) external view registeredPowerToken(powerToken) returns (uint256) {
        require(isSupportedPaymentToken(paymentToken), "Interest payment token is disabled or not supported");
        require(isServiceAllowedLoanDuration(powerToken, duration), "Duration is not allowed");

        (uint112 interest, uint112 serviceFee, uint112 gcFee) =
            _estimateLoan(powerToken, paymentToken, amount, duration);

        return interest + serviceFee + gcFee;
    }

    /**
     * @dev Estimates loan cost divided into 3 parts:
     *  1) Pool interest
     *  2) Service operational fee
     *  3) Loan return lien
     */
    function _estimateLoan(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration
    )
        internal
        view
        returns (
            uint112 interest,
            uint112 serviceFee,
            uint112 gcFee
        )
    {
        uint112 loanBaseCost = _estimator.estimateCost(powerToken, amount, duration);

        uint112 serviceBaseFee = _estimateServiceFee(powerToken, loanBaseCost);

        uint256 loanCost = _converter.estimateConvert(_serviceConfig[powerToken].baseToken, loanBaseCost, paymentToken);

        serviceFee = uint112((uint256(serviceBaseFee) * loanCost) / loanBaseCost);
        interest = uint112(loanCost - serviceFee);
        gcFee = _estimateGCFee(powerToken, paymentToken, amount);
    }

    function _estimateServiceFee(IPowerToken powerToken, uint112 loanCost) internal view returns (uint112) {
        return uint112((uint256(loanCost) * _serviceConfig[powerToken].serviceFeePercent) / 10_000);
    }

    function _estimateGCFee(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount
    ) internal view returns (uint112) {
        uint112 gcFeeAmount = uint112((uint256(amount) * _gcFeePercent) / 10_000);
        uint112 minGcFee =
            uint112(
                _converter.estimateConvert(
                    _serviceConfig[powerToken].baseToken,
                    _serviceConfig[powerToken].minGCFee,
                    paymentToken
                )
            );
        return gcFeeAmount < minGcFee ? minGcFee : gcFeeAmount;
    }

    function reborrow(
        uint256 tokenId,
        IERC20 paymentToken,
        uint256 maximumPayment,
        uint32 duration
    ) external {
        require(isSupportedPaymentToken(paymentToken), "Interest payment token is disabled or not supported");
        LoanInfo storage loan = _loanInfo[tokenId];
        IPowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(address(powerToken) != address(0), "Invalid tokenId");
        require(isServiceAllowedLoanDuration(powerToken, duration), "Duration is not allowed");
        require(loan.maturityTime + duration >= block.timestamp, "Invalid duration");

        // emulating here loan return
        _usedReserve -= loan.amount;

        (uint112 interest, uint112 serviceFee, ) = _estimateLoan(powerToken, paymentToken, loan.amount, duration);

        // emulating here borrow
        _usedReserve += loan.amount;

        uint256 loanCost = interest + serviceFee;
        require(loanCost <= maximumPayment, "Slippage is too big");

        paymentToken.safeTransferFrom(msg.sender, address(this), loanCost);

        uint256 convertedLiquidityTokens = _converter.convert(paymentToken, loanCost, _liquidityToken);

        uint256 serviceLiquidity = (serviceFee * convertedLiquidityTokens) / loanCost;
        _liquidityToken.safeTransfer(_enterpriseVault, serviceLiquidity);

        uint112 poolInterest = uint112(convertedLiquidityTokens - serviceLiquidity);
        _increaseStreamingReserveTarget(poolInterest);

        uint32 borrowingTime = loan.maturityTime;
        loan.maturityTime = loan.maturityTime + duration;
        loan.borrowerReturnGraceTime = loan.maturityTime + _borrowerLoanReturnGracePeriod;
        loan.enterpriseCollectGraceTime = loan.maturityTime + _enterpriseLoanCollectGracePeriod;

        _estimator.notifyNewLoan(tokenId);

        emit Borrowed(address(powerToken), tokenId, borrowingTime, loan.maturityTime);
    }

    function returnLoan(uint256 tokenId) public {
        _returnLoan(tokenId, msg.sender);
    }

    /**
     * One must approve sufficient amount of liquidity tokens to
     * Enterprise address before calling this function
     */
    function addLiquidity(uint256 liquidityAmount) external {
        _liquidityToken.safeTransferFrom(msg.sender, address(this), liquidityAmount);

        uint256 newShares = 0;
        if (_totalShares == 0) {
            newShares = liquidityAmount;
        } else {
            newShares = _sharesToLiquidity(liquidityAmount);
        }

        _fixedReserve += liquidityAmount;

        uint256 tokenId = _interestToken.mint(msg.sender);

        _liquidityInfo[tokenId] = LiquidityInfo(liquidityAmount, newShares, block.number);

        _totalShares += newShares;
    }

    function withdrawInterest(uint256 tokenId) external {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];
        uint256 shares = liquidityInfo.shares;

        uint256 interest = _sharesToLiquidity(shares) - liquidityInfo.amount;
        require(interest <= getAvailableReserve(), "Insufficient liquidity");

        _liquidityToken.safeTransfer(msg.sender, interest);

        uint256 newShares = _liquidityToShares(liquidityInfo.amount);
        liquidityInfo.shares = newShares;
        _totalShares -= (shares - newShares);

        _decreaseReserve(interest);
    }

    function removeLiquidity(uint256 tokenId) external {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];
        require(liquidityInfo.block < block.number, "Cannot add and remove liquidity in same block");
        uint256 shares = liquidityInfo.shares;

        uint256 liquidityWithInterest = _sharesToLiquidity(shares);
        require(liquidityWithInterest <= getAvailableReserve(), "Insufficient liquidity");

        _interestToken.burn(tokenId);
        _liquidityToken.safeTransfer(msg.sender, liquidityWithInterest);
        _totalShares -= shares;

        _decreaseReserve(liquidityWithInterest);
        delete _liquidityInfo[tokenId];
    }

    function _decreaseReserve(uint256 delta) internal {
        if (_fixedReserve >= delta) {
            _fixedReserve -= delta;
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

    /**
     * @dev Wraps liquidity tokens to perpetual PowerTokens
     *
     * One must approve sufficient amount of liquidity tokens to
     * corresponding PowerToken address before calling this function
     */
    function wrap(IPowerToken powerToken, uint256 amount) public registeredPowerToken(powerToken) returns (bool) {
        return _wrapTo(powerToken, msg.sender, amount);
    }

    /**
     * @dev Wraps liquidity tokens to perpetual PowerTokens
     *
     * One must approve sufficient amount of liquidity tokens to
     * corresponding PowerToken address before calling this function
     */
    function wrapTo(
        IPowerToken powerToken,
        address to,
        uint256 amount
    ) public registeredPowerToken(powerToken) returns (bool) {
        return _wrapTo(powerToken, to, amount);
    }

    function _wrapTo(
        IPowerToken powerToken,
        address to,
        uint256 amount
    ) internal returns (bool) {
        require(_serviceConfig[powerToken].allowsPerpetual == true, "Wrapping is not allowed");

        powerToken.wrap(_liquidityToken, msg.sender, to, amount);
        return true;
    }

    function unwrap(IPowerToken powerToken, uint256 amount) external registeredPowerToken(powerToken) returns (bool) {
        powerToken.unwrap(_liquidityToken, msg.sender, amount);
        return true;
    }

    function loanTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external onlyBorrowToken {
        LoanInfo memory loan = _loanInfo[tokenId];
        IPowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(address(powerToken) != address(0), "Invalid tokenId");

        bool isExpiredBorrow = (block.timestamp > loan.maturityTime);
        bool isMinting = (from == address(0));
        bool isBurning = (to == address(0));

        if (isBurning) {
            powerToken.burnFrom(from, loan.amount);
        } else if (isMinting) {
            powerToken.mint(to, loan.amount);
        } else if (!isExpiredBorrow) {
            powerToken.forceTransfer(from, to, loan.amount);
        } else {
            revert("Not allowed transfer");
        }
    }

    function getOwedInterest(uint256 tokenId) external view returns (uint256) {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];

        return _sharesToLiquidity(liquidityInfo.shares) - liquidityInfo.amount;
    }

    function _returnLoan(uint256 tokenId, address account) internal {
        LoanInfo storage loan = _loanInfo[tokenId];
        IPowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(address(powerToken) != address(0), "Invalid tokenId");
        address borrower = _borrowToken.ownerOf(tokenId);
        uint32 timestamp = uint32(block.timestamp);

        require(
            loan.borrowerReturnGraceTime < timestamp || account == borrower,
            "Only borrower can return within borrower grace period"
        );
        require(
            loan.enterpriseCollectGraceTime < timestamp || account == borrower || account == _enterpriseCollector,
            "Only borrower or enterprise can return within enterprise grace period"
        );

        _usedReserve -= loan.amount;

        _borrowToken.burn(tokenId, account); // burns PowerTokens, returns gc fee

        delete _loanInfo[tokenId];
    }
}
