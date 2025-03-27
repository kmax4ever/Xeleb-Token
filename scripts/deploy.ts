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
  toWei,
} from "./utils";

// case 1 test balance vesting

import * as FactoryJson from "../artifacts/contracts/Controller.sol/Controller.json";
import { mine, mineUpTo } from "@nomicfoundation/hardhat-network-helpers";

async function main() {
  const pkeyAdmin = process.env.ADMIN_KEY;
  const admin = getWalletFromPkey(pkeyAdmin);
  const creator = getWalletFromPkey(process.env.CREATOR_KEY);

  // const TOKEN_FEE = await ethers.getContractFactory("Token");
  // const token = await TOKEN_FEE.connect(creator).deploy();
  // console.log({ token: await token.getAddress() });

  // return;

  // const TOKEN_FEE = await ethers.getContractAt(
  //   "Token",
  //   "0x54e8c201A65A2dcAA29Fea2c3525D5c8aA79268A"
  // );

  const Controller = await ethers.getContractFactory("Controller");
  const receiver = admin.address;
  const factory = await Controller.connect(admin).deploy(receiver);

  const factoryAddr = await factory.getAddress();

  // await TOKEN_FEE.connect(creator).approve(factoryAddr, toWei(`5000000000`));

  // await TOKEN_FEE.connect(admin).transferFrom(
  //   creator.address,
  //   config.WALLET.TO,
  //   toWei("10"),
  //   { nonce: await provider.getTransactionCount(admin.address, "latest") }
  // );

  console.log({ factoryAddr });

  const newToken = config.NEW_TOKEN;
  let agentTokenAddr = "";
  let bondingAddr = "";

  if (Number(process.env.CHAIN_ID) == 1337) {
    await mineUpTo(10);
  }

  if (Number(process.env.CHAIN_ID) !== 97) {
    console.log("-------CREATE TOKEN------");

    const tx = await factory
      .connect(creator)
      .createToken(
        newToken.name,
        newToken.symbol,
        config.WALLET.STAKING,
        toWei(newToken.totalSupply),
        {
          nonce: await provider.getTransactionCount(creator.address, "latest"),
          value: toWei(0.101),
        }
      );
    await tx.wait();
    console.log("hash :", tx.hash);
    agentTokenAddr = await factory.getTokenByOwner(creator.address);
    bondingAddr = await factory.getBondingByToken(agentTokenAddr);

    // await mine(10);
    // const bodingContract = await ethers.getContractAt(
    //   "BondingCurve",
    //   bondingAddr
    // );
    // const currentPrice = await bodingContract.getCurrentPrice();
    // console.log({ currentPrice: +fromWei(currentPrice) });
  }

  // const bondingList = await factory.getBondingList();
  // console.log({ bondingList });
  // const data = bondingList[0];

  const CONTRACT_ADDRESSES_MAP = {
    controller: await factory.getAddress(),
    agentTokenAddr,
    bondingAddr,
    chainID: process.env.CHAIN_ID,
    rpc: process.env.RPC_ENDPOINT,
  };
  var fs = require("fs");
  fs.writeFileSync(
    "./scripts/contracts.json",
    JSON.stringify(CONTRACT_ADDRESSES_MAP, null, 4)
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
