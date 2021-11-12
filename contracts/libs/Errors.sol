// SPDX-License-Identifier: MIT
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
    string internal constant NOT_INITIALIZED = "1";
    string internal constant ALREADY_INITIALIZED = "2";
    string internal constant CALLER_NOT_OWNER = "3";
    string internal constant CALLER_NOT_ENTERPRISE = "4";
    string internal constant INVALID_ADDRESS = "5";
    string internal constant UNREGISTERED_POWER_TOKEN = "6";
    string internal constant INVALID_ARRAY_LENGTH = "7";

    // contract specific errors
    string internal constant EXP_INVALID_PERIOD = "8";

    string internal constant ERC20_INVALID_PERIOD = "9";
    string internal constant ERC20_TRANSFER_AMOUNT_EXCEEDS_ALLOWANCE = "10";
    string internal constant ERC20_DECREASED_ALLOWANCE_BELOW_ZERO = "11";
    string internal constant ERC20_TRANSFER_FROM_THE_ZERO_ADDRESS = "12";
    string internal constant ERC20_TRANSFER_TO_THE_ZERO_ADDRESS = "13";
    string internal constant ERC20_TRANSFER_AMOUNT_EXCEEDS_BALANCE = "14";
    string internal constant ERC20_MINT_TO_THE_ZERO_ADDRESS = "15";
    string internal constant ERC20_BURN_FROM_THE_ZERO_ADDRESS = "16";
    string internal constant ERC20_BURN_AMOUNT_EXCEEDS_BALANCE = "17";
    string internal constant ERC20_APPROVE_FROM_THE_ZERO_ADDRESS = "18";
    string internal constant ERC20_APPROVE_TO_THE_ZERO_ADDRESS = "19";

    string internal constant ERC721_BALANCE_QUERY_FOR_THE_ZERO_ADDRESS = "20";
    string internal constant ERC721_OWNER_QUERY_FOR_NONEXISTENT_TOKEN = "21";
    string internal constant ERC721_APPROVAL_TO_CURRENT_OWNER = "22";
    string internal constant ERC721_APPROVE_CALLER_IS_NOT_OWNER_NOR_APPROVED_FOR_ALL = "23";
    string internal constant ERC721_APPROVED_QUERY_FOR_NONEXISTENT_TOKEN = "24";
    string internal constant ERC721_APPROVE_TO_CALLER = "25";
    string internal constant ERC721_TRANSFER_CALLER_IS_NOT_OWNER_NOR_APPROVED = "26";
    string internal constant ERC721_TRANSFER_TO_NON_ERC721RECEIVER_IMPLEMENTER = "27";
    string internal constant ERC721_OPERATOR_QUERY_FOR_NONEXISTENT_TOKEN = "28";
    string internal constant ERC721_MINT_TO_THE_ZERO_ADDRESS = "29";
    string internal constant ERC721_TOKEN_ALREADY_MINTED = "30";
    string internal constant ERC721_TRANSFER_OF_TOKEN_THAT_IS_NOT_OWN = "31";
    string internal constant ERC721_TRANSFER_TO_THE_ZERO_ADDRESS = "32";

    string internal constant ERC721META_URI_QUERY_FOR_NONEXISTENT_TOKEN = "33";

    string internal constant ERC721ENUM_OWNER_INDEX_OUT_OF_BOUNDS = "34";
    string internal constant ERC721ENUM_GLOBAL_INDEX_OUT_OF_BOUNDS = "35";

    string internal constant DC_UNSUPPORTED_PAIR = "36";

    string internal constant DE_INVALID_ENTERPRISE_ADDRESS = "37";
    string internal constant DE_LABMDA_NOT_GT_0 = "38";

    string internal constant E_CALLER_NOT_RENTAL_TOKEN = "39";
    string internal constant E_INVALID_BASE_TOKEN_ADDRESS = "40";
    string internal constant E_SERVICE_LIMIT_REACHED = "41";
    string internal constant E_INVALID_RENTAL_PERIOD_RANGE = "42";
    string internal constant E_SERVICE_ENERGY_GAP_HALVING_PERIOD_NOT_GT_0 = "43";
    string internal constant E_UNSUPPORTED_PAYMENT_TOKEN = "44";
    string internal constant E_RENTAL_PERIOD_OUT_OF_RANGE = "45";
    string internal constant E_INSUFFICIENT_LIQUIDITY = "46";
    string internal constant E_RENTAL_PAYMENT_SLIPPAGE = "47";
    string internal constant E_INVALID_RENTAL_TOKEN_ID = "48";
    string internal constant E_INVALID_RENTAL_PERIOD = "49";
    string internal constant E_FLASH_LIQUIDITY_REMOVAL = "50";
    string internal constant E_SWAPPING_DISABLED = "51";
    string internal constant E_RENTAL_TRANSFER_NOT_ALLOWED = "52";
    string internal constant E_INVALID_CALLER_WITHIN_RENTER_ONLY_RETURN_PERIOD = "53";
    string internal constant E_INVALID_CALLER_WITHIN_ENTERPRISE_ONLY_COLLECTION_PERIOD = "54";

    string internal constant EF_INVALID_ENTERPRISE_IMPLEMENTATION_ADDRESS = "55";
    string internal constant EF_INVALID_POWER_TOKEN_IMPLEMENTATION_ADDRESS = "56";
    string internal constant EF_INVALID_STAKE_TOKEN_IMPLEMENTATION_ADDRESS = "57";
    string internal constant EF_INVALID_RENTAL_TOKEN_IMPLEMENTATION_ADDRESS = "58";

    string internal constant EO_INVALID_ENTERPRISE_ADDRESS = "59";

    string internal constant ES_INVALID_ESTIMATOR_ADDRESS = "60";
    string internal constant ES_INVALID_COLLECTOR_ADDRESS = "61";
    string internal constant ES_INVALID_WALLET_ADDRESS = "62";
    string internal constant ES_INVALID_CONVERTER_ADDRESS = "63";
    string internal constant ES_INVALID_RENTER_ONLY_RETURN_PERIOD = "64";
    string internal constant ES_INVALID_ENTERPRISE_ONLY_COLLECTION_PERIOD = "65";
    string internal constant ES_STREAMING_RESERVE_HALVING_PERIOD_NOT_GT_0 = "66";
    string internal constant ES_MAX_SERVICE_FEE_PERCENT_EXCEEDED = "67";
    string internal constant ES_INVALID_BASE_TOKEN_ADDRESS = "68";
    string internal constant ES_INVALID_RENTAL_PERIOD_RANGE = "69";
    string internal constant ES_SWAPPING_ALREADY_ENABLED = "70";
    string internal constant ES_INVALID_PAYMENT_TOKEN_ADDRESS = "71";
    string internal constant ES_UNREGISTERED_PAYMENT_TOKEN = "72";

    string internal constant IO_INVALID_OWNER_ADDRESS = "73";

    string internal constant PT_INSUFFICIENT_AVAILABLE_BALANCE = "74";

    string internal constant E_ENTERPRISE_SHUTDOWN = "75";
    string internal constant E_INVALID_RENTAL_AMOUNT = "76";
    string internal constant ES_INVALID_BONDING_POLE = "77";
    string internal constant ES_INVALID_BONDING_SLOPE = "78";
    string internal constant ES_TRANSFER_ALREADY_ENABLED = "79";
    string internal constant PT_TRANSFER_DISABLED = "80";
    string internal constant E_INVALID_ENTERPRISE_NAME = "81";
    string internal constant PT_INVALID_MAX_RENTAL_PERIOD = "82";
    string internal constant E_INVALID_ENTERPRISE_FACTORY_ADDRESS = "83";
}
