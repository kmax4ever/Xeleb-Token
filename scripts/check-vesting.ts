import { ethers } from "hardhat";
import * as config from "./config.json";
import {
  balanceOf,
  delay,
  fromWei,
  getBalanceAndDetails,
  getDetails,
  getWalletFromPkey,
  toWei,
  waitMs,
} from "./utils";
import common from "mocha/lib/interfaces/common";
import { mineUpTo } from "@nomicfoundation/hardhat-network-helpers";
import { increaseTo } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time";
import { agentAddr, agenToken, initContract } from "./initContract";
// case 1 test balance vesting
async function main() {
  await initContract();
  let day = 1;
  let isContinue = true;
  const agentAddr = await agenToken.getAddress();
  await getBalanceAndDetails(
    agentAddr,
    getWalletFromPkey(config.PKEY.COMMUNITY).address,
    "COMMUNITY"
  );
  while (isContinue) {
    await delay(1);
    day++;

    const block = await ethers.provider.getBlockNumber();
    await mineUpTo(block + 100);
    console.log({ block });
    const time = await ethers.provider.getBlock(block);
    const timestamp = time?.timestamp || 0;
    const nextTime = config.DAY_AS_SECOND;
    await increaseTo(timestamp + nextTime);
    console.log(day);
    await getBalanceAndDetails(
      agentAddr,
      getWalletFromPkey(config.PKEY.COMMUNITY).address,
      "COMMUNITY"
    );
    if (day > 35) {
      isContinue = false;
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
