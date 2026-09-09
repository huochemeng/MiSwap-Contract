// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IMiSwapOrderBook} from "./interface/IMiSwapOrderBook.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract MiSwapOrderBook is 
    // IMiSwapOrderBook,
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{

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
        //todo __OrderValidator_init & __ProtocolManager_init
        
        setVault(newVault);
    }

    function setVault(address newVault) public onlyOwner { 
        require(newVault != address(0), "Vault cannot be zero address");
        _vault = newVault;
    }
}