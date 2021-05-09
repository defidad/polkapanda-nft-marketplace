// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "../lib-asset/LibAsset.sol";

interface ITransferProxy {
    function transfer(
        LibAsset.Asset calldata asset,
        address from,
        address to
    ) external;
}
