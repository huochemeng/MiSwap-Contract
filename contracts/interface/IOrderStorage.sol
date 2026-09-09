// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {LibOrder, OrderKey, Price} from "../libraries/LibOrder.sol";

interface IOrderStorage {
    function getOrders(
        address collection, 
        uint256 tokenId,
        LibOrder.Side side,
        LibOrder.SaleKind saleKind,
        uint256 count,              // 分页参数
        Price price,                // 价格过滤/游标条件
        OrderKey firstOrderKey      // 分页游标（cursor）
    )
        external
        view
        returns (LibOrder.Order[] memory orders, OrderKey nextOrderKey); 

    function getBestOrder(
        address collection, 
        uint256 tokenId,
        LibOrder.Side side,
        LibOrder.SaleKind saleKind
    )
        external
        view
        returns (LibOrder.Order memory order);    

}
