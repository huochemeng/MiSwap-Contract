// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {LibPayInfo} from "./libraries/LibPayInfo.sol";

contract ProtocolManager is Initializable, OwnableUpgradeable { 

    uint128 public protocolShare;
    uint256[50] private __gap;

    event LogProtocolShareUpdated(uint128 indexed newShare);

    function __ProtocolManager_init(uint128 _protocolShare, address initialOwner) internal onlyInitializing { 
        //ProtocolManager.sol 继承了 OwnableUpgradeable，但在其 initialize 函数中没有调用父级的初始化器。
        //这会导致代理合约的 owner 永远为零地址，且后续升级可能失败。
        __ProtocolManager_init_unchained(_protocolShare,initialOwner);
    }

    function __ProtocolManager_init_unchained(uint128 _protocolShare,address initialOwner) internal onlyInitializing { 
        // ✅ _init_unchained 必须独立、直接调用父级初始化器
        __Ownable_init(initialOwner);
        _setProtocolShare(_protocolShare);
    }

    function setProtocolShare(uint128 _protocolShare) external onlyOwner { 
        _setProtocolShare(_protocolShare);
    }

    function _setProtocolShare(uint128 _protocolShare) internal { 
        require(_protocolShare <= LibPayInfo.MAX_PROTOCOL_SHARE, "PM: protocol share must <= 10000");
        protocolShare = _protocolShare;
        emit LogProtocolShareUpdated(_protocolShare);
    }

}