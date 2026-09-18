// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {LibPayInfo} from "./libraries/LibPayInfo.sol";

contract ProtocolManager is Initializable, OwnableUpgradeable { 

    uint128 public protocolShare;
    uint256[50] private __gap;

    event LogProtocolShareUpdated(uint128 indexed newShare);

    function __ProtocolManager_init(uint128 _protocolShare) internal onlyInitializing { 
        __ProtocolManager_init_unchained(_protocolShare);
    }

    function __ProtocolManager_init_unchained(uint128 _protocolShare) internal onlyInitializing { 
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