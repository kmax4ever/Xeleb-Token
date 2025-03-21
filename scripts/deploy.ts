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

async function main() {
  const pkeyAdmin = process.env.ADMIN_KEY;
  const admin = getWalletFromPkey(pkeyAdmin);

  const Controller = await ethers.getContractFactory("Controller");
  const receiver = admin.address;
  const factory = await Controller.connect(admin).deploy(receiver);
  const creator = getWalletFromPkey(process.env.CREATOR_KEY);
  const newToken = config.NEW_TOKEN;

  if (Number(process.env.CHAIN_ID) !== 97) {
    console.log("-------CREATE TOKEN------");
    const tx = await factory
      .connect(creator)
      .createToken(
        newToken.name,
        newToken.symbol,
        config.WALLET.STAKING,
        toWei(newToken.totalSupply),
        { value: toWei(0.4) }
      );

    await tx.wait();
    console.log("hash :", tx.hash);
    const agentTokenAddr = await factory.getTokenByOwner(creator.address);
    const bondingAddr = await factory.getBondingByToken(agentTokenAddr);
    const bodingContract = await ethers.getContractAt(
      "BondingCurve",
      bondingAddr
    );

    //await getDetails(agentTokenAddr, creator.address, "CREATOR");

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
  } else {
    console.log("DEPLOY factory");
    const CONTRACT_ADDRESSES_MAP = {
      controller: await factory.getAddress(),
      chainID: process.env.CHAIN_ID,
      rpc: process.env.RPC_ENDPOINT,
    };
    var fs = require("fs");
    fs.writeFileSync(
      "./scripts/contracts.json",
      JSON.stringify(CONTRACT_ADDRESSES_MAP, null, 4)
    );
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
