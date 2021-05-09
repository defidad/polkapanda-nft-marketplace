// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./LibOrder.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";

library LibFill {
    using SafeMathUpgradeable for uint256;

    struct FillResult {
        uint256 makeValue;
        uint256 takeValue;
    }

    /**
     * @dev Should return filled values
     * @param leftOrder left order
     * @param rightOrder right order
     * @param leftOrderFill current fill of the left order (0 if order is unfilled)
     * @param rightOrderFill current fill of the right order (0 if order is unfilled)
     */
    function fillOrder(
        LibOrder.Order memory leftOrder,
        LibOrder.Order memory rightOrder,
        uint256 leftOrderFill,
        uint256 rightOrderFill
    ) internal pure returns (FillResult memory) {
        (uint256 leftMakeValue, uint256 leftTakeValue) =
            LibOrder.calculateRemaining(leftOrder, leftOrderFill);
        (uint256 rightMakeValue, uint256 rightTakeValue) =
            LibOrder.calculateRemaining(rightOrder, rightOrderFill);

        //We have 3 cases here:
        if (leftTakeValue > rightMakeValue) {
            //1st: right order should be fully filled
            return
                fillRight(
                    leftOrder.makeAsset.value,
                    leftOrder.takeAsset.value,
                    rightMakeValue,
                    rightTakeValue
                );
        }
        if (rightTakeValue > leftMakeValue) {
            //2nd: left order should be fully filled
            return
                fillLeft(
                    leftMakeValue,
                    leftTakeValue,
                    rightOrder.makeAsset.value,
                    rightOrder.takeAsset.value
                );
        }
        return fillBoth(leftMakeValue, leftTakeValue);
    }

    function fillBoth(uint256 leftMakeValue, uint256 leftTakeValue)
        internal
        pure
        returns (FillResult memory result)
    {
        return FillResult(leftMakeValue, leftTakeValue);
    }

    function fillRight(
        uint256 leftMakeValue,
        uint256 leftTakeValue,
        uint256 rightMakeValue,
        uint256 rightTakeValue
    ) internal pure returns (FillResult memory result) {
        uint256 makerValue =
            LibMath.safeGetPartialAmountFloor(
                rightTakeValue,
                leftMakeValue,
                leftTakeValue
            );
        require(makerValue <= rightMakeValue, "fillRight: unable to fill");
        return FillResult(rightTakeValue, makerValue);
    }

    function fillLeft(
        uint256 leftMakeValue,
        uint256 leftTakeValue,
        uint256 rightMakeValue,
        uint256 rightTakeValue
    ) internal pure returns (FillResult memory result) {
        uint256 rightTake =
            LibMath.safeGetPartialAmountFloor(
                leftTakeValue,
                rightMakeValue,
                rightTakeValue
            );
        require(rightTake <= leftMakeValue, "fillLeft: unable to fill");
        return FillResult(leftMakeValue, leftTakeValue);
    }
}
