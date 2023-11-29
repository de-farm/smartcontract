import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, ContractTransaction, Wallet, getBytes, hashMessage, parseUnits, randomBytes, toBigInt } from "ethers";
import { ChainConfig } from "../config/seasonalFarm.config";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { randomInt } from "crypto";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { DexSimulator, AssetSimulator, FarmManagement, MockERC20, SeasonalFarm, SeasonalFarmFactory, ERC20Upgradeable } from "../types";
import { IHasFeeInfo } from "../types/contracts/seasonal/SeasonalFarmFactory";
import { seasonal } from "../types/contracts";
import { AsyncLocalStorage } from "async_hooks";

describe("Seasonal Farm Test", function () {
  const USDC_DECIMALS = 6
  const BTC_DECIMALS = 18
  const ETH_DECIMALS = 18
  const ASSET_DECIMALS = 18 // This is the decimals of USD
  const SHARE_DECIMALS = 18
  const ONE_USDC = parseUnits("1", USDC_DECIMALS);
  const ONE_DOLLAR = parseUnits("1", ASSET_DECIMALS);
  const ONE_SHARE = parseUnits("1", SHARE_DECIMALS);
  const FEE_DENOMINATOR = parseUnits("100", 18)
  const ZERO = BigInt(0)

  const DEFAULT_USDC_PRICE = parseUnits("1", ASSET_DECIMALS); // $1
  const DEFAULT_BTC_PRICE = parseUnits("10", ASSET_DECIMALS); // $10
  const DEFAULT_ETH_PRICE = parseUnits("5", ASSET_DECIMALS); // $5

  function usdcTo18Decimals(usdcAmount: bigint): bigint {
    return usdcAmount*ONE_DOLLAR/ONE_USDC
  }

  async function deployFixture() {
    /* const SeasonalFarm = await ethers.getContractFactory("SeasonalFarm");
    const seasonalFarm = await SeasonalFarm.deploy();

    const FarmManagement = await ethers.getContractFactory("FarmManagement");
    const farmManagerment = await FarmManagement.deploy(); */
    const usdcAddress = '0x179522635726710Dd7D2035a81d856de4Aa7836c'
    const USDC = await ethers.getContractFactory("ERC20Upgradeable");
    const usdc = USDC.attach(usdcAddress) as unknown as ERC20Upgradeable

    const seasonalFarmFactory = await ethers.getContractFactory("SeasonalFarmFactory");
    const farmFactory = seasonalFarmFactory.attach('') as unknown as SeasonalFarmFactory

    return {
      usdc, usdcAddress,
      farmFactory
    };
  }

  describe("Asset handler test", function () {
    it("Should be able to update the asset prices", async function () {
      /* const { farmFactory, usdc, usdcAddress } = await loadFixture(deployFixture);
      const price = await farmFactory.getAssetPrice(usdcAddress)
      console.log(price.toString()) */

      const usdcAddress = '0x179522635726710Dd7D2035a81d856de4Aa7836c'
      const USDC = await ethers.getContractFactory("ERC20Upgradeable");
      const usdc = USDC.attach(usdcAddress) as unknown as ERC20Upgradeable

      const seasonalFarmFactory = await ethers.getContractFactory("SeasonalFarmFactory");
      const farmFactory = seasonalFarmFactory.attach('0x8bDC58b59f281DAb3d8b77ce1Ee35A9C027c215A') as unknown as SeasonalFarmFactory

      const price = await farmFactory.getAssetPrice(usdcAddress)
      console.log(price.toString())

      const farmAddress = '0x5f83905561c6c29f3026862342ca6340a8c9cc6a'
      const SeasonalFarm = await ethers.getContractFactory("SeasonalFarm");
      const farm = SeasonalFarm.attach(farmAddress) as unknown as SeasonalFarm

      const operator = await farm.operator()
      console.log('operator', operator)

      const usdcDepositAmount = parseUnits("500", USDC_DECIMALS);
      const sharePriceBefore =  await farm.getSharePrice();
      console.log(sharePriceBefore/ONE_DOLLAR)

      const totalSupply =  await farm.totalSupply();
      console.log('totalSupply', totalSupply/ONE_SHARE)

      const FarmManagement = await ethers.getContractFactory("FarmManagement");
      const farmManagement = FarmManagement.attach(await farm.farmManagement()) as unknown as FarmManagement
      const totalFund = await farmManagement.totalFundValue();
      const totalAssetValue = await farmManagement.totalAssetValue()
      const totalBalanceOnDex = await farmManagement.totalBalanceOnDex()
      console.log('totalFund', totalFund/ONE_DOLLAR)
      console.log('totalAssetValue', totalAssetValue/ONE_DOLLAR)
      console.log('totalBalanceOnDex', totalBalanceOnDex/ONE_DOLLAR)

      await usdc.approve(farmAddress, usdcDepositAmount)
      const assetValueInDollar = await farmFactory.assetValue(usdcAddress, usdcDepositAmount)
      const expectedShares = await farm.assetValueToShares(assetValueInDollar, sharePriceBefore)
      const [entranceFeeNumerator, entranceFeeDenominator] = await farmManagement.getEntranceFee()
      const entranceFee = expectedShares*entranceFeeNumerator/entranceFeeDenominator
      const receivedShares = expectedShares - entranceFee
      console.log('receivedShares', receivedShares/ONE_SHARE)

      await farm.deposit(
        usdcAddress,
        usdcDepositAmount,
        receivedShares
      )
    })
  })
});
