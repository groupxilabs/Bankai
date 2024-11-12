import { ethers, network } from "hardhat";
import { verify } from "./verify";

async function main() {
    console.log("Deploying TrustFund contract...");

    try {
        const TrustFund = await ethers.getContractFactory("TrustFund");
        const trustFund = await TrustFund.deploy();
        
        await trustFund.waitForDeployment();
        const trustFundAddress = await trustFund.getAddress();

        console.log(`TrustFund deployed to: ${trustFundAddress}`);

        console.log("Waiting for block confirmations...");
        await trustFund.deploymentTransaction()?.wait(6);

        console.log("Verifying contract on Etherscan...");
        await verify(trustFundAddress, []);

        console.log("Deployment and verification completed successfully!");

        // Log deployment information
        console.log("\nDeployment Summary:");
        console.log("===================");
        console.log(`Network: ${network.name}`);
        console.log(`Contract Address: ${trustFundAddress}`);
        console.log(`Transaction Hash: ${trustFund.deploymentTransaction()?.hash}`);
        console.log(`Deployer Address: ${(await ethers.getSigners())[0].address}`);
        
    } catch (error) {
        console.error("Deployment failed:", error);
        process.exitCode = 1;
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});