// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {RedBlackTreeLibrary, Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";

error CannotInsertDuplicateOrder(OrderKey orderKey);

contract OrderStorage is Initializable {

    /// @dev all order keys are wrapped in a sentinel value to avoid collisions
    mapping(OrderKey => LibOrder.DBOrder) public orders;

    function __OrderStorage_init(
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing{}

    function __OrderStorage_init_unchained() internal onlyInitializing {}

    function _removeOrder(LibOrder.Order memory order) internal returns (OrderKey orderKey) {
        // todo _removeOrder
    }

}