
# WillRegistry Smart Contract Documentation

## Introduction
The **WillRegistry** contract is a smart contract built on the Ethereum blockchain for managing digital wills involving cryptocurrency assets. It allows users to allocate assets such as Ether, ERC20, ERC721 (NFTs), and ERC1155 tokens to designated beneficiaries, who can claim the assets after the owner's death, following a specified grace period.

## Contract Overview
This contract leverages OpenZeppelin's secure and battle-tested libraries to ensure safe and reliable operations. The main components include:
- Asset allocation (Ether, ERC20, ERC721, ERC1155 tokens).
- Grace period handling to prevent premature claims.
- Secure claiming mechanism for beneficiaries.
- Ownership and access control using OpenZeppelin's `Ownable` module.
- Reentrancy protection using `ReentrancyGuard`.

## Features
1. **Asset Allocation**: Allows the allocation of various types of assets to beneficiaries.
2. **Will Lifecycle Management**: Create, update, revoke, and execute wills.
3. **Grace Period**: Implements a grace period to prevent premature claims after the owner's death.
4. **Secure Claiming**: Ensures that only designated beneficiaries can claim allocated assets.
5. **Supports Multiple Token Standards**: Compatible with Ether, ERC20, ERC721, and ERC1155 token standards.
6. **Event Logging**: Emits detailed events for all major actions, providing transparency and traceability.

## Architecture
### Enums

- **`TokenType`**:
  - `ETH`: Represents native Ether.
  - `ERC20`: Represents fungible tokens.
  - `ERC721`: Represents non-fungible tokens.
  - `ERC1155`: Represents multi-token standard assets.
  - `Unknown` : Represents unknown tokens.

### Structs
- `TokenAllocation`: Represents an asset allocation with fields for token type, token address, token ID, and amount.
- `Will`: Represents a user's will with information about the owner, grace period, and allocations.
- `BeneficiaryAllocation`: Stores details of allocations made to a specific beneficiary.

## Functions Overview
### Public/External Functions
- **createWill(uint256 gracePeriod)**: Creates a new will with a specified grace period.
- **allocateAssets(uint256 willId, address beneficiary, Allocation[] memory allocations)**: Allocates assets to a beneficiary.
- **updateGracePeriod(uint256 willId, uint256 newGracePeriod)**: Updates the grace period for an existing will.
- **markDeceased(uint256 willId)**: Marks the owner of a will as deceased, triggering the grace period countdown.
- **claim(uint256 willId)**: Allows a beneficiary to claim allocated assets after the grace period has ended.

### Internal/Private Functions
- **addBeneficiaryAllocation(...)**: Adds a new allocation to a beneficiary.
- **hasGracePeriodEnded(uint256 willId)**: Checks if the grace period has ended.

## Events
- `WillCreated(address indexed owner, uint256 indexed willId)`: Emitted when a new will is created.
- `AssetAllocated(address indexed owner, address indexed beneficiary, address indexed tokenAddress, uint256 tokenId, uint256 amount)`: Emitted when assets are allocated to a beneficiary.
- `GracePeriodUpdated(uint256 indexed willId, uint256 newGracePeriod)`: Emitted when the grace period is updated.
- `OwnerMarkedDeceased(address indexed owner, uint256 indexed willId)`: Emitted when the owner is marked as deceased.
- `BeneficiaryClaimed(address indexed beneficiary, address indexed tokenAddress, uint256 tokenId, uint256 amount)`: Emitted when a beneficiary claims their allocated assets.
- `WillClaimed(address indexed beneficiary, address indexed owner)`: Emitted when all assets from a will are claimed.

## Security Considerations
- **Reentrancy Protection**: Utilizes OpenZeppelin's `ReentrancyGuard` to prevent reentrancy attacks.
- **Ownership Verification**: Ensures only the owner or authorized individuals can update will details.
- **Grace Period Enforcement**: Prevents premature claims by enforcing a grace period.

## Dependencies
- OpenZeppelin Contracts:
  - `IERC20`: Interface for ERC20 tokens.
  - `IERC721`: Interface for ERC721 tokens (NFTs).
  - `IERC1155`: Interface for ERC1155 tokens (multi-token standard).
  - `Ownable`: Access control for contract ownership.
  - `ReentrancyGuard`: Protection against reentrancy attacks.

## User Interactions
- Will Owners Can:

    - Create a new will
    - Add/remove beneficiaries
    - Allocate different token types
    - Update grace periods and activity thresholds
    - Track will status

- Beneficiaries Can:

    - View allocated assets
    - Claim inheritance after grace period
    - Verify claim status

- Security Considerations

    - Onchain validation of token types
    - Non-reentrant function modifiers
    - Owner and backend authorization checks
    - Strict time period validations
    - Comprehensive error handling

## Usage Examples
### Creating a Will
```solidity
willRegistry.createWill(30 days);
```

### Allocating Assets
```solidity
Allocation[] memory allocations = new Allocation[](1);
allocations[0] = Allocation({
    tokenType: TokenType.ERC20,
    tokenAddress: 0xTokenAddress,
    tokenId: 0,
    amounts: [1000]
});
willRegistry.allocateAssets(1, 0xBeneficiaryAddress, allocations);
```

### Marking Owner as Deceased
```solidity
willRegistry.markDeceased(1);
```

### Claiming Allocated Assets
```solidity
willRegistry.claim(1);
```

## Deployment Instructions
Ensure you have the following prerequisites:
- Node.js and npm installed.
- Hardhat or Foundry for contract deployment.
- OpenZeppelin Contracts installed via npm.

### Deployment Example
```bash
npx hardhat run scripts/deploy.js
```

## Conclusion
The **WillRegistry** contract provides a robust solution for managing digital wills on the blockchain. It offers secure asset allocation and claiming mechanisms, supports various token standards, and enforces a grace period to protect against premature claims.
