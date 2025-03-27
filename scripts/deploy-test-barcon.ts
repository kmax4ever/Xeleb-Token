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
    const historys = [];
    try {
      const BondingTest = await ethers.getContractFactory("BondingTestBarcon");
      const bondingTest = await BondingTest.deploy();
      //const tokenForETh = await bondingTest.getTokensForETH(toWei(24));
      let totalRaisedAmount = +fromWei(await bondingTest.totalRaisedAmount());
      console.log("totalRaisedAmount", totalRaisedAmount);
      let isContinue = true;
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
          value: toWei(buyAmount.toFixed(5)),
        });
        totalRaisedAmount += buyAmount;
        console.log({ totalRaisedAmount });
        historys.push(buyAmount);
        const totalSoldAmount = +fromWei(await bondingTest.totalSoldAmount());
        if (totalRaisedAmount >= 24 || totalSoldAmount == 750000000) {
          rs.push({
            totalSoldAmount,
            totalRaisedAmount,
            historys: historys.toString(),
          });
          console.log("totalSoldAmount", totalSoldAmount);
          isContinue = false;
        }
      }
    } catch (error) {
      rs.push(0);
    }
  }
  console.log({ rs });
  var fs = require("fs");
  fs.writeFileSync("./scripts/test-bonding.json", JSON.stringify(rs, null, 4));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
