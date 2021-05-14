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

contract Enterprise is InitializableOwnable, IEnterprise {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Detailed;
    using Clones for address;

    uint8 internal constant REFUND_CURVATURE = 1;

    struct Service {
        uint32[] allowedLoanDurations;
        uint256 borrowed;
        uint112 factor;
        uint32 lastDeal;
        uint32 interestRateHalvingPeriod;
        // demand, borrowing rate, volumes
    }

    struct State {
        uint112 plannedBalance;
        uint32 timestamp;
    }

    IERC20Detailed private _liquidityToken;
    IInterestToken private _iToken;
    address private _powerTokenImpl;
    uint256 private _reserve;
    uint256 private _availableReserve;
    uint256 private _totalShares;
    string private _baseUri;
    string private _name;
    mapping(IPowerToken => Service) private _services;
    mapping(address => mapping(uint32 => mapping(uint8 => State))) private _states;
    mapping(address => int16) private _supportedInterestTokensIndex;
    address[] private _supportedInterestTokens;
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
        address liquidityToken_,
        string memory baseUri_,
        address interestTokenImpl,
        address powerTokenImpl,
        address owner
    ) public override {
        require(address(_liquidityToken) == address(0), "Contract already initialized");
        require(liquidityToken_ != address(0), "Invalid liquidity token address");
        this.initialize(owner);

        _liquidityToken = IERC20Detailed(liquidityToken_);
        _baseUri = baseUri_;
        _name = enterpriseName;
        _enableInterestToken(address(liquidityToken_));
        string memory symbol = _liquidityToken.symbol();

        string memory iTokenName = string(abi.encodePacked("Interest Bearing ", symbol));
        string memory iTokenSymbol = string(abi.encodePacked("i", symbol));

        _iToken = IInterestToken(interestTokenImpl.clone());
        _iToken.initialize(address(this), iTokenName, iTokenSymbol, _baseUri);
        _powerTokenImpl = powerTokenImpl;
    }

    function registerService(
        string memory serviceName,
        string memory symbol,
        uint32 halfLife,
        uint112 factor,
        uint32 interestRateHalvingPeriod,
        uint32[] memory _allowedLoanDurations
    ) external onlyOwner {
        string memory tokenSymbol = _liquidityToken.symbol();
        string memory powerTokenSymbol = string(abi.encodePacked(tokenSymbol, " ", symbol));

        IPowerToken powerToken = IPowerToken(_powerTokenImpl.clone());
        powerToken.initialize(serviceName, powerTokenSymbol, _baseUri, halfLife);

        _services[powerToken].allowedLoanDurations = _allowedLoanDurations;
        _services[powerToken].factor = factor;
        _services[powerToken].interestRateHalvingPeriod = interestRateHalvingPeriod;
        _services[powerToken].lastDeal = uint32(block.timestamp);

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
        require(isAllowedLoanDuration(powerToken, duration), "Duration not allowed");
        require(amount <= _availableReserve, "Insufficient reserves");

        uint112 interest = estimateBorrow(powerToken, interestPaymentToken, amount, duration, uint32(block.timestamp));
        require(interest <= maximumInterest, "Slippage too big");

        interestPaymentToken.safeTransferFrom(msg.sender, address(this), interest);

        _availableReserve -= amount;
        _services[powerToken].borrowed += amount;

        uint256 tokenId =
            _getTokenId(
                uint32(block.timestamp),
                uint32(block.timestamp) + duration,
                REFUND_CURVATURE,
                uint16(_supportedInterestTokensIndex[address(interestPaymentToken)]),
                interest
            );

        powerToken.mint(msg.sender, tokenId, amount, "");

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
        require(isAllowedLoanDuration(powerToken, duration), "Duration not allowed");
        require(amount <= _availableReserve, "Too low available reserves");

        Service memory service = _services[powerToken];

        uint112 c0 = uint112((uint256(amount) * duration * service.factor) >> (112 - REFUND_CURVATURE));
        uint112 halfLife =
            ExpMath.halfLife(service.lastDeal, c0, service.interestRateHalvingPeriod, estimateAtTimestamp);

        // TODO: SafeMath, analyze bits
        uint256 uintInterestInLiquidityTokens = (halfLife * _reserve) / (_availableReserve - amount);
        uint112 interestInLiquidityTokens =
            uintInterestInLiquidityTokens > type(uint112).max
                ? type(uint112).max
                : uint112(uintInterestInLiquidityTokens);

        return convertTo(interestInLiquidityTokens, interestPaymentToken);
    }

    function burn(
        IPowerToken powerToken,
        uint256 tokenId,
        uint112 amount
    ) external {
        //TODO: allow burn other users token (if it is expired)
        uint256 balance = powerToken.balanceOf(msg.sender, tokenId);
        require(amount <= balance, "Can't burn more that balance");

        (address paymentToken, uint112 refund) =
            estimateRefund(powerToken, msg.sender, tokenId, amount, uint32(block.timestamp));

        State storage state = _updateState(tokenId);
        state.plannedBalance -= refund;

        _availableReserve += amount;
        _services[powerToken].borrowed -= amount;

        IERC20(paymentToken).safeTransfer(msg.sender, refund);

        powerToken.burn(msg.sender, tokenId, refund);
    }

    function estimateRefund(
        IPowerToken powerToken,
        address tokenHolder,
        uint256 tokenId,
        uint112 amountToBurn,
        uint32 estimateAt
    ) public view returns (address paymentToken, uint112 amount) {
        (uint32 from, uint32 to, uint8 curvature, uint16 tokenIndex, uint112 interest) = _extractTokenId(tokenId);
        paymentToken = _supportedInterestTokens[tokenIndex - 1];

        uint256 balance = powerToken.balanceOf(tokenHolder, tokenId);
        if (balance == 0) {
            return (paymentToken, 0);
        }

        amount = uint112(
            (ExpMath.halfLife(uint32(from), interest, uint32(to - from) / curvature, estimateAt) * amountToBurn) /
                balance
        );
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

        _iToken.mint(msg.sender, tokenId, newShares);
        _totalShares += newShares;
        emit Lended(msg.sender, liquidityAmount, newShares, tokenId);
    }

    function withdrawLiquidity(
        uint256 sharesAmount,
        uint256 tokenId,
        address interestToken
    ) external {
        uint256 balance = _iToken.balanceOf(msg.sender, tokenId);
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
        (uint32 from, uint32 to, uint8 curvature, uint16 tokenIndex, ) = _extractTokenId(tokenId);
        address interestPaymentToken = _supportedInterestTokens[tokenIndex - 1];
        uint32 duration = uint32(to - from);

        state = _states[interestPaymentToken][duration][curvature];

        uint112 interest =
            state.plannedBalance -
                ExpMath.halfLife(state.timestamp, state.plannedBalance, duration / curvature, uint32(block.timestamp));

        if (interestPaymentToken == address(_liquidityToken)) {
            _reserve += interest;
            _availableReserve += interest;
        } else {
            _collectedInterest[interestPaymentToken] += interest;
        }

        state.plannedBalance -= interest;
        state.timestamp = uint32(block.timestamp);
    }

    function _getTokenId(
        uint32 from,
        uint32 to,
        uint8 curvature,
        uint16 tokenIndex,
        uint112 interest
    ) internal pure returns (uint256 tokenId) {
        tokenId =
            (uint256(from) << 224) |
            (uint256(to) << 192) |
            (uint256(curvature) << 184) |
            (uint256(tokenIndex) << 168) |
            interest;
    }

    function _extractTokenId(uint256 tokenId)
        internal
        pure
        returns (
            uint32 from,
            uint32 to,
            uint8 curvature,
            uint16 tokenIndex,
            uint112 interest
        )
    {
        from = uint32((tokenId >> 224) & type(uint32).max);
        to = uint32((tokenId >> 192) & type(uint32).max);
        curvature = uint8((tokenId >> 184) & type(uint8).max);
        tokenIndex = uint16((tokenId >> 168) & type(uint16).max);
        interest = uint112(tokenId & type(uint112).max);
        require(from > 0, "Invalid from");
        require(to > 0, "Invalid to");
        require(curvature > 0, "Invalid curvature");
        require(interest > 0, "Invalid interest");
    }

    function isAllowedLoanDuration(IPowerToken token, uint32 duration) public view returns (bool allowed) {
        Service storage service = _services[token];
        uint256 n = service.allowedLoanDurations.length;
        for (uint256 i = 0; i < n; i++) {
            if (service.allowedLoanDurations[i] == duration) return true;
        }
        return false;
    }

    function getServices() external view returns (Service[] memory) {
        uint256 tokenCount = _powerTokens.length;
        Service[] memory result = new Service[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            result[i] = _services[_powerTokens[i]];
        }
        return result;
    }

    function getInfo()
        external
        view
        returns (
            uint256 reserve,
            uint256 availableReserve,
            uint256 totalShares,
            string memory baseUri,
            string memory name,
            address owner
        )
    {
        return (_reserve, _availableReserve, _totalShares, _baseUri, _name, this.owner());
    }

    function liquidityToken() external view returns (IERC20Detailed) {
        return _liquidityToken;
    }

    function iToken() external view returns (IInterestToken) {
        return _iToken;
    }

    function services(IPowerToken powerToken) external view returns (Service memory) {
        return _services[powerToken];
    }

    function states(
        address token,
        uint32 duration,
        uint8 curvature
    ) external view returns (State memory) {
        return _states[token][duration][curvature];
    }

    function supportedInterestTokensIndex(address token) external view returns (int16) {
        return _supportedInterestTokensIndex[token];
    }

    function supportedInterestTokens(uint256 index) external view returns (address) {
        return _supportedInterestTokens[index];
    }

    function powerTokens(uint256 index) external view returns (IPowerToken) {
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
