// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LibOrder, OrderKey} from "../libraries/LibOrder.sol";

interface IMiSwapVault {
    // Get balance of an order
    function balanceOf(OrderKey OrderKey) external view returns (uint256 ETHAmount, uint256 tokenId);
    // Deposit ETH to an order
    function depositETH(OrderKey OrderKey, uint256 ETHAmount) external payable;
    // Withdraw ETH from an order
    function withdrawETH(OrderKey OrderKey, uint256 ETHAmount, address to) external;
    // Deposit NFT to the order when creating a list order
    function depositNFT(OrderKey OrderKey, uint256 tokenId,address from, address collection) external;
    // Withdraw NFT from the order when the order is canceled
    function withdrawNFT(OrderKey OrderKey, address to, address collection, uint256 tokenId) external;
    // Edit the order's NFT when editing the order
    function editNFT(OrderKey oldOrderKey, OrderKey newOrderKey) external;
    // Edit the order's ETH when editing the order
    function editETH(OrderKey oldOrderKey, OrderKey newOrderKey, uint256 oldETHAmount, uint256 newETHAmount, address to) external payable;
    // Batch transfer ERC721 NFTs
    function batchTransferERC721(LibOrder.NFTInfo[] calldata nfts, address to) external;
    // Transfer ERC721 NFT
    function transferERC721(address from, address to, LibOrder.Asset calldata assets) external;
}