import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "hardhat";

describe("WillRegistry", function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployWillRegistrykFixture() {
    const [owner, signer1, signer2] = await ethers.getSigners();
    
    const WillRegistry = await ethers.getContractFactory("WillRegistry");
    const willRegistry = await WillRegistry.deploy();

    
    const NFT = await ethers.getContractFactory("MyNFT");
    const nft = await NFT.deploy(owner);
    const tokenURI = "https://example.com/token/1";
    await nft.mintNFT(owner, tokenURI);
    await nft.mintNFT(owner, tokenURI);
    await nft.mintNFT(owner, tokenURI);

    const GameItems = await ethers.getContractFactory("GameItems");
    const gameItems = await GameItems.deploy();
    await gameItems.mint(owner, 0, 100, "0x"); // Mint 100 of token ID 0
    await gameItems.mint(owner, 1, 50, "0x"); 
    
    const WillToken = await ethers.getContractFactory("WillToken");
    const willToken = await WillToken.deploy();

    return { gameItems,   tokenURI, willToken, willRegistry, nft, owner, signer1, signer2};
  }

  describe("Will", function () {
    it("create Will", async function () {
      const { nft, owner, signer1, signer2, willToken, willRegistry} = await loadFixture(deployWillRegistrykFixture);

      const ownerBalance = await willToken.balanceOf(owner)
      const ownerNFTBalance = await nft.balanceOf(owner)
      console.log("Owner Balance", ownerBalance);
      console.log("Owner Balance", ownerNFTBalance);
       
      const willTokenAddress = await willToken.getAddress();
      const amount = ethers.parseUnits("100", 18);
      await willToken.approve(willRegistry, ethers.parseUnits("200", 18));
      await nft.approve(willRegistry, 1)
      await nft.approve(willRegistry, 2)

      const tokenAllocations = [{
        tokenAddress: willTokenAddress,
        tokenType: 1, // ERC20
        tokenIds: [amount, amount],
        amounts: [amount, amount],
        beneficiaries: [signer1, signer2]
      }];
      
      await expect(willRegistry.createWill("make money", tokenAllocations))
        .to.emit(willRegistry, "WillCreated")
        .withArgs(owner.address, "make money", anyValue);

        const ownerBalanceAfter = await willToken.balanceOf(owner)
        console.log("Owner Balance After", ownerBalanceAfter);
        const ownerNFTBalanceAfter = await nft.balanceOf(owner)
        console.log("Owner Balance", ownerNFTBalanceAfter);



      const signer1Allocations = await willRegistry.getBeneficiaryAllocations(owner, signer1);
      expect(signer1Allocations[0].tokenAddress).to.equal(willTokenAddress);
      expect(signer1Allocations[0].amount).to.equal(amount);

      console.log("signer 1", signer1Allocations);
      
      

      const signer2Allocations = await willRegistry.getBeneficiaryAllocations(owner, signer2);
      expect(signer2Allocations[0].tokenAddress).to.equal(willTokenAddress);
      expect(signer2Allocations[0].amount).to.equal(amount);

      console.log("signer 2", signer2Allocations);

      const nftContractBalance = await nft.balanceOf(willRegistry)
      const tokenContractBalance = await willToken.balanceOf(willRegistry)
      console.log("Contract NFT balances ::", nftContractBalance);
      console.log("Contract Token balances ::", tokenContractBalance);
      
      
    });
    
    it("addBeneficiaryWithAllocation", async function () {
      const { nft, owner, signer1, signer2, willToken, willRegistry} = await loadFixture(deployWillRegistrykFixture);

      // First, create an initial will
      const willTokenAddress = await willToken.getAddress();
      const amount = ethers.parseUnits("50", 18);
      await willToken.approve(willRegistry, ethers.parseUnits("100", 18));

      await willRegistry.createWill("Initial Will", [{
        tokenAddress: willTokenAddress,
        tokenType: 1,
        tokenIds: [],
        amounts: [amount],
        beneficiaries: [signer1]
      }]);

      const newAllocations = [{
        tokenAddress: willTokenAddress,
        tokenType: 1,
        tokenIds: [],
        amounts: [amount],
        beneficiaries: [signer1]
      }];

      // Call addBeneficiaryWithAllocation
      await expect(willRegistry.connect(owner).addBeneficiaryWithAllocation(signer1, newAllocations))
       
      
      // Check allocations
      const signer3Allocations = await willRegistry.getBeneficiaryAllocations(owner, signer1);
      expect(signer3Allocations[0].tokenAddress).to.equal(willTokenAddress);
      expect(signer3Allocations[0].amount).to.equal(amount);
    });

  
});
})