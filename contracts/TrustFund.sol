// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title TrustFund
 * @dev A contract for managing trust funds with multiple beneficiaries
 */
contract TrustFund is ReentrancyGuard {
    uint256 private _fundCounter;
    
    struct Fund {
        string fundName;
        string purpose;
        address beneficiary;
        uint256 targetAmount;
        uint256 targetDate;
        uint256 currentBalance;
        address trustee;
        bool isActive;
        string category;
        bool isWithdrawn;
    }
    
    mapping(uint256 => Fund) private _funds;
    mapping(address => uint256[]) private _trusteeFunds;
    
    event FundCreated(
        uint256 indexed fundId,
        string fundName,
        address indexed trustee,
        address beneficiary,
        uint256 targetAmount,
        uint256 targetDate
    );
    
    event FundDeposit(
        uint256 indexed fundId,
        address indexed depositor,
        uint256 amount,
        uint256 newBalance
    );
    
    event FundStatusChanged(
        uint256 indexed fundId,
        bool isActive
    );

    event FundWithdrawn(
        uint256 indexed fundId,
        address indexed beneficiary,
        uint256 amount,
        uint256 withdrawalTime
    );
    
    error InvalidFundParameters();
    error InvalidFundId();
    error UnauthorizedAccess();
    error InvalidDeposit();
    error FundInactive();
    error InvalidTargetDate();
    error InvalidAmount();
    error WithdrawalNotAllowed();
    error FundAlreadyWithdrawn();
    error WithdrawalBeforeTargetDate();
    
    modifier onlyTrustee(uint256 fundId) {
        if (_funds[fundId].trustee != msg.sender) {
            revert UnauthorizedAccess();
        }
        _;
    }
    
    modifier validFundId(uint256 fundId) {
        if (fundId >= _fundCounter || _funds[fundId].trustee == address(0)) {
            revert InvalidFundId();
        }
        _;
    }
    
    modifier activeFund(uint256 fundId) {
        if (!_funds[fundId].isActive) {
            revert FundInactive();
        }
        _;
    }

    modifier onlyBeneficiary(uint256 fundId) {
        if (_funds[fundId].beneficiary != msg.sender) {
            revert UnauthorizedAccess();
        }
        _;
    }

    function _validateFundParameters(
        string memory fundName,
        string memory purpose,
        address beneficiary,
        uint256 targetAmount,
        uint256 targetDate,
        string memory category
    ) private view {
        if (bytes(fundName).length == 0 ||
            bytes(purpose).length == 0 ||
            beneficiary == address(0) ||
            bytes(category).length == 0) {
            revert InvalidFundParameters();
        }
        
        if (targetAmount == 0) {
            revert InvalidAmount();
        }
        
        if (targetDate <= block.timestamp) {
            revert InvalidTargetDate();
        }
    }

    /**
     * @dev Creates a new trust fund
     * @param fundName Name of the fund
     * @param purpose Purpose of the fund
     * @param beneficiary Beneficiary of the fund
     * @param targetAmount Target amount for the fund
     * @param targetDate Target date for the fund
     * @param category Category of the fund
     * @return fundId The ID of the newly created fund
     */
    function createFund(
        string memory fundName,
        string memory purpose,
        address beneficiary,
        uint256 targetAmount,
        uint256 targetDate,
        string memory category
    ) external returns (uint256 fundId) {
        _validateFundParameters(
            fundName,
            purpose,
            beneficiary,
            targetAmount,
            targetDate,
            category
        );
        
        fundId = _fundCounter++;
        
        Fund storage newFund = _funds[fundId];
        newFund.fundName = fundName;
        newFund.purpose = purpose;
        newFund.beneficiary = beneficiary;
        newFund.targetAmount = targetAmount;
        newFund.targetDate = targetDate;
        newFund.currentBalance = 0;
        newFund.trustee = msg.sender;
        newFund.isActive = true;
        newFund.category = category;
        newFund.isWithdrawn = false;
        
        _trusteeFunds[msg.sender].push(fundId);
        
        emit FundCreated(
            fundId,
            fundName,
            msg.sender,
            beneficiary,
            targetAmount,
            targetDate
        );
        
        return fundId;
    }

    /**
     * @dev Deposits funds into a trust fund
     * @param fundId The ID of the fund to deposit into
     */
    function deposit(uint256 fundId) 
        external 
        payable 
        nonReentrant 
        validFundId(fundId) 
        activeFund(fundId) 
    {
        if (msg.value == 0) {
            revert InvalidDeposit();
        }

        Fund storage fund = _funds[fundId];
        
        fund.currentBalance += msg.value;
        
        emit FundDeposit(
            fundId,
            msg.sender,
            msg.value,
            fund.currentBalance
        );
    }

    /**
     * @dev Allows the beneficiary to withdraw funds after target date
     * @param fundId The ID of the fund to withdraw
     */
    function withdrawFund(uint256 fundId) 
        external 
        nonReentrant 
        validFundId(fundId) 
        activeFund(fundId)
        onlyBeneficiary(fundId) 
    {
        Fund storage fund = _funds[fundId];

        if (!fund.isActive) {
            revert FundInactive();
        }

        if (fund.isWithdrawn) {
            revert FundAlreadyWithdrawn();
        }
        
        if (block.timestamp < fund.targetDate) {
            revert WithdrawalBeforeTargetDate();
        }
        
        if (fund.currentBalance == 0) {
            revert InvalidAmount();
        }

        uint256 amountToWithdraw = fund.currentBalance;
        fund.currentBalance = 0;
        fund.isWithdrawn = true;
        fund.isActive = false;

        (bool success, ) = payable(msg.sender).call{value: amountToWithdraw}("");
        if (!success) {
            revert InvalidDeposit();
        }

        emit FundWithdrawn(
            fundId,
            msg.sender,
            amountToWithdraw,
            block.timestamp
        );
    }

    /**
     * @dev Retrieves detailed information about a specific fund
     * @param fundId The ID of the fund to query
     * @return Fund struct containing all fund details
     */
    function getFundDetails(uint256 fundId) 
        external 
        view 
        validFundId(fundId) 
        returns (Fund memory) 
    {
        return _funds[fundId];
    }

    /**
     * @dev Retrieves all fund IDs associated with a trustee
     * @param trustee The address of the trustee
     * @return uint256[] Array of fund IDs
     */
    function getTrusteeFunds(address trustee) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return _trusteeFunds[trustee];
    }

    /**
     * @dev Gets the current balance of a specific fund
     * @param fundId The ID of the fund to query
     * @return uint256 Current balance of the fund
     */
    function getFundBalance(uint256 fundId) 
        external 
        view 
        validFundId(fundId) 
        returns (uint256) 
    {
        return _funds[fundId].currentBalance;
    }

    /**
     * @dev Allows a trustee to set the active status of their fund
     * @param fundId The ID of the fund to update
     * @param status New active status
     */
    function setFundStatus(uint256 fundId, bool status) 
        external 
        validFundId(fundId) 
        onlyTrustee(fundId) 
    {
        _funds[fundId].isActive = status;
        emit FundStatusChanged(fundId, status);
    }

    /**
     * @dev Returns the total number of funds created
     * @return uint256 Total number of funds
     */
    function getTotalFunds() external view returns (uint256) {
        return _fundCounter;
    }

    /**
     * @dev Checks if an address is the trustee of a specific fund
     * @param fundId The ID of the fund to check
     * @param address_ The address to verify
     * @return bool True if the address is the trustee
     */
    function isTrustee(uint256 fundId, address address_) 
        external 
        view 
        validFundId(fundId) 
        returns (bool) 
    {
        return _funds[fundId].trustee == address_;
    }

    /**
     * @dev Allows retrieving multiple fund details at once
     * @param fundIds Array of fund IDs to query
     * @return Fund[] Array of fund details
     */
    function getBatchFundDetails(uint256[] calldata fundIds) 
        external 
        view 
        returns (Fund[] memory) 
    {
        Fund[] memory funds = new Fund[](fundIds.length);
        
        for (uint256 i = 0; i < fundIds.length; i++) {
            if (fundIds[i] >= _fundCounter || _funds[fundIds[i]].trustee == address(0)) {
                revert InvalidFundId();
            }
            funds[i] = _funds[fundIds[i]];
        }
        
        return funds;
    }

    /**
     * @dev Checks if a fund has reached its target amount
     * @param fundId The ID of the fund to check
     * @return bool True if target amount is reached
     */
    function isTargetReached(uint256 fundId) 
        external 
        view 
        validFundId(fundId) 
        returns (bool) 
    {
        Fund storage fund = _funds[fundId];
        return fund.currentBalance >= fund.targetAmount;
    }

    /**
     * @dev Checks if a fund is withdrawable
     * @param fundId The ID of the fund to check
     * @return bool True if target amount is reached
     */
    function isWithdrawable(uint256 fundId) 
        external 
        view 
        validFundId(fundId) 
        returns (bool) 
    {
        Fund storage fund = _funds[fundId];
        return (
            !fund.isWithdrawn && 
            fund.isActive && 
            block.timestamp >= fund.targetDate && 
            fund.currentBalance > 0
        );
    }

    /**
     * @dev Get time remaining until target date
     * @param fundId The ID of the fund to check
     * @return uint256 Time remaining in seconds
     */
    function getTimeRemaining(uint256 fundId) 
        external 
        view 
        validFundId(fundId) 
        returns (uint256) 
    {
        Fund storage fund = _funds[fundId];
        if (block.timestamp >= fund.targetDate) {
            return 0;
        }
        return fund.targetDate - block.timestamp;
    }
}
