import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, ContractTransaction, ContractTransactionReceipt, EventLog, Wallet, getBytes, hashMessage, parseUnits, randomBytes, toBigInt } from "ethers";
import { ChainConfig } from "../config/seasonalFarm.config";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { randomInt } from "crypto";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { DexSimulator, AssetSimulator, SingleFarmFactory, FarmManagement, MockERC20, SeasonalFarm, SeasonalFarmFactory, ERC20Upgradeable } from "../types";
import { ISingleFarmFactory, SingleFarm } from "../types/contracts/single/SingleFarm";
import { IHasFeeInfo } from "../types/contracts/seasonal/SeasonalFarmFactory";
import { seasonal } from "../types/contracts";
import { AsyncLocalStorage } from "async_hooks";

describe("Single Farm Test", function () {
  const usdcAddress = '0xbC47901f4d2C5fc871ae0037Ea05c3F614690781'
  const baseTokenAddress = '0xA7Fcb606611358afa388b6bd23b3B2F2c6abEd82'
  const farmFactoryAddress = '0x0935F491045FB4642D4718708f68FD7B63ec53b8'
  let farmAddress = '0xFA51cd8bc8B56B9737E5086Bef3B0Dd5e03eDCD0'
  it("Create a farm", async function () {
    const [owner] = await ethers.getSigners();

    const singleFarmFactory = await ethers.getContractFactory("SingleFarmFactory");
    const farmFactory = singleFarmFactory.attach(farmFactoryAddress) as unknown as SingleFarmFactory

    const operator = owner
    const manager = owner
    const maker = owner

    await farmFactory.setMaker(maker.address)
    const hash = await farmFactory.getCreateFarmDigest(operator.address, manager.address)
    const message = getBytes(hash)
    const signature = await maker.signMessage(message);

    const ethFee = await farmFactory.ethFee()
    const st: ISingleFarmFactory.SfStruct = {
      baseToken: baseTokenAddress,
      tradeDirection: true,
      fundraisingPeriod: 15*60,
      entryPrice: 1000000000,
      targetPrice: 200000000,
      liquidationPrice: 4000000000,
      leverage: await farmFactory.minLeverage()
    }

    const tx = await farmFactory.connect(manager).createFarm(
      st, parseUnits("10", 18), operator.address, signature, {value: ethFee}
    )

    const receipt: ContractTransactionReceipt | null = await tx.wait();
    const x = receipt?.logs[2] as EventLog
    farmAddress = x!.args[0] as string
    console.log(farmAddress)
  })

  it("Deposit", async function () {
    const [owner] = await ethers.getSigners();

    const USDC = await ethers.getContractFactory("ERC20Upgradeable");
    const usdc = USDC.attach(usdcAddress) as unknown as ERC20Upgradeable

    const singleFarm = await ethers.getContractFactory("SingleFarm");
    const farm = singleFarm.attach(farmAddress) as unknown as SingleFarm

    const operator = owner
    const manager = owner
    const maker = owner

    const usdcDepositAmount = parseUnits("50", 6)
    await usdc.approve(farmAddress, usdcDepositAmount)

    await farm.deposit(
      usdcDepositAmount
    )
  })

  it("Close fundraising", async function () {
    const [owner] = await ethers.getSigners();

    const singleFarm = await ethers.getContractFactory("SingleFarm");
    const farm = singleFarm.attach(farmAddress) as unknown as SingleFarm

    const operator = owner
    const manager = owner
    const maker = owner

    const hash = hashMessage("limit")
    await farm.closeFundraising()
  })

  it("Open position", async function () {
    const [owner] = await ethers.getSigners();

    const singleFarm = await ethers.getContractFactory("SingleFarm");
    const farm = singleFarm.attach(farmAddress) as unknown as SingleFarm

    const operator = owner
    const manager = owner
    const maker = owner

    const hash = hashMessage("limit")
    const tx2 = await farm.openPosition(hash)
  })

  /* it("Link signer", async function () {
    const [owner] = await ethers.getSigners();

    const singleFarm = await ethers.getContractFactory("SingleFarm");
    const farm = singleFarm.attach(farmAddress) as unknown as SingleFarm

    const operator = owner
    const manager = owner
    const maker = owner

    const tx = await farm.linkSigner2()
  }) */

  it("Close position", async function () {
    const [owner] = await ethers.getSigners();

    const singleFarm = await ethers.getContractFactory("SingleFarm");
    const farm = singleFarm.attach(farmAddress) as unknown as SingleFarm

    const operator = owner
    const manager = owner
    const maker = owner

    const hash = hashMessage("limit")
    await farm.setStatus(0)
    const tx2 = await farm.closePosition(parseUnits("48", 6))
  })

  it("Withdraw", async function () {
    const USDC = await ethers.getContractFactory("ERC20Upgradeable");
    const usdc = USDC.attach(usdcAddress) as unknown as ERC20Upgradeable
    const balance = await usdc.balanceOf(farmAddress)
    console.log(balance)
  })
});
