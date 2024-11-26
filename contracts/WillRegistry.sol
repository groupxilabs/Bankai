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
    enum TokenType { Ether, ERC20, Unknown }

    // Minimum and maximum bounds for time periods (in days)
    uint256 private constant MIN_GRACE_PERIOD = 1 seconds;
    uint256 private constant MAX_GRACE_PERIOD = 30 seconds;
    uint256 private constant MIN_ACTIVITY_THRESHOLD = 30 seconds;
    uint256 private constant MAX_ACTIVITY_THRESHOLD = 365 seconds; 
    
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

    struct BeneficiaryWillInfo {
        uint256 willId;
        string willName;
        address tokenAddress;
        TokenType tokenType;
        uint256 amount;
        bool claimed;
        address willOwner;
    }

    struct WillDetails {
        uint256 willId;
        string willName;
        address tokenAddress;
        uint8 tokenType;
        uint256 totalAmount;
        uint256 beneficiaryCount;
        uint256 activityPeriod;
        uint256 gracePeriod;
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
    error Unauthorized();
    error NotWillOwner();
    error InvalidBeneficiary();
    error NoAllocation();
    error WillNotFound();
    error InvalidToken();
    error BeneficiaryExists();
    error BeneficiaryMissing();
    error DeadSwitchActive();
    error WillInactive();
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
        if (!authorizedBackends[msg.sender]) revert Unauthorized();
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
    function getTokenType(address tokenAddress) internal view returns (TokenType) {
        // Default implementation always returns ERC20 for demonstration
        // In a full implementation, this would detect different token types
        if (tokenAddress == address(0)) return TokenType.Unknown;
        
        // Attempt to call a view method of ERC20 to validate
        try IERC20(tokenAddress).totalSupply() returns (uint256) {
            return TokenType.ERC20;
        } catch {
            return TokenType.Unknown;
        }
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
    ) external  nonReentrant {
        if (beneficiary == address(0)) revert InvalidBeneficiary();

        
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
    
        // Process token allocations
        for (uint i = 0; i < allocations.length; i++) {
            TokenType tokenType = allocations[i].tokenType;
            if (tokenType == TokenType.Unknown) revert InvalidToken();
    
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
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        
        Will storage will = willsById[willId];
        if (will.isBeneficiary[beneficiary]) revert BeneficiaryExists();
        if (will.owner != msg.sender) revert NotWillOwner();

        will.isBeneficiary[beneficiary] = true;
        will.beneficiaryList.push(beneficiary);
        
        // Add this will to beneficiary's list of wills
        beneficiaryWills[beneficiary].push(msg.sender);

        emit BeneficiaryAdded(msg.sender, beneficiary);
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
        if (_allocations.length == 0 && msg.value == 0) revert NoAllocation();

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
            if (tokenType == TokenType.Unknown) revert InvalidToken();

            // Transfer tokens to the contract based on type
            if (tokenType == TokenType.ERC20) {
                for (uint j = 0; j < _allocations[i].beneficiaries.length; j++) {
                    uint256 amount = _allocations[i].amounts[j];
                    IERC20(_allocations[i].tokenAddress).transferFrom(msg.sender, address(this), amount);
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
                    TokenType.ERC20,
                    0, // No token ID for ERC20
                    _allocations[i].amounts[j]
                );

                // Emit allocation event
                emit TokenAllocated(
                    msg.sender,
                    _allocations[i].tokenAddress,
                    TokenType.ERC20,
                    beneficiary,
                    0, // No token ID for ERC20
                    _allocations[i].amounts[j]
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
        if (!wills[owner].isActive) revert WillNotFound();
        return wills[owner].beneficiaryList;
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
        if (will.deadManSwitchTriggered) revert DeadSwitchActive();
        
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
        if (!will.isActive) revert WillInactive();
        if (will.deadManSwitchTriggered) revert DeadSwitchActive();
        
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
    // function getActivityThreshold(uint256 willId) external view returns (uint256) {
    //     if (willId == 0) revert WillIdInvalid();
    //     Will storage will = willsById[willId];
    //     if (!will.isActive) revert WillIdNotFound(willId);
        
    //     return will.activityThreshold;
    // }

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

   
    function getWillDetailsByIdAndOwner(uint256 willId, address owner) external view returns (
        uint256 id,
        address willOwner,
        string memory name,
        uint256 lastActivity,
        bool isActive,
        uint256 etherAllocation,
        uint256 gracePeriod,
        uint256 activityThreshold,
        bool deadManSwitchTriggered,
        uint256 deadManSwitchTimestamp,
        address[] memory beneficiaries
    ) {
        // Validate that the will exists and belongs to the specified owner
        Will storage will = _getActiveWill(willId);
        if (will.owner != owner) revert NotWillOwner();
        
        return (
            will.id,
            will.owner,
            will.name,
            will.lastActivity,
            will.isActive,
            will.etherAllocation,
            will.gracePeriod,
            will.activityThreshold,
            will.deadManSwitchTriggered,
            will.deadManSwitchTimestamp,
            will.beneficiaryList
        );
    }


    /**
     * @dev Allows beneficiaries to claim their allocated assets after grace period
     * @param willId ID of the will to claim from
     */
    function claimInheritance(uint256 willId) external nonReentrant {
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        
        if (!will.isActive) revert WillInactive();
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

    /**
  * @dev Returns the total number of unique beneficiaries across all wills
  * @return Total number of unique beneficiaries
  */
    function getTotalUniqueBeneficiaries(address owner) external view returns (uint256) {
        // Get all will IDs for this owner
        uint256[] memory willIds = ownerWillIds[owner];
        
        // Create temporary array to track unique beneficiaries
        address[] memory tempBeneficiaries = new address[](willIds.length * 10); // Oversized for safety
        uint256 uniqueBeneficiaryCount = 0;
        
        // Iterate through all wills owned by this address
        for (uint256 i = 0; i < willIds.length; i++) {
            Will storage will = willsById[willIds[i]];
            
            // For each beneficiary in this will
            for (uint256 j = 0; j < will.beneficiaryList.length; j++) {
                address beneficiary = will.beneficiaryList[j];
                
                // Check if this beneficiary is already in our unique list
                bool isUnique = true;
                for (uint256 k = 0; k < uniqueBeneficiaryCount; k++) {
                    if (tempBeneficiaries[k] == beneficiary) {
                        isUnique = false;
                        break;
                    }
                }
                
                // If it's unique, increment counter and add to tracking array
                if (isUnique) {
                    tempBeneficiaries[uniqueBeneficiaryCount] = beneficiary;
                    uniqueBeneficiaryCount++;
                }
            }
        }
        
        return uniqueBeneficiaryCount;
    }

    function getTotalTokensWilled(address owner) external view returns (uint256) {
        uint256 totalTokensWilled = 0;
        uint256[] memory ownerWills = ownerWillIds[owner];
        
        // Iterate through all wills owned by this address
        for (uint256 i = 0; i < ownerWills.length; i++) {
            uint256 willId = ownerWills[i];
            Will storage will = willsById[willId];
            
            // Skip if will is not active
            if (!will.isActive) continue;
            
            // Iterate through all beneficiaries in this will
            for (uint256 j = 0; j < will.beneficiaryList.length; j++) {
                address beneficiary = will.beneficiaryList[j];
    
                // Get beneficiary allocations
                BeneficiaryAllocation[] storage allocations = will.beneficiaryAllocations[beneficiary];
                
                // Sum up unclaimed ERC20 token amounts
                for (uint256 k = 0; k < allocations.length; k++) {
                    if (!allocations[k].claimed && allocations[k].tokenType == TokenType.ERC20) {
                        totalTokensWilled += allocations[k].amount;
                    }
                }
            }
        }
    
        return totalTokensWilled;
    }

    /**
     * @dev Returns the total number of wills created by a specific address
     * @param owner Address of the will creator
     * @return uint256 Total number of wills created by the owner
     */
    function getTotalWillsCreated(address owner) external view returns (uint256) {
        return ownerWillIds[owner].length;
    }

    
        function getWillsWilledToBeneficiary(address beneficiary) 
        external 
        view 
        returns (BeneficiaryWillInfo[] memory) 
    {
        // Get total allocations first
        uint256 totalAllocations = _countTotalAllocations(beneficiary);
        
        // Create return array with exact size needed
        BeneficiaryWillInfo[] memory willInfos = new BeneficiaryWillInfo[](totalAllocations);
        
        // Keep track of unique allocations
        uint256 currentIndex = 0;
        
        address[] memory willOwnerAddresses = beneficiaryWills[beneficiary];
        
        for (uint256 i = 0; i < willOwnerAddresses.length; i++) {
            address owner = willOwnerAddresses[i];
            uint256[] memory ownerWills = ownerWillIds[owner];
            
            for (uint256 j = 0; j < ownerWills.length; j++) {
                uint256 willId = ownerWills[j];
                Will storage will = willsById[willId];
                
                if (!will.isActive || !will.isBeneficiary[beneficiary]) {
                    continue;
                }
                
                BeneficiaryAllocation[] storage allocations = will.beneficiaryAllocations[beneficiary];
                
                // Add only the first allocation for this will
                if (allocations.length > 0) {
                    bool isDuplicate = false;
                    
                    // Check if this allocation is already added
                    for (uint256 k = 0; k < currentIndex; k++) {
                        if (willInfos[k].willId == willId && 
                            willInfos[k].tokenAddress == allocations[0].tokenAddress &&
                            willInfos[k].amount == allocations[0].amount) {
                            isDuplicate = true;
                            break;
                        }
                    }
                    
                    if (!isDuplicate) {
                        willInfos[currentIndex] = BeneficiaryWillInfo({
                            willId: willId,
                            willName: will.name,
                            tokenAddress: allocations[0].tokenAddress,
                            tokenType: allocations[0].tokenType,
                            amount: allocations[0].amount,
                            claimed: allocations[0].claimed,
                            willOwner: owner
                        });
                        currentIndex++;
                    }
                }
            }
        }
        
        // Create final array with correct size
        BeneficiaryWillInfo[] memory finalWillInfos = new BeneficiaryWillInfo[](currentIndex);
        for (uint256 i = 0; i < currentIndex; i++) {
            finalWillInfos[i] = willInfos[i];
        }
        
        return finalWillInfos;
    }

    function _countTotalAllocations(address beneficiary) internal view returns (uint256) {
        address[] memory willOwnerAddresses = beneficiaryWills[beneficiary];
        uint256 totalAllocations = 0;
        
        for (uint256 i = 0; i < willOwnerAddresses.length; i++) {
            uint256[] memory ownerWills = ownerWillIds[willOwnerAddresses[i]];
            
            for (uint256 j = 0; j < ownerWills.length; j++) {
                Will storage will = willsById[ownerWills[j]];
                
                if (will.isActive && will.isBeneficiary[beneficiary]) {
                    totalAllocations += will.beneficiaryAllocations[beneficiary].length;
                }
            }
        }
        
        return totalAllocations;
    }

    function _fillWillInfoArray(address beneficiary, BeneficiaryWillInfo[] memory willInfos) internal view {
        address[] memory willOwnerAddresses = beneficiaryWills[beneficiary];
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < willOwnerAddresses.length; i++) {
            address owner = willOwnerAddresses[i];
            uint256[] memory ownerWills = ownerWillIds[owner];
            
            for (uint256 j = 0; j < ownerWills.length; j++) {
                uint256 willId = ownerWills[j];
                Will storage will = willsById[willId];
                
                if (!will.isActive || !will.isBeneficiary[beneficiary]) {
                    continue;
                }
                
                BeneficiaryAllocation[] storage allocations = will.beneficiaryAllocations[beneficiary];
                currentIndex = _processAllocations(willInfos, currentIndex, will, allocations, owner, willId);
            }
        }
    }

    function _processAllocations(
        BeneficiaryWillInfo[] memory willInfos,
        uint256 startIndex,
        Will storage will,
        BeneficiaryAllocation[] storage allocations,
        address owner,
        uint256 willId
    ) internal view returns (uint256) {
        uint256 currentIndex = startIndex;
        
        for (uint256 i = 0; i < allocations.length; i++) {
            willInfos[currentIndex] = BeneficiaryWillInfo({
                willId: willId,
                willName: will.name,
                tokenAddress: allocations[i].tokenAddress,
                tokenType: allocations[i].tokenType,
                amount: allocations[i].amount,
                claimed: allocations[i].claimed,
                willOwner: owner
            });
            currentIndex++;
        }
        
        return currentIndex;
    }
 

    /**
     * @dev Get detailed information about all wills owned by an address
     * @param owner Address to check
     * @return WillDetails[] Array of detailed information about each will
     */
    function getWillsByOwner(address owner) external view returns (WillDetails[] memory) {
        uint256[] memory willIds = ownerWillIds[owner];
        WillDetails[] memory details = new WillDetails[](willIds.length);
        
        for (uint256 i = 0; i < willIds.length; i++) {
            Will storage will = willsById[willIds[i]];
            
            // Calculate total amount across all allocations
            uint256 totalAmount = will.etherAllocation; // Start with Ether allocation
            
            // Loop through all beneficiaries to sum up their allocations
            for (uint256 j = 0; j < will.beneficiaryList.length; j++) {
                address beneficiary = will.beneficiaryList[j];
                BeneficiaryAllocation[] storage allocations = will.beneficiaryAllocations[beneficiary];
                
                for (uint256 k = 0; k < allocations.length; k++) {
                    if (allocations[k].tokenType == TokenType.ERC20) {
                        totalAmount += allocations[k].amount;
                    }
                }
            }
            
            // Get the token address and type from the first allocation if it exists
            address tokenAddress = address(0);
            uint8 tokenType = uint8(TokenType.Unknown);
            
            if (will.beneficiaryList.length > 0) {
                address firstBeneficiary = will.beneficiaryList[0];
                BeneficiaryAllocation[] storage firstAllocations = will.beneficiaryAllocations[firstBeneficiary];
                if (firstAllocations.length > 0) {
                    tokenAddress = firstAllocations[0].tokenAddress;
                    tokenType = uint8(firstAllocations[0].tokenType);
                }
            }
            
            details[i] = WillDetails({
                willId: will.id,
                willName: will.name,
                tokenAddress: tokenAddress,
                tokenType: tokenType,
                totalAmount: totalAmount,
                beneficiaryCount: will.beneficiaryList.length,
                activityPeriod: will.activityThreshold,
                gracePeriod: will.gracePeriod
            });
        }
        
        return details;
    }
    

}