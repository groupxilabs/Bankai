# TrustFund Smart Contract Documentation

## Overview
The **TrustFund** contract is a decentralized application that allows trustees to create and manage trust funds with designated beneficiaries. Each fund has a defined purpose, target amount, and withdrawal conditions.

### Key Features
- Trustees can create and manage multiple trust funds.
- Beneficiaries can withdraw funds once conditions are met.
- Funds are securely held and cannot be withdrawn prematurely.
- Supports deposits from external parties.
- Includes validation, status updates, and error handling.

---

## Contract Structure

### State Variables
1. **_fundCounter**: Tracks the total number of funds created.
2. **_funds**: A mapping that stores all trust fund details by `fundId`.
3. **_trusteeFunds**: Tracks all funds created by a specific trustee.

### Fund Structure
Each trust fund is represented by the `Fund` struct:
- **fundName**: Name of the fund.
- **purpose**: Purpose of the fund.
- **beneficiary**: Address of the beneficiary.
- **targetAmount**: The financial goal of the fund (in wei).
- **targetDate**: The deadline for fund completion (Unix timestamp).
- **currentBalance**: Current balance of the fund (in wei).
- **trustee**: Address of the fund creator.
- **isActive**: Boolean indicating if the fund is active.
- **category**: Category of the fund (e.g., "Charitable").
- **isWithdrawn**: Boolean indicating if the funds have been withdrawn.

---

## Functionality

### Fund Creation
#### `createFund()`
Allows a trustee to create a new fund.
- **Parameters**:
  - `fundName`: Name of the fund.
  - `purpose`: Description of the fund's purpose.
  - `beneficiary`: Address of the beneficiary.
  - `targetAmount`: Goal amount (in wei).
  - `targetDate`: Deadline for reaching the goal.
  - `category`: Fund category.
- **Returns**: `fundId` (ID of the newly created fund).
- **Validations**:
  - Fund name, purpose, and category must not be empty.
  - Target amount must be greater than 0.
  - Target date must be in the future.

---

### Deposits
#### `deposit()`
Allows anyone to deposit funds into an active trust fund.
- **Parameters**:
  - `fundId`: The ID of the fund to deposit into.
- **Validations**:
  - Fund must exist and be active.
  - Deposit amount must be greater than 0.
- **Emits**: `FundDeposit` event.

---

### Withdrawals
#### `withdrawFund()`
Allows a beneficiary to withdraw funds after the target date.
- **Parameters**:
  - `fundId`: The ID of the fund to withdraw from.
- **Validations**:
  - Caller must be the fund's beneficiary.
  - Fund must be active and have sufficient balance.
  - Target date must have passed.
  - Funds must not already be withdrawn.
- **Emits**: `FundWithdrawn` event.

---

### Fund Management
#### `setFundStatus()`
Allows the trustee to activate or deactivate a fund.
- **Parameters**:
  - `fundId`: ID of the fund to update.
  - `status`: New active status.
- **Emits**: `FundStatusChanged` event.

---

### View Functions
- **`getFundDetails()`**: Retrieves details of a specific fund.
- **`getTrusteeFunds()`**: Retrieves all fund IDs associated with a trustee.
- **`getFundBalance()`**: Returns the current balance of a specific fund.
- **`getBatchFundDetails()`**: Retrieves details for multiple funds in one call.
- **`isTargetReached()`**: Checks if a fund's goal has been reached.
- **`isWithdrawable()`**: Verifies if the fund is eligible for withdrawal.
- **`getTimeRemaining()`**: Returns the time remaining until the target date.

---

## Events

### `FundCreated`
Emitted when a new trust fund is created.
- **Parameters**:
  - `fundId`: ID of the created fund.
  - `fundName`: Name of the fund.
  - `trustee`: Address of the trustee.
  - `beneficiary`: Address of the beneficiary.
  - `targetAmount`: Goal amount of the fund.
  - `targetDate`: Deadline for the fund.

### `FundDeposit`
Emitted when funds are deposited.
- **Parameters**:
  - `fundId`: ID of the fund.
  - `depositor`: Address of the depositor.
  - `amount`: Amount deposited.
  - `newBalance`: Updated fund balance.

### `FundWithdrawn`
Emitted when funds are withdrawn by the beneficiary.
- **Parameters**:
  - `fundId`: ID of the fund.
  - `beneficiary`: Address of the beneficiary.
  - `amount`: Amount withdrawn.
  - `withdrawalTime`: Time of withdrawal.

### `FundStatusChanged`
Emitted when a fund's status is updated.
- **Parameters**:
  - `fundId`: ID of the fund.
  - `isActive`: Updated status.

---

## Error Handling

- **`InvalidFundParameters`**: Triggered for invalid fund data during creation.
- **`InvalidFundId`**: Triggered for non-existent or invalid fund IDs.
- **`UnauthorizedAccess`**: Triggered when an unauthorized caller tries to access restricted functionality.
- **`InvalidDeposit`**: Triggered when a deposit amount is invalid.
- **`FundInactive`**: Triggered for inactive funds.
- **`InvalidTargetDate`**: Triggered for invalid fund target dates.
- **`InvalidAmount`**: Triggered for invalid withdrawal or deposit amounts.
- **`WithdrawalNotAllowed`**: Triggered for premature withdrawal attempts.
- **`FundAlreadyWithdrawn`**: Triggered when attempting to withdraw from a completed fund.
- **`WithdrawalBeforeTargetDate`**: Triggered when attempting to withdraw before the target date.

---

## Deployment and Integration

### Prerequisites
1. Install a compatible Ethereum development environment (e.g., Hardhat or Foundry).
2. Add OpenZeppelin Contracts to your project:
   ```bash
   npm install @openzeppelin/contracts

## Deployment

1. **Compile the contract** using your chosen framework.

   For example, if you're using Hardhat, you can compile the contract by running:

   ```bash
   npx hardhat compile

2. Deploy the contract to your desired network.

    Use the deployment script for your desired Ethereum network (e.g. Mainnet). Here's an example using Hardhat:

    ```bash
    npx hardhat run scripts/deploy.js --network lisk-sepolia


3. Verify the contract on a block explorer if required.

    After deployment, you can verify the contract on Etherscan by running:

    ```bash
    npx hardhat verify --network lisk-sepolia <contract_address> <constructor_arguments>

## Example Interaction

### Create a Fund

To create a fund for a specific purpose (e.g., education), use the following Solidity function:

```solidity
    trustFund.createFund(
    "Education Fund",
    "For beneficiary's education expenses",
    0x123...abc,  // Beneficiary's address
    10 ether,     // Fund goal (10 Ether)
    block.timestamp + 30 days,  // Fund duration (30 days)
    "Education"   // Fund type or category
    );
```

### Deposit into Fund
To deposit Ether into the trust fund, use the following Solidity code:

```solidity
trustFund.deposit{value: 1 ether}(fundId);
```
This sends 1 Ether to the fund identified by fundId.

### Withdraw Funds
To withdraw funds from the created trust fund, use this function:

```solidity
trustFund.withdrawFund(fundId);
```

## Conclusion
The TrustFund contract offers a secure way to create and manage trust funds on the Ethereum blockchain. By leveraging decentralized technology, it ensures transparency and accessibility for both trustees and beneficiaries.


