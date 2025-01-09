// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWillRegistry {
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
    );
}

contract WillStatistics {
    IWillRegistry public immutable willRegistry;
    
    error WillIdInvalid();
    error WillIdNotFound();
    error Unauthorized();

    constructor(address _willRegistryAddress) {
        willRegistry = IWillRegistry(_willRegistryAddress);
    }

    /**
     * @dev Returns the activity threshold for a specific will
     * @param willId ID of the will to check
     * @param owner Address of the will owner
     * @return uint256 Activity threshold in seconds
     */
    function getActivityThreshold(uint256 willId, address owner) external view returns (uint256) {
        if (willId == 0) revert WillIdInvalid();
        
        (
            ,
            address willOwner,
            ,
            ,
            bool isActive,
            ,
            ,
            uint256 activityThreshold,
            ,
            ,
        ) = willRegistry.getWillDetailsByIdAndOwner(willId, owner);
        
        if (!isActive) revert WillIdNotFound();
        if (willOwner != owner) revert Unauthorized();
        
        return activityThreshold;
    }

    

    /**
     * @dev Returns the grace period for a specific will
     * @param willId ID of the will to check
     * @param owner Address of the will owner
     * @return uint256 Grace period in seconds
     */
    function getGracePeriod(uint256 willId, address owner) external view returns (uint256) {
        if (willId == 0) revert WillIdInvalid();
        
        (
            ,
            address willOwner,
            ,
            ,
            bool isActive,
            ,
            uint256 gracePeriod,
            ,
            ,
            ,
        ) = willRegistry.getWillDetailsByIdAndOwner(willId, owner);
        
        if (!isActive) revert WillIdNotFound();
        if (willOwner != owner) revert Unauthorized();
        
        return gracePeriod;
    }
}