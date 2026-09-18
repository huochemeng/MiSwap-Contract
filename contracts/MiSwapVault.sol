// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {LibTransferSafeUpgradeable, IERC721} from "./libraries/LibTransferSafeUpgradeable.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";

import {IMiSwapVault} from "./interface/IMiSwapVault.sol";

contract MiSwapVault is IMiSwapVault, OwnableUpgradeable { 
    using LibTransferSafeUpgradeable for address;
    using LibTransferSafeUpgradeable for IERC721;

    address public orderBook;
    mapping(OrderKey => uint256) public ETHBalance;
    mapping(OrderKey => uint256) public NFTBalance;
    uint256[50] private __gap;

    modifier onlyEasySwapOrderBook() {
        require(msg.sender == orderBook, "HV: only EasySwap OrderBook");
        _;
    }

    function initialize() public initializer {
        __Ownable_init(_msgSender());
    }

    function setOrderBook(address _orderBook) external onlyOwner { 
        require(_orderBook != address(0), "VA:zero address");
        orderBook = _orderBook;
    }

    function balanceOf(OrderKey orderKey) external view returns (uint256 ETHAmount, uint256 tokenId) {
        ETHAmount = ETHBalance[orderKey];
        tokenId = NFTBalance[orderKey];
    }

    function depositETH(OrderKey orderKey, uint256 ETHAmount) external payable {
        require(msg.value >= ETHAmount, "VA:exceeds amount");
        ETHBalance[orderKey] += ETHAmount;
    }

    function withdrawETH(OrderKey orderKey, uint256 ETHAmount, address to) external {
        // require(ETHBalance[orderKey] >= ETHAmount, "VA:insufficient balance");
        //  自 Solidity 0.8.0 起，所有算术运算默认开启溢出/下溢检查。如果 ETHAmount > ETHBalance[orderKey]，
        // 这行代码会直接 revert（抛出 Panic(0x11)），交易失败，资金不会被转出。
        ETHBalance[orderKey] -= ETHAmount;
        to.safeTransferETH(ETHAmount);// 函数已经内部处理了payable转换
    }

    function depositNFT(OrderKey orderKey, uint256 tokenId,address from, address collection) external {
        /**
        IDE 对 Yul Assembly 语义解析能力的天然限制.
        safeTransferETH 能跳转是因为它用的是 Solidity 高级语法，而 safeTransferNFT 的 Assembly 实现对 IDE 来说是一个语义黑盒。
        建议通过常量命名和 NatSpec 注释来弥补可读性损失。
         */
        IERC721(collection).safeTransferNFT(from, address(this), tokenId);
        NFTBalance[orderKey] = tokenId;
    }

    function withdrawNFT(OrderKey orderKey, address to, address collection, uint256 tokenId) external {
        require(NFTBalance[orderKey] == tokenId, "VA:NFT not found");
        delete NFTBalance[orderKey];
        IERC721(collection).safeTransferNFT(address(this), to, tokenId);
    }

    function editNFT(OrderKey oldOrderKey, OrderKey newOrderKey) external { 
        NFTBalance[newOrderKey] = NFTBalance[oldOrderKey];
        delete NFTBalance[oldOrderKey];
    }

    function editETH(OrderKey oldOrderKey, OrderKey newOrderKey, uint256 oldETHAmount, uint256 newETHAmount, address to) external payable { 
        ETHBalance[oldOrderKey] = 0;
        if (oldETHAmount > newETHAmount) {
            ETHBalance[newOrderKey] = newETHAmount;
            to.safeTransferETH(oldETHAmount - newETHAmount);
        } else if (oldETHAmount < newETHAmount) {
            require(
                msg.value >= newETHAmount - oldETHAmount,
                "HV: not match newETHAmount"
            );
            ETHBalance[newOrderKey] = msg.value + oldETHAmount;
        } else {
            ETHBalance[newOrderKey] = oldETHAmount;
        }
    }

    function transferERC721(address from, address to, LibOrder.Asset calldata assets) external {
        // 单个调用，调用者需持有 from 的 approve/Operator 权限
        IERC721(assets.collection).safeTransferNFT(from, to, assets.tokenId);
    }

    function batchTransferERC721(LibOrder.NFTInfo[] calldata nfts, address to) external {
        for (uint256 i = 0; i < nfts.length; i++) {
            // 批量场景，采用硬编码形式_msgSender()，保证所有 NFT 的发送方都必须是同一个（即当前调用者）
            IERC721(nfts[i].collection).safeTransferNFT(_msgSender(), to, nfts[i].tokenId);
        }
    }

    //ERC-721 安全接收钩子，它的作用是告诉外部 NFT 合约："我是一个合法的、能够安全持有 NFT 的合约"。
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}

}
