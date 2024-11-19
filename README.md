# WillRegistry Smart Contract

## Overview
A blockchain-based crypto will management system with Dead Man's Switch functionality, allowing users to create wills, allocate assets, and set inheritance conditions.

## Key Functions for Frontend Interaction

### User-Facing Primary Functions

1. **`createWill()`**
   - Primary function for users to create a new will
   - Requires:
     - Will name
     - Token allocations
     - Grace period
     - Activity threshold
   - Frontend needs:
     - Form to input beneficiaries
     - Token allocation mechanism
     - Timeframe selection

2. **`addBeneficiaryWithAllocation()`**
   - Add new beneficiaries to existing will
   - Requires:
     - Will ID
     - Beneficiary address
     - Token allocations
   - Frontend needs:
     - Will selection dropdown
     - Beneficiary address input
     - Token allocation interface

3. **`claimInheritance()`**
   - Beneficiaries claim allocated assets
   - Requires:
     - Will ID
   - Frontend needs:
     - List of wills user is a beneficiary in
     - Check grace period status
     - Claim button

4. **`updateTimeframes()`**
   - Modify will's grace period and activity threshold
   - Requires:
     - Will ID
     - New grace period
     - New activity threshold
   - Frontend needs:
     - Timeframe adjustment sliders/inputs



## Utility Read Functions (Frontend Display)

- `getWillsByOwner()`: Retrieve user's wills
- `getBeneficiaryAllocations()`: View beneficiary's allocated assets
- `getRemainingGracePeriod()`: Display remaining grace period
- `getTimeUntilDeadManSwitch()`: Show time before inactivity trigger
- `hasGracePeriodEnded()`: Check claim eligibility




## Deployed Addresses

WillRegistryModule#WillRegistry - 0x9515ac929D2103787381eca5c629dFa5362373E5

## Verifying deployed contracts

Verifying contract "contracts/WillRegistry.sol:WillRegistry" for network lisk-sepolia...
Successfully verified contract "contracts/WillRegistry.sol:WillRegistry" for network lisk-sepolia:
  - https://sepolia-blockscout.lisk.com//address/0x9515ac929D2103787381eca5c629dFa5362373E5#code