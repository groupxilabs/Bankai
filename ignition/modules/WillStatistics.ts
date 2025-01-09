import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";


const WillStatisticsModule = buildModule("WillStatisticsModule", (m) => {

  const willRegistryAddress = "0x810C94bD7DC8aF98f6F142C6aaca13824b51Ac42"

  const willStatisticsSummary = m.contract("WillStatistics", [willRegistryAddress]);

  return { willStatisticsSummary };
});

export default WillStatisticsModule;