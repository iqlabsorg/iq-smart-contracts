// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./math/ExpMath.sol";
import "./InitializableOwnable.sol";
import "./interfaces/IEnterprise.sol";
import "./interfaces/IInterestToken.sol";
import "./interfaces/IPowerToken.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/ILoanCostEstimator.sol";
import "./EnterpriseConfigurator.sol";

contract Enterprise is IEnterprise {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;
    using Clones for address;

    EnterpriseConfigurator private _configurator;

    /**
     * @dev Total amount of `_liquidityToken`
     */
    uint256 private _reserve;

    /**
     * @dev Available to borrow reserves of `_liquidityToken`
     */
    uint256 private _availableReserve;

    uint256 private _totalShares;

    string private _name;
    mapping(uint256 => LoanInfo) private _loanInfo;
    mapping(uint256 => LiquidityInfo) private _liquidityInfo;
    mapping(IPowerToken => uint256) private _powerTokenIndexMap; // 1 - based because empty value points to 0 index
    IPowerToken[] private _powerTokens;

    event ServiceRegistered(address indexed powerToken, uint32 halfLife, uint112 factor);
    event Borrowed(address indexed powerToken, uint256 tokenId, uint32 from, uint32 to);

    modifier onlyBorrowToken() {
        require(msg.sender == address(_configurator.getBorrowToken()), "Not BorrowToken");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner(), "Ownable: caller is not the owner");
        _;
    }

    modifier registeredPowerToken(IPowerToken powerToken) {
        require(isRegisteredPowerToken(powerToken), "Unknown PowerToken");
        _;
    }

    function initialize(string memory enterpriseName, EnterpriseConfigurator configurator) public override {
        require(address(_configurator) == address(0), "Already initialized");
        require(address(configurator) != address(0), "Invalid configurator");

        _name = enterpriseName;
        _configurator = configurator;
    }

    function registerService(
        string memory serviceName,
        string memory symbol,
        uint32 halfLife,
        uint112 baseRate,
        IERC20Metadata baseToken,
        uint16 serviceFee,
        uint32 minLoanDuration,
        uint32 maxLoanDuration,
        uint112 minGCFee
    ) external onlyOwner {
        require(_powerTokens.length < type(uint16).max, "Cannot register more services");
        require(minLoanDuration <= maxLoanDuration, "Invalid min and max periods");
        require(halfLife > 0, "Invalid half life");

        string memory tokenSymbol = _configurator.getLiquidityToken().symbol();
        string memory powerTokenSymbol = string(abi.encodePacked(tokenSymbol, " ", symbol));

        IPowerToken powerToken = IPowerToken(_configurator.getPowerTokenImpl().clone());

        EnterpriseConfigurator.ServiceConfig memory config =
            EnterpriseConfigurator.ServiceConfig(
                baseRate,
                minGCFee,
                halfLife,
                baseToken,
                minLoanDuration,
                maxLoanDuration,
                serviceFee
            );

        _configurator.addService(powerToken, config);

        powerToken.initialize(serviceName, powerTokenSymbol, _configurator);

        _powerTokens.push(powerToken);
        _powerTokenIndexMap[powerToken] = _powerTokens.length;

        _configurator.getLoanCostEstimator().initializeService(powerToken);
        emit ServiceRegistered(address(powerToken), halfLife, baseRate);
    }

    function borrow(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint256 maximumPayment,
        uint32 duration
    ) external registeredPowerToken(powerToken) {
        require(
            _configurator.isSupportedPaymentToken(paymentToken),
            "Interest payment token is disabled or not supported"
        );
        require(_configurator.isAllowedLoanDuration(powerToken, duration), "Duration is not allowed");
        require(amount <= _availableReserve, "Insufficient reserves");

        uint112 gcFee;
        {
            // scope to avaid stack too deep errors
            (uint112 interest, uint112 serviceFee, uint112 gcFeeAmount) =
                _estimateLoan(powerToken, paymentToken, amount, duration);
            gcFee = gcFeeAmount;

            uint256 loanCost = interest + serviceFee;
            require(loanCost + gcFee <= maximumPayment, "Slippage is too big");

            paymentToken.safeTransferFrom(msg.sender, address(this), loanCost);

            IERC20 liquidityToken = _configurator.getLiquidityToken();

            uint256 convertedLiquidityTokens =
                _configurator.getConverter().convert(paymentToken, loanCost, liquidityToken);

            uint256 serviceLiquidity = (serviceFee * convertedLiquidityTokens) / loanCost;
            liquidityToken.safeTransfer(_configurator.getEnterpriseVault(), serviceLiquidity);

            uint256 poolInterest = convertedLiquidityTokens - serviceLiquidity;

            _availableReserve = _availableReserve - amount + poolInterest;
            _reserve += poolInterest;
        }
        IBorrowToken borrowToken = _configurator.getBorrowToken();
        paymentToken.safeTransferFrom(msg.sender, address(borrowToken), gcFee);
        uint32 borrowingTime = uint32(block.timestamp);
        uint32 maturiryTime = borrowingTime + duration;
        uint256 tokenId = borrowToken.getCounter();
        _loanInfo[tokenId] = LoanInfo(
            amount,
            uint16(_powerTokenIndexMap[powerToken] - 1), // _powerTokenIndexMap is 1-based
            borrowingTime,
            maturiryTime,
            maturiryTime + _configurator.getBorrowerLoanReturnGracePeriod(),
            maturiryTime + _configurator.getEnterpriseLoanCollectGracePeriod(),
            gcFee,
            uint16(_configurator.supportedPaymentTokensIndex(paymentToken))
        );
        emit Borrowed(address(powerToken), tokenId, borrowingTime, maturiryTime);

        _configurator.getLoanCostEstimator().notifyNewLoan(tokenId);

        borrowToken.mint(msg.sender); // also mints PowerTokens
    }

    function estimateLoan(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration
    ) external view registeredPowerToken(powerToken) returns (uint256) {
        require(
            _configurator.isSupportedPaymentToken(paymentToken),
            "Interest payment token is disabled or not supported"
        );
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
        uint112 loanBaseCost = _configurator.getLoanCostEstimator().estimateCost(powerToken, amount, duration);

        uint112 serviceBaseFee = estimateServiceFee(powerToken, loanBaseCost);

        uint256 loanCost =
            _configurator.getConverter().estimateConvert(
                _configurator.getBaseToken(powerToken),
                loanBaseCost,
                paymentToken
            );

        serviceFee = uint112((uint256(serviceBaseFee) * loanCost) / loanBaseCost);
        interest = uint112(loanCost - serviceFee);
        gcFee = estimateGCFee(powerToken, paymentToken, amount);
    }

    function estimateServiceFee(IPowerToken powerToken, uint112 loanCost) internal view returns (uint112) {
        return uint112((uint256(loanCost) * _configurator.getServiceFeePercent(powerToken)) / 10_000);
    }

    function estimateGCFee(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount
    ) internal view returns (uint112) {
        uint16 gcFeePercent = _configurator.getGCFeePercent();
        uint112 gcFeeAmount = uint112((uint256(amount) * gcFeePercent) / 10_000);
        IConverter converter = _configurator.getConverter();
        uint112 minGcFee =
            uint112(
                converter.estimateConvert(
                    _configurator.getBaseToken(powerToken),
                    _configurator.getMinGCFee(powerToken),
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
        require(
            _configurator.isSupportedPaymentToken(paymentToken),
            "Interest payment token is disabled or not supported"
        );
        LoanInfo storage loan = _loanInfo[tokenId];
        IPowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(address(powerToken) != address(0), "Invalid tokenId");
        require(_configurator.isAllowedLoanDuration(powerToken, duration), "Duration is not allowed");
        require(loan.maturityTime + duration >= block.timestamp, "Invalid duration");

        (uint112 interest, uint112 serviceFee, ) = _estimateLoan(powerToken, paymentToken, loan.amount, duration);
        uint256 loanCost = interest + serviceFee;
        require(loanCost <= maximumPayment, "Slippage is too big");

        paymentToken.safeTransferFrom(msg.sender, address(this), loanCost);

        IERC20 liquidityToken = _configurator.getLiquidityToken();

        uint256 convertedLiquidityTokens = _configurator.getConverter().convert(paymentToken, loanCost, liquidityToken);

        uint256 serviceLiquidity = (serviceFee * convertedLiquidityTokens) / loanCost;
        liquidityToken.safeTransfer(_configurator.getEnterpriseVault(), serviceLiquidity);
        uint256 poolInterest = convertedLiquidityTokens - serviceLiquidity;

        _availableReserve += poolInterest;
        _reserve += poolInterest;

        uint32 borrowingTime = loan.maturityTime;
        loan.maturityTime = loan.maturityTime + duration;
        loan.borrowerReturnGraceTime = loan.maturityTime + _configurator.getBorrowerLoanReturnGracePeriod();
        loan.enterpriseCollectGraceTime = loan.maturityTime + _configurator.getEnterpriseLoanCollectGracePeriod();

        _configurator.getLoanCostEstimator().notifyNewLoan(tokenId);

        emit Borrowed(address(powerToken), tokenId, borrowingTime, loan.maturityTime);
    }

    function returnLoan(uint256 tokenId) public {
        LoanInfo storage loan = _loanInfo[tokenId];
        IPowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(address(powerToken) != address(0), "Invalid tokenId");
        IBorrowToken borrowToken = _configurator.getBorrowToken();
        address borrower = borrowToken.ownerOf(tokenId);
        //TODO: implement grace periods for loan borrower and enterprise
        uint32 timestamp = uint32(block.timestamp);

        require(
            loan.borrowerReturnGraceTime < timestamp || msg.sender == borrower,
            "Only borrower can return within borrower grace period"
        );
        require(
            loan.enterpriseCollectGraceTime < timestamp ||
                msg.sender == borrower ||
                msg.sender == _configurator.getEnterpriseCollector(),
            "Only borrower or enterprise can return within enterprise grace period"
        );

        _availableReserve += loan.amount;

        borrowToken.burn(tokenId, msg.sender); // burns PowerTokens, returns gc fee

        delete _loanInfo[tokenId];
    }

    /**
     * One must approve sufficient amount of liquidity tokens to
     * Enterprise address before calling this function
     */
    function addLiquidity(uint256 liquidityAmount) external {
        _configurator.getLiquidityToken().safeTransferFrom(msg.sender, address(this), liquidityAmount);

        uint256 newShares = 0;
        if (_totalShares == 0) {
            newShares = liquidityAmount;
        } else {
            newShares = sharesToLiquidity(liquidityAmount);
        }

        _reserve += liquidityAmount;
        _availableReserve += liquidityAmount;

        uint256 tokenId = _configurator.getInterestToken().mint(msg.sender);

        _liquidityInfo[tokenId] = LiquidityInfo(liquidityAmount, newShares, block.number);

        _totalShares += newShares;
    }

    function withdrawInterest(uint256 tokenId) external {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];
        uint256 shares = liquidityInfo.shares;

        uint256 interest = sharesToLiquidity(shares) - liquidityInfo.amount;
        require(interest <= _availableReserve, "Insufficient liquidity");

        _configurator.getLiquidityToken().safeTransfer(msg.sender, interest);

        uint256 newShares = liquidityToShares(liquidityInfo.amount);
        liquidityInfo.shares = newShares;
        _totalShares -= (shares - newShares);

        _availableReserve -= interest;
        _reserve -= interest;
    }

    function removeLiquidity(uint256 tokenId) external {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];
        require(liquidityInfo.block < block.number, "Cannot add and remove liquidity in same block");
        uint256 shares = liquidityInfo.shares;

        uint256 liquidityWithInterest = sharesToLiquidity(shares);
        require(liquidityWithInterest <= _availableReserve, "Insufficient liquidity");

        _configurator.getInterestToken().burn(tokenId);
        _configurator.getLiquidityToken().safeTransfer(msg.sender, liquidityWithInterest);

        _reserve -= liquidityWithInterest;
        _availableReserve -= liquidityWithInterest;

        _totalShares -= shares;
        delete _liquidityInfo[tokenId];
    }

    function liquidityToShares(uint256 amount) internal view returns (uint256) {
        return (_totalShares * amount) / _reserve;
    }

    function sharesToLiquidity(uint256 shares) internal view returns (uint256) {
        return (_reserve * shares) / _totalShares;
    }

    /**
     * @dev Wraps liquidity tokens to perpetual PowerTokens
     *
     * One must approve sufficient amount of liquidity tokens to
     * corresponding PowerToken address before calling this function
     */
    function wrap(IPowerToken powerToken, uint256 amount) public registeredPowerToken(powerToken) returns (bool) {
        return wrapTo(powerToken, msg.sender, amount);
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
        powerToken.wrap(_configurator.getLiquidityToken(), msg.sender, to, amount);
        return true;
    }

    function unwrap(IPowerToken powerToken, uint256 amount) public registeredPowerToken(powerToken) returns (bool) {
        powerToken.unwrap(_configurator.getLiquidityToken(), msg.sender, amount);
        return true;
    }

    function loanTransfer(
        address from,
        address to,
        uint256 tokenId
    ) external override onlyBorrowToken {
        LoanInfo memory loan = _loanInfo[tokenId];
        IPowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(address(powerToken) != address(0), "Invalid tokenId");

        bool isExpiredBorrow = (block.timestamp > loan.maturityTime);
        bool isMinting = (from == address(0));
        bool isBurning = (to == address(0));
        bool isBorrowReturn = (to == address(this));

        if (isBorrowReturn) {
            returnLoan(tokenId);
        } else if (isBurning) {
            powerToken.burnFrom(from, loan.amount);
        } else if (isMinting) {
            powerToken.mint(to, loan.amount);
        } else if (!isExpiredBorrow) {
            powerToken.forceTransfer(from, to, loan.amount);
        } else {
            revert("Not allowed transfer");
        }
    }

    function getInfo()
        external
        view
        returns (
            uint256 reserve,
            uint256 availableReserve,
            uint256 totalShares,
            string memory name
        )
    {
        return (_reserve, _availableReserve, _totalShares, _name);
    }

    function getPowerTokens() external view returns (IPowerToken[] memory) {
        return _powerTokens;
    }

    function getPowerTokensInfo()
        external
        view
        returns (
            address[] memory addresses,
            string[] memory names,
            string[] memory symbols,
            uint32[] memory halfLifes
        )
    {
        uint256 powerTokenCount = _powerTokens.length;
        addresses = new address[](powerTokenCount);
        names = new string[](powerTokenCount);
        symbols = new string[](powerTokenCount);
        halfLifes = new uint32[](powerTokenCount);

        for (uint256 i = 0; i < powerTokenCount; i++) {
            IPowerToken token = _powerTokens[i];
            addresses[i] = address(token);
            names[i] = token.name();
            symbols[i] = token.symbol();
            halfLifes[i] = _configurator.getHalfLife(token);
        }
    }

    function getLoanInfo(uint256 tokenId) external view override returns (LoanInfo memory) {
        return _loanInfo[tokenId];
    }

    function getLiquidityInfo(uint256 tokenId) external view returns (LiquidityInfo memory) {
        return _liquidityInfo[tokenId];
    }

    function getPowerToken(uint256 index) external view returns (IPowerToken) {
        return _powerTokens[index];
    }

    function getPowerTokenIndex(IPowerToken powerToken) external view returns (int256) {
        return _powerTokenIndexMap[powerToken] == 0 ? -1 : int256(_powerTokenIndexMap[powerToken] - 1);
    }

    function isRegisteredPowerToken(IPowerToken powerToken) public view override returns (bool) {
        return _powerTokenIndexMap[powerToken] > 0;
    }

    function getOwedInterest(uint256 tokenId) external view returns (uint256) {
        LiquidityInfo storage liquidityInfo = _liquidityInfo[tokenId];

        return sharesToLiquidity(liquidityInfo.shares) - liquidityInfo.amount;
    }

    function getReserve() external view override returns (uint256) {
        return _reserve;
    }

    function getAvailableReserve() external view override returns (uint256) {
        return _availableReserve;
    }

    function getConfigurator() external view override returns (EnterpriseConfigurator) {
        return _configurator;
    }

    function owner() public view override returns (address) {
        return _configurator.owner();
    }
}
