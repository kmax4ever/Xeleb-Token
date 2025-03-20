import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import * as config from "../scripts/config.json";
import { fromWei, getWalletFromPkey, toWei } from "../scripts/utils";

const getBalance = async (tokenAddr: string, address: string, key: string) => {
  const token = await hre.ethers.getContractAt("AiAgentToken", tokenAddr);
  const balance = await token.balanceOf(address);
  console.log(`xxx balanceOf : ${key}`, +fromWei(balance));

  return +fromWei(balance);
};

const getDetails = async (tokenAddr: string, address: string, key: string) => {
  const token = await hre.ethers.getContractAt("AiAgentToken", tokenAddr);
  const details = await token.getDetailsAccount(address);
  console.log(`xxx details : ${key}`);
  const {
    actualBalance,
    vestedBalance,
    claimableAmount,
    totalBalance,
    vestingEndTime,
  } = details;

  console.table({
    actualBalance,
    vestedBalance,
    claimableAmount,
    totalBalance,
    vestingEndTime,
  });
  return details;
};

var WALLET = {
  COMMUNITY: "",
  TREASURY: "",
  LIQUIDITY: "",
  STAKING: "",
  TEAM: "",
  AGENT: "",
  STRONGBOX: "",
} as any;
describe("----- DEPLOY ----------", async function () {
  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.

  describe("Deployment", async function () {
    it("Check distibutor", async function () {
      for (const key in WALLET) {
        WALLET[key] = getWalletFromPkey(config.PKEY[key] as any);
      }
      const AgentToken = await hre.ethers.getContractFactory("AiAgentToken");
      const agentToken = await AgentToken.deploy(
        config.NEW_TOKEN.name,
        config.NEW_TOKEN.symbol,
        `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`,
        WALLET.COMMUNITY,
        WALLET.TREASURY,
        WALLET.LIQUIDITY,
        WALLET.STAKING,
        WALLET.TEAM,
        WALLET.AGENT,
        WALLET.STRONGBOX,
        [toWei(config.NEW_TOKEN.totalSupply), config.NEW_TOKEN.transferFee]
      );

      const agentAddr = await agentToken.getAddress();
      console.log({ agentAddr });
      const communityBalance = await getBalance(
        agentAddr,
        WALLET.COMMUNITY,
        "COMMUNITY"
      );
      const communityDetail = await getDetails(
        agentAddr,
        WALLET.COMMUNITY,
        "COMMUNITY"
      );

      const treasuryBalance = await getBalance(
        agentAddr,
        WALLET.TREASURY,
        "TREASURY"
      );
      await getBalance(agentAddr, WALLET.LIQUIDITY, "LIQUIDITY");
      await getBalance(agentAddr, WALLET.STAKING, "STAKING");
      await getBalance(agentAddr, WALLET.TEAM, "TEAM");
      await getBalance(agentAddr, WALLET.AGENT, "AGENT");
      await getBalance(agentAddr, WALLET.STRONGBOX, "STRONGBOX");

      expect(communityBalance).to.equal(
        +fromWei(communityDetail.actualBalance),
        "Error ! balance must be equal actualBalance"
      );
    });

    it("xxx", async function () {
      //  expect(await lock.owner()).to.equal(owner.address);
    });
  });
});
