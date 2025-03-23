const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BondingCurve", function () {
  let bondingCurve;
  let aiAgentToken;
  let owner;
  let addr1;
  let addr2;
  const MAX_SUPPLY = ethers.parseEther("700000000"); // 700M tokens
  const BONDING_TARGET = ethers.parseEther("24"); // 24 ETH
  const INITIAL_PRICE = ethers.parseEther("0.00001"); // 0.00001 ETH

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy AiAgentToken
    const AiAgentToken = await ethers.getContractFactory("AiAgentToken");
    aiAgentToken = await AiAgentToken.deploy(owner.address);
    await aiAgentToken.waitForDeployment();

    // Deploy BondingCurve
    const BondingCurve = await ethers.getContractFactory("BondingCurve");
    bondingCurve = await BondingCurve.deploy(
      await aiAgentToken.getAddress(),
      owner.address,
      MAX_SUPPLY
    );
    await bondingCurve.waitForDeployment();
  });

  describe("Initial Setup", function () {
    it("Should set correct initial values", async function () {
      expect(await bondingCurve.MAX_SUPPLY()).to.equal(MAX_SUPPLY);
      expect(await bondingCurve.BONDING_TARGET()).to.equal(BONDING_TARGET);
      expect(await bondingCurve.INITIAL_PRICE()).to.equal(INITIAL_PRICE);
    });

    it("Should calculate correct slope", async function () {
      const slope = await bondingCurve.SLOPE();
      console.log("Calculated slope:", slope.toString());

      // Verify slope calculation
      // P = m⋅S + b
      // At S = MAX_SUPPLY: P = BONDING_TARGET
      // BONDING_TARGET = m⋅MAX_SUPPLY + INITIAL_PRICE
      // m = (BONDING_TARGET - INITIAL_PRICE) / MAX_SUPPLY
      const expectedSlope = (BONDING_TARGET - INITIAL_PRICE) / MAX_SUPPLY;
      expect(slope).to.be.closeTo(expectedSlope, expectedSlope / 1000); // Allow 0.1% deviation
    });
  });

  describe("Price Calculation", function () {
    it("Should return initial price when no tokens sold", async function () {
      const price = await bondingCurve.getCurrentPrice();
      expect(price).to.equal(INITIAL_PRICE);
    });

    it("Should calculate correct price after some tokens sold", async function () {
      // Buy some tokens first
      const buyAmount = ethers.parseEther("1"); // 1 ETH
      await bondingCurve.connect(addr1).buyTokens({ value: buyAmount });

      const price = await bondingCurve.getCurrentPrice();
      const totalSold = await bondingCurve.totalSoldAmount();
      const slope = await bondingCurve.SLOPE();

      // Verify price calculation: P = m⋅S + b
      const expectedPrice =
        (slope * totalSold) / ethers.parseEther("1") + INITIAL_PRICE;
      expect(price).to.be.closeTo(expectedPrice, expectedPrice / 1000); // Allow 0.1% deviation
    });
  });

  describe("Token Purchase", function () {
    it("Should calculate correct token amount for first buy", async function () {
      const ethAmount = ethers.parseEther("1"); // 1 ETH
      const tokenAmount = await bondingCurve.getTokensForETH(ethAmount);

      // Verify token amount calculation: tokens = ethAmount / INITIAL_PRICE
      const expectedTokens = ethAmount / INITIAL_PRICE;
      expect(tokenAmount).to.be.closeTo(expectedTokens, expectedTokens / 1000); // Allow 0.1% deviation
    });

    it("Should not exceed max supply", async function () {
      const largeAmount = ethers.parseEther("1000"); // 1000 ETH
      const tokenAmount = await bondingCurve.getTokensForETH(largeAmount);
      expect(tokenAmount).to.be.lte(MAX_SUPPLY);
    });
  });

  describe("Total ETH Collection", function () {
    it("Should collect approximately BONDING_TARGET when all tokens sold", async function () {
      // Buy all tokens in small increments
      const increment = ethers.parseEther("0.1"); // 0.1 ETH
      let totalEth = ethers.parseEther("0");

      while (true) {
        const tokenAmount = await bondingCurve.getTokensForETH(increment);
        if (tokenAmount.eq(0)) break;

        await bondingCurve.connect(addr1).buyTokens({ value: increment });
        totalEth = totalEth.add(increment);
      }

      // Verify total ETH collected is close to BONDING_TARGET
      expect(totalEth).to.be.closeTo(BONDING_TARGET, BONDING_TARGET / 100); // Allow 1% deviation
    });
  });
});
