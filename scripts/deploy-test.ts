import { ethers } from "hardhat";
const provider = new ethers.JsonRpcProvider(process.env.RPC_ENDPOINT);
import * as config from "./config.json";
import {
  delay,
  etherProvider,
  fromWei,
  getDetails,
  getTokensForETH,
  getWalletFromPkey,
  randomInt,
} from "./utils";

// case 1 test balance vesting

import * as FactoryJson from "../artifacts/contracts/Controller.sol/Controller.json";
export const toWei = (value: any) => {
  return ethers.parseUnits(value.toString(), 18);
};
async function main() {
  const rs = [];

  for (let index = 0; index < 20; index++) {
    try {
      const BondingTest = await ethers.getContractFactory("BondingTest");
      const bondingTest = await BondingTest.deploy();
      //const tokenForETh = await bondingTest.getTokensForETH(toWei(24));
      let totalRaisedAmount = +fromWei(await bondingTest.totalRaisedAmount());
      console.log("totalRaisedAmount", totalRaisedAmount);
      let isContinue = true;
      while (isContinue) {
        // const currentPrice = await bondingTest.getCurrentPrice();
        // console.log("currentPrice", +fromWei(currentPrice));

        let buyAmount = randomInt(1, 10) / 100;
        console.log({ buyAmount });

        if (totalRaisedAmount + buyAmount > 24) {
          buyAmount = 24 - totalRaisedAmount;
        }
        //console.log({ buyAmount });
        const tx = await bondingTest.buyTokens({
          value: toWei(buyAmount),
        });
        totalRaisedAmount += buyAmount;
        console.log({ totalRaisedAmount });

        if (totalRaisedAmount >= 24) {
          const totalSoldAmount = await bondingTest.totalSoldAmount();
          rs.push(totalSoldAmount);
          console.log("totalSoldAmount", +fromWei(totalSoldAmount));
          isContinue = false;
        }
      }
    } catch (error) {
      rs.push(0);
    }
  }
  console.log({ rs });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
