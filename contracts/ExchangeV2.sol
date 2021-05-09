// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "./ExchangeV2Core.sol";
import "./PolkaPandaTransferManager.sol";
import "./utilities/panda-royalities/IRoyaltiesProvider.sol";

contract ExchangeV2 is ExchangeV2Core, PolkaPandaTransferManager {
    function __ExchangeV2_init(
        INftTransferProxy _transferProxy,
        IERC20TransferProxy _erc20TransferProxy,
        uint256 newProtocolFee,
        address newDefaultFeeReceiver,
        IRoyaltiesProvider newRoyaltiesProvider
    ) external initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __TransferExecutor_init_unchained(_transferProxy, _erc20TransferProxy);
        __PolkaPandaTransferManager_init_unchained(
            newProtocolFee,
            newDefaultFeeReceiver,
            newRoyaltiesProvider
        );
        __OrderValidator_init_unchained();
    }
}
