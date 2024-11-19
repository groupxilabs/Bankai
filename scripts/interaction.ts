import { ethers } from "hardhat";

async function main() {
    const WillTokenAddress = "0xf373b5fbF1F4075E240Ea2EB76bdE01f54bf75f6";
    const willToken = await ethers.getContractAt("IERC20", WillTokenAddress);

    const WillRegistryContractAddress = "0x9515ac929D2103787381eca5c629dFa5362373E5";
    const willRegistry = await ethers.getContractAt("IWillRegistry", WillRegistryContractAddress);

    const MIN_GRACE_PERIOD = 24 * 60 * 60; 
    const MAX_GRACE_PERIOD = 90 * 24 * 60 * 60; 
    const MIN_ACTIVITY_THRESHOLD = 30 * 24 * 60 * 60; 
    const MAX_ACTIVITY_THRESHOLD = 365 * 24 * 60 * 60; 

    const amount = ethers.parseUnits("10", 18);
    const approveTx = await willToken.approve(willRegistry, ethers.parseUnits("10", 18));
    approveTx.wait();

    const tokenAllocations = [{
     tokenAddress: WillTokenAddress,
     tokenType: 1, 
     tokenIds: [],
     amounts: [amount],
     beneficiaries: [WillTokenAddress]
   }];

   const createWill = await willRegistry.createWill("test", tokenAllocations, MIN_GRACE_PERIOD, MIN_ACTIVITY_THRESHOLD,  { gasLimit: 1000000 });
   createWill.wait()
   console.log("create will :::", createWill);
   
    
    
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});