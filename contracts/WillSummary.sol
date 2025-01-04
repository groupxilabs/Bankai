// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Interface for the WillRegistry contract
interface IWillRegistry {
    enum TokenType { Ether, ERC20, Unknown }

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
        bool isActive;
        address[] beneficiaryList;
    }

    function _nextWillId() external view returns (uint256);
    function willsById(uint256 willId) external view returns (Will memory);
    function getBeneficiaryAllocations(uint256 willId, address beneficiary) external view returns (BeneficiaryAllocation[] memory);
}

contract WillSummary {
    IWillRegistry public willRegistry;

    constructor(address _registryAddress) {
        willRegistry = IWillRegistry(_registryAddress);
    }

    /**
     * @dev Gets total statistics for the entire contract
     * @return totalTokens Total amount of tokens across all wills
     * @return totalWills Total number of wills created
     * @return totalBeneficiaries Total number of unique beneficiaries
     */
    function getContractStatistics() external view returns (
        uint256 totalTokens,
        uint256 totalWills,
        uint256 totalBeneficiaries
    ) {
        // Get total wills (using _nextWillId which starts at 1)
        totalWills = willRegistry._nextWillId() - 1;

        // Create a temporary array to track unique beneficiaries
        address[] memory uniqueBeneficiaries = new address[](totalWills * 10);
        uint256 beneficiaryCount = 0;

        // Iterate through all wills
        for (uint256 i = 1; i < willRegistry._nextWillId(); i++) {
            IWillRegistry.Will memory will = willRegistry.willsById(i);

            // Skip if will is not active
            if (!will.isActive) continue;

            // Count unique beneficiaries
            for (uint256 j = 0; j < will.beneficiaryList.length; j++) {
                address beneficiary = will.beneficiaryList[j];
                
                // Check if beneficiary is already counted
                bool isUnique = true;
                for (uint256 k = 0; k < beneficiaryCount; k++) {
                    if (uniqueBeneficiaries[k] == beneficiary) {
                        isUnique = false;
                        break;
                    }
                }

                // Add unique beneficiary
                if (isUnique) {
                    uniqueBeneficiaries[beneficiaryCount] = beneficiary;
                    beneficiaryCount++;
                }

                // Sum up all unclaimed ERC20 token allocations
                IWillRegistry.BeneficiaryAllocation[] memory allocations = 
                    willRegistry.getBeneficiaryAllocations(i, beneficiary);
                
                for (uint256 k = 0; k < allocations.length; k++) {
                    if (!allocations[k].claimed && allocations[k].tokenType == IWillRegistry.TokenType.ERC20) {
                        totalTokens += allocations[k].amount;
                    }
                }
            }
        }

        totalBeneficiaries = beneficiaryCount;
    }

    /**
     * @dev Gets total unclaimed tokens in the contract
     * @return uint256 Total amount of unclaimed tokens
     */
    function getTotalUnclaimedTokens() external view returns (uint256) {
        uint256 totalTokens = 0;

        for (uint256 i = 1; i < willRegistry._nextWillId(); i++) {
            IWillRegistry.Will memory will = willRegistry.willsById(i);

            if (!will.isActive) continue;

            for (uint256 j = 0; j < will.beneficiaryList.length; j++) {
                address beneficiary = will.beneficiaryList[j];
                IWillRegistry.BeneficiaryAllocation[] memory allocations = 
                    willRegistry.getBeneficiaryAllocations(i, beneficiary);

                for (uint256 k = 0; k < allocations.length; k++) {
                    if (!allocations[k].claimed && allocations[k].tokenType == IWillRegistry.TokenType.ERC20) {
                        totalTokens += allocations[k].amount;
                    }
                }
            }
        }

        return totalTokens;
    }

    /**
     * @dev Gets total number of active wills in the contract
     * @return uint256 Total number of active wills
     */
    function getTotalActiveWills() external view returns (uint256) {
        uint256 activeWills = 0;

        for (uint256 i = 1; i < willRegistry._nextWillId(); i++) {
            IWillRegistry.Will memory will = willRegistry.willsById(i);
            if (will.isActive) {
                activeWills++;
            }
        }

        return activeWills;
    }
}