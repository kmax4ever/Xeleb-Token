import { mine, mineUpTo } from "@nomicfoundation/hardhat-network-helpers";
import { increaseTo } from "@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time";
import { ethers } from "hardhat";
import * as utils from "web3-utils";
const { NonceManager } = ethers;
export const waitMs = (msDuration: number) => {
  return new Promise((resolve, reject) => {
    setTimeout(() => {
      resolve(null);
    }, msDuration);
  });
};
const provider = new ethers.JsonRpcProvider(process.env.RPC_ENDPOINT);

export const etherProvider = new ethers.JsonRpcProvider(
  process.env.RPC_ENDPOINT
);

export const fromWei = (value: any) => {
  return ethers.formatUnits(value.toString());
};

export const toWei = (value: any) => {
  return ethers.parseUnits(value.toString(), 18);
};

export const toWeiDecimal = (value: any) => {
  return utils.toWei(value.toString(), "ether");
};

export const delay = async (second: number) => {
  for (let i = 0; i < second; i++) {
    console.log(`${i}........`);
    await waitMs(1000);
  }
};

export const balanceOf = async (
  tokenAddr: string,
  address: string,
  key: string
) => {
  const token = await ethers.getContractAt("AiAgentToken", tokenAddr);
  const balance = await token.balanceOf(address);
  console.log(`xxx balanceOf : ${key}`, +fromWei(balance));

  return +fromWei(balance);
};

export const getDetails = async (
  tokenAddr: string,
  address: string,
  key: string
) => {
  const token = await ethers.getContractAt("AiAgentToken", tokenAddr);
  const details = await token.getDetailsAccount(address);
  console.log(`xxx -------- : ${key}`);
  const {
    actualBalance,
    vestedBalance,
    claimableAmount,
    totalBalance,
    vestingEndTime,
    releasedAmount,
  } = details;

  const rs = {
    actualBalance: +fromWei(actualBalance),
    vestedBalance: +fromWei(vestedBalance),
    claimableAmount: +fromWei(claimableAmount),
    totalBalance: +fromWei(totalBalance),
    vestingEndTime: +vestingEndTime.toString(),
    releasedAmount: +fromWei(releasedAmount),
  };
  console.table(rs);
  return rs;
};

export const getWalletFromPkey = (pkey: any) => {
  return new ethers.Wallet(pkey).connect(etherProvider);
};

export const getBalanceAndDetails = async (
  tokenAddr: string,
  account: string,
  key: string
) => {
  await balanceOf(tokenAddr, account, key);
  await getDetails(tokenAddr, account, key);
};

export const increaseTime = async (nextTime: number) => {
  const blockNum = await ethers.provider.getBlockNumber();
  const blockTime = await ethers.provider.getBlock(blockNum);
  await mineUpTo(blockNum + 1);
  const timestamp = blockTime?.timestamp || 0;
  console.log(`----- increate time ${nextTime} s----- `);

  await increaseTo(timestamp + nextTime);
};

export const checkBalance = async (token: any, address: string) => {
  const balance = await token.balanceOf(address);
  console.log({ balance: +fromWei(balance) });
};

export const checkSupply = async (token: any) => {
  const totalSupply = await token.totalSupply();
  console.log({ totalSupply: +fromWei(totalSupply) });
};

export const nativeBalance = async (address: string, key: string) => {
  const balance = await etherProvider.getBalance(address);
  console.log(`------------- ${key} ETH : ${+fromWei(balance)}`);
  //console.log({ balance: +fromWei(balance) });
};

export const raiseAamount = async (bodingContract: any) => {
  const raisedAmount = await bodingContract.getRaisedAmount();
  console.log({ raisedAmount: +fromWei(raisedAmount) });
  //console.log({ balance: +fromWei(balance) });
};

export const getTotalSoldAmount = async (bodingContract: any) => {
  const getTotalSoldAmount = await bodingContract.getTotalSoldAmount();
  console.log({ getTotalSoldAmount: +fromWei(getTotalSoldAmount) });

  return +fromWei(getTotalSoldAmount);
  //console.log({ balance: +fromWei(balance) });
};

export const vestingDetails = async (token: any, address: string) => {
  console.log("------------------------ VESTING DETAIL-----------------------");

  const details = await token.vestingDetails(address);
  const { totalAmount, startTime, cliffEnd, lastClaimTime, releasedAmount } =
    details;
  console.table({
    totalAmount: +fromWei(totalAmount),
    startTime: +startTime.toString(),
    cliffEnd: +cliffEnd.toString(),
    lastClaimTime: +lastClaimTime.toString(),
    releasedAmount: +fromWei(releasedAmount),
  });
  console.log("-----------------------------------------------");
};

export const buyFunc = async (
  bodingContract: any,
  user: any,
  token: any,
  amount: number
) => {
  console.log("-------------------- BUY---------------------");

  await bodingContract.get;
  await bodingContract.connect(user).buyTokens({
    value: toWei(amount),
    nonce: await provider.getTransactionCount(user.address, "latest"),
  });

  const bondingAddr = await bodingContract.getAddress();

  await delay(1);
  //await mine(10);
  // await nativeBalance(user.address, "BUYER");
  // await nativeBalance(bondingAddr, "BONDING");
  // await checkPrice(bodingContract);
  await raiseAamount(bodingContract);
  await getTotalSoldAmount(bodingContract);
  // const tokenAddr = await token.getAddress();
  // await getBalanceAndDetails(
  //   tokenAddr,
  //   user,
  //   "-----------BALANCE AND  VESTING DETAILS----------"
  // );

  console.log("----------------------------------------------");
};

export const sellFunc = async (
  bodingContract: any,
  user: any,
  token: any,
  amount: number
) => {
  console.log("---------------------- SELL----------------------");
  await delay(3);
  await mine(10);

  const tokenAddr = await token.getAddress();
  const bondingAddr = await bodingContract.getAddress();

  console.log("-------------------- APPROVE----------------------");
  await token.connect(user).approve(bondingAddr, toWei(amount - 0.1), {
    nonce: await provider.getTransactionCount(user.address, "latest"),
  });
  await delay(5);
  await mine(10);
  await bodingContract.connect(user).sellTokens(toWei(amount - 1), {
    nonce: await provider.getTransactionCount(user.address, "latest"),
  });
  await checkBalance(token, user.address);
  await checkBalance(token, tokenAddr);
  await nativeBalance(user.address, "BUYER");
  await nativeBalance(bondingAddr, "BONDING");
  await checkSupply(token);
  await raiseAamount(bodingContract);
  await getTotalSoldAmount(bodingContract);
  await getBalanceAndDetails(
    tokenAddr,
    user,
    "-----------BALANCE AND  VESTING DETAILS----------"
  );

  console.log("--------------------------------------------------");
};

export const getTokensForETH = async (bodingContract, amount) => {
  const tokenForEth = await bodingContract.getTokensForETH(toWei(amount));
  console.log({ tokenForEth: +fromWei(tokenForEth) });
};

export const getEthForToken = async (bodingContract, amount) => {
  const ethForToken = await bodingContract.getETHForTokens(toWei(amount));
  console.log({ ethForToken: +fromWei(ethForToken) });
};

export const randomInt = (min, max) => {
  min = Math.ceil(min);
  max = Math.floor(max);
  return Math.floor(Math.random() * (max - min + 1)) + min;
};
