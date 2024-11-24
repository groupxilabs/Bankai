import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "hardhat";
import { Block } from "ethers";


describe("WillRegistry", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployWillRegistrykFixture() {
    const [owner, signer1, signer2] = await ethers.getSigners();
    
    const WillRegistry = await ethers.getContractFactory("WillRegistry");
    const willRegistry = await WillRegistry.deploy();

    
    const WillToken = await ethers.getContractFactory("WillToken");
    const willToken = await WillToken.deploy();

    return {willToken, willRegistry, owner, signer1, signer2};
  }

  describe("Will", function () {
    const MIN_GRACE_PERIOD = 24 * 60 * 60; 
    const MAX_GRACE_PERIOD = 90 * 24 * 60 * 60; 
    const MIN_ACTIVITY_THRESHOLD = 30 * 24 * 60 * 60; 
    const MAX_ACTIVITY_THRESHOLD = 365 * 24 * 60 * 60; 

    it("create Will", async function () {
      const {owner, signer1, signer2, willToken, willRegistry} = await loadFixture(deployWillRegistrykFixture);

      const ownerBalance = await willToken.balanceOf(owner)
      console.log("Owner Balance", ownerBalance);
       
      const willTokenAddress = await willToken.getAddress();
      const amount = ethers.parseUnits("100", 18);
      await willToken.approve(willRegistry, ethers.parseUnits("200", 18));

      const tokenAllocations = [{
        tokenAddress: willTokenAddress,
        tokenType: 1, 
        tokenIds: [],
        amounts: [amount, amount],
        beneficiaries: [signer1, signer2]
      }];

      const gracePeriod = MIN_GRACE_PERIOD * 2; 
      const activityThreshold = MIN_ACTIVITY_THRESHOLD * 2; 
      
      await expect(willRegistry.connect(owner).createWill("make money", tokenAllocations, gracePeriod, activityThreshold))
        .to.emit(willRegistry, "WillCreated")
        .withArgs(owner.address, "make money", anyValue);

      const ownerBalanceAfter = await willToken.balanceOf(owner)
      console.log("Owner Balance After", ownerBalanceAfter);
        
      const tokenContractBalance = await willToken.balanceOf(willRegistry)
      console.log("Contract Token balances ::", tokenContractBalance);
      
      
    });

    it("should add beneficiary with allocation to existing will", async function () {
      const {owner, signer1, signer2, willToken, willRegistry} = await loadFixture(deployWillRegistrykFixture);
      
      
      const willTokenAddress = await willToken.getAddress();
      const amount = ethers.parseUnits("100", 18);
      await willToken.approve(willRegistry, ethers.parseUnits("300", 18));
    
      const tokenAllocations = [{
        tokenAddress: willTokenAddress,
        tokenType: 1,
        tokenIds: [],
        amounts: [amount],
        beneficiaries: [signer1]
      }];
    
      const gracePeriod = MIN_GRACE_PERIOD * 2;
      const activityThreshold = MIN_ACTIVITY_THRESHOLD * 2;
      
      await willRegistry.createWill("First Will", tokenAllocations, gracePeriod, activityThreshold);
      
 
      const newBeneficiaryAllocations = [{
        tokenAddress: willTokenAddress,
        tokenType: 1, 
        tokenIds: [],
        amounts: [amount],
        beneficiaries: [signer2]
      }];
      
      
      const willId = 1;
      
      await expect(willRegistry.addBeneficiaryWithAllocation(
        willId,
        signer2.address,
        newBeneficiaryAllocations
      )).to.emit(willRegistry, "BeneficiaryAdded")
        .withArgs(owner.address, signer2.address);
        
      
      const allocations = await willRegistry.getBeneficiaryAllocations(willId, signer2.address);
      expect(allocations[0].amount).to.equal(amount);
    });

    it("Advanced Will Functions", async function () {
      const {owner, signer1, signer2, willToken, willRegistry} = await loadFixture(deployWillRegistrykFixture);
      const willTokenAddress = await willToken.getAddress();
        const amount = ethers.parseUnits("100", 18);
        await willToken.approve(willRegistry, ethers.parseUnits("600", 18));

        // Create first will with signer1 and signer2 as beneficiaries
        const tokenAllocations1 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create second will with signer2 and signer3 as beneficiaries
        const tokenAllocations2 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create third will from signer1 with signer3 and signer4 as beneficiaries
        const tokenAllocations3 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        const gracePeriod = MIN_GRACE_PERIOD * 2;
        const activityThreshold = MIN_ACTIVITY_THRESHOLD * 2;

        await willRegistry.createWill("First Will", tokenAllocations1, gracePeriod, activityThreshold);
        await willRegistry.createWill("Second Will", tokenAllocations2, gracePeriod, activityThreshold);
        await willToken.transfer(signer1, ethers.parseUnits("200", 18));
        await willToken.connect(signer1).approve(willRegistry, ethers.parseUnits("200", 18));
        await willRegistry.connect(signer1).createWill("Third Will", tokenAllocations3, gracePeriod, activityThreshold);

        return {
            owner, signer1, signer2, willToken, willRegistry, amount
        };

    })

    it("getTotalUniqueBeneficiaries", async function () {
      const {owner, signer1, signer2, willToken, willRegistry} = await loadFixture(deployWillRegistrykFixture);
      const willTokenAddress = await willToken.getAddress();
        const amount = ethers.parseUnits("100", 18);
        await willToken.approve(willRegistry, ethers.parseUnits("600", 18));

        // Create first will with signer1 and signer2 as beneficiaries
        const tokenAllocations1 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create second will with signer2 and signer3 as beneficiaries
        const tokenAllocations2 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create third will from signer1 with signer3 and signer4 as beneficiaries
        const tokenAllocations3 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        const gracePeriod = MIN_GRACE_PERIOD * 2;
        const activityThreshold = MIN_ACTIVITY_THRESHOLD * 2;

        await willRegistry.createWill("First Will", tokenAllocations1, gracePeriod, activityThreshold);
        await willRegistry.createWill("Second Will", tokenAllocations2, gracePeriod, activityThreshold);
        await willToken.transfer(signer1, ethers.parseUnits("200", 18));
        await willToken.connect(signer1).approve(willRegistry, ethers.parseUnits("200", 18));
        // await willRegistry.connect(signer1).createWill("Third Will", tokenAllocations3, gracePeriod, activityThreshold);

        const totalUniqueBeneficiaries = await willRegistry.getTotalUniqueBeneficiaries(owner);
        expect(totalUniqueBeneficiaries).to.equal(2);
    })
    
    it("getTotalWillsCreated", async function () {
      const {owner, signer1, signer2, willToken, willRegistry} = await loadFixture(deployWillRegistrykFixture);
      const willTokenAddress = await willToken.getAddress();
        const amount = ethers.parseUnits("100", 18);
        await willToken.approve(willRegistry, ethers.parseUnits("600", 18));

        // Create first will with signer1 and signer2 as beneficiaries
        const tokenAllocations1 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create second will with signer2 and signer3 as beneficiaries
        const tokenAllocations2 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create third will from signer1 with signer3 and signer4 as beneficiaries
        const tokenAllocations3 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        const gracePeriod = MIN_GRACE_PERIOD * 2;
        const activityThreshold = MIN_ACTIVITY_THRESHOLD * 2;

        await willRegistry.createWill("First Will", tokenAllocations1, gracePeriod, activityThreshold);
        await willRegistry.createWill("Second Will", tokenAllocations2, gracePeriod, activityThreshold);
        await willToken.transfer(signer1, ethers.parseUnits("200", 18));
        await willToken.connect(signer1).approve(willRegistry, ethers.parseUnits("200", 18));
        // await willRegistry.connect(signer1).createWill("Third Will", tokenAllocations3, gracePeriod, activityThreshold);

        const ownerWillCount = await willRegistry.getTotalWillsCreated(owner.address);
        expect(ownerWillCount).to.equal(2);
    })
    
    it("getWillsWilledToBeneficiary", async function () {
      const {owner, signer1, signer2, willToken, willRegistry} = await loadFixture(deployWillRegistrykFixture);
      const willTokenAddress = await willToken.getAddress();
        const amount = ethers.parseUnits("100", 18);
        await willToken.approve(willRegistry, ethers.parseUnits("600", 18));

        // Create first will with signer1 and signer2 as beneficiaries
        const tokenAllocations1 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create second will with signer2 and signer3 as beneficiaries
        const tokenAllocations2 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create third will from signer1 with signer3 and signer4 as beneficiaries
        const tokenAllocations3 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        const gracePeriod = MIN_GRACE_PERIOD * 2;
        const activityThreshold = MIN_ACTIVITY_THRESHOLD * 2;

        await willRegistry.createWill("First Will", tokenAllocations1, gracePeriod, activityThreshold);
        await willRegistry.createWill("Second Will", tokenAllocations2, gracePeriod, activityThreshold);
        await willToken.transfer(signer1, ethers.parseUnits("200", 18));
        await willToken.connect(signer1).approve(willRegistry, ethers.parseUnits("200", 18));
        

        const willInfo= await willRegistry.getWillsWilledToBeneficiary(signer2.address);
            
      
        expect(willInfo[0].willId).to.equal(1);
        expect(willInfo[0].willName).to.equal("First Will");
        expect(willInfo[0].tokenAddress).to.equal(willTokenAddress);
        expect(willInfo[0].amount).to.equal(amount);
    })
  
    it("claimInheritance", async function () {
      const {owner, signer1, signer2, willToken, willRegistry} = await loadFixture(deployWillRegistrykFixture);
      const willTokenAddress = await willToken.getAddress();
        const amount = ethers.parseUnits("100", 18);
        await willToken.approve(willRegistry, ethers.parseUnits("600", 18));

        // Create first will with signer1 and signer2 as beneficiaries
        const tokenAllocations1 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create second will with signer2 and signer3 as beneficiaries
        const tokenAllocations2 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        // Create third will from signer1 with signer3 and signer4 as beneficiaries
        const tokenAllocations3 = [{
            tokenAddress: willTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [signer1, signer2]
        }];

        const gracePeriod = MIN_GRACE_PERIOD * 2;
        const activityThreshold = MIN_ACTIVITY_THRESHOLD * 2;

        await willRegistry.createWill("First Will", tokenAllocations1, gracePeriod, activityThreshold);
        await willRegistry.createWill("Second Will", tokenAllocations2, gracePeriod, activityThreshold);
        await willToken.transfer(signer1, ethers.parseUnits("200", 18));
        await willToken.connect(signer1).approve(willRegistry, ethers.parseUnits("200", 18));
        

        const latestTime = await time.latest()
        await time.increase(gracePeriod + latestTime);
        await time.increase(  activityThreshold + latestTime);
        
        await time.setNextBlockTimestamp(gracePeriod + activityThreshold)
        await time.setNextBlockTimestamp(gracePeriod + activityThreshold)
        
        

 

        await willRegistry.setAuthorizedBackend(owner, true);

        await willRegistry.checkAndTriggerDeadManSwitch(owner);

        await willRegistry.connect(owner).claimInheritance(1);

       
    })
});
})