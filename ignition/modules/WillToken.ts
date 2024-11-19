// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";


const WillTokenModule = buildModule("WillTokenModule", (m) => {

  const willRegistry = m.contract("WillToken");

  return { willRegistry };
});

export default WillTokenModule;
