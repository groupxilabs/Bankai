// import { ethers } from "hardhat";

// async function main() {
//     const WillTokenAddress = "0xf373b5fbF1F4075E240Ea2EB76bdE01f54bf75f6";
//     const willToken = await ethers.getContractAt("IERC20", WillTokenAddress);

//     const WillRegistryContractAddress = "0x1fC8743dB501e5166De1B198c8D26891b07F2Fc8";
//     const willRegistry = await ethers.getContractAt("IWillRegistry", WillRegistryContractAddress);

//     const MIN_GRACE_PERIOD = 24 * 60 * 60; 
//     const MAX_GRACE_PERIOD = 90 * 24 * 60 * 60; 
//     const MIN_ACTIVITY_THRESHOLD = 30 * 24 * 60 * 60; 
//     const MAX_ACTIVITY_THRESHOLD = 365 * 24 * 60 * 60; 

//     const amount = ethers.parseUnits("30", 18);
//     const approveTx = await willToken.approve(willRegistry, ethers.parseUnits("60", 18));
//     approveTx.wait();

//     const tokenAllocations = [{
//      tokenAddress: WillTokenAddress,
//      tokenType: 1, 
//      tokenIds: [],
//      amounts: [amount, amount],
//      beneficiaries: [WillTokenAddress, willRegistry]
//    }];

//    const createWill = await willRegistry.createWill("test", tokenAllocations, MIN_GRACE_PERIOD, MIN_ACTIVITY_THRESHOLD,  { gasLimit: 1000000 });
//    createWill.wait()
//    console.log("create will :::", createWill);
   
    
    
// }

// // We recommend this pattern to be able to use async/await everywhere
// // and properly handle errors.
// main().catch((error) => {
//     console.error(error);
//     process.exitCode = 1;
// });

import { ethers } from "hardhat";

async function executeTransaction(iteration: number) {
    const WillTokenAddress = "0xf373b5fbF1F4075E240Ea2EB76bdE01f54bf75f6";
    const willToken = await ethers.getContractAt("IERC20", WillTokenAddress);

    const WillRegistryContractAddress = "0x26E43756aaEa3ca4cA0C84f0FbA21e1b9a85B61B";
    const willRegistry = await ethers.getContractAt("IWillRegistry", WillRegistryContractAddress);

    const MIN_GRACE_PERIOD = 24 * 60 * 60;
    const MAX_GRACE_PERIOD = 90 * 24 * 60 * 60;
    const MIN_ACTIVITY_THRESHOLD = 30 * 24 * 60 * 60;
    const MAX_ACTIVITY_THRESHOLD = 365 * 24 * 60 * 60;

    console.log(`Starting iteration ${iteration + 1} of 15`);

    try {
        ethers.provider.getBlockNumber
        // First approve the tokens
        const amount = ethers.parseUnits("30", 18);
        console.log(`Approving tokens for iteration ${iteration + 1}...`);
        const approveTx = await willToken.approve(willRegistry, ethers.parseUnits("60", 18));
        const approveReceipt = await approveTx.wait();
        console.log(`Approval confirmed in block ${approveReceipt}`);

        // Create the token allocations
        const tokenAllocations = [{
            tokenAddress: WillTokenAddress,
            tokenType: 1,
            tokenIds: [],
            amounts: [amount, amount],
            beneficiaries: [WillTokenAddress, willRegistry]
        }];

        // Create the will after approval is confirmed
        console.log(`Creating will for iteration ${iteration + 1}...`);
        const createWill = await willRegistry.createWill(
            `test-${iteration + 1}`,
            tokenAllocations,
            MIN_GRACE_PERIOD,
            MIN_ACTIVITY_THRESHOLD,
            { gasLimit: 1000000 }
        );
        const createWillReceipt = await createWill.wait();
        console.log(`Will created in block ${createWillReceipt} for iteration ${iteration + 1}`);

        // Add a small delay between iterations to prevent potential nonce issues
        await new Promise(resolve => setTimeout(resolve, 2000));

    } catch (error) {
        console.error(`Error in iteration ${iteration + 1}:`, error);
        throw error; // Re-throw to stop the sequence if there's an error
    }
}

async function main() {
    try {
        for (let i = 0; i < 15; i++) {
            await executeTransaction(i);
            console.log(`Completed iteration ${i + 1} of 15`);
            console.log('------------------------');
        }
        console.log("All 15 iterations completed successfully");
    } catch (error) {
        console.error("Sequence stopped due to error:", error);
        process.exitCode = 1;
    }
}

// Execute the main function
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});