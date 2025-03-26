import { getWalletFromPkey, toWei } from "./utils";

const ethers = require("ethers");
require("dotenv").config();

const provider = new ethers.JsonRpcProvider(process.env.RPC_ENDPOINT);
const wallet = new ethers.Wallet(`0x` + process.env.CREATOR_KEY).connect(
  provider
);
const address = wallet.address;
const controllerJson = require("../artifacts/contracts/Controller.sol/Controller.json");
import * as config from "./contracts.json";
const controllerAddress = config.controller;
async function main() {
  console.log("CREATE TOKEN BSC");

  try {
    const controller = new ethers.Contract(
      controllerAddress,
      controllerJson.abi,
      provider
    );

    const dataObj = controller.interface.encodeFunctionData("createToken", [
      "Agent01",
      "Agent01",
      controllerAddress,
      `1000000000000000000000000000`,
    ]);
    console.log({ address });

    const tx = {
      chainId: Number(process.env.CHAIN_ID),
      from: address,
      nonce: (await provider.getTransactionCount(address, "latest")) + 1,
      to: controllerAddress,
      data: dataObj,
      value: toWei(0.011),
    };

    const txn = await wallet.sendTransaction(tx);
    await txn.wait();
    console.info(`... Sent! ${txn.hash}`);
    const tokenAddr = await controller.getTokenByOwner(address);
    const bondingAddr = await controller.getBondingByToken(tokenAddr);
    console.log({
      tx: txn.hash,
      controllerAddress,
      tokenAddr,
      bondingAddr,
    });

    return txn.hash;
  } catch (error) {
    console.log(error.message);
  }
}

async function start() {
  await main();
}

start();
