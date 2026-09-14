// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";
import {Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibTransferSafeUpgradeable, IERC721} from "./libraries/LibTransferSafeUpgradeable.sol";
import {LibPayInfo} from "./libraries/LibPayInfo.sol";

import {IMiSwapOrderBook} from "./interface/IMiSwapOrderBook.sol";
import {IMiSwapVault} from "./interface/IMiSwapVault.sol";
import {OrderStorage} from "./OrderStorage.sol";
import {OrderValidator} from "./OrderValidator.sol";


contract MiSwapOrderBook is 
    IMiSwapOrderBook,
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OrderStorage,
    OrderValidator
{
    using LibTransferSafeUpgradeable for address;

    event LogMake(
        OrderKey orderKey,
        LibOrder.Side indexed side,
        LibOrder.SaleKind indexed saleKind,
        address indexed maker,
        LibOrder.Asset nft,
        Price price,
        uint64 expiry,
        uint64 salt
    );

    event LogSkipOrder(OrderKey orderKey, uint64 salt);
    event LogCancel(OrderKey indexed orderKey, address indexed maker);


    address private _vault;


    /**  @notice Initialize contract
    */
    function initialize(
        uint128 newProtocolShare, 
        address newVault, 
        string memory EIP712Name, 
        string memory EIP712Version
    ) public initializer {
        __MiSwapOrderBook_init(newProtocolShare, newVault, EIP712Name, EIP712Version);
    }

    function __MiSwapOrderBook_init(
        uint128 newProtocolShare, 
        address newVault, 
        string memory EIP712Name, 
        string memory EIP712Version
    ) internal onlyInitializing {
        __MiSwapOrderBook_init_unchained(
            newProtocolShare, 
            newVault, 
            EIP712Name, 
            EIP712Version
        );
    }

    function __MiSwapOrderBook_init_unchained(
        uint128 newProtocolShare, 
        address newVault, 
        string memory EIP712Name, 
        string memory EIP712Version
    ) internal onlyInitializing {
        __Context_init();
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
        __Pausable_init();
        __OrderValidator_init(EIP712Name, EIP712Version);
        //todo  & __ProtocolManager_init
        
        setVault(newVault);
    }

    function setVault(address newVault) public onlyOwner { 
        require(newVault != address(0), "Vault cannot be zero address");
        _vault = newVault;
    }

    function makeOrders(
        LibOrder.Order[] calldata orders
    )
        external 
        payable
        override
        whenNotPaused
        nonReentrant 
        returns (OrderKey[] memory orderKeys)
    {
        uint256 orderAmount = orders.length;
        orderKeys = new OrderKey[](orderAmount);
        uint128 ETHAmout;
        for (uint256 i = 0; i < orderAmount; i++) {
            // the price of bid order
            uint128 buyPrice;
            if(orders[i].side == LibOrder.Side.Bid){
                buyPrice = Price.unwrap(orders[i].price) * orders[i].nft.amount;
            }

            OrderKey newOrderKey = _makeOrderTry(orders[i], buyPrice);
            orderKeys[i] = newOrderKey;
            // if the order is create success, the ETH amount will be transfer to vault
            if(OrderKey.unwrap(newOrderKey) != OrderKey.unwrap(LibOrder.ORDERKEY_SENTINEL)){
                ETHAmout += buyPrice;
            }
            // return the remaining eth，if the eth is not enough, the transaction will be reverted
            if(msg.value > ETHAmout){
                _msgSender().safeTransferETH(msg.value - ETHAmout);
            }
        }
    }


    function _makeOrderTry(
        LibOrder.Order calldata order,
        uint128 buyPrice
    ) 
        internal 
        returns (OrderKey newOrderKey) 
    { 
        if(
            order.maker == _msgSender() &&
           Price.unwrap(order.price) != 0 && // price cannot be zero
            order.salt != 0 && // salt cannot be zero
            (order.expiry > block.timestamp || order.expiry == 0) && // expiry must be greater than current block timestamp or no expiry
            filledAmount[LibOrder.hash(order)] == 0
        ) {
            newOrderKey = LibOrder.hash(order);
            //depost asset to vault
            if(order.side == LibOrder.Side.List) { 
                if(order.nft.amount != 1){
                    return LibOrder.ORDERKEY_SENTINEL;
                }
                IMiSwapVault(_vault).depositNFT(newOrderKey, order.nft.tokenId, order.maker, order.nft.collection);
            }else if(order.side == LibOrder.Side.Bid) {
                if(order.nft.amount == 0){
                    return LibOrder.ORDERKEY_SENTINEL;
                }
                IMiSwapVault(_vault).depositETH{value: uint256(buyPrice)}(newOrderKey, buyPrice);
            }
            // todo _addOrder(order);
            
            emit LogMake(
                newOrderKey,
                order.side,
                order.saleKind,
                order.maker,
                order.nft,
                order.price,
                order.expiry,
                order.salt
            );
        }else { 
            emit LogSkipOrder(LibOrder.hash(order), order.salt);
        }

    }

    function cancelOrders(
        OrderKey[] calldata orderKeys
    ) 
        external
        override
        whenNotPaused
        nonReentrant 
        returns (bool[] memory canceled )
    {
        canceled = new bool[](orderKeys.length);
        for (uint256 i = 0; i < orderKeys.length; i++){
            bool success = _cancelOrderTry(orderKeys[i]);
            canceled[i] = success;
        }
    }

    function _cancelOrderTry(
        OrderKey orderKey
    ) 
        internal 
        returns (bool success) 
    { 
        LibOrder.Order memory order = orders[orderKey].order;
        if (
            order.maker == _msgSender() &&
            filledAmount[orderKey] < order.nft.amount // 已成交的订单数量严格小于挂单总量，这样订单才可以删除
        ) {
            OrderKey orderHash = LibOrder.hash(order);
            _removeOrder(order);
            // withdraw asset from vault
            if (order.side == LibOrder.Side.List) {
                IMiSwapVault(_vault).withdrawNFT(
                    orderHash,
                    order.maker,
                    order.nft.collection,
                    order.nft.tokenId
                );
            } else if (order.side == LibOrder.Side.Bid) {
                uint256 availNFTAmount = order.nft.amount -
                    filledAmount[orderKey];
                IMiSwapVault(_vault).withdrawETH(
                    orderHash,
                    Price.unwrap(order.price) * availNFTAmount, // the withdraw amount of eth
                    order.maker
                );
            }
            _cancelOrder(orderKey);
            success = true;
            emit LogCancel(orderKey, order.maker);
        } else {
            emit LogSkipOrder(orderKey, order.salt);
        }

    }

    function editOrders(LibOrder.EditDetail[] calldata editDetails) external payable returns (OrderKey[] memory orderKeys){
        //todo
    }

    function matchOrders(LibOrder.MatchDetail[] calldata matchDetails) external payable returns (bool[] memory matched){
        //todo
    }

    function matchOrder(LibOrder.Order calldata sellOrder, LibOrder.Order calldata buyOrder) external payable{
        //todo
    }
    
}