// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract Token is ERC20Upgradeable, OwnableUpgradeable {
    string private _ipfsHash;
    string private _description;
    address public factory;
    
    event MetadataUpdated(string ipfsHash, string description);
    error NotFactory();

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    function initialize(
        string memory name, 
        string memory symbol,
        string memory ipfsHash,
        string memory description
    ) public initializer {
        __ERC20_init(name, symbol);
        __Ownable_init(msg.sender);
        factory = msg.sender;  // Removed immutable, now just a regular state variable
        _ipfsHash = ipfsHash;
        _description = description;
        
        emit MetadataUpdated(ipfsHash, description);
    }

    function mint(address to, uint256 amount) public onlyFactory {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) public onlyFactory {
        _burn(to, amount);
    }
    
    // Metadata getters - anyone can read
    function getMetadata() public view returns (string memory ipfsHash, string memory description) {
        return (_ipfsHash, _description);
    }
    
    // Only factory can update metadata
    function updateMetadata(string memory newIpfsHash, string memory newDescription) public onlyFactory {
        _ipfsHash = newIpfsHash;
        _description = newDescription;
        
        emit MetadataUpdated(newIpfsHash, newDescription);
    }
}