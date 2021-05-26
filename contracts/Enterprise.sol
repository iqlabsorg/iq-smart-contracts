// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./token/IERC20Detailed.sol";
import "./math/ExpMath.sol";
import "./InitializableOwnable.sol";
import "./interfaces/IEnterprise.sol";
import "./interfaces/IInterestToken.sol";
import "./interfaces/IPowerToken.sol";
import "./interfaces/IBorrowToken.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/ILoanCostEstimator.sol";

contract Enterprise is InitializableOwnable, IEnterprise {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Detailed;
    using Clones for address;

    uint256 private constant MAX_ENTERPRISE_FEE = 50; // 50%
    uint32 private constant ENTERPRISE_CONFIG_CHANGE_MINIMUM_GRACE_PERIOD = 24 hours;

    /**
     * @dev ERC20 token backed by enterprise services
     */
    IERC20Detailed private _liquidityToken;

    IInterestToken private _interestToken;
    /**
     * @dev ERC721 token to keep loan
     */
    IBorrowToken private _borrowToken;
    address private _powerTokenImpl;

    /**
     * @dev Total amount of `_liquidityToken`
     */
    uint256 private _reserve;

    /**
     * @dev Available to borrow reserves of `_liquidityToken`
     */
    uint256 private _availableReserve;

    uint256 private _totalShares;

    /**
     * @dev Rate which goes to the enterprise on each loan to cover enterprise operational costs
     */
    uint256 private _enterpriseFee;
    uint256 private _previousEnterpriseFee;

    ILoanCostEstimator _loanCostEstimator;
    ILoanCostEstimator _previousLoanCostEstimator;
    IConverter private _converter;
    address private _enterpriseCollector;
    uint32 private _enterpriseConfigChangeGracePeriod = ENTERPRISE_CONFIG_CHANGE_MINIMUM_GRACE_PERIOD;
    uint32 private _enterpriseFeeChangeTime;
    uint32 private _loanCostEstimatorChangeTime;

    address private _enterpriseVault;
    uint32 private _borrowerLoanReturnGracePeriod;
    uint32 private _enterpriseLoanCollectGracePeriod;

    string private _name;
    mapping(address => int16) private _supportedPaymentTokensIndex;
    address[] private _supportedPaymentTokens;
    mapping(uint256 => LoanInfo) private _loanInfo;
    mapping(IPowerToken => uint256) private _powerTokenIndexMap; // 1 - based because empty value points to 0 index
    IPowerToken[] private _powerTokens;

    event ServiceRegistered(address indexed powerToken, uint32 halfLife, uint112 factor);
    event Borrowed(address indexed powerToken, uint256 tokenId, uint32 from, uint32 to);

    modifier onlyBorrowToken() {
        require(msg.sender == address(_borrowToken), "Not BorrowToken");
        _;
    }

    modifier registeredPowerToken(IPowerToken powerToken) {
        require(_powerTokenIndexMap[powerToken] > 0, "Unknown PowerToken");
        _;
    }

    function initialize(
        string memory enterpriseName,
        address liquidityToken,
        string memory baseUri,
        address interestTokenImpl,
        address borrowTokenImpl,
        address owner
    ) public override {
        require(address(_liquidityToken) == address(0), "Contract already initialized");
        require(liquidityToken != address(0), "Invalid liquidity token address");
        InitializableOwnable.initialize(owner);
        _liquidityToken = IERC20Detailed(liquidityToken);
        string memory symbol = _liquidityToken.symbol();
        {
            // scope to avoid stack too deep error
            _name = enterpriseName;
            _enableInterestToken(address(liquidityToken));

            string memory interestTokenName = string(abi.encodePacked("Interest Bearing ", symbol));
            string memory interestTokenSymbol = string(abi.encodePacked("i", symbol));

            _interestToken = IInterestToken(interestTokenImpl.clone());
            _interestToken.initialize(interestTokenName, interestTokenSymbol);
        }
        {
            // scope to avoid stack too deep error
            string memory borrowTokenName = string(abi.encodePacked("Borrow ", symbol));
            string memory borrowTokenSymbol = string(abi.encodePacked("b", symbol));

            _borrowToken = IBorrowToken(borrowTokenImpl.clone());
            _borrowToken.initialize(borrowTokenName, borrowTokenSymbol, baseUri);
        }
    }

    function initialize2(
        uint256 enterpriseFee,
        address powerTokenImpl,
        uint32 borrowerLoanReturnGracePeriod,
        uint32 enterpriseLoanCollectGracePeriod,
        ILoanCostEstimator estimator,
        IConverter converter
    ) public override {
        require(_powerTokenImpl != address(0), "Already initialized");
        require(borrowerLoanReturnGracePeriod <= enterpriseLoanCollectGracePeriod, "Invalid grace periods");

        _powerTokenImpl = powerTokenImpl;
        _enterpriseFee = enterpriseFee;
        _enterpriseFeeChangeTime = uint32(block.timestamp) + _enterpriseConfigChangeGracePeriod;
        _enterpriseCollector = owner();
        _enterpriseVault = owner();
        _borrowerLoanReturnGracePeriod = borrowerLoanReturnGracePeriod;
        _enterpriseLoanCollectGracePeriod = enterpriseLoanCollectGracePeriod;
        _loanCostEstimator = estimator;
        _converter = converter;
    }

    function registerService(
        string memory serviceName,
        string memory symbol,
        uint32 halfLife,
        uint112 factor,
        uint32 minLoanDuration,
        uint32 maxLoanDuration
    ) external onlyOwner {
        require(_powerTokens.length < type(uint16).max, "Cannot register more services");

        string memory tokenSymbol = _liquidityToken.symbol();
        string memory powerTokenSymbol = string(abi.encodePacked(tokenSymbol, " ", symbol));

        IPowerToken powerToken = IPowerToken(_powerTokenImpl.clone());
        powerToken.initialize(serviceName, powerTokenSymbol, halfLife, factor, minLoanDuration, maxLoanDuration);

        _powerTokens.push(powerToken);
        _powerTokenIndexMap[powerToken] = _powerTokens.length;

        emit ServiceRegistered(address(powerToken), halfLife, factor);
    }

    function borrow(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint256 maximumPayment,
        uint32 duration
    ) external registeredPowerToken(powerToken) {
        require(
            _supportedPaymentTokensIndex[address(paymentToken)] > 0,
            "Interest payment token is disabled or not supported"
        );
        require(powerToken.isAllowedLoanDuration(duration), "Duration is not allowed");
        require(amount <= _availableReserve, "Insufficient reserves");
        uint112 lienAmount;
        {
            // scope to avoid stack too deep error
            getLoanCostEstimator().estimateCost(powerToken, amount, duration);

            (uint112 interest, uint112 lien, uint112 enterpriseFee) =
                estimateLoan(powerToken, paymentToken, amount, duration);
            lienAmount = lien;

            require(interest + lien + enterpriseFee <= maximumPayment, "Slippage is too big");

            //TODO: send to enterpriseVault according to enterpriseFee
            paymentToken.safeTransferFrom(msg.sender, address(this), interest);

            //uint112 lien = 0; //TODO: store loan return incentivication amount
            paymentToken.safeTransfer(address(_borrowToken), lien);

            _availableReserve = _availableReserve - amount + interest;
        }

        uint32 borrowingTime = uint32(block.timestamp);
        uint32 maturiryTime = borrowingTime + duration;
        uint256 tokenId = _borrowToken.getCounter();
        _loanInfo[tokenId] = LoanInfo(
            amount,
            uint16(_powerTokenIndexMap[powerToken] - 1), // note: _powerTokenIndexMap is 1-based
            borrowingTime,
            maturiryTime,
            maturiryTime + _borrowerLoanReturnGracePeriod,
            maturiryTime + _enterpriseLoanCollectGracePeriod,
            lienAmount,
            uint16(_supportedPaymentTokensIndex[address(paymentToken)] - 1)
        );
        emit Borrowed(address(powerToken), tokenId, borrowingTime, maturiryTime);

        _borrowToken.mint(msg.sender); // also mints PowerTokens
    }

    /**
     * @dev Estimates loan cost divided into 3 parts:
     *  1) Pool interest
     *  2) Enterprise operational fee
     *  3) Loan return lien
     *
     * Denominated in `interestPaymentToken` units
     */
    function estimateLoan(
        IPowerToken powerToken,
        IERC20 paymentToken,
        uint112 amount,
        uint32 duration
    )
        public
        view
        registeredPowerToken(powerToken)
        returns (
            uint112 interest,
            uint112 lien,
            uint112 enterpriseFee
        )
    {
        ILoanCostEstimator estimator = getLoanCostEstimator();
        interest = estimator.estimateCost(powerToken, amount, duration);
        enterpriseFee = uint112(interest * getEnterpriseFee());

        lien = estimator.estimateLien(powerToken, paymentToken, amount, duration);
    }

    function reborrow(
        uint256 tokenId,
        IERC20 paymentToken,
        uint256 maximumPayment,
        uint32 duration
    ) external {
        require(
            _supportedPaymentTokensIndex[address(paymentToken)] > 0,
            "Interest payment token is disabled or not supported"
        );
        LoanInfo storage loan = _loanInfo[tokenId];
        IPowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(address(powerToken) != address(0), "Invalid tokenId");
        require(powerToken.isAllowedLoanDuration(duration), "Duration is not allowed");
        require(loan.maturityTime + duration >= block.timestamp, "Invalid duration");

        (uint112 interest, uint112 lean, uint112 enterpriseFee) =
            estimateLoan(powerToken, paymentToken, loan.amount, duration);
        require(interest <= maximumPayment, "Slippage is too big");

        paymentToken.safeTransferFrom(msg.sender, address(this), interest);

        uint32 borrowingTime = loan.maturityTime;
        loan.maturityTime = loan.maturityTime + duration;
        loan.borrowerReturnGraceTime = loan.maturityTime + _borrowerLoanReturnGracePeriod;
        loan.enterpriseCollectGraceTime = loan.maturityTime + _enterpriseLoanCollectGracePeriod;

        emit Borrowed(address(powerToken), tokenId, borrowingTime, loan.maturityTime);
    }

    function returnLoan(uint256 tokenId) public {
        LoanInfo storage loan = _loanInfo[tokenId];
        IPowerToken powerToken = _powerTokens[loan.powerTokenIndex];
        require(address(powerToken) != address(0), "Invalid tokenId");
        address borrower = _borrowToken.ownerOf(tokenId);
        //TODO: implement grace periods for loan borrower and enterprise
        uint32 timestamp = uint32(block.timestamp);

        require(
            loan.borrowerReturnGraceTime < timestamp || msg.sender == borrower,
            "Only borrower can return within borrower grace period"
        );
        require(
            loan.enterpriseCollectGraceTime < timestamp || msg.sender == borrower || msg.sender == _enterpriseCollector,
            "Only borrower or enterprise can return within enterprise grace period"
        );

        _availableReserve += loan.amount;

        _borrowToken.burn(tokenId, msg.sender); // burns PowerTokens, returns lien

        delete _loanInfo[tokenId];
    }

    /**
     * One must approve sufficient amount of liquidity tokens to
     * Enterprise address before calling this function
     */
    function addLiquidity(uint256 liquidityAmount) external {
        _liquidityToken.safeTransferFrom(msg.sender, address(this), liquidityAmount);

        _reserve += liquidityAmount;
        _availableReserve += liquidityAmount;

        uint256 newShares = 0;
        if (_totalShares == 0) {
            newShares = liquidityAmount;
        } else {
            newShares = (_totalShares * liquidityAmount) / _reserve;
        }

        _interestToken.mint(msg.sender, newShares);
        _totalShares += newShares;
    }

    function removeLiquidity(uint256 sharesAmount) external {
        uint256 liquidityWithInterest = (_reserve * sharesAmount) / _totalShares;
        require(liquidityWithInterest <= _availableReserve, "Insufficient liquidity");

        _interestToken.burnFrom(msg.sender, sharesAmount);
        _liquidityToken.safeTransfer(msg.sender, liquidityWithInterest);

        _reserve -= liquidityWithInterest;
        _availableReserve -= liquidityWithInterest;
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
        powerToken.wrap(_liquidityToken, msg.sender, to, amount);
        return true;
    }

    function unwrap(IPowerToken powerToken, uint256 amount) public registeredPowerToken(powerToken) returns (bool) {
        powerToken.unwrap(_liquidityToken, msg.sender, amount);
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
            powerToken.mint(from, loan.amount);
        } else if (!isExpiredBorrow) {
            powerToken.forceTransfer(from, to, loan.amount);
        } else {
            revert("Not allowed transfer");
        }
    }

    function setEnterpriseCollector(address newCollector) public onlyOwner {
        require(newCollector != address(0), "Zero address");
        _enterpriseCollector = newCollector;
    }

    function setEnterpriseVault(address newVault) public onlyOwner {
        require(newVault != address(0), "Zero address");
        _enterpriseVault = newVault;
    }

    function scheduleEnterpriseFee(uint256 newFee) public onlyOwner {
        if (_enterpriseFeeChangeTime <= block.timestamp) {
            _previousEnterpriseFee = _enterpriseFee;
        }
        _enterpriseFee = newFee;
        _enterpriseFeeChangeTime = uint32(block.timestamp) + _enterpriseConfigChangeGracePeriod;
        //TODO: emit event
    }

    function getEnterpriseFee() public view returns (uint256) {
        if (block.timestamp < _enterpriseFeeChangeTime) return _previousEnterpriseFee;

        return _enterpriseFee;
    }

    function setEnterpriseFeeGracePeriod(uint32 newPeriod) public onlyOwner {
        _enterpriseConfigChangeGracePeriod = newPeriod;
    }

    function scheduleLoanCostEstimator(ILoanCostEstimator newEstimator) external onlyOwner {
        require(address(newEstimator) != address(0), "Zero address");
        if (_loanCostEstimatorChangeTime <= block.timestamp) {
            _previousLoanCostEstimator = _loanCostEstimator;
        }
        _loanCostEstimator = newEstimator;
        _loanCostEstimatorChangeTime = uint32(block.timestamp) + _enterpriseConfigChangeGracePeriod;

        //TODO: emit event
    }

    function getLoanCostEstimator() public view returns (ILoanCostEstimator) {
        if (block.timestamp < _loanCostEstimatorChangeTime) return _previousLoanCostEstimator;

        return _loanCostEstimator;
    }

    function getInfo()
        external
        view
        returns (
            uint256 reserve,
            uint256 availableReserve,
            uint256 totalShares,
            string memory name,
            address loanEstimator,
            address previousEstimator,
            uint32 loanEstimatorChangeTime,
            uint256 enterpriseFee,
            uint256 previousEnterpriseFee,
            uint32 enterpriseFeeChangeTime
        )
    {
        return (
            _reserve,
            _availableReserve,
            _totalShares,
            _name,
            address(_loanCostEstimator),
            address(_previousLoanCostEstimator),
            _loanCostEstimatorChangeTime,
            _enterpriseFee,
            _previousEnterpriseFee,
            _enterpriseFeeChangeTime
        );
    }

    function getLiquidityToken() external view returns (IERC20) {
        return _liquidityToken;
    }

    function getInterestToken() external view returns (IInterestToken) {
        return _interestToken;
    }

    function supportedInterestTokensIndex(address token) external view returns (int16) {
        return _supportedPaymentTokensIndex[token];
    }

    function supportedInterestTokens(uint256 index) external view override returns (address) {
        return _supportedPaymentTokens[index];
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
            halfLifes[i] = token.getHalfLife();
        }
    }

    function getLoanInfo(uint256 tokenId) external view override returns (LoanInfo memory) {
        return _loanInfo[tokenId];
    }

    function getPowerToken(uint256 index) external view returns (IPowerToken) {
        return _powerTokens[index];
    }

    function getPowerTokenIndex(IPowerToken powerToken) external view returns (int256) {
        return _powerTokenIndexMap[powerToken] == 0 ? -1 : int256(_powerTokenIndexMap[powerToken] - 1);
    }

    function getReserve() external view override returns (uint256) {
        return _reserve;
    }

    function getAvailableReserve() external view override returns (uint256) {
        return _availableReserve;
    }

    function getEnterpriseCollector() external view returns (address) {
        return _enterpriseCollector;
    }

    function getEnterpriseVault() external view returns (address) {
        return _enterpriseVault;
    }

    function _enableInterestToken(address token) internal {
        if (_supportedPaymentTokensIndex[token] == 0) {
            _supportedPaymentTokens.push(token);
            _supportedPaymentTokensIndex[token] = int16(_supportedPaymentTokens.length);
        } else if (_supportedPaymentTokensIndex[token] < 0) {
            _supportedPaymentTokensIndex[token] = -_supportedPaymentTokensIndex[token];
        }
    }

    function _disableInterestToken(address token) internal {
        require(_supportedPaymentTokensIndex[token] != 0, "Invalid token");

        if (_supportedPaymentTokensIndex[token] > 0) {
            _supportedPaymentTokensIndex[token] = -_supportedPaymentTokensIndex[token];
        }
    }
}
