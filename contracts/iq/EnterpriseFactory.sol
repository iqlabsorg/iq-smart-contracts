pragma solidity 0.7.6;

import "./Enterprise.sol";

contract EnterpriseFactory {
    event EnterpriseDeployed(address indexed liquidityToken, string name, string baseUrl, address deployed);

    function deploy(
        string calldata name,
        address liquidityToken,
        string calldata baseUrl
    ) external {
        Enterprise enterprise = new Enterprise(name, liquidityToken, baseUrl);

        emit EnterpriseDeployed(liquidityToken, name, baseUrl, address(enterprise));
    }
}
