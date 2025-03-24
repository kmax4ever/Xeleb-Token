import { ethers } from "hardhat";

import * as config from "./config.json";
import {
  balanceOf,
  buyFunc,
  checkBalance,
  checkPrice,
  delay,
  etherProvider,
  fromWei,
  getBalanceAndDetails,
  getDetails,
  getEthForToken,
  getTokensForETH,
  getTotalSoldAmount,
  getWalletFromPkey,
  increaseTime,
  nativeBalance,
  raiseAamount,
  randomInt,
  sellFunc,
  toWei,
  toWeiDecimal,
  vestingDetails,
  waitMs,
} from "./utils";
import common from "mocha/lib/interfaces/common";
import { mine, mineUpTo } from "@nomicfoundation/hardhat-network-helpers";
import { increaseTo } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time";
import * as contractJson from "./contracts.json";
// case 1 test balance vesting

const testCaseUpdateVestingData = async (
  bodingContract: any,
  user: any,
  token: any,
  buyAmount: any
) => {
  await buyFunc(bodingContract, user, token, buyAmount);
  await vestingDetails(token, user.address);
  await buyFunc(bodingContract, user, token, buyAmount);
  await vestingDetails(token, user.address);
  //
};

const testCaseBuyAndTransfer = async (
  bodingContract: any,
  user: any,
  token: any,
  buyAmount: any
) => {
  await buyFunc(bodingContract, user, token, buyAmount);
  const tokenAddr = await token.getAddress();
  const rs = await getDetails(tokenAddr, user.address, "DETAILS");
  const { actualBalance, totalBalance, claimableAmount } = rs;

  // console.log(
  //   "--------------------TRASFER AMOUNT< ACTUAL BALANCE -------------------------"
  // );
  // await token.connect(user).transfer(config.WALLET.TO, toWei("90000"));
  // console.log("----------------------------------------------------");

  // await getDetails(tokenAddr, user.address, "DETAILS");
  // await getDetails(tokenAddr, config.WALLET.TO, "DETAILS");

  // console.log(
  //   "--------------------TRASFER AMOUNT > TOTAL BALANCE -------------------------"
  // );
  // await token.connect(user).transfer(config.WALLET.TO, toWei("490005"));
  // console.log("----------------------------------------------------");

  // await getDetails(tokenAddr, user.address, "DETAILS");
  // await getDetails(tokenAddr, config.WALLET.TO, "DETAILS");

  console.log(
    "--------------------TRASFER  ACTUAL < AMOUNT < TOTAL BALANCE (CLAIMED VESTING) -------------------------"
  );
  await token.connect(user).transfer(config.WALLET.TO, toWei("490001.9"), {});

  console.log("----------------------------------------------------");

  await getDetails(tokenAddr, user.address, "DETAILS");
  await getDetails(tokenAddr, config.WALLET.TO, "DETAILS");

  // transfer

  //
};

const testCasBuyAndSell = async (
  bodingContract: any,
  user: any,
  token: any,
  buyAmount: any
) => {
  const tokenAddr = await token.getAddress();
  await buyFunc(bodingContract, user, token, buyAmount);
  await getDetails(tokenAddr, user.address, "BEFOR SALE ");

  await increaseTime(config.DAY_AS_SECOND);
  const balance = await balanceOf(tokenAddr, user.address, "USER");
  console.log("sell balance: ", balance);

  await sellFunc(bodingContract, token, user, balance);
  await getDetails(tokenAddr, user.address, "AFTER SALE ");
  //
};

const checkStakingBalance = async (token: any) => {
  const tokenAddr = await token.getAddress();
  await balanceOf(tokenAddr, config.WALLET.STAKING, "STAKING");
};

const checkCreatorBalance = async (token: any) => {
  const tokenAddr = await token.getAddress();
  const createWallet = getWalletFromPkey(config.PKEY.CREATOR);
  await getDetails(tokenAddr, createWallet.address, "CREATOR DETAILS");
  await increaseTime(config.DAY_AS_SECOND);
  await getDetails(tokenAddr, createWallet.address, "CREATOR DETAILS");
};

const testTransferEndVesting = async (
  bodingContract: any,
  user: any,
  token: any,
  buyAmount: any
) => {
  await buyFunc(bodingContract, user, token, buyAmount);
  const tokenAddr = await token.getAddress();
  const rs = await getDetails(tokenAddr, user.address, "DETAILS");
  const { actualBalance, totalBalance, claimableAmount } = rs;

  await increaseTime(config.DAY_AS_SECOND * 270);

  console.log("----------------------------------------------------");
  const balance = await balanceOf(tokenAddr, user.address, "USER");
  console.log("end balance: ", balance);

  await token.connect(user).transfer(config.WALLET.TO, toWei(balance), {});

  console.log("----------------------------------------------------");

  await getDetails(tokenAddr, user.address, "DETAILS");
  await getDetails(tokenAddr, config.WALLET.TO, "DETAILS");

  await buyFunc(bodingContract, user, token, buyAmount);
  await getDetails(tokenAddr, user.address, "DETAILS");

  // transfer

  //
};

// user1 buy , user2 buy, user1 sell

const testCaseMultiBuySell = async (
  bodingContract: any,
  token: any,
  buyAmount: any
) => {
  const user1 = getWalletFromPkey(config.PKEY.USER1);
  const user2 = getWalletFromPkey(config.PKEY.USER2);
  const tokenAddr = await token.getAddress();

  await buyFunc(bodingContract, user1, token, buyAmount);
  await buyFunc(bodingContract, user2, token, buyAmount);
  await checkPrice(bodingContract);

  await getDetails(tokenAddr, user1.address, "USER1");
  await getDetails(tokenAddr, user2.address, "USER2");
  await sellFunc(
    bodingContract,
    token,
    user1,
    await balanceOf(tokenAddr, user1.address, "")
  );

  await sellFunc(
    bodingContract,
    token,
    user2,
    await balanceOf(tokenAddr, user2.address, "")
  );

  await delay(5);
  await increaseTime(config.DAY_AS_SECOND);

  await getDetails(tokenAddr, user1.address, "USER1");
  await getDetails(tokenAddr, user2.address, "USER2");
  await checkPrice(bodingContract);
  //
};

async function main() {
  const pkeyAdmin = process.env.ADMIN_KEY;
  const admin = getWalletFromPkey(pkeyAdmin);

  const tokenAddr = contractJson.agentTokenAddr;
  const bondingAddr = contractJson.bondingAddr;

  const token = await ethers.getContractAt("AiAgentToken", tokenAddr);
  const bodingContract = await ethers.getContractAt(
    "BondingCurve",
    bondingAddr
  );

  // const txAddliquid = await bodingContract.connect(admin).addLiquidity();

  // console.log("tx add liquid", txAddliquid.hash);

  // return;

  await getTokensForETH(bodingContract, 24);

  await balanceOf(tokenAddr, bondingAddr, "BONDING");
  const user1 = getWalletFromPkey(process.env.CREATOR_KEY);
  const isAdmin = await token.isAdmin(bondingAddr);
  console.log({ isAdmin });

  console.log({ bondingAddr });

  // const tokenForEth = await bodingContract.getTokensForETH(toWei(23));
  // console.log({ tokenForEth: +fromWei(tokenForEth) });

  //await mine(1);
  // check after buy
  await checkBalance(token, user1.address);
  await checkBalance(token, bondingAddr);
  await nativeBalance(user1.address, "BUYER");
  await nativeBalance(bondingAddr, "BONDING");
  await raiseAamount(bodingContract);
  await getTotalSoldAmount(bodingContract);

  let totalRaiseAamount = await raiseAamount(bodingContract);
  let isContinue = true;
  const sellAmount = 50000000;
  await getTokensForETH(bodingContract, 23);
  console.log("====================================");

  const count = await token.getHolderCount();
  console.log({ count: +count.toString() });

  while (isContinue) {
    let buyAmount = randomInt(1, 10) / (+process.env.PERCENT | 10);
    if (buyAmount + totalRaiseAamount > 24) {
      console.log("xxxxxxxxxxxxxxxxxx");

      buyAmount = 24 - totalRaiseAamount;
    }

    const currentPrice = await bodingContract.getCurrentPrice();
    console.log({ currentPrice: +fromWei(currentPrice) });

    await buyFunc(bodingContract, user1, token, buyAmount);
    const count = await token.getHolderCount();
    console.log({ count: +count.toString() });

    await getTokensForETH(bodingContract, buyAmount);

    await getEthForToken(bodingContract, sellAmount);
    console.log("xxxxxxxxxxxxxxxxxx");
    await getTokensForETH(bodingContract, 0.1);
    totalRaiseAamount += buyAmount;

    if (totalRaiseAamount >= 24) {
      isContinue = false;
    }
  }

  return;
  let totalSoldAount = await getTotalSoldAmount(bodingContract);

  let isSellContinue = true;
  while (isSellContinue) {
    await sellFunc(bodingContract, user1, token, sellAmount);
    await getTokensForETH(bodingContract, 0.1);
    await getEthForToken(bodingContract, sellAmount);
    await raiseAamount(bodingContract);
    totalSoldAount -= sellAmount;

    if (totalSoldAount < sellAmount) {
      isSellContinue = false;
    }
  }

  // for (let index = 0; index < step; index++) {
  //   await getEthForToken(bodingContract, 5000000);
  //       await sellFunc(bodingContract, user1, token, sellAmount);
  // }

  //await buyFunc(bodingContract, user1, token, 0.1);

  // await checkStakingBalance(token);

  // await testCaseUpdateVestingData(bodingContract, user1, token, buyAmount);

  //await testCaseBuyAndTransfer(bodingContract, user1, token, buyAmount);

  //await testCasBuyAndSell(bodingContract, user1, token, buyAmount);

  // await testTransferEndVesting(bodingContract, user1, token, buyAmount);

  //await checkCreatorBalance(token);

  // await testCaseMultiBuySell(bodingContract, token, buyAmount);

  // await buyFunc(bodingContract, user1, token, buyAmount);
  // await vestingDetails(token, user1.address);

  // await increaseTime(config.DAY_AS_SECOND * 270);
  // await getBalanceAndDetails(tokenAddr, user1.address, "xxxx");
  // const sellAmount = 495000 + 16500;

  // await sellFunc(bodingContract, token, user1, sellAmount);

  // await increaseTime(config.DAY_AS_SECOND * 10);
  // await checkBalance(token, user2.address);

  return;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

// TODO no vesting to test buy and sell
