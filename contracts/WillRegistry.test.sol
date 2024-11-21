// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title WillRegistry
 * @notice Contract for managing crypto wills with token allocations
 */
contract WillRegistryyy is Ownable, ReentrancyGuard {
    // Token type enumeration preserved
    enum TokenType { Ether, ERC20, ERC721, ERC1155, Unknown }

    // Minimum and maximum bounds for time periods (in days)
    uint256 private constant MIN_GRACE_PERIOD = 1 days;
    uint256 private constant MAX_GRACE_PERIOD = 30 days;
    uint256 private constant MIN_ACTIVITY_THRESHOLD = 30 days;
    uint256 private constant MAX_ACTIVITY_THRESHOLD = 365 days; 
    
    uint256 private _nextWillId = 1;

    struct TokenAllocation {
        address tokenAddress;
        TokenType tokenType;  // Enum preserved
        uint256 amount;        
        address[] beneficiaries;   
    }

    struct BeneficiaryAllocation {
        address tokenAddress;
        TokenType tokenType;  // Enum preserved
        uint256 amount;
        bool claimed;
    }
    
    struct Will {
        uint256 id;
        address owner;
        string name;
        uint256 lastActivity;
        bool isActive;
        TokenAllocation[] allocations;
        mapping(address => bool) isBeneficiary;
        address[] beneficiaryList;
        mapping(address => BeneficiaryAllocation[]) beneficiaryAllocations;
        uint256 gracePeriod;        
        uint256 activityThreshold;  
        bool deadManSwitchTriggered;
        uint256 deadManSwitchTimestamp;
        mapping(address => bool) hasClaimedDuringGrace;
    }

    mapping(uint256 => Will) public willsById;
    mapping(address => uint256[]) public ownerWillIds; 
    mapping(address => address[]) public beneficiaryWills;
    
    event WillCreated(address indexed owner, string name, address[] beneficiaries);
    event TokenAllocated(
        address indexed owner,
        address indexed token,
        TokenType tokenType,
        address indexed beneficiary,
        uint256 amount
    );
    event BeneficiaryClaimed(
        address indexed beneficiary,
        address indexed token,
        TokenType tokenType,
        uint256 amount
    );

    // Custom Errors
    error Unauthorized();
    error NotWillOwner();
    error InvalidBeneficiary();
    error NoAllocation();
    error WillNotFound();
    error BeneficiaryExists();
    error DeadSwitchActive();
    error WillInactive();
    error NotABeneficiary();
    error DeadManSwitchNotTriggered();
    error GracePeriodNotEnded();
    error AlreadyClaimed();
    error TokenTransferFailed();
    error GracePeriodInvalid(uint256 provided, uint256 min, uint256 max);
    error ActivityThresholdInvalid(uint256 provided, uint256 min, uint256 max);
    error ActivityThresholdTooShortForGracePeriod(uint256 activityThreshold, uint256 gracePeriod);
    error WillIdNotFound(uint256 willId);
    error WillIdInvalid();
    error InvalidToken();

    constructor() Ownable(msg.sender) {}

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
     * @dev Creates a new will with token allocations
     */
    function createWill(
        string memory _name, 
        TokenAllocation[] calldata _allocations, 
        uint256 _gracePeriod,
        uint256 _activityThreshold
    ) external nonReentrant {
        if (_allocations.length == 0) revert NoAllocation();

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

        // Process each token allocation
        for (uint i = 0; i < _allocations.length; i++) {
            // Validate token type
            if (_allocations[i].tokenType != TokenType.ERC20) revert InvalidToken();

            for (uint j = 0; j < _allocations[i].beneficiaries.length; j++) {
                address beneficiary = _allocations[i].beneficiaries[j];
                
                // Ensure beneficiary is added
                if (!newWill.isBeneficiary[beneficiary]) {
                    addBeneficiary(beneficiary, newWillId);
                }

                // Transfer ERC20 tokens
                uint256 amount = _allocations[i].amount;
                IERC20(_allocations[i].tokenAddress).transferFrom(msg.sender, address(this), amount);

                // Add to beneficiary tracking
                addBeneficiaryAllocation(
                    newWill,
                    beneficiary,
                    _allocations[i].tokenAddress,
                    TokenType.ERC20,
                    amount
                );

                // Emit allocation event
                emit TokenAllocated(
                    msg.sender,
                    _allocations[i].tokenAddress,
                    TokenType.ERC20,
                    beneficiary,
                    amount
                );
            }
        }

        emit WillCreated(msg.sender, _name, newWill.beneficiaryList);
    }

    /**
     * @dev Adds a beneficiary allocation to tracking
     */
    function addBeneficiaryAllocation(
        Will storage will,
        address beneficiary,
        address tokenAddress,
        TokenType tokenType,
        uint256 amount
    ) internal {
        BeneficiaryAllocation memory allocation = BeneficiaryAllocation({
            tokenAddress: tokenAddress,
            tokenType: tokenType,
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
        if (will.owner != msg.sender) revert Unauthorized();

        will.isBeneficiary[beneficiary] = true;
        will.beneficiaryList.push(beneficiary);
        
        // Add this will to beneficiary's list of wills
        beneficiaryWills[beneficiary].push(msg.sender);
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
     * @dev Allows beneficiaries to claim their allocated tokens after grace period
     * @param willId ID of the will to claim from
     */
    function claimInheritance(uint256 willId) external nonReentrant {
        if (willId == 0) revert WillIdInvalid();
        Will storage will = willsById[willId];
        
        if (!will.isActive) revert WillInactive();
        if (!will.isBeneficiary[msg.sender]) revert NotABeneficiary();
        if (!will.deadManSwitchTriggered) revert DeadManSwitchNotTriggered();
        if (block.timestamp <= will.deadManSwitchTimestamp + will.gracePeriod) revert GracePeriodNotEnded();
        if (will.hasClaimedDuringGrace[msg.sender]) revert AlreadyClaimed();

        // Mark as claimed
        will.hasClaimedDuringGrace[msg.sender] = true;

        // Get beneficiary allocations
        BeneficiaryAllocation[] storage allocations = will.beneficiaryAllocations[msg.sender];

        // Process each allocation
        for (uint i = 0; i < allocations.length; i++) {
            if (allocations[i].claimed) continue;

            // Only process ERC20 tokens
            if (allocations[i].tokenType == TokenType.ERC20) {
                // Transfer ERC20 tokens
                IERC20(allocations[i].tokenAddress).transfer(msg.sender, allocations[i].amount);
                allocations[i].claimed = true;

                emit BeneficiaryClaimed(
                    msg.sender,
                    allocations[i].tokenAddress,
                    TokenType.ERC20,
                    allocations[i].amount
                );
            }
        }
    }

    /**
     * @dev Returns the total number of wills created
     * @return Total number of wills created
     */
    function getTotalWillsCreated() external view returns (uint256) {
     return _nextWillId - 1;  // Subtract 1 since _nextWillId starts at 1 and is incremented after each will creation
 }

 /**
  * @dev Returns the total number of unique beneficiaries across all wills
  * @return Total number of unique beneficiaries
  */
 function getTotalUniqueBeneficiaries() external view returns (uint256) {
     // Use an array to track unique beneficiaries instead of a mapping
     address[] memory uniqueBeneficiaries = new address[](_nextWillId * 10);  // Oversized to ensure capacity
     uint256 uniqueBeneficiaryCount = 0;

     // Iterate through all will IDs
     for (uint256 willId = 1; willId < _nextWillId; willId++) {
         Will storage will = willsById[willId];
         
         // Check each beneficiary in the will
         for (uint256 i = 0; i < will.beneficiaryList.length; i++) {
             address beneficiary = will.beneficiaryList[i];
             
             // Check if beneficiary is already in the unique list
             bool alreadyAdded = false;
             for (uint256 j = 0; j < uniqueBeneficiaryCount; j++) {
                 if (uniqueBeneficiaries[j] == beneficiary) {
                     alreadyAdded = true;
                     break;
                 }
             }
             
             // If not already added, add to unique list
             if (!alreadyAdded) {
                 uniqueBeneficiaries[uniqueBeneficiaryCount] = beneficiary;
                 uniqueBeneficiaryCount++;
             }
         }
     }

     return uniqueBeneficiaryCount;
 }

 /**
  * @dev Calculates the total amount of tokens willed across all wills
  * @return Total amount of tokens willed
  */
 function getTotalTokensWilled() external view returns (uint256) {
     uint256 totalTokensWilled = 0;

     // Iterate through all will IDs
     for (uint256 willId = 1; willId < _nextWillId; willId++) {
         Will storage will = willsById[willId];
         
         // Iterate through all beneficiaries in this will
         for (uint256 i = 0; i < will.beneficiaryList.length; i++) {
             address beneficiary = will.beneficiaryList[i];

             // Get beneficiary allocations
             BeneficiaryAllocation[] storage allocations = will.beneficiaryAllocations[beneficiary];
             
             // Sum up unclaimed ERC20 token amounts
             for (uint256 j = 0; j < allocations.length; j++) {
                 if (!allocations[j].claimed && allocations[j].tokenType == TokenType.ERC20) {
                     totalTokensWilled += allocations[j].amount;
                 }
             }
         }
     }

     return totalTokensWilled;
 }

 /**
  * @dev Returns detailed statistics about wills
  * @return willCount Total number of wills
  * @return uniqueBeneficiaries Total number of unique beneficiaries
  * @return totalTokensAllocated Total amount of tokens allocated
  */
 function getWillRegistryStats() external view returns (
     uint256 willCount, 
     uint256 uniqueBeneficiaries, 
     uint256 totalTokensAllocated
 ) {
     willCount = _nextWillId - 1;
     
     // Use an array to track unique beneficiaries
     address[] memory uniqueBeneficiariesArray = new address[](_nextWillId * 10);  // Oversized to ensure capacity
     uint256 uniqueBeneficiaryCount = 0;
     uint256 totalTokens = 0;

     for (uint256 willId = 1; willId < _nextWillId; willId++) {
         Will storage will = willsById[willId];
         
         for (uint256 i = 0; i < will.beneficiaryList.length; i++) {
             address beneficiary = will.beneficiaryList[i];
             
             // Check if beneficiary is already in the unique list
             bool alreadyAdded = false;
             for (uint256 j = 0; j < uniqueBeneficiaryCount; j++) {
                 if (uniqueBeneficiariesArray[j] == beneficiary) {
                     alreadyAdded = true;
                     break;
                 }
             }
             
             // If not already added, add to unique list
             if (!alreadyAdded) {
                 uniqueBeneficiariesArray[uniqueBeneficiaryCount] = beneficiary;
                 uniqueBeneficiaryCount++;
             }

             // Get beneficiary allocations
             BeneficiaryAllocation[] storage allocations = will.beneficiaryAllocations[beneficiary];
             
             // Sum up unclaimed ERC20 token amounts
             for (uint256 j = 0; j < allocations.length; j++) {
                 if (!allocations[j].claimed && allocations[j].tokenType == TokenType.ERC20) {
                     totalTokens += allocations[j].amount;
                 }
             }
         }
     }

     uniqueBeneficiaries = uniqueBeneficiaryCount;
     totalTokensAllocated = totalTokens;
 }
}