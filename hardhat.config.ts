import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
require("dotenv").config();
const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 500,
      },
      viaIR: true,
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      chainId: Number(process.env.CHAIN_ID),
    },
    deploy: {
      url: process.env.RPC_ENDPOINT,
      // gasPrice: 10000000000,
      gasPrice: 10000000000,
      gas: 50000000,
      chainId: Number(process.env.CHAIN_ID),
      accounts: [process.env.ADMIN_KEY as string],
      allowUnlimitedContractSize: true,
    },
  },
};

export default config;
