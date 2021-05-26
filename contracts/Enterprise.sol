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
import "./EnterpriseConfigurator.sol";

contract Enterprise is IEnterprise {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Detailed;
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
    mapping(IPowerToken => uint256) private _powerTokenIndexMap; // 1 - based because empty value points to 0 index
    IPowerToken[] private _powerTokens;

    event ServiceRegistered(address indexed powerToken, uint32 halfLife, uint112 factor);
    event Borrowed(address indexed powerToken, uint256 tokenId, uint32 from, uint32 to);

    modifier onlyBorrowToken() {
        require(msg.sender == address(_configurator.getBorrowToken()), "Not BorrowToken");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == _configurator.owner(), "Ownable: caller is not the owner");
        _;
    }

    modifier registeredPowerToken(IPowerToken powerToken) {
        require(_powerTokenIndexMap[powerToken] > 0, "Unknown PowerToken");
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
        uint112 factor,
        IERC20 factorToken,
        uint16 serviceFee,
        uint32 minLoanDuration,
        uint32 maxLoanDuration
    ) external onlyOwner {
        require(_powerTokens.length < type(uint16).max, "Cannot register more services");
        require(minLoanDuration <= maxLoanDuration, "Invalid min and max periods");
        require(halfLife > 0, "Invalid half life");

        string memory tokenSymbol = _configurator.getLiquidityToken().symbol();
        string memory powerTokenSymbol = string(abi.encodePacked(tokenSymbol, " ", symbol));

        IPowerToken powerToken = IPowerToken(_configurator.getPowerTokenImpl().clone());

        EnterpriseConfigurator.ServiceConfig memory config =
            EnterpriseConfigurator.ServiceConfig(
                factor,
                halfLife,
                serviceFee,
                serviceFee,
                factorToken,
                uint32(block.timestamp),
                minLoanDuration,
                maxLoanDuration
            );

        _configurator.addService(powerToken, config);

        powerToken.initialize(serviceName, powerTokenSymbol, _configurator);

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
            _configurator.isSupportedPaymentToken(paymentToken),
            "Interest payment token is disabled or not supported"
        );
        require(_configurator.isAllowedLoanDuration(powerToken, duration), "Duration is not allowed");
        require(amount <= _availableReserve, "Insufficient reserves");

        IBorrowToken borrowToken = _configurator.getBorrowToken();
        uint112 lienAmount;
        {
            // scope to avoid stack too deep error
            _configurator.getLoanCostEstimator().estimateCost(powerToken, amount, duration);

            (uint112 interest, uint112 lien, uint112 enterpriseFee) =
                estimateLoan(powerToken, paymentToken, amount, duration);
            lienAmount = lien;

            require(interest + lien + enterpriseFee <= maximumPayment, "Slippage is too big");

            //TODO: send to enterpriseVault according to enterpriseFee
            paymentToken.safeTransferFrom(msg.sender, address(this), interest);

            //uint112 lien = 0; //TODO: store loan return incentivication amount
            paymentToken.safeTransfer(address(borrowToken), lien);

            _availableReserve = _availableReserve - amount + interest;
        }

        uint32 borrowingTime = uint32(block.timestamp);
        uint32 maturiryTime = borrowingTime + duration;
        uint256 tokenId = borrowToken.getCounter();
        _loanInfo[tokenId] = LoanInfo(
            amount,
            uint16(_powerTokenIndexMap[powerToken] - 1), // note: _powerTokenIndexMap is 1-based
            borrowingTime,
            maturiryTime,
            maturiryTime + _configurator.getBorrowerLoanReturnGracePeriod(),
            maturiryTime + _configurator.getEnterpriseLoanCollectGracePeriod(),
            lienAmount,
            uint16(_configurator.supportedPaymentTokensIndex(paymentToken))
        );
        emit Borrowed(address(powerToken), tokenId, borrowingTime, maturiryTime);

        borrowToken.mint(msg.sender); // also mints PowerTokens
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
        ILoanCostEstimator estimator = _configurator.getLoanCostEstimator();
        interest = estimator.estimateCost(powerToken, amount, duration);
        enterpriseFee = uint112(interest * _configurator.getServiceFee(powerToken));

        lien = estimator.estimateLien(powerToken, paymentToken, amount, duration);
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

        (uint112 interest, uint112 lean, uint112 enterpriseFee) =
            estimateLoan(powerToken, paymentToken, loan.amount, duration);
        require(interest <= maximumPayment, "Slippage is too big");

        paymentToken.safeTransferFrom(msg.sender, address(this), interest);

        uint32 borrowingTime = loan.maturityTime;
        loan.maturityTime = loan.maturityTime + duration;
        loan.borrowerReturnGraceTime = loan.maturityTime + _configurator.getBorrowerLoanReturnGracePeriod();
        loan.enterpriseCollectGraceTime = loan.maturityTime + _configurator.getEnterpriseLoanCollectGracePeriod();

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

        borrowToken.burn(tokenId, msg.sender); // burns PowerTokens, returns lien

        delete _loanInfo[tokenId];
    }

    /**
     * One must approve sufficient amount of liquidity tokens to
     * Enterprise address before calling this function
     */
    function addLiquidity(uint256 liquidityAmount) external {
        _configurator.getLiquidityToken().safeTransferFrom(msg.sender, address(this), liquidityAmount);

        _reserve += liquidityAmount;
        _availableReserve += liquidityAmount;

        uint256 newShares = 0;
        if (_totalShares == 0) {
            newShares = liquidityAmount;
        } else {
            newShares = (_totalShares * liquidityAmount) / _reserve;
        }

        _configurator.getInterestToken().mint(msg.sender, newShares);
        _totalShares += newShares;
    }

    function removeLiquidity(uint256 sharesAmount) external {
        uint256 liquidityWithInterest = (_reserve * sharesAmount) / _totalShares;
        require(liquidityWithInterest <= _availableReserve, "Insufficient liquidity");

        _configurator.getInterestToken().burnFrom(msg.sender, sharesAmount);
        _configurator.getLiquidityToken().safeTransfer(msg.sender, liquidityWithInterest);

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
            powerToken.mint(from, loan.amount);
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

    function getConfigurator() external view override returns (EnterpriseConfigurator) {
        return _configurator;
    }
}
