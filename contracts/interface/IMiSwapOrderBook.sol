// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {LibOrder, OrderKey, Price} from "../libraries/LibOrder.sol";

interface IMiSwapOrderBook {
    function makeOrders(LibOrder.Order[] calldata orders) external payable returns (OrderKey[] memory orderKeys);

    function cancelOrders(OrderKey[] calldata orderKeys) external returns (bool[] memory canceled );

    function editOrders(LibOrder.EditDetail[] calldata editDetails) external payable returns (OrderKey[] memory orderKeys);

    function matchOrders(LibOrder.MatchDetail[] calldata matchDetails) external payable returns (bool[] memory matched);

    function matchOrder(LibOrder.Order calldata sellOrder, LibOrder.Order calldata buyOrder) external payable;

}