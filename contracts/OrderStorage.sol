// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {RedBlackTreeLibrary, Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";

error CannotInsertDuplicateOrder(OrderKey orderKey);

contract OrderStorage is Initializable {

    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;

    /// @dev all order keys are wrapped in a sentinel value to avoid collisions
    mapping(OrderKey => LibOrder.DBOrder) public orders;

     /// @dev price tree for each collection and side, sorted by price
    mapping(address => mapping(LibOrder.Side => RedBlackTreeLibrary.Tree))
        public priceTrees;

    /// @dev order queue for each collection, side and expecially price, sorted by orderKey
    mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue)))
        public orderQueues;

    function __OrderStorage_init(
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing{}

    function __OrderStorage_init_unchained() internal onlyInitializing {}

    function _addOrder(LibOrder.Order memory order) internal returns (OrderKey orderKey) {
       orderKey = LibOrder.hash(order);
       //前置检验：判断槽位是否已经被占用
       if (orders[orderKey].order.maker != address(0)) {
            revert CannotInsertDuplicateOrder(orderKey);
        }
        // insert price to price tree if not exists
        // 价格树维护，红黑树是全局的价格排序索引，与订单队列是两套独立的数据结构。
        // 队列只负责同一价格下的 FIFO 排序，树负责跨价格的有序遍历。
        RedBlackTreeLibrary.Tree storage priceTree = priceTrees[
            order.nft.collection
        ][order.side];
        if(!priceTree.exists(order.price)) {
            priceTree.insert(order.price);
        }

        // insert order to order queue  订单队列
        LibOrder.OrderQueue storage orderQueue = orderQueues[
            order.nft.collection
        ][order.side][order.price];
        // 判断是否为空队列
        if (LibOrder.isSentinel(orderQueue.head)) {
            // 为空，初始化队列，head和tail都设置为ORDERKEY_SENTINEL
            orderQueues[order.nft.collection][order.side][
                order.price
            ] = LibOrder.OrderQueue(
                LibOrder.ORDERKEY_SENTINEL,
                LibOrder.ORDERKEY_SENTINEL
            );
            // 重新获取索引
            orderQueue = orderQueues[order.nft.collection][order.side][
                order.price
            ];
        }
        if (LibOrder.isSentinel(orderQueue.tail)) {
            orderQueue.head = orderKey;
            orderQueue.tail = orderKey;
            orders[orderKey] = LibOrder.DBOrder(
                order,
                LibOrder.ORDERKEY_SENTINEL
            );
        } else {
            orders[orderQueue.tail].next = orderKey;
            orders[orderKey] = LibOrder.DBOrder(
                order,
                LibOrder.ORDERKEY_SENTINEL
            );
            orderQueue.tail = orderKey;
        }
    }

    function _removeOrder(LibOrder.Order memory order) internal returns (OrderKey orderKey) {
        LibOrder.OrderQueue storage orderQueue = orderQueues[
            order.nft.collection
        ][order.side][order.price];
        orderKey = orderQueue.head;
        OrderKey prevOrderKey;
        bool found;
        while(LibOrder.isNotSentinel(orderKey) && !found) {
            LibOrder.DBOrder memory dbOrder = orders[orderKey];
            if(
                // 6个字段严格匹配，就是找到了对应的订单
                (dbOrder.order.maker == order.maker) &&
                (dbOrder.order.saleKind == order.saleKind) &&
                (dbOrder.order.expiry == order.expiry) &&
                (dbOrder.order.salt == order.salt) &&
                (dbOrder.order.nft.tokenId == order.nft.tokenId) &&
                (dbOrder.order.nft.amount == order.nft.amount)
            ) {
                 // 对订单进行删除操作，链表摘除逻辑
                OrderKey temp = orderKey;
                // emit OrderRemoved(order.nft.collection, orderKey, order.maker, order.side, order.price, order.nft, block.timestamp);
                if (
                    OrderKey.unwrap(orderQueue.head) ==
                    OrderKey.unwrap(orderKey)
                ) {
                    orderQueue.head = dbOrder.next;
                } else {
                    orders[prevOrderKey].next = dbOrder.next;
                }
                if (
                    OrderKey.unwrap(orderQueue.tail) ==
                    OrderKey.unwrap(orderKey)
                ) {
                    orderQueue.tail = prevOrderKey;
                }
                prevOrderKey = orderKey;
                orderKey = dbOrder.next;
                delete orders[temp];
                found = true;
            } else {
                // 不匹配，继续查找
                prevOrderKey = orderKey;
                orderKey = dbOrder.next;
            }
        }
        if (found) {
            //  空队列清理 + 价格树同步
            if (LibOrder.isSentinel(orderQueue.head)) {
                delete orderQueues[order.nft.collection][order.side][
                    order.price
                ];
                RedBlackTreeLibrary.Tree storage priceTree = priceTrees[
                    order.nft.collection
                ][order.side];
                if (priceTree.exists(order.price)) {
                    priceTree.remove(order.price);
                }
            }
        } else {
            revert("Non-existent order cannot be deleted");
        }
    }

}