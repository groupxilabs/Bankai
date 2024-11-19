// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWillRegistry {
    enum TokenType { Ether, ERC20, ERC721, ERC1155, Unknown }

    struct TokenAllocation {
        address tokenAddress;
        TokenType tokenType;
        uint256[] tokenIds;        
        uint256[] amounts;         
        address[] beneficiaries;   
    }

    function createWill(
        string memory _name, 
        TokenAllocation[] calldata _allocations, 
        uint256 _gracePeriod,
        uint256 _activityThreshold
    ) external payable;

  
}