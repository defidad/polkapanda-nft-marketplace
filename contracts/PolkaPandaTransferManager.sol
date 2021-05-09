// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "./utilities/lib-asset/LibAsset.sol";
import "./utilities/panda-royalities/IRoyaltiesProvider.sol";
import "./LibFill.sol";
import "./LibFeeSide.sol";
import "./LibOrderDataV1.sol";
import "./ITransferManager.sol";
import "./TransferExecutor.sol";
import "./LibOrderData.sol";
import "./libraries/BPLibrary.sol";

abstract contract PolkaPandaTransferManager is
    OwnableUpgradeable,
    ITransferManager
{
    using BPLibrary for uint256;
    using SafeMathUpgradeable for uint256;

    uint256 public protocolFee;
    IRoyaltiesProvider public royaltiesRegistry;

    address public defaultFeeReceiver;
    mapping(address => address) public feeReceivers;

    function __PolkaPandaTransferManager_init_unchained(
        uint256 newProtocolFee,
        address newDefaultFeeReceiver,
        IRoyaltiesProvider newRoyaltiesProvider
    ) internal initializer {
        protocolFee = newProtocolFee;
        defaultFeeReceiver = newDefaultFeeReceiver;
        royaltiesRegistry = newRoyaltiesProvider;
    }

    function setRoyaltiesRegistry(IRoyaltiesProvider newRoyaltiesRegistry)
        external
        onlyOwner
    {
        royaltiesRegistry = newRoyaltiesRegistry;
    }

    function setProtocolFee(uint256 newProtocolFee) external onlyOwner {
        protocolFee = newProtocolFee;
    }

    function setDefaultFeeReceiver(address payable newDefaultFeeReceiver)
        external
        onlyOwner
    {
        defaultFeeReceiver = newDefaultFeeReceiver;
    }

    function setFeeReceiver(address token, address wallet) external onlyOwner {
        feeReceivers[token] = wallet;
    }

    function getFeeReceiver(address token) internal view returns (address) {
        address wallet = feeReceivers[token];
        if (wallet != address(0)) {
            return wallet;
        }
        return defaultFeeReceiver;
    }

    function doTransfers(
        LibAsset.AssetType memory makeMatch,
        LibAsset.AssetType memory takeMatch,
        LibFill.FillResult memory fill,
        LibOrder.Order memory leftOrder,
        LibOrder.Order memory rightOrder
    )
        internal
        override
        returns (uint256 totalMakeValue, uint256 totalTakeValue)
    {
        LibFeeSide.FeeSide feeSide =
            LibFeeSide.getFeeSide(makeMatch.assetClass, takeMatch.assetClass);
        totalMakeValue = fill.makeValue;
        totalTakeValue = fill.takeValue;
        LibOrderDataV1.DataV1 memory leftOrderData =
            LibOrderData.parse(leftOrder);
        LibOrderDataV1.DataV1 memory rightOrderData =
            LibOrderData.parse(rightOrder);
        if (feeSide == LibFeeSide.FeeSide.MAKE) {
            totalMakeValue = doTransfersWithFees(
                fill.makeValue,
                leftOrder.maker,
                leftOrderData,
                rightOrderData,
                makeMatch,
                takeMatch,
                TO_TAKER
            );
            transferPayouts(
                takeMatch,
                fill.takeValue,
                rightOrder.maker,
                leftOrderData.payouts,
                TO_MAKER
            );
        } else if (feeSide == LibFeeSide.FeeSide.TAKE) {
            totalTakeValue = doTransfersWithFees(
                fill.takeValue,
                rightOrder.maker,
                rightOrderData,
                leftOrderData,
                takeMatch,
                makeMatch,
                TO_MAKER
            );
            transferPayouts(
                makeMatch,
                fill.makeValue,
                leftOrder.maker,
                rightOrderData.payouts,
                TO_TAKER
            );
        }
    }

    function doTransfersWithFees(
        uint256 amount,
        address from,
        LibOrderDataV1.DataV1 memory dataCalculate,
        LibOrderDataV1.DataV1 memory dataNft,
        LibAsset.AssetType memory matchCalculate,
        LibAsset.AssetType memory matchNft,
        bytes4 transferDirection
    ) internal returns (uint256 totalAmount) {
        totalAmount = calculateTotalAmount(
            amount,
            protocolFee,
            dataCalculate.originFees
        );
        uint256 rest =
            transferProtocolFee(
                totalAmount,
                amount,
                from,
                matchCalculate,
                transferDirection
            );
        rest = transferRoyalties(
            matchCalculate,
            matchNft,
            rest,
            amount,
            from,
            transferDirection
        );
        rest = transferFees(
            matchCalculate,
            rest,
            amount,
            dataCalculate.originFees,
            from,
            transferDirection,
            ORIGIN
        );
        rest = transferFees(
            matchCalculate,
            rest,
            amount,
            dataNft.originFees,
            from,
            transferDirection,
            ORIGIN
        );
        transferPayouts(
            matchCalculate,
            rest,
            from,
            dataNft.payouts,
            transferDirection
        );
    }

    function transferProtocolFee(
        uint256 totalAmount,
        uint256 amount,
        address from,
        LibAsset.AssetType memory matchCalculate,
        bytes4 transferDirection
    ) internal returns (uint256) {
        (uint256 rest, uint256 fee) =
            subFeeInBp(totalAmount, amount, protocolFee * 2);
        if (fee > 0) {
            address tokenAddress = address(0);
            if (matchCalculate.assetClass == LibAsset.ERC20_ASSET_CLASS) {
                tokenAddress = abi.decode(matchCalculate.data, (address));
            } else if (
                matchCalculate.assetClass == LibAsset.ERC1155_ASSET_CLASS
            ) {
                uint256 tokenId;
                (tokenAddress, tokenId) = abi.decode(
                    matchCalculate.data,
                    (address, uint256)
                );
            }
            transfer(
                LibAsset.Asset(matchCalculate, fee),
                from,
                getFeeReceiver(tokenAddress),
                transferDirection,
                PROTOCOL
            );
        }
        return rest;
    }

    function transferRoyalties(
        LibAsset.AssetType memory matchCalculate,
        LibAsset.AssetType memory matchNft,
        uint256 rest,
        uint256 amount,
        address from,
        bytes4 transferDirection
    ) internal returns (uint256) {
        if (
            matchNft.assetClass != LibAsset.ERC1155_ASSET_CLASS &&
            matchNft.assetClass != LibAsset.ERC721_ASSET_CLASS
        ) {
            return rest;
        }
        (address token, uint256 tokenId) =
            abi.decode(matchNft.data, (address, uint256));
        LibPart.Part[] memory fees =
            royaltiesRegistry.getRoyalties(token, tokenId);
        return
            transferFees(
                matchCalculate,
                rest,
                amount,
                fees,
                from,
                transferDirection,
                ROYALTY
            );
    }

    function transferFees(
        LibAsset.AssetType memory matchCalculate,
        uint256 rest,
        uint256 amount,
        LibPart.Part[] memory fees,
        address from,
        bytes4 transferDirection,
        bytes4 transferType
    ) internal returns (uint256 restValue) {
        restValue = rest;
        for (uint256 i = 0; i < fees.length; i++) {
            (uint256 newRestValue, uint256 feeValue) =
                subFeeInBp(restValue, amount, fees[i].value);
            restValue = newRestValue;
            if (feeValue > 0) {
                transfer(
                    LibAsset.Asset(matchCalculate, feeValue),
                    from,
                    fees[i].account,
                    transferDirection,
                    transferType
                );
            }
        }
    }

    function transferPayouts(
        LibAsset.AssetType memory matchCalculate,
        uint256 amount,
        address from,
        LibPart.Part[] memory payouts,
        bytes4 transferDirection
    ) internal {
        uint256 sumBps = 0;
        uint256 restValue = amount;
        for (uint256 i = 0; i < payouts.length - 1; i++) {
            uint256 currentAmount = amount.bp(payouts[i].value);
            sumBps += payouts[i].value;
            if (currentAmount > 0) {
                restValue = restValue.sub(currentAmount);
                transfer(
                    LibAsset.Asset(matchCalculate, currentAmount),
                    from,
                    payouts[i].account,
                    transferDirection,
                    PAYOUT
                );
            }
        }
        LibPart.Part memory lastPayout = payouts[payouts.length - 1];
        sumBps += lastPayout.value;
        require(sumBps == 10000, "Sum payouts Bps not equal 100%");
        transfer(
            LibAsset.Asset(matchCalculate, restValue),
            from,
            lastPayout.account,
            transferDirection,
            PAYOUT
        );
    }

    function calculateTotalAmount(
        uint256 amount,
        uint256 feeOnTopBp,
        LibPart.Part[] memory orderOriginFees
    ) internal pure returns (uint256 total) {
        total = amount.add(amount.bp(feeOnTopBp));
        for (uint256 i = 0; i < orderOriginFees.length; i++) {
            total = total.add(amount.bp(orderOriginFees[i].value));
        }
    }

    function subFeeInBp(
        uint256 value,
        uint256 total,
        uint256 feeInBp
    ) internal pure returns (uint256 newValue, uint256 realFee) {
        return subFee(value, total.bp(feeInBp));
    }

    function subFee(uint256 value, uint256 fee)
        internal
        pure
        returns (uint256 newValue, uint256 realFee)
    {
        if (value > fee) {
            newValue = value - fee;
            realFee = fee;
        } else {
            newValue = 0;
            realFee = value;
        }
    }

    uint256[46] private __gap;
}
