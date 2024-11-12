// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title WillRegistry
 * @notice Main contract for managing crypto wills
 */
contract WillRegistry is Ownable, ReentrancyGuard, Pausable {
    enum TokenType { ERC20, ERC721, ERC1155 }

    struct TokenAllocation {
        address tokenAddress;
        TokenType tokenType;
        uint256[] tokenIds;        
        uint256[] amounts;         
        address[] beneficiaries;   
    }

    struct Will {
        address owner;
        uint256 lastActivity;
        uint256 inactivityPeriod;
        uint256 gracePeriod;
        bool isActive;
        TokenAllocation[] allocations;
        mapping(address => bool) isBeneficiary;
        address[] beneficiaryList;
    }

    mapping(address => Will) public wills;
    mapping(address => bool) public authorizedBackends;
    
    event WillCreated(address indexed owner, address[] beneficiaries);
    event TokenAllocated(
        address indexed owner,
        address indexed token,
        TokenType tokenType,
        address indexed beneficiary,
        uint256 amount
    );
    event DeadManSwitchTriggered(address indexed owner);
    event PanicButtonPressed(address indexed owner);
    event BeneficiaryClaimed(
        address indexed beneficiary,
        address indexed token,
        uint256 tokenId,
        uint256 amount
    );

    modifier onlyAuthorizedBackend() {
        require(authorizedBackends[msg.sender], "Not authorized backend");
        _;
    }

    modifier onlyWillOwner() {
        require(wills[msg.sender].isActive && wills[msg.sender].owner == msg.sender, "Not will owner");
        _;
    }

    constructor() Ownable(msg.sender) {}

    function createWill(
        uint256 _inactivityPeriod,
        uint256 _gracePeriod,
        TokenAllocation[] calldata _allocations
    ) external nonReentrant {
        require(!wills[msg.sender].isActive, "Will already exists");
        require(_allocations.length > 0, "No allocations provided");
        
        Will storage newWill = wills[msg.sender];
        newWill.owner = msg.sender;
        newWill.lastActivity = block.timestamp;
        newWill.inactivityPeriod = _inactivityPeriod;
        newWill.gracePeriod = _gracePeriod;
        newWill.isActive = true;

        
        for (uint i = 0; i < _allocations.length; i++) {
            // validateAndAddAllocation(newWill, _allocations[i]);
        }

        emit WillCreated(msg.sender, newWill.beneficiaryList);
    }

    
}