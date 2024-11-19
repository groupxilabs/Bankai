// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/**
 * @title WillRegistry
 * @notice Main contract for managing crypto wills
 */
contract WillRegistry is Ownable, ReentrancyGuard {
    enum TokenType { Ether, ERC20, ERC721, ERC1155, Unknown }

    // Minimum and maximum bounds for time periods (in days)
    uint256 private constant MIN_GRACE_PERIOD = 1 days;
    uint256 private constant MAX_GRACE_PERIOD = 30 days;
    uint256 private constant MIN_ACTIVITY_THRESHOLD = 30 days;
    uint256 private constant MAX_ACTIVITY_THRESHOLD = 365 days; 
    
    uint256 private _nextWillId = 1;


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
        uint256 gracePeriod;        
        uint256 activityThreshold;  
        bool deadManSwitchTriggered;
        uint256 deadManSwitchTimestamp;
        mapping(address => bool) hasClaimedDuringGrace;
    }

    mapping(address => Will) public wills;
    mapping(address => bool) public authorizedBackends;
    
    // Track which wills a beneficiary is part of
    mapping(address => address[]) public beneficiaryWills;

    // Update the will mapping to use willId instead of address
    mapping(uint256 => Will) public willsById;
    mapping(address => uint256[]) public ownerWillIds; 
    
    event ActivityUpdated(address indexed owner, uint256 timestamp);
    event TimeframesUpdated(address indexed owner, uint256 gracePeriod, uint256 activityThreshold);
    event WillClaimed(address indexed beneficiary, address indexed willOwner);
    event GracePeriodStarted(address indexed owner, uint256 timestamp, uint256 gracePeriod);
    event DeadManSwitchActivated(address indexed owner, uint256 timestamp);
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

    // Custom Errors
    error NotAuthorizedBackend();
    error NotWillOwner();
    error InvalidBeneficiaryAddress();
    error NoAllocationsOrEtherProvided();
    error WillDoesNotExist();
    error InvalidTokenType();
    error BeneficiaryAlreadyExists();
    error BeneficiaryDoesNotExist();
    error GracePeriodOutOfRange();
    error ActivityThresholdOutOfRange();
    error ActivityThresholdTooShort();
    error DeadManSwitchAlreadyTriggered();
    error WillNotActive();
    error NotABeneficiary();
    error DeadManSwitchNotTriggered();
    error GracePeriodNotEnded();
    error AlreadyClaimed();
    error EtherTransferFailed();
    error GracePeriodInvalid(uint256 provided, uint256 min, uint256 max);
    error ActivityThresholdInvalid(uint256 provided, uint256 min, uint256 max);
    error ActivityThresholdTooShortForGracePeriod(uint256 activityThreshold, uint256 gracePeriod);
    error WillIdNotFound(uint256 willId);
    error WillIdInvalid();
 

    modifier onlyAuthorizedBackend() {
        if (!authorizedBackends[msg.sender]) revert NotAuthorizedBackend();
        _;
    }

    modifier onlyWillOwner() {
        if (!wills[msg.sender].isActive || wills[msg.sender].owner != msg.sender) {
            revert NotWillOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setAuthorizedBackend(address backend, bool authorized) external onlyOwner {
        authorizedBackends[backend] = authorized;
    }
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
     * @param willId ID of the will
     * @param beneficiary Address of the new beneficiary
     * @param allocations Array of token allocations for the beneficiary
     */
    function addBeneficiaryWithAllocation(
        uint256 willId,
        address beneficiary,
        TokenAllocation[] calldata allocations
    ) external payable nonReentrant {
        if (beneficiary == address(0)) revert InvalidBeneficiaryAddress();
        if (allocations.length == 0 && msg.value == 0) revert NoAllocationsOrEtherProvided();
        
        // Get the specific will using ID
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        if (!will.isActive) revert WillIdNotFound(willId);
        
        // Check ownership
        if (will.owner != msg.sender) revert NotWillOwner();
    
        // Add beneficiary if they are not already included
        if (!will.isBeneficiary[beneficiary]) {
            addBeneficiary(beneficiary, willId);
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
            if (tokenType == TokenType.Unknown) revert InvalidTokenType();
    
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
    function addBeneficiary(address beneficiary, uint256 willId) private {
        if (beneficiary == address(0)) revert InvalidBeneficiaryAddress();
        
        Will storage will = willsById[willId];
        if (will.isBeneficiary[beneficiary]) revert BeneficiaryAlreadyExists();
        if (will.owner != msg.sender) revert NotWillOwner();

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
        if (!wills[msg.sender].isBeneficiary[beneficiary]) revert BeneficiaryDoesNotExist();


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
     * @dev Creates a new will with token allocations
     */
    function createWill(
        string memory _name, 
        TokenAllocation[] calldata _allocations, 
        uint256 _gracePeriod,
        uint256 _activityThreshold
    ) external payable nonReentrant {
        if (_allocations.length == 0 && msg.value == 0) revert NoAllocationsOrEtherProvided();

        // Validate timeframes
        validateTimeframes(_gracePeriod, _activityThreshold);

        uint256 newWillId = _nextWillId++;
        Will storage newWill = willsById[newWillId];
        
        newWill.id = newWillId;
        newWill.owner = msg.sender;
        newWill.name = _name;
        newWill.gracePeriod = _gracePeriod;
        newWill.activityThreshold = _activityThreshold;
        newWill.lastActivity = block.timestamp;
        newWill.isActive = true;

        ownerWillIds[msg.sender].push(newWillId);

        // Store Ether allocation if provided
        if (msg.value > 0) {
            newWill.etherAllocation = msg.value;

            for (uint j = 0; j < _allocations[0].beneficiaries.length; j++) {
                address beneficiary = _allocations[0].beneficiaries[j];
                if (!newWill.isBeneficiary[beneficiary]) {
                    addBeneficiary(beneficiary, newWillId);
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
            if (tokenType == TokenType.Unknown) revert InvalidTokenType();

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
                    addBeneficiary(beneficiary, newWillId);
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
        emit TimeframesUpdated(msg.sender, _gracePeriod, _activityThreshold);
    }

    

    /**
     * @dev Returns list of beneficiaries for a will
     */
    function getBeneficiaries(address owner) external view returns (address[] memory) {
        if (!wills[owner].isActive) revert WillDoesNotExist();
        return wills[owner].beneficiaryList;
    }


    // function onERC721Received(
    //     address ,
    //     address ,
    //     uint256 ,
    //     bytes calldata 
    // ) external pure override returns (bytes4) {
    //     // Return the function selector to indicate successful receipt
    //     return this.onERC721Received.selector;
    // }

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

     /**
     * @dev Validates user-specified timeframes
     */
    function validateTimeframes(uint256 _gracePeriod, uint256 _activityThreshold) internal pure {
        if (_gracePeriod < MIN_GRACE_PERIOD || _gracePeriod > MAX_GRACE_PERIOD) {
            revert GracePeriodInvalid(_gracePeriod, MIN_GRACE_PERIOD, MAX_GRACE_PERIOD);
        }
        if (_activityThreshold < MIN_ACTIVITY_THRESHOLD || _activityThreshold > MAX_ACTIVITY_THRESHOLD) {
            revert ActivityThresholdInvalid(_activityThreshold, MIN_ACTIVITY_THRESHOLD, MAX_ACTIVITY_THRESHOLD);
        }
        if (_activityThreshold <= _gracePeriod) {
            revert ActivityThresholdTooShortForGracePeriod(_activityThreshold, _gracePeriod);
        }
    }

     /**
     * @dev Allows will owner to update timeframes for a specific will
     * @param willId ID of the will to update
     * @param _gracePeriod New grace period in seconds
     * @param _activityThreshold New activity threshold in seconds
     */
    function updateTimeframes(
        uint256 willId,
        uint256 _gracePeriod, 
        uint256 _activityThreshold
    ) external {
        // Validate will ID and get will
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        if (!will.isActive) revert WillIdNotFound(willId);
        
        // Verify ownership
        if (will.owner != msg.sender) revert NotWillOwner();
        
        // Validate the new timeframes
        validateTimeframes(_gracePeriod, _activityThreshold);
        
        // Check if dead man's switch is already triggered
        if (will.deadManSwitchTriggered) revert DeadManSwitchAlreadyTriggered();
        
        // Update the timeframes
        will.gracePeriod = _gracePeriod;
        will.activityThreshold = _activityThreshold;
        will.lastActivity = block.timestamp;
        
        emit TimeframesUpdated(msg.sender, _gracePeriod, _activityThreshold);
    }

    /**
     * @dev Modified check for Dead Man's Switch using custom timeframes
     */
    function checkAndTriggerDeadManSwitch(address willOwner) external onlyAuthorizedBackend {
        Will storage will = wills[willOwner];
        if (!will.isActive) revert WillNotActive();
        if (will.deadManSwitchTriggered) revert DeadManSwitchAlreadyTriggered();
        
        if (block.timestamp - will.lastActivity > will.activityThreshold) {
            will.deadManSwitchTriggered = true;
            will.deadManSwitchTimestamp = block.timestamp;
            emit GracePeriodStarted(willOwner, block.timestamp, will.gracePeriod);
        }
    }

        /**
     * @dev Checks if grace period has ended for a specific will ID
     * @param willId ID of the will to check
     * @return bool indicating if grace period has ended
     */
    function hasGracePeriodEnded(uint256 willId) public view returns (bool) {
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        if (!will.isActive) revert WillIdNotFound(willId);
        
        if (!will.deadManSwitchTriggered) return false;
        return block.timestamp > will.deadManSwitchTimestamp + will.gracePeriod;
    }

    /**
     * @dev Gets remaining grace period time for a specific will ID
     * @param willId ID of the will to check
     * @return uint256 remaining time in seconds
     */
    function getRemainingGracePeriod(uint256 willId) external view returns (uint256) {
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        if (!will.isActive) revert WillIdNotFound(willId);
        
        if (!will.deadManSwitchTriggered || hasGracePeriodEnded(willId)) return 0;
        
        uint256 endTime = will.deadManSwitchTimestamp + will.gracePeriod;
        return endTime > block.timestamp ? endTime - block.timestamp : 0;
    }

    /**
     * @dev Returns the activity threshold for a specific will
     * @param willId ID of the will to check
     * @return uint256 Activity threshold in seconds
     */
    function getActivityThreshold(uint256 willId) external view returns (uint256) {
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        if (!will.isActive) revert WillIdNotFound(willId);
        
        return will.activityThreshold;
    }

     /**
     * @dev Returns all allocations for a beneficiary in a specific will
     * @param willId ID of the will to check
     * @param beneficiary Address of the beneficiary
     * @return BeneficiaryAllocation[] Array of allocations for the beneficiary
     */
    function getBeneficiaryAllocations(uint256 willId, address beneficiary) 
    external 
    view 
    returns (BeneficiaryAllocation[] memory) 
{
    Will storage will = _getActiveWill(willId);
    if (!will.isBeneficiary[beneficiary]) revert NotABeneficiary();
    
    return will.beneficiaryAllocations[beneficiary];
}

    /**
     * @dev Gets time remaining until Dead Man's Switch triggers for a specific will ID
     * @param willId ID of the will to check
     * @return uint256 remaining time in seconds
     */
    function getTimeUntilDeadManSwitch(uint256 willId) external view returns (uint256) {
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        if (!will.isActive) revert WillIdNotFound(willId);
        
        if (will.deadManSwitchTriggered) return 0;
        
        uint256 timeSinceActivity = block.timestamp - will.lastActivity;
        if (timeSinceActivity >= will.activityThreshold) return 0;
        
        return will.activityThreshold - timeSinceActivity;
    }

    /**
     * @dev Get all will IDs owned by an address
     * @param owner Address to check
     * @return uint256[] Array of will IDs owned by the address
     */
    function getWillsByOwner(address owner) external view returns (uint256[] memory) {
        return ownerWillIds[owner];
    }

    /**
     * @dev Helper function to verify will exists and is active
     * @param willId ID of the will to verify
     * @return Will storage Returns the will if found and active
     */
    function _getActiveWill(uint256 willId) internal view returns (Will storage) {
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        if (!will.isActive) revert WillIdNotFound(willId);
        return will;
    }


    /**
     * @dev Allows beneficiaries to claim their allocated assets after grace period
     * @param willId ID of the will to claim from
     */
    function claimInheritance(uint256 willId) external nonReentrant {
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        
        if (!will.isActive) revert WillNotActive();
        if (!will.isBeneficiary[msg.sender]) revert NotABeneficiary();
        if (!will.deadManSwitchTriggered) revert DeadManSwitchNotTriggered();
        if (!hasGracePeriodEnded(willId)) revert GracePeriodNotEnded();
        if (will.hasClaimedDuringGrace[msg.sender]) revert AlreadyClaimed();

        // Mark as claimed
        will.hasClaimedDuringGrace[msg.sender] = true;

        // Get beneficiary allocations
        BeneficiaryAllocation[] storage allocations = will.beneficiaryAllocations[msg.sender];

        // Process each allocation
        for (uint i = 0; i < allocations.length; i++) {
            if (allocations[i].claimed) continue;

            if (allocations[i].tokenType == TokenType.Ether) {
                // Transfer Ether
                (bool success, ) = payable(msg.sender).call{value: allocations[i].amount}("");
                if (!success) revert EtherTransferFailed();
            } else if (allocations[i].tokenType == TokenType.ERC20) {
                // Transfer ERC20 tokens
                IERC20(allocations[i].tokenAddress).transfer(msg.sender, allocations[i].amount);
            } else if (allocations[i].tokenType == TokenType.ERC721) {
                // Transfer ERC721 token
                IERC721(allocations[i].tokenAddress).safeTransferFrom(
                    address(this),
                    msg.sender,
                    allocations[i].tokenId
                );
            } else if (allocations[i].tokenType == TokenType.ERC1155) {
                // Transfer ERC1155 tokens
                IERC1155(allocations[i].tokenAddress).safeTransferFrom(
                    address(this),
                    msg.sender,
                    allocations[i].tokenId,
                    allocations[i].amount,
                    ""
                );
            }

            allocations[i].claimed = true;
            emit BeneficiaryClaimed(
                msg.sender,
                allocations[i].tokenAddress,
                allocations[i].tokenId,
                allocations[i].amount
            );
        }

        emit WillClaimed(msg.sender, will.owner);
    }
}