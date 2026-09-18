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
import {ProtocolManager} from "./ProtocolManager.sol";


contract MiSwapOrderBook is 
    IMiSwapOrderBook,
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OrderStorage,
    OrderValidator,
    ProtocolManager
{
    using LibTransferSafeUpgradeable for address;

    address private immutable self = address(this);// immutable 优先
    address private _vault;                        // 可变状态变量
    uint256[50] private __gap;                     // 必须紧贴最后

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
    event LogMatch(
        OrderKey indexed makeOrderKey,
        OrderKey indexed takeOrderKey,
        LibOrder.Order makeOrder,
        LibOrder.Order takeOrder,
        uint128 fillPrice
    );
    event BatchMatchInnerError(uint256 offset, bytes msg);

    modifier onlyDelegateCall() {
        _checkDelegateCall();
        _;
    }



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
        __ProtocolManager_init(newProtocolShare);
        
        setVault(newVault);
    }



    // 挂单
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
            _addOrder(order);
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

    // 订单删除
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

    // 修改订单
    function editOrders(LibOrder.EditDetail[] calldata editDetails) 
        external
        payable
        override
        whenNotPaused
        nonReentrant 
        returns (OrderKey[] memory newOrderKeys){
        newOrderKeys = new OrderKey[](editDetails.length);
        uint256 bidETHAmout;
        for (uint256 i = 0; i < editDetails.length; i++){
            (OrderKey newOrderKey, uint256 bidPrice) = _editOrderTry(
                editDetails[i].oldOrderKey,
                editDetails[i].newOrder
            );
            bidETHAmout += bidPrice;
            newOrderKeys[i] = newOrderKey;
        }
        if(msg.value > bidETHAmout){
            _msgSender().safeTransferETH(msg.value - bidETHAmout);
        }
    }

    function _editOrderTry(
        OrderKey oldOrderKey,
        LibOrder.Order calldata newOrder
    ) 
        internal 
        returns (OrderKey newOrderKey, uint256 deltaBidPrice) 
    { 
        LibOrder.Order memory oldOrder = orders[oldOrderKey].order;
        // check order, only the price and amount can be modified
        if (
            (oldOrder.saleKind != newOrder.saleKind) ||
            (oldOrder.side != newOrder.side) ||
            (oldOrder.maker != newOrder.maker) ||
            (oldOrder.nft.collection != newOrder.nft.collection) ||
            (oldOrder.nft.tokenId != newOrder.nft.tokenId) ||
            filledAmount[oldOrderKey] >= oldOrder.nft.amount // order cannot be canceled or filled
        ) {
            // 可优化，细化为LogSkipOrder_Mismatch()
            emit LogSkipOrder(oldOrderKey, oldOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }

        // check new order is valid
        if (
            newOrder.maker != _msgSender() ||
            newOrder.salt == 0 ||
            (newOrder.expiry < block.timestamp && newOrder.expiry != 0) ||
            filledAmount[LibOrder.hash(newOrder)] != 0 // order cannot be canceled or filled
        ) {
            // 可优化，细化为LogSkipOrder_InvalidAuth()
            emit LogSkipOrder(oldOrderKey, newOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }
        // cancel old order
        // remove old order from order storage
        _removeOrder(oldOrder);
        // cancel old order form order book
        _cancelOrder(oldOrderKey);
        emit LogCancel(oldOrderKey, oldOrder.maker);
        // add new order to order book
        newOrderKey = _addOrder(newOrder);
        uint256 oldFilledAmount = filledAmount[oldOrderKey];
        //  make new order
        if(oldOrder.side == LibOrder.Side.List) {
            IMiSwapVault(_vault).editNFT(oldOrderKey, newOrderKey);
        }else if(oldOrder.side == LibOrder.Side.Bid) {
            //比较新旧订单剩余需要锁定的 ETH 总量，根据差额决定是"补钱"还是"仅更新账本"
            uint256 oldRemainingPrice = Price.unwrap(oldOrder.price) *
                (oldOrder.nft.amount - oldFilledAmount);
            uint256 newRemainingPrice = Price.unwrap(newOrder.price) *
                newOrder.nft.amount;
            // 优化为一个分支，统一处理(使用三目运算符处理，考虑负数触发下溢revert)
            deltaBidPrice = oldRemainingPrice <= newRemainingPrice
                ? newRemainingPrice - oldRemainingPrice : 0;
            IMiSwapVault(_vault).editETH{value: uint256(deltaBidPrice)}(
                oldOrderKey,
                newOrderKey,
                oldRemainingPrice,
                newRemainingPrice,
                oldOrder.maker
            );
        }
        emit LogMake(
            newOrderKey,
            newOrder.side,
            newOrder.saleKind,
            newOrder.maker,
            newOrder.nft,
            newOrder.price,
            newOrder.expiry,
            newOrder.salt
        );

    }

    // 订单匹配批量
    function matchOrders(LibOrder.MatchDetail[] calldata matchDetails) 
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (bool[] memory matched)
    {
        matched = new bool[](matchDetails.length);

        uint128 buyETHAmount;

        for (uint256 i = 0; i < matchDetails.length; ++i) {
            LibOrder.MatchDetail calldata matchDetail = matchDetails[i];
            (bool success, bytes memory data) = address(this).delegatecall(
                abi.encodeWithSignature(
                    "matchOrderWithoutPayback((uint8,uint8,address,(uint256,address,uint96),uint128,uint64,uint64),(uint8,uint8,address,(uint256,address,uint96),uint128,uint64,uint64),uint256)",
                    matchDetail.sellOrder,
                    matchDetail.buyOrder,
                    msg.value - buyETHAmount
                )
            );
            if (success) {
                matched[i] = success;
                if (matchDetail.buyOrder.maker == _msgSender()) { // buy order
                    uint128 buyPrice;
                    buyPrice = abi.decode(data, (uint128));
                    // Calculate ETH the buyer has spent
                    buyETHAmount += buyPrice;
                }
            } else {
                emit BatchMatchInnerError(i, data);
            }
        }

        if (msg.value > buyETHAmount) { // return the remaining eth
            _msgSender().safeTransferETH(msg.value - buyETHAmount);
        }
    }

    function matchOrderWithoutPayback(
        LibOrder.Order calldata sellOrder,
        LibOrder.Order calldata buyOrder,
        uint256 msgValue
    )
        external
        payable
        whenNotPaused
        onlyDelegateCall
        returns (uint128 costValue)
    {
        costValue = _matchOrder(sellOrder, buyOrder, msgValue);
    }

    // 订单匹配
    function matchOrder(LibOrder.Order calldata sellOrder, LibOrder.Order calldata buyOrder) 
        external payable override whenNotPaused nonReentrant {
        uint256 costValue = _matchOrder(sellOrder, buyOrder, msg.value);
        if (msg.value > costValue) {
            _msgSender().safeTransferETH(msg.value - costValue);
        }
    }

    function _matchOrder(LibOrder.Order calldata sellOrder, LibOrder.Order calldata buyOrder, uint256 msgValue) 
        internal returns (uint128 costValue) 
    {
        OrderKey sellOrderKey = LibOrder.hash(sellOrder);
        OrderKey buyOrderKey = LibOrder.hash(buyOrder);
        _isMatchAvailable(sellOrder, buyOrder, sellOrderKey, buyOrderKey);
        if (_msgSender() == sellOrder.maker) { // sell order
            // accept bid
            // 卖方在接受Bid单时，必须要求msgValue==0
            require(msgValue == 0, "HD: value > 0"); // sell order cannot accept eth
            bool isSellExist = orders[sellOrderKey].order.maker != address(0); // check if sellOrder exist in order storage
            _validateOrder(sellOrder, isSellExist);
            _validateOrder(orders[buyOrderKey].order, false); // check if exist in order storage

            uint128 fillPrice = Price.unwrap(buyOrder.price); // the price of bid order
            if (isSellExist) { // 仅当卖单在链上时，才需要清理卖单状态
                // check if sellOrder exist in order storage , del&fill if exist
                _removeOrder(sellOrder); // 删除链上卖单
                _updateFilledAmount(sellOrder.nft.amount, sellOrderKey); //  // 标记卖单已全部成交
            }
            // 无论卖单是否在链上，买单都被吃掉了1个，必须更新买单状态
            _updateFilledAmount(filledAmount[buyOrderKey] + 1, buyOrderKey);
            emit LogMatch(
                sellOrderKey,
                buyOrderKey,
                sellOrder,
                buyOrder,
                fillPrice
            );

            // transfer nft&eth
            /*
            注意：不是卖方直接去 Vault 提，也不是买方提。而是由撮合合约作为可信中介，
            先把钱从 Vault 拉到自己的账户里，再完成分账。 */
            // ① 从 Vault 中提取买方的 ETH 到当前合约（交易所合约）
            IMiSwapVault(_vault).withdrawETH(
                buyOrderKey,
                fillPrice,
                address(this)
            );
            // ② 计算协议手续费
            uint128 protocolFee = _shareToAmount(fillPrice, protocolShare);
            // ③ 扣除手续费后，将剩余 ETH 转给卖方
            sellOrder.maker.safeTransferETH(fillPrice - protocolFee);

            // NFT 的结算路径（卖方交货 → 买方收货）
            if (isSellExist) {
                // 卖单已在 Vault 中托管
                IMiSwapVault(_vault).withdrawNFT(
                    sellOrderKey,
                    buyOrder.maker,
                    sellOrder.nft.collection,
                    sellOrder.nft.tokenId
                );
            } else {
                // 卖单未托管（链下签名 / Taker 卖单）
                IMiSwapVault(_vault).transferERC721(
                    sellOrder.maker,
                    buyOrder.maker,
                    sellOrder.nft
                );
            }
        }else if(_msgSender() == buyOrder.maker) {
            // accept list
            bool isBuyExist = orders[buyOrderKey].order.maker != address(0);
            _validateOrder(orders[sellOrderKey].order, false); // check if exist in order storage
            _validateOrder(buyOrder, isBuyExist);

            uint128 buyPrice = Price.unwrap(buyOrder.price);
            uint128 fillPrice = Price.unwrap(sellOrder.price);
            if (!isBuyExist) {
                // 即时吃单，Take / Market Buy ，当前调用者（买方）并没有提前在链上挂出这笔买单，而是直接发起一笔交易来“吃掉”已存在的卖单。
                require(msgValue >= fillPrice, "HD: value < fill price");
            } else {
                require(buyPrice >= fillPrice, "HD: buy price < fill price");
                IMiSwapVault(_vault).withdrawETH(
                    buyOrderKey,
                    buyPrice,
                    address(this)
                );
                // check if buyOrder exist in order storage , del&fill if exist
                _removeOrder(buyOrder);
                _updateFilledAmount(filledAmount[buyOrderKey] + 1, buyOrderKey);
            }
            _updateFilledAmount(sellOrder.nft.amount, sellOrderKey);

            emit LogMatch(
                buyOrderKey,
                sellOrderKey,
                buyOrder,
                sellOrder,
                fillPrice
            );

            uint128 protocolFee = _shareToAmount(fillPrice, protocolShare);
            // ③ 扣除手续费后，将剩余 ETH 转给卖方
            sellOrder.maker.safeTransferETH(fillPrice - protocolFee);
            if (buyPrice > fillPrice) {
                buyOrder.maker.safeTransferETH(buyPrice - fillPrice);
            }

            IMiSwapVault(_vault).withdrawNFT(
                sellOrderKey,
                buyOrder.maker,
                sellOrder.nft.collection,
                sellOrder.nft.tokenId
            );
            costValue = isBuyExist ? 0 : buyPrice;
        } else {
            revert("HD: sender invalid");
        }
    }
    
    function _shareToAmount(uint128 total, uint128 share) internal pure returns (uint128) {
        return (total * share) / LibPayInfo.MAX_PROTOCOL_SHARE;
    }

    function _isMatchAvailable(
        LibOrder.Order memory sellOrder,
        LibOrder.Order memory buyOrder,
        OrderKey sellOrderKey,
        OrderKey buyOrderKey
    ) internal view {
        require(
            OrderKey.unwrap(sellOrderKey) != OrderKey.unwrap(buyOrderKey),
            "Oops: same order"
        );
        require(
            sellOrder.side == LibOrder.Side.List &&
                buyOrder.side == LibOrder.Side.Bid,
            "Oops: side mismatch"
        );
        require(
            sellOrder.saleKind == LibOrder.SaleKind.FixedPriceForItem,
            "Oops: kind mismatch"
        );
        require(sellOrder.maker != buyOrder.maker, "Oops: same maker");
        require( // check if the asset is the same
            buyOrder.saleKind == LibOrder.SaleKind.FixedPriceForCollection ||
                (sellOrder.nft.collection == buyOrder.nft.collection &&
                    sellOrder.nft.tokenId == buyOrder.nft.tokenId),
            "Oops: asset mismatch"
        );
        require(
            filledAmount[sellOrderKey] < sellOrder.nft.amount &&
                filledAmount[buyOrderKey] < buyOrder.nft.amount,
            "Oops: order closed"
        );
    }

    function _checkDelegateCall() private view {
        // 验证当前函数是通过delegatecall调用的，禁止直接调用
        require(address(this) != self);
    }

    function setVault(address newVault) public onlyOwner { 
        require(newVault != address(0), "Vault cannot be zero address");
        _vault = newVault;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}

    

}