// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title WillRegistry
 * @notice Main contract for managing crypto wills
 */
contract WillRegistry is Ownable, ReentrancyGuard, Pausable, IERC721Receiver, ERC1155Holder {
    enum TokenType { Ether, ERC20, ERC721, ERC1155, Unknown }

    struct TokenAllocation {
        address tokenAddress;
        TokenType tokenType;
        uint256[] tokenIds;        
        uint256[] amounts;         
        address[] beneficiaries;   
    }

    struct BeneficiaryAllocation {
        address tokenAddress;
        TokenType tokenType;
        uint256 tokenId;
        uint256 amount;
        bool claimed;
    }

    
    struct Will {
        uint256 id;
        address owner;
        string name;  // Will name
        uint256 lastActivity;
        bool isActive;
        TokenAllocation[] allocations;
        uint256 etherAllocation; // Ether allocation amount
        mapping(address => bool) isBeneficiary;
        address[] beneficiaryList;
        // Track allocations per beneficiary
        mapping(address => BeneficiaryAllocation[]) beneficiaryAllocations;
    }

    mapping(address => Will) public wills;
    mapping(address => bool) public authorizedBackends;
    
    // Track which wills a beneficiary is part of
    mapping(address => address[]) public beneficiaryWills;
    
    event WillCreated(address indexed owner, string name, address[] beneficiaries);
    event TokenAllocated(
        address indexed owner,
        address indexed token,
        TokenType tokenType,
        address indexed beneficiary,
        uint256 tokenId,
        uint256 amount
    );
    event EtherAllocated(address indexed owner, uint256 amount, address indexed beneficiary);
    event BeneficiaryAdded(address indexed owner, address indexed beneficiary);
    event BeneficiaryRemoved(address indexed owner, address indexed beneficiary);
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


    /**
     * @dev Checks the token type for a given token address
     * @param tokenAddress Address of the token contract
     * @return TokenType of the token contract
     */
    function getTokenType(address tokenAddress) internal pure  returns (TokenType) {
        // Check for ERC20 token
        IERC20 erc20Token = IERC20(tokenAddress);
        if (address(erc20Token) != address(0)) {
            return TokenType.ERC20;
        }

        // Check for ERC721 token
        IERC721 erc721Token = IERC721(tokenAddress);
        if (address(erc721Token) != address(0)) {
            return TokenType.ERC721;
        }

        // Check for ERC1155 token
        IERC1155 erc1155Token = IERC1155(tokenAddress);
        if (address(erc1155Token) != address(0)) {
            return TokenType.ERC1155;
        }

        // If none of the above, return 0 (invalid token type)
        return TokenType.Unknown;
    }

        /**
     * @dev Adds a new beneficiary to the will and allocates tokens to them
     * @param beneficiary Address of the new beneficiary
     * @param allocations Array of token allocations for the beneficiary
     */
    function addBeneficiaryWithAllocation(
        address beneficiary,
        TokenAllocation[] calldata allocations
    ) external payable nonReentrant onlyWillOwner {
        require(beneficiary != address(0), "Invalid beneficiary address");
        require(allocations.length > 0 || msg.value > 0, "No allocations or Ether provided");
    
        // Retrieve the specific will of the sender
        Will storage will = wills[msg.sender];
        require(will.isActive, "Will does not exist");
    
        // Add beneficiary if they are not already included
        if (!will.isBeneficiary[beneficiary]) {
            addBeneficiary(beneficiary);
        }
    
        // Handle Ether allocation if provided
        if (msg.value > 0) {
            addBeneficiaryAllocation(
                will,
                beneficiary,
                address(0), // No token address for Ether
                TokenType.Ether,
                0,
                msg.value
            );
            emit EtherAllocated(msg.sender, msg.value, beneficiary);
        }
    
        // Process token allocations
        for (uint i = 0; i < allocations.length; i++) {
            TokenType tokenType = allocations[i].tokenType;
            require(tokenType != TokenType.Unknown, "Invalid token type");
    
            // Transfer tokens based on type
            if (tokenType == TokenType.ERC20) {
                for (uint j = 0; j < allocations[i].amounts.length; j++) {
                    uint256 amount = allocations[i].amounts[j];
                    IERC20(allocations[i].tokenAddress).transferFrom(msg.sender, address(this), amount);
    
                    addBeneficiaryAllocation(
                        will,
                        beneficiary,
                        allocations[i].tokenAddress,
                        tokenType,
                        0,
                        amount
                    );
                    emit TokenAllocated(msg.sender, allocations[i].tokenAddress, tokenType, beneficiary, 0, amount);
                }
            } else if (tokenType == TokenType.ERC721) {
                for (uint j = 0; j < allocations[i].tokenIds.length; j++) {
                    uint256 tokenId = allocations[i].tokenIds[j];
                    IERC721(allocations[i].tokenAddress).safeTransferFrom(msg.sender, address(this), tokenId);
    
                    addBeneficiaryAllocation(
                        will,
                        beneficiary,
                        allocations[i].tokenAddress,
                        tokenType,
                        tokenId,
                        1
                    );
                    emit TokenAllocated(msg.sender, allocations[i].tokenAddress, tokenType, beneficiary, tokenId, 1);
                }
            } else if (tokenType == TokenType.ERC1155) {
                for (uint j = 0; j < allocations[i].tokenIds.length; j++) {
                    uint256 tokenId = allocations[i].tokenIds[j];
                    uint256 amount = allocations[i].amounts[j];
                    IERC1155(allocations[i].tokenAddress).safeTransferFrom(
                        msg.sender,
                        address(this),
                        tokenId,
                        amount,
                        ""
                    );
    
                    addBeneficiaryAllocation(
                        will,
                        beneficiary,
                        allocations[i].tokenAddress,
                        tokenType,
                        tokenId,
                        amount
                    );
                    emit TokenAllocated(msg.sender, allocations[i].tokenAddress, tokenType, beneficiary, tokenId, amount);
                }
            }
        }
    
        // Update the last activity timestamp for the will
        will.lastActivity = block.timestamp;
    }
    


    /**
     * @dev Adds a beneficiary allocation to tracking
     */
    function addBeneficiaryAllocation(
        Will storage will,
        address beneficiary,
        address tokenAddress,
        TokenType tokenType,
        uint256 tokenId,
        uint256 amount
    ) internal {
        BeneficiaryAllocation memory allocation = BeneficiaryAllocation({
            tokenAddress: tokenAddress,
            tokenType: tokenType,
            tokenId: tokenId,
            amount: amount,
            claimed: false
        });
        
        will.beneficiaryAllocations[beneficiary].push(allocation);
    }
    
    /**
     * @dev Validates and adds a beneficiary to the will
     */
    function addBeneficiary(address beneficiary) private onlyWillOwner {
        require(beneficiary != address(0), "Invalid beneficiary address");
        require(!wills[msg.sender].isBeneficiary[beneficiary], "Beneficiary already exists");

        Will storage will = wills[msg.sender];
        will.isBeneficiary[beneficiary] = true;
        will.beneficiaryList.push(beneficiary);
        
        // Add this will to beneficiary's list of wills
        beneficiaryWills[beneficiary].push(msg.sender);

        emit BeneficiaryAdded(msg.sender, beneficiary);
    }

    /**
     * @dev Removes a beneficiary from the will
     */
    function removeBeneficiary(address beneficiary) public onlyWillOwner {
        require(wills[msg.sender].isBeneficiary[beneficiary], "Beneficiary doesn't exist");

        Will storage will = wills[msg.sender];
        will.isBeneficiary[beneficiary] = false;

        // Remove from beneficiaryList
        for (uint i = 0; i < will.beneficiaryList.length; i++) {
            if (will.beneficiaryList[i] == beneficiary) {
                will.beneficiaryList[i] = will.beneficiaryList[will.beneficiaryList.length - 1];
                will.beneficiaryList.pop();
                break;
            }
        }

        // Remove from beneficiaryWills
        address[] storage beneficiaryWillsList = beneficiaryWills[beneficiary];
        for (uint i = 0; i < beneficiaryWillsList.length; i++) {
            if (beneficiaryWillsList[i] == msg.sender) {
                beneficiaryWillsList[i] = beneficiaryWillsList[beneficiaryWillsList.length - 1];
                beneficiaryWillsList.pop();
                break;
            }
        }

        // Clear beneficiary allocations
        delete will.beneficiaryAllocations[beneficiary];

        emit BeneficiaryRemoved(msg.sender, beneficiary);
    }

    /**
     * @dev Validates token allocation parameters
     */

    /**
     * @dev Creates a new will with token allocations
     */
    function createWill(string memory _name, TokenAllocation[] calldata _allocations) 
        external 
        payable
        nonReentrant 
    {
        require(!wills[msg.sender].isActive, "Will already exists");
        require(_allocations.length > 0 || msg.value > 0, "No allocations or Ether provided");

        Will storage newWill = wills[msg.sender];
        newWill.owner = msg.sender;
        newWill.name = _name;
        newWill.lastActivity = block.timestamp;
        newWill.isActive = true;

        // Store Ether allocation if provided
        if (msg.value > 0) {
            newWill.etherAllocation = msg.value;

            for (uint j = 0; j < _allocations[0].beneficiaries.length; j++) {
                address beneficiary = _allocations[0].beneficiaries[j];
                if (!newWill.isBeneficiary[beneficiary]) {
                    addBeneficiary(beneficiary);
                }

                // Add Ether allocation for each beneficiary
                addBeneficiaryAllocation(
                    newWill,
                    beneficiary,
                    address(0), // No token address for Ether
                    TokenType.Ether,
                    0,
                    msg.value / _allocations[0].beneficiaries.length // Split Ether equally among beneficiaries
                );
            }
        }

        // Process each token allocation
        for (uint i = 0; i < _allocations.length; i++) {
            TokenType tokenType = _allocations[i].tokenType;
            require(tokenType != TokenType.Unknown, "Invalid token type");

            // Transfer tokens to the contract based on type
            if (tokenType == TokenType.ERC20) {
                for (uint j = 0; j < _allocations[i].beneficiaries.length; j++) {
                    uint256 amount = _allocations[i].amounts[j];
                    IERC20(_allocations[i].tokenAddress).transferFrom(msg.sender, address(this), amount);
                }
            } else if (tokenType == TokenType.ERC721) {
                for (uint j = 0; j < _allocations[i].beneficiaries.length; j++) {
                    uint256 tokenId = _allocations[i].tokenIds[j];
                    IERC721(_allocations[i].tokenAddress).safeTransferFrom(msg.sender, address(this), tokenId);
                }
            } else if (tokenType == TokenType.ERC1155) {
                for (uint j = 0; j < _allocations[i].beneficiaries.length; j++) {
                    uint256 tokenId = _allocations[i].tokenIds[j];
                    uint256 amount = _allocations[i].amounts[j];
                    IERC1155(_allocations[i].tokenAddress).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
                }
            }

            for (uint j = 0; j < _allocations[i].beneficiaries.length; j++) {
                address beneficiary = _allocations[i].beneficiaries[j];
                if (!newWill.isBeneficiary[beneficiary]) {
                    addBeneficiary(beneficiary);
                }

                // Add to beneficiary tracking
                addBeneficiaryAllocation(
                    newWill,
                    beneficiary,
                    _allocations[i].tokenAddress,
                    tokenType,
                    tokenType == TokenType.ERC721 ? _allocations[i].tokenIds[j] : 0,
                    tokenType == TokenType.ERC20 ? _allocations[i].amounts[j] : 
                    tokenType == TokenType.ERC1155 ? _allocations[i].amounts[j] : 1
                );

                // Emit allocation event
                emit TokenAllocated(
                    msg.sender,
                    _allocations[i].tokenAddress,
                    tokenType,
                    beneficiary,
                    tokenType == TokenType.ERC721 ? _allocations[i].tokenIds[j] : 0,
                    tokenType == TokenType.ERC20 ? _allocations[i].amounts[j] : 
                    tokenType == TokenType.ERC1155 ? _allocations[i].amounts[j] : 1
                );
            }
        }

        emit WillCreated(msg.sender, _name, newWill.beneficiaryList);
    }

    

    /**
     * @dev Returns list of beneficiaries for a will
     */
    function getBeneficiaries(address owner) external view returns (address[] memory) {
        require(wills[owner].isActive, "Will doesn't exist");
        return wills[owner].beneficiaryList;
    }

    /**
     * @dev Returns all allocations for a beneficiary in a specific will
     */
    function getBeneficiaryAllocations(address owner, address beneficiary) 
        external 
        view 
        returns (BeneficiaryAllocation[] memory) 
    {
        require(wills[owner].isActive, "Will doesn't exist");
        require(wills[owner].isBeneficiary[beneficiary], "Not a beneficiary");
        return wills[owner].beneficiaryAllocations[beneficiary];
    }

    function onERC721Received(
        address ,
        address ,
        uint256 ,
        bytes calldata 
    ) external pure override returns (bytes4) {
        // Return the function selector to indicate successful receipt
        return this.onERC721Received.selector;
    }

    /**
     * @dev Returns all wills where address is a beneficiary
     */
    function getWillsAsBeneficiary(address beneficiary) 
        external 
        view 
        returns (address[] memory) 
    {
        return beneficiaryWills[beneficiary];
    }
}