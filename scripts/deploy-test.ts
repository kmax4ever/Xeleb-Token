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
      const historys = [];
      while (isContinue) {
        // const currentPrice = await bondingTest.getCurrentPrice();
        // console.log("currentPrice", +fromWei(currentPrice));

        let buyAmount = randomInt(1, 10) / 10;
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
        historys.push(buyAmount);
        const totalSoldAmount = +fromWei(await bondingTest.totalSoldAmount());
        if (totalRaisedAmount >= 24 || totalSoldAmount == 700000000) {
          rs.push({
            totalRaisedAmount,
            totalSoldAmount,
            historys: historys.toString(),
          });
          console.log("totalSoldAmount", +fromWei(totalSoldAmount));
          isContinue = false;
        }
      }
    } catch (error) {
      rs.push({});
    }
  }

  var fs = require("fs");
  fs.writeFileSync("./scripts/test-result.json", JSON.stringify(rs, null, 4));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
