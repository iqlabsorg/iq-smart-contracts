// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

/**
 * @title Errors library
 * @dev Error messages prefix glossary:
 *  - EXP = ExpMath
 *  - ERC20 = ERC20
 *  - ERC721 = ERC721
 *  - ERC721META = ERC721Metadata
 *  - ERC721ENUM = ERC721Enumerable
 *  - DC = DefaultConverter
 *  - DE = DefaultEstimator
 *  - E = Enterprise
 *  - EO = EnterpriseOwnable
 *  - ES = EnterpriseStorage
 *  - IO = InitializableOwnable
 *  - PT = PowerToken
 */
library Errors {
    // common errors
    string public constant NOT_INITIALIZED = "1";
    string public constant ALREADY_INITIALIZED = "2";
    string public constant CALLER_NOT_OWNER = "3";
    string public constant CALLER_NOT_ENTERPRISE = "4";
    string public constant INVALID_ADDRESS = "5";
    string public constant UNREGISTERED_POWER_TOKEN = "6";
    string public constant INVALID_ARRAY_LENGTH = "7";

    // contract specific errors
    string public constant EXP_INVALID_PERIOD = "8";

    string public constant ERC20_INVALID_PERIOD = "9";
    string public constant ERC20_TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE = "10";
    string public constant ERC20_DECREASED_ALLOWANCE_BELOW_ZERO = "11";
    string public constant ERC20_TRANSFER_FROM_THE_ZERO_ADDRESS = "12";
    string public constant ERC20_TRANSFER_TO_THE_ZERO_ADDRESS = "13";
    string public constant ERC20_TRANSFER_AMOUNT_EXCEEDS_BALANCE = "14";
    string public constant ERC20_MINT_TO_THE_ZERO_ADDRESS = "15";
    string public constant ERC20_BURN_FROM_THE_ZERO_ADDRESS = "16";
    string public constant ERC20_BURN_AMOUNT_EXCEEDS_BALANCE = "17";
    string public constant ERC20_APPROVE_FROM_THE_ZERO_ADDRESS = "18";
    string public constant ERC20_APPROVE_TO_THE_ZERO_ADDRESS = "19";

    string public constant ERC721_BALANCE_QUERY_FOR_THE_ZERO_ADDRESS = "20";
    string public constant ERC721_OWNER_QUERY_FOR_NONEXISTENT_TOKEN = "21";
    string public constant ERC721_APPROVAL_TO_CURRENT_OWNER = "22";
    string public constant ERC721_APPROVE_CALLER_IS_NOT_OWNER_NOR_APPROVED_FOR_ALL = "23";
    string public constant ERC721_APPROVED_QUERY_FOR_NONEXISTENT_TOKEN = "24";
    string public constant ERC721_APPROVE_TO_CALLER = "25";
    string public constant ERC721_TRANSFER_CALLER_IS_NOT_OWNER_NOR_APPROVED = "26";
    string public constant ERC721_TRANSFER_TO_NON_ERC721RECEIVER_IMPLEMENTER = "27";
    string public constant ERC721_OPERATOR_QUERY_FOR_NONEXISTENT_TOKEN = "28";
    string public constant ERC721_MINT_TO_THE_ZERO_ADDRESS = "29";
    string public constant ERC721_TOKEN_ALREADY_MINTED = "30";
    string public constant ERC721_TRANSFER_OF_TOKEN_THAT_IS_NOT_OWN = "31";
    string public constant ERC721_TRANSFER_TO_THE_ZERO_ADDRESS = "32";

    string public constant ERC721META_URI_QUERY_FOR_NONEXISTENT_TOKEN = "33";

    string public constant ERC721ENUM_OWNER_INDEX_OUT_OF_BOUNDS = "34";
    string public constant ERC721ENUM_GLOBAL_INDEX_OUT_OF_BOUNDS = "35";

    string public constant DC_UNSUPPORTED_PAIR = "36";

    string public constant DE_INVALID_ENTERPRISE_ADDRESS = "37";
    string public constant DE_LABMDA_NOT_GT_0 = "38";

    string public constant E_CALLER_NOT_BORROW_TOKEN = "39";
    string public constant E_INVALID_BASE_TOKEN_ADDRESS = "40";
    string public constant E_SERVICE_LIMIT_REACHED = "41";
    string public constant E_INVALID_LOAN_DURATION_RANGE = "42";
    string public constant E_SERVICE_HALF_LIFE_NOT_GT_0 = "43";
    string public constant E_UNSUPPORTED_INTEREST_PAYMENT_TOKEN = "44"; // Interest payment token is disabled or not supported
    string public constant E_LOAN_DURATION_OUT_OF_RANGE = "45"; // Loan duration is out of allowed range
    string public constant E_INSUFFICIENT_LIQUIDITY = "46";
    string public constant E_LOAN_COST_SLIPPAGE = "47"; // Effective loan cost exceeds max payment limit set by borrower
    string public constant E_INVALID_LOAN_TOKEN_ID = "48";
    string public constant E_INVALID_LOAN_DURATION = "49";
    string public constant E_FLASH_LIQUIDITY_REMOVAL = "50"; // Adding and removing liquidity in the same block is not allowed
    string public constant E_WRAPPING_NOT_ALLOWED = "51";
    string public constant E_LOAN_TRANSFER_NOT_ALLOWED = "52";
    string public constant E_INVALID_CALLER_WITHIN_BORROWER_GRACE_PERIOD = "53"; // Only borrower can return within borrower grace period
    string public constant E_INVALID_CALLER_WITHIN_ENTERPRISE_GRACE_PERIOD = "54"; // Only borrower or enterprise can return within enterprise grace period

    string public constant EF_INVALID_ENTERPRISE_IMPLEMENTATION_ADDRESS = "55";
    string public constant EF_INVALID_POWER_TOKEN_IMPLEMENTATION_ADDRESS = "56";
    string public constant EF_INVALID_INTEREST_TOKEN_IMPLEMENTATION_ADDRESS = "57";
    string public constant EF_INVALID_BORROW_TOKEN_IMPLEMENTATION_ADDRESS = "58";

    string public constant EO_INVALID_ENTERPRISE_ADDRESS = "59";

    string public constant ES_INVALID_ESTIMATOR_ADDRESS = "60";
    string public constant ES_INVALID_COLLECTOR_ADDRESS = "61";
    string public constant ES_INVALID_VAULT_ADDRESS = "62";
    string public constant ES_INVALID_CONVERTER_ADDRESS = "63";
    string public constant ES_INVALID_BORROWER_LOAN_RETURN_GRACE_PERIOD = "64";
    string public constant ES_INVALID_ENTERPRISE_LOAN_COLLECT_GRACE_PERIOD = "65";
    string public constant ES_INTEREST_HALF_LIFE_NOT_GT_0 = "66";
    string public constant ES_MAX_SERVICE_FEE_PERCENT_EXCEEDED = "67";
    string public constant ES_INVALID_BASE_TOKEN_ADDRESS = "68";
    string public constant ES_INVALID_LOAN_DURATION_RANGE = "69";
    string public constant ES_PERPETUAL_TOKENS_ALREADY_ALLOWED = "70";
    string public constant ES_INVALID_PAYMENT_TOKEN_ADDRESS = "71";
    string public constant ES_UNREGISTERED_PAYMENT_TOKEN = "72";

    string public constant IO_INVALID_OWNER_ADDRESS = "73";

    string public constant PT_INSUFFICIENT_AVAILABLE_BALANCE = "74";
}
