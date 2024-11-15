import { expect } from "chai";
import { ethers, network } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { TrustFund } from "../typechain-types/contracts/TrustFund";
import { TrustFund__factory } from "../typechain-types/factories/contracts/TrustFund__factory";
import { Log } from "ethers";

describe("TrustFund", function () {
    async function deployTrustFundFixture() {
        const [owner, addr1, addr2] = await ethers.getSigners();
        
        const TrustFundFactory = await ethers.getContractFactory("TrustFund") as TrustFund__factory;
        const trustFund = await TrustFundFactory.deploy() as TrustFund;
        await trustFund.waitForDeployment();
        
        return { trustFund, owner, addr1, addr2 };
    }
    
    const testFund = {
        name: "Education Fund",
        purpose: "University Tuition",
        beneficiary: ethers.getAddress("0x1234567890abcdef1234567890abcdef12345678"),
        targetAmount: ethers.parseEther("10"),
        targetDate: Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60,
        category: "Education",
        isWithdrawn: false
    };
    
    describe("Deployment", function () {
        it("Should deploy successfully", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            expect(await trustFund.getTotalFunds()).to.equal(0);
        });
    });
    
    describe("Fund Creation", function () {
        it("Should create a new fund with correct parameters", async function () {
            const { trustFund, owner } = await loadFixture(deployTrustFundFixture);
            
            await expect(trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            )).to.emit(trustFund, "FundCreated")
              .withArgs(
                  0,
                  testFund.name,
                  owner.address,
                  testFund.beneficiary,
                  testFund.targetAmount,
                  testFund.targetDate
              );
            
            const fund = await trustFund.getFundDetails(0);
            expect(fund.fundName).to.equal(testFund.name);
            expect(fund.trustee).to.equal(owner.address);
            expect(fund.isActive).to.be.true;
        });
        
        it("Should reject invalid fund parameters", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            
            await expect(trustFund.createFund(
                "",
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            )).to.be.revertedWithCustomError(trustFund, "InvalidFundParameters");
            
            await expect(trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                0,
                testFund.targetDate,
                testFund.category
            )).to.be.revertedWithCustomError(trustFund, "InvalidAmount");
        });
    });
    
    describe("Deposits", function () {
        async function createTestFund() {
            const { trustFund, owner, addr1 } = await loadFixture(deployTrustFundFixture);
            
            await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            );
            
            return { trustFund, owner, addr1 };
        }
        
        it("Should accept valid deposits", async function () {
            const { trustFund, addr1 } = await createTestFund();
            const depositAmount = ethers.parseEther("1");
            
            await expect(trustFund.connect(addr1).deposit(0, { value: depositAmount }))
                .to.emit(trustFund, "FundDeposit")
                .withArgs(0, addr1.address, depositAmount, depositAmount);
            
            expect(await trustFund.getFundBalance(0)).to.equal(depositAmount);
        });
        
        it("Should reject zero deposits", async function () {
            const { trustFund } = await createTestFund();
            
            await expect(trustFund.deposit(0, { value: 0 }))
                .to.be.revertedWithCustomError(trustFund, "InvalidDeposit");
        });
        
        it("Should accumulate multiple deposits correctly", async function () {
            const { trustFund, addr1, owner } = await createTestFund();
            const deposit1 = ethers.parseEther("1");
            const deposit2 = ethers.parseEther("2");
            
            await trustFund.connect(addr1).deposit(0, { value: deposit1 });
            await trustFund.connect(owner).deposit(0, { value: deposit2 });
            
            expect(await trustFund.getFundBalance(0)).to.equal(deposit1 + deposit2);
        });
    });

    describe("Fund Withdrawals", function () {
        async function setupFundWithDeposit() {
            const { trustFund, owner, addr1, addr2 } = await loadFixture(deployTrustFundFixture);
            
            const latestBlock = await ethers.provider.getBlock('latest');
            const currentTimestamp = latestBlock!.timestamp;
            
            await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                addr1.address,
                testFund.targetAmount,
                currentTimestamp + 100,
                testFund.category
            );
            
            const depositAmount = ethers.parseEther("1");
            await trustFund.connect(addr2).deposit(0, { value: depositAmount });
            
            return { 
                trustFund, 
                owner, 
                beneficiary: addr1, 
                depositor: addr2, 
                fundId: 0, 
                targetDate: currentTimestamp + 100,
                depositAmount 
            };
        }
    
        describe("Withdrawal Conditions", function () {
            it("Should not allow withdrawal before target date", async function () {
                const { trustFund, beneficiary, fundId } = await setupFundWithDeposit();
                
                await expect(trustFund.connect(beneficiary).withdrawFund(fundId))
                    .to.be.revertedWithCustomError(trustFund, "WithdrawalBeforeTargetDate");
            });
    
            it("Should allow withdrawal after target date", async function () {
                const { trustFund, beneficiary, fundId, depositAmount } = await setupFundWithDeposit();
                
                await ethers.provider.send("evm_increaseTime", [150]);
                
                const withdrawalTx = await trustFund.connect(beneficiary).withdrawFund(fundId);
                
                const txReceipt = await withdrawalTx.wait();
                const block = await ethers.provider.getBlock(txReceipt!.blockNumber);
                
                await expect(withdrawalTx)
                    .to.emit(trustFund, "FundWithdrawn")
                    .withArgs(fundId, beneficiary.address, depositAmount, block!.timestamp);
            });
    
            it("Should not allow non-beneficiary to withdraw", async function () {
                const { trustFund, owner, fundId } = await setupFundWithDeposit();
                
                await ethers.provider.send("evm_increaseTime", [150]);
                await ethers.provider.send("evm_mine", []);
                
                await expect(trustFund.connect(owner).withdrawFund(fundId))
                    .to.be.revertedWithCustomError(trustFund, "UnauthorizedAccess");
            });
    
            it("Should not allow double withdrawal", async function () {
                const { trustFund, beneficiary, fundId } = await setupFundWithDeposit();
                
                await ethers.provider.send("evm_increaseTime", [150]);
                await ethers.provider.send("evm_mine", []);
                
                await trustFund.connect(beneficiary).withdrawFund(fundId);
                
                await expect(trustFund.connect(beneficiary).withdrawFund(fundId))
                    .to.be.revertedWithCustomError(trustFund, "FundInactive");
            });
    
            it("Should not allow withdrawal from inactive fund", async function () {
                const { trustFund, beneficiary, owner, fundId } = await setupFundWithDeposit();
                
                await trustFund.connect(owner).setFundStatus(fundId, false);
                
                await ethers.provider.send("evm_increaseTime", [150]);
                await ethers.provider.send("evm_mine", []);
                
                await expect(trustFund.connect(beneficiary).withdrawFund(fundId))
                    .to.be.revertedWithCustomError(trustFund, "FundInactive");
            });
    
            it("Should transfer exact amount to beneficiary", async function () {
                const { trustFund, beneficiary, fundId, depositAmount } = await setupFundWithDeposit();
                
                await ethers.provider.send("evm_increaseTime", [150]);
                await ethers.provider.send("evm_mine", []);
                
                const beneficiaryBalanceBefore = await ethers.provider.getBalance(beneficiary.address);
                const tx = await trustFund.connect(beneficiary).withdrawFund(fundId);
                const receipt = await tx.wait();
                const gasUsed = receipt!.gasUsed * receipt!.gasPrice;
                
                const beneficiaryBalanceAfter = await ethers.provider.getBalance(beneficiary.address);
                
                expect(beneficiaryBalanceAfter).to.equal(
                    beneficiaryBalanceBefore + depositAmount - gasUsed
                );
            });
        });
    
        describe("Withdrawal Status Checks", function () {
            it("Should correctly identify withdrawal conditions", async function () {
                const { trustFund, beneficiary, fundId } = await setupFundWithDeposit();
                
                expect(await trustFund.isWithdrawable(fundId)).to.be.false;
                
                await ethers.provider.send("evm_increaseTime", [150]);
                await ethers.provider.send("evm_mine", []);
                expect(await trustFund.isWithdrawable(fundId)).to.be.true;
                
                await trustFund.connect(beneficiary).withdrawFund(fundId);
                expect(await trustFund.isWithdrawable(fundId)).to.be.false;
            });

            it("Should correctly report withdrawable status", async function () {
                const { trustFund, fundId } = await setupFundWithDeposit();
                
                expect(await trustFund.isWithdrawable(fundId)).to.be.false;
                
                await ethers.provider.send("evm_increaseTime", [150]);
                await ethers.provider.send("evm_mine", []);
                expect(await trustFund.isWithdrawable(fundId)).to.be.true;
                
                await trustFund.connect(await ethers.getSigner(await trustFund.getFundDetails(fundId).then(f => f.beneficiary))).withdrawFund(fundId);
                expect(await trustFund.isWithdrawable(fundId)).to.be.false;
            });
    
            it("Should update all relevant fund properties after withdrawal", async function () {
                const { trustFund, beneficiary, fundId } = await setupFundWithDeposit();
                
                await ethers.provider.send("evm_increaseTime", [150]);
                await ethers.provider.send("evm_mine", []);
                
                await trustFund.connect(beneficiary).withdrawFund(fundId);
                
                const fund = await trustFund.getFundDetails(fundId);
                expect(fund.currentBalance).to.equal(0);
                expect(fund.isWithdrawn).to.be.true;
                expect(fund.isActive).to.be.false;
            });
        });
    });
    
    describe("Fund Queries", function () {
        async function setupMultipleFunds() {
            const { trustFund, owner, addr1 } = await loadFixture(deployTrustFundFixture);
            
            await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            );
            
            await trustFund.connect(addr1).createFund(
                "Second Fund",
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            );
            
            return { trustFund, owner, addr1 };
        }
        
        it("Should retrieve correct fund details", async function () {
            const { trustFund, owner } = await setupMultipleFunds();
            
            const fund = await trustFund.getFundDetails(0);
            expect(fund.fundName).to.equal(testFund.name);
            expect(fund.trustee).to.equal(owner.address);
        });
        
        it("Should list all trustee funds correctly", async function () {
            const { trustFund, owner, addr1 } = await setupMultipleFunds();
            
            const ownerFunds = await trustFund.getTrusteeFunds(owner.address);
            const addr1Funds = await trustFund.getTrusteeFunds(addr1.address);
            
            expect(ownerFunds.length).to.equal(1);
            expect(addr1Funds.length).to.equal(1);
            expect(ownerFunds[0]).to.equal(0);
            expect(addr1Funds[0]).to.equal(1);
        });
    });
    
    describe("Fund Status Management", function () {
        it("Should allow trustee to change fund status", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            
            await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            );
            
            await expect(trustFund.setFundStatus(0, false))
                .to.emit(trustFund, "FundStatusChanged")
                .withArgs(0, false);
            
            const fund = await trustFund.getFundDetails(0);
            expect(fund.isActive).to.be.false;
        });
        
        it("Should prevent non-trustee from changing fund status", async function () {
            const { trustFund, addr1 } = await loadFixture(deployTrustFundFixture);
            
            await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            );
            
            await expect(trustFund.connect(addr1).setFundStatus(0, false))
                .to.be.revertedWithCustomError(trustFund, "UnauthorizedAccess");
        });
    });

    describe("Fuzz Testing - Fund Creation", function () {
        const generateRandomString = (length: number) => {
            const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
            let result = '';
            for (let i = 0; i < length; i++) {
                result += chars.charAt(Math.floor(Math.random() * chars.length));
            }
            return result;
        };

        it("Should handle various string lengths for fund parameters", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            const signers = await ethers.getSigners();
        
            for (let i = 1; i <= 100; i += 10) {
                const randomName = generateRandomString(i);
                const randomPurpose = generateRandomString(i);
                const randomCategory = generateRandomString(i);
                const randomBeneficiary = signers[i % signers.length].address; 
        
                await expect(trustFund.createFund(
                    randomName,
                    randomPurpose,
                    randomBeneficiary,
                    ethers.parseEther("1"),
                    Math.floor(Date.now() / 1000) + 86400,
                    randomCategory
                )).to.not.be.reverted;
            }
        });

        it("Should handle various target amounts", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            
            const amounts = [
                "0.000000000000000001",
                "1.234567890123456789",
                "999999999999999999",
                "1",
            ];

            for (const amount of amounts) {
                await expect(trustFund.createFund(
                    testFund.name,
                    testFund.purpose,
                    testFund.beneficiary,
                    ethers.parseEther(amount),
                    testFund.targetDate,
                    testFund.category
                )).to.not.be.reverted;
            }
        });
    });

    describe("Edge Cases - Deposits", function () {
        let fundId: bigint;

        async function createTestFund(trustFund: TrustFund) {
            const tx = await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                ethers.parseEther("100"),
                testFund.targetDate,
                testFund.category
            );
            const receipt = await tx.wait();
            
            const fundCreatedEvent = receipt?.logs?.find(
                (log) => {
                    try {
                        const parsedLog = trustFund.interface.parseLog(log as Log);
                        return parsedLog?.name === 'FundCreated';
                    } catch {
                        return false;
                    }
                }
            );

            if (fundCreatedEvent) {
                const parsedEvent = trustFund.interface.parseLog(fundCreatedEvent as Log);
                return parsedEvent?.args[0] || 0n;
            }
            return 0n;
        }

        beforeEach(async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            const tx = await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                ethers.parseEther("100"),
                testFund.targetDate,
                testFund.category
            );
            const receipt = await tx.wait();
            
            const fundCreatedEvent = receipt?.logs?.find(
                (log) => {
                    try {
                        const parsedLog = trustFund.interface.parseLog(log as Log);
                        return parsedLog?.name === 'FundCreated';
                    } catch {
                        return false;
                    }
                }
            );

            if (fundCreatedEvent) {
                const parsedEvent = trustFund.interface.parseLog(fundCreatedEvent as Log);
                fundId = parsedEvent?.args[0] || 0n;
            } else {
                fundId = 0n;
            }
        });

        it("Should handle multiple rapid deposits from different accounts", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            const fundId = await createTestFund(trustFund);
            const signers = await ethers.getSigners();
            const depositAmount = ethers.parseEther("1");
            
            const depositPromises = signers.slice(0, 5).map(signer => 
                trustFund.connect(signer).deposit(fundId, { value: depositAmount })
            );
            
            await Promise.all(depositPromises);

            const balance = await trustFund.getFundBalance(fundId);
            expect(balance).to.equal(depositAmount * BigInt(5));
        });

        it("Should handle large deposits within reasonable limits", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            
            const largeAmount = ethers.parseEther("1000000");
            const [deployer, largeBeneficiary] = await ethers.getSigners();
            const tx = await trustFund.createFund(
                "Large Fund",
                "Testing large values",
                largeBeneficiary.address,
                largeAmount,
                testFund.targetDate,
                "Test"
            );
            
            const receipt = await tx.wait();
            let fundId: bigint = 0n;
            
            const fundCreatedEvent = receipt?.logs?.find(
                (log) => {
                    try {
                        const parsedLog = trustFund.interface.parseLog(log as Log);
                        return parsedLog?.name === 'FundCreated';
                    } catch {
                        return false;
                    }
                }
            );

            if (fundCreatedEvent) {
                const parsedEvent = trustFund.interface.parseLog(fundCreatedEvent as Log);
                fundId = parsedEvent?.args[0] || 0n;
            }

            const depositAmount = ethers.parseEther("1000");
            await expect(
                trustFund.deposit(fundId, { value: depositAmount })
            ).to.not.be.reverted;

            const balance = await trustFund.getFundBalance(fundId);
            expect(balance).to.equal(depositAmount);
        });
    });

    describe("Time-based Edge Cases", function () {
        it("Should handle funds with reasonable future dates", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            
            const oneYearFromNow = (await time.latest()) + 365 * 24 * 60 * 60;
            await expect(trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                oneYearFromNow,
                testFund.category
            )).to.not.be.reverted;

            const oneDayFromNow = (await time.latest()) + 24 * 60 * 60;
            await expect(trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                oneDayFromNow,
                testFund.category
            )).to.not.be.reverted;
        });

        it("Should correctly handle time manipulation scenarios", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            
            const targetDate = (await time.latest()) + 3600;
            await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                targetDate,
                testFund.category
            );

            expect(await trustFund.getTimeRemaining(0)).to.be.approximately(3600n, 5n);

            await time.increase(1800);
            expect(await trustFund.getTimeRemaining(0)).to.be.approximately(1800n, 5n);

            await time.increase(3600);
            expect(await trustFund.getTimeRemaining(0)).to.equal(0);
        });
    });

    describe("Concurrent Operations", function () {
        it("Should handle multiple sequential operations", async function () {
            const { trustFund, addr1 } = await loadFixture(deployTrustFundFixture);
            
            const tx1 = await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            );
            await tx1.wait();

            const tx2 = await trustFund.connect(addr1).createFund(
                "Second Fund",
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            );
            await tx2.wait();

            const depositTx = await trustFund.deposit(0n, { value: ethers.parseEther("1") });
            await depositTx.wait();

            const fund0Balance = await trustFund.getFundBalance(0n);
            expect(fund0Balance).to.equal(ethers.parseEther("1"));
        });
    });

    describe("Gas Usage Optimization Tests", function () {
        it("Should maintain reasonable gas usage for fund creation", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            
            const tx = await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            );
            
            const receipt = await tx.wait();
            expect(receipt?.gasUsed).to.be.below(500000);
        });

        it("Should maintain reasonable gas usage for deposits", async function () {
            const { trustFund } = await loadFixture(deployTrustFundFixture);
            
            await trustFund.createFund(
                testFund.name,
                testFund.purpose,
                testFund.beneficiary,
                testFund.targetAmount,
                testFund.targetDate,
                testFund.category
            );

            const tx = await trustFund.deposit(0, { value: ethers.parseEther("1") });
            const receipt = await tx.wait();
            expect(receipt?.gasUsed).to.be.below(100000);
        });
    });
});