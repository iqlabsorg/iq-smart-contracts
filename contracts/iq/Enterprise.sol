// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../token/IERC20Detailed.sol";
import "./ExpMath.sol";
import "./InitializableOwnable.sol";
import "./interfaces/IEnterprise.sol";
import "./interfaces/IInterestToken.sol";
import "./interfaces/IPowerToken.sol";
import "./interfaces/IBorrowToken.sol";

contract Enterprise is InitializableOwnable, IEnterprise {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Detailed;
    using Clones for address;

    struct State {
        uint112 plannedBalance;
        uint32 timestamp;
    }

    IERC20Detailed private _liquidityToken;
    IInterestToken private _interestToken;
    IBorrowToken private _borrowToken;
    address private _powerTokenImpl;
    uint256 private _reserve;
    uint256 private _availableReserve;
    uint256 private _totalShares;
    string private _name;
    mapping(address => mapping(uint32 => State)) private _states;
    mapping(address => int16) private _supportedInterestTokensIndex;
    address[] private _supportedInterestTokens;
    mapping(uint256 => BorrowInfo) private _borrowInfo;
    IPowerToken[] private _powerTokens;
    mapping(address => uint112) private _collectedInterest;

    event ServiceRegistered(
        address indexed powerToken,
        uint32 halfLife,
        uint112 factor,
        uint32 interestRateHalvingPeriod
    );
    event Borrowed(address indexed powerToken, uint256 tokenId);
    event Lended(address indexed lender, uint256 liquidityAmount, uint256 shares, uint256 tokenId);
    event Withdraw(address indexed lender, uint256 liquidityAmount, uint256 shares, uint256 tokenId);

    function initialize(
        string memory enterpriseName,
        address liquidityToken,
        string memory baseUri,
        address interestTokenImpl,
        address borrowTokenImpl,
        address powerTokenImpl,
        address owner
    ) public override {
        require(address(_liquidityToken) == address(0), "Contract already initialized");
        require(liquidityToken != address(0), "Invalid liquidity token address");
        this.initialize(owner);

        _liquidityToken = IERC20Detailed(liquidityToken);
        _name = enterpriseName;
        _enableInterestToken(address(liquidityToken));
        string memory symbol = _liquidityToken.symbol();

        string memory iTokenName = string(abi.encodePacked("Interest Bearing ", symbol));
        string memory iTokenSymbol = string(abi.encodePacked("i", symbol));

        _interestToken = IInterestToken(interestTokenImpl.clone());
        _interestToken.initialize(iTokenName, iTokenSymbol);

        string memory bTokenName = string(abi.encodePacked("Borrow ", symbol));
        string memory bTokenSymbol = string(abi.encodePacked("b", symbol));

        _borrowToken = IBorrowToken(borrowTokenImpl.clone());
        _borrowToken.initialize(this, bTokenName, bTokenSymbol, baseUri, address(this));

        _powerTokenImpl = powerTokenImpl;
    }

    function registerService(
        string memory serviceName,
        string memory symbol,
        uint32 halfLife,
        uint112 factor,
        uint32 interestRateHalvingPeriod,
        uint32[] memory allowedLoanDurations
    ) external onlyOwner {
        string memory tokenSymbol = _liquidityToken.symbol();
        string memory powerTokenSymbol = string(abi.encodePacked(tokenSymbol, " ", symbol));

        IPowerToken powerToken = IPowerToken(_powerTokenImpl.clone());
        powerToken.initialize(
            serviceName,
            powerTokenSymbol,
            halfLife,
            allowedLoanDurations,
            factor,
            interestRateHalvingPeriod,
            address(this)
        );
        powerToken.addOwner(address(_borrowToken));

        _powerTokens.push(powerToken);

        emit ServiceRegistered(address(powerToken), halfLife, factor, interestRateHalvingPeriod);
    }

    function borrow(
        IPowerToken powerToken,
        IERC20 interestPaymentToken,
        uint112 amount,
        uint256 maximumInterest,
        uint32 duration
    ) external {
        require(
            _supportedInterestTokensIndex[address(interestPaymentToken)] > 0,
            "Interest payment token is disabled or not supported"
        );
        require(powerToken.isAllowedLoanDuration(duration), "Duration is not allowed");
        require(amount <= _availableReserve, "Insufficient reserves");

        uint112 interest = estimateBorrow(powerToken, interestPaymentToken, amount, duration, uint32(block.timestamp));
        require(interest <= maximumInterest, "Slippage is too big");

        interestPaymentToken.safeTransferFrom(msg.sender, address(this), interest);

        _availableReserve = _availableReserve - amount + interest;

        uint256 tokenId = _borrowToken.mint(msg.sender);
        powerToken.mint(msg.sender, amount, true);

        _borrowInfo[tokenId] = BorrowInfo(
            powerToken,
            uint32(block.timestamp),
            uint32(block.timestamp) + duration,
            amount
        );

        State storage state = _updateState(tokenId);
        state.plannedBalance += interest;

        emit Borrowed(address(powerToken), tokenId);
    }

    function estimateBorrow(
        IPowerToken powerToken,
        IERC20 interestPaymentToken,
        uint112 amount,
        uint32 duration,
        uint32 estimateAtTimestamp
    ) public view returns (uint112 result) {
        require(powerToken.isAllowedLoanDuration(duration), "Duration not allowed");
        require(amount <= _availableReserve, "Too low available reserves");

        uint112 c0 = uint112((uint256(amount) * duration * powerToken.getFactor()) >> (112 - 1));
        uint112 halfLife =
            ExpMath.halfLife(
                powerToken.getLastDeal(),
                c0,
                powerToken.getInterestRateHalvingPeriod(),
                estimateAtTimestamp
            );

        // TODO: SafeMath, analyze bits
        uint256 uintInterestInLiquidityTokens = (halfLife * _reserve) / (_availableReserve - amount);
        uint112 interestInLiquidityTokens =
            uintInterestInLiquidityTokens > type(uint112).max
                ? type(uint112).max
                : uint112(uintInterestInLiquidityTokens);

        return convertTo(interestInLiquidityTokens, interestPaymentToken);
    }

    function returnBorrowed(uint256 tokenId) external override {
        BorrowInfo storage borrowed = _borrowInfo[tokenId];
        require(address(borrowed.powerToken) != address(0), "Invalid tokenId");

        address holder = _borrowToken.ownerOf(tokenId);
        //TODO: implement grace periods for loan holder and enterprise
        require(
            borrowed.to <= uint32(block.timestamp) || holder == msg.sender,
            "Only holder can return before expiration"
        );

        _updateState(tokenId);

        _availableReserve += borrowed.amount;

        _borrowToken.burn(tokenId); // also burns PowerTokens

        delete _borrowInfo[tokenId];
    }

    function convertTo(uint112 liquidityAmount, IERC20 payment) internal view returns (uint112) {
        //TODO: apply convertation
        require(address(payment) == address(_liquidityToken), "Other payment options are not supported yet");

        return liquidityAmount;
    }

    function convertFrom(uint112 interestAmount, IERC20 payment) internal view returns (uint112) {
        //TODO: apply convertation
        require(address(payment) == address(_liquidityToken), "Other payment options are not supported yet");

        return interestAmount;
    }

    function lend(uint256 liquidityAmount, uint32 halfWithdrawPeriod) external {
        _liquidityToken.safeTransferFrom(msg.sender, address(this), liquidityAmount);

        _reserve += liquidityAmount;
        _availableReserve += liquidityAmount;

        uint256 totalLiquidity = getTotalLiquidity();
        uint256 newShares = 0;
        if (_totalShares == 0) {
            newShares = liquidityAmount;
        } else {
            newShares = (_totalShares * liquidityAmount) / totalLiquidity;
        }
        uint256 tokenId = halfWithdrawPeriod;

        _interestToken.mint(msg.sender, newShares);
        _totalShares += newShares;
        emit Lended(msg.sender, liquidityAmount, newShares, tokenId);
    }

    function withdrawLiquidity(
        uint256 sharesAmount,
        uint256 tokenId,
        address interestToken
    ) external {
        uint256 balance = _interestToken.balanceOf(msg.sender);
        require(balance >= sharesAmount, "Insufficient balance");

        uint256 liquidityWithInterest = (getTotalLiquidity() * sharesAmount) / _totalShares;
        require(interestToken == address(_liquidityToken), "Not supported yet");
        require(liquidityWithInterest <= _availableReserve, "Insufficient liquidity");

        _liquidityToken.safeTransfer(msg.sender, liquidityWithInterest);

        _reserve -= liquidityWithInterest;
        _availableReserve -= liquidityWithInterest;

        emit Withdraw(msg.sender, liquidityWithInterest, sharesAmount, tokenId);
    }

    function getTotalLiquidity() internal view returns (uint256 result) {
        result = _reserve;
        uint256 n = _supportedInterestTokens.length;
        for (uint256 i = 0; i < n; i++) {
            address tokenAddress = _supportedInterestTokens[i];

            result += convertFrom(_collectedInterest[tokenAddress], IERC20(tokenAddress));
        }
    }

    function _updateState(uint256 tokenId) internal returns (State storage state) {
        BorrowInfo storage borrowed = _borrowInfo[tokenId];
        require(address(borrowed.powerToken) != address(0), "Invalid tokenId");

        address interestPaymentToken = _supportedInterestTokens[0];
        uint32 duration = uint32(borrowed.to - borrowed.from);

        state = _states[interestPaymentToken][duration];

        uint112 interest =
            state.plannedBalance -
                ExpMath.halfLife(state.timestamp, state.plannedBalance, duration, uint32(block.timestamp));

        if (interestPaymentToken == address(_liquidityToken)) {
            _reserve += interest;
            _availableReserve += interest;
        } else {
            _collectedInterest[interestPaymentToken] += interest;
        }

        state.plannedBalance -= interest;
        state.timestamp = uint32(block.timestamp);
    }

    function wrap(IPowerToken token, uint256 amount) external returns (bool) {
        _liquidityToken.safeTransferFrom(msg.sender, address(this), amount);
        token.mint(msg.sender, amount, false);
        return true;
    }

    function wrapTo(
        IPowerToken token,
        address to,
        uint256 amount
    ) external returns (bool) {
        _liquidityToken.safeTransferFrom(msg.sender, address(this), amount);
        token.mint(to, amount, false);
        return true;
    }

    function unwrap(IPowerToken token, uint256 amount) external returns (bool) {
        token.burnFrom(msg.sender, amount, false);
        _liquidityToken.safeTransfer(msg.sender, amount);
        return true;
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

    function getLiquidityToken() external view returns (IERC20Detailed) {
        return _liquidityToken;
    }

    function iToken() external view returns (IInterestToken) {
        return _interestToken;
    }

    function states(address token, uint32 duration) external view returns (State memory) {
        return _states[token][duration];
    }

    function supportedInterestTokensIndex(address token) external view returns (int16) {
        return _supportedInterestTokensIndex[token];
    }

    function supportedInterestTokens(uint256 index) external view returns (address) {
        return _supportedInterestTokens[index];
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

    function getBorrowInfo(uint256 tokenId) external view override returns (BorrowInfo memory) {
        return _borrowInfo[tokenId];
    }

    function getPowerToken(uint256 index) external view returns (IPowerToken) {
        return _powerTokens[index];
    }

    function collectedInterest(address account) external view returns (uint112) {
        return _collectedInterest[account];
    }

    function _enableInterestToken(address token) internal {
        if (_supportedInterestTokensIndex[token] == 0) {
            _supportedInterestTokens.push(token);
            _supportedInterestTokensIndex[token] = int16(_supportedInterestTokens.length);
        } else if (_supportedInterestTokensIndex[token] < 0) {
            _supportedInterestTokensIndex[token] = -_supportedInterestTokensIndex[token];
        }
    }

    function _disableInterestToken(address token) internal {
        require(_supportedInterestTokensIndex[token] != 0, "Invalid token");

        if (_supportedInterestTokensIndex[token] > 0) {
            _supportedInterestTokensIndex[token] = -_supportedInterestTokensIndex[token];
        }
    }
}
