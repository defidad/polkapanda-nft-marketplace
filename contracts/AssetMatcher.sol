// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;
pragma abicoder v2;

import "./IAssetMatcher.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

abstract contract AssetMatcher is Initializable, OwnableUpgradeable {
    bytes constant EMPTY = "";
    mapping(bytes4 => address) matchers;

    event MatcherChange(bytes4 indexed assetType, address matcher);

    function setAssetMatcher(bytes4 assetType, address matcher)
        public
        onlyOwner
    {
        matchers[assetType] = matcher;
        emit MatcherChange(assetType, matcher);
    }

    function matchAssets(
        LibAsset.AssetType memory leftAssetType,
        LibAsset.AssetType memory rightAssetType
    ) internal view returns (LibAsset.AssetType memory) {
        LibAsset.AssetType memory result =
            matchAssetOneSide(leftAssetType, rightAssetType);
        if (result.assetClass == 0) {
            return matchAssetOneSide(rightAssetType, leftAssetType);
        } else {
            return result;
        }
    }

    function matchAssetOneSide(
        LibAsset.AssetType memory leftAssetType,
        LibAsset.AssetType memory rightAssetType
    ) private view returns (LibAsset.AssetType memory) {
        bytes4 classLeft = leftAssetType.assetClass;
        bytes4 classRight = rightAssetType.assetClass;
        if (classLeft == LibAsset.ETH_ASSET_CLASS) {
            if (classRight == LibAsset.ETH_ASSET_CLASS) {
                return leftAssetType;
            }
            return LibAsset.AssetType(0, EMPTY);
        }
        if (classLeft == LibAsset.ERC20_ASSET_CLASS) {
            if (classRight == LibAsset.ERC20_ASSET_CLASS) {
                address addressLeft = abi.decode(leftAssetType.data, (address));
                address addressRight =
                    abi.decode(rightAssetType.data, (address));
                if (addressLeft == addressRight) {
                    return leftAssetType;
                }
            }
            return LibAsset.AssetType(0, EMPTY);
        }
        if (classLeft == LibAsset.ERC721_ASSET_CLASS) {
            if (classRight == LibAsset.ERC721_ASSET_CLASS) {
                (address addressLeft, uint256 tokenIdLeft) =
                    abi.decode(leftAssetType.data, (address, uint256));
                (address addressRight, uint256 tokenIdRight) =
                    abi.decode(rightAssetType.data, (address, uint256));
                if (
                    addressLeft == addressRight && tokenIdLeft == tokenIdRight
                ) {
                    return leftAssetType;
                }
            }
            return LibAsset.AssetType(0, EMPTY);
        }
        if (classLeft == LibAsset.ERC1155_ASSET_CLASS) {
            if (classRight == LibAsset.ERC1155_ASSET_CLASS) {
                (address addressLeft, uint256 tokenIdLeft) =
                    abi.decode(leftAssetType.data, (address, uint256));
                (address addressRight, uint256 tokenIdRight) =
                    abi.decode(rightAssetType.data, (address, uint256));
                if (
                    addressLeft == addressRight && tokenIdLeft == tokenIdRight
                ) {
                    return leftAssetType;
                }
            }
            return LibAsset.AssetType(0, EMPTY);
        }
        address matcher = matchers[classLeft];
        if (matcher != address(0)) {
            return
                IAssetMatcher(matcher).matchAssets(
                    leftAssetType,
                    rightAssetType
                );
        }
        if (classLeft == classRight) {
            bytes32 leftHash = keccak256(leftAssetType.data);
            bytes32 rightHash = keccak256(rightAssetType.data);
            if (leftHash == rightHash) {
                return leftAssetType;
            }
        }
        revert("not found IAssetMatcher");
    }

    uint256[49] private __gap;
}
