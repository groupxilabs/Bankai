import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";


const WillSummaryModule = buildModule("WillSummaryModule", (m) => {

  const willRegistryAddress = "0x810C94bD7DC8aF98f6F142C6aaca13824b51Ac42"

  const willSummary = m.contract("WillSummary", [willRegistryAddress]);

  return { willSummary };
});

export default WillSummaryModule;