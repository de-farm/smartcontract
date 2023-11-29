import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { DeFarmSeeds } from "../types";
import { randomInt } from "crypto";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("DeFarm Seeds Test", function () {
  async function deployFixture() {
    const [owner, admin, manager, user1, user2] = await ethers.getSigners();

    const DeFarmSeeds = await ethers.getContractFactory("DeFarmSeeds");
    const deFarmSeeds = await upgrades.deployProxy(
      DeFarmSeeds,
    ) as unknown as DeFarmSeeds;

    return {
      owner, admin, manager, user1, user2,
      deFarmSeeds
    };
  }

  describe("Config", function () {
    it("Init", async function () {
      const { deFarmSeeds, owner } = await loadFixture(deployFixture);

      expect(await deFarmSeeds.owner()).to.equal(owner.address)
      expect(await deFarmSeeds.protocolFeeDestination()).to.equal(owner.address)
    })

    it("Protocol Fee Destination", async function () {
      const { deFarmSeeds, owner, admin } = await loadFixture(deployFixture);

      await deFarmSeeds.connect(owner).setProtocolFeeDestination(admin.address)

      expect(await deFarmSeeds.protocolFeeDestination()).to.equal(admin.address)
    })

    it("Protocol Fee Percent", async function () {
      const { deFarmSeeds, owner } = await loadFixture(deployFixture);

      const protocolFeePercent = await deFarmSeeds.protocolFeePercent()
      const newProtocolFeePercent = protocolFeePercent + BigInt(randomInt(1, 10000))

      await deFarmSeeds.connect(owner).setProtocolFeePercent(newProtocolFeePercent)

      expect(await deFarmSeeds.protocolFeePercent()).to.equal(newProtocolFeePercent)
    })

    it("Subject Fee Percent", async function () {
      const { deFarmSeeds, owner } = await loadFixture(deployFixture);

      const subjectFeePercent = await deFarmSeeds.subjectFeePercent()
      const newSubjectFeePercent = subjectFeePercent + BigInt(randomInt(1, 10000))

      await deFarmSeeds.connect(owner).setSubjectFeePercent(newSubjectFeePercent)

      expect(await deFarmSeeds.subjectFeePercent()).to.equal(newSubjectFeePercent)
    })
  })

  describe("Buy & Sell", function () {
    let deFarmSeeds: DeFarmSeeds
    let owner: HardhatEthersSigner, admin, manager: HardhatEthersSigner, user1: HardhatEthersSigner, user2: HardhatEthersSigner
    let totalSupply = BigInt(0)

    this.beforeAll(async function () {
      ({ deFarmSeeds, owner, manager, user1, user2 } = await loadFixture(deployFixture))
    })

    it("Config fees", async function () {
      const protocolFeePercent = BigInt(randomInt(123, 100000000))
      const subjectFeePercent = BigInt(randomInt(1, 100000000))

      await deFarmSeeds.setProtocolFeePercent(protocolFeePercent)
      await deFarmSeeds.setSubjectFeePercent(subjectFeePercent)

      expect(await deFarmSeeds.protocolFeePercent()).to.equal(protocolFeePercent)
      expect(await deFarmSeeds.subjectFeePercent()).to.equal(subjectFeePercent)
    })

    it("Manager buys the first seed", async function () {
      const price = await deFarmSeeds.getBuyPriceAfterFee(manager.address, 1)
      expect(price).to.equal(0)

      const _tx = await deFarmSeeds.connect(manager).buySeeds(manager.address, 1)
      totalSupply++

      expect(await deFarmSeeds.seedsSupply(manager.address)).to.equal(totalSupply)
      expect(await deFarmSeeds.seedsBalance(manager.address, manager.address)).to.equal(1)
    })

    it("Manager buys N seeds", async function () {
      const balanceBefore = await deFarmSeeds.seedsBalance(manager.address, manager.address)

      const amount = BigInt(randomInt(1, 5))
      const price = await deFarmSeeds.getBuyPriceAfterFee(manager.address, amount)
      expect(price).to.gt(BigInt(0))

      await deFarmSeeds.connect(manager).buySeeds(manager.address, amount, { value: price*amount })
      totalSupply += amount

      expect(await deFarmSeeds.seedsSupply(manager.address)).to.equal(totalSupply)
      expect(await deFarmSeeds.seedsBalance(manager.address, manager.address)).to.equal(balanceBefore + amount)
    })

    it("User1 buys a seed", async function () {
      const price = await deFarmSeeds.getBuyPriceAfterFee(manager.address, 1)

      await deFarmSeeds.connect(user1).buySeeds(manager.address, 1, { value: price })
      totalSupply++

      expect(await deFarmSeeds.seedsSupply(manager.address)).to.equal(totalSupply)
      expect(await deFarmSeeds.seedsBalance(manager.address, user1.address)).to.equal(1)
    })

    it("User2 buys N seeds", async function () {
      const balanceBefore = await deFarmSeeds.seedsBalance(manager.address, user2.address)

      const amount = BigInt(randomInt(1, 5))
      const price = await deFarmSeeds.getBuyPriceAfterFee(manager.address, amount)

      await deFarmSeeds.connect(user2).buySeeds(manager.address, amount, { value: price*amount })
      totalSupply += amount
      const balanceAfter = await deFarmSeeds.seedsBalance(manager.address, user2.address)

      expect(await deFarmSeeds.seedsSupply(manager.address)).to.equal(totalSupply)
      expect(balanceAfter - balanceBefore).to.equal(amount)
    })

    it("User1 sells a seed", async function () {
      const balanceBefore = await deFarmSeeds.seedsBalance(manager.address, user1.address)

      await deFarmSeeds.connect(user1).sellSeeds(manager.address, 1)
      totalSupply--
      const balanceAfter = await deFarmSeeds.seedsBalance(manager.address, user1.address)

      expect(await deFarmSeeds.seedsSupply(manager.address)).to.equal(totalSupply)
      expect(balanceBefore - balanceAfter).to.equal(1)
    })

    it("User2 sells all seeds", async function () {
      const balanceBefore = await deFarmSeeds.seedsBalance(manager.address, user2.address)
      expect(balanceBefore).to.gt(0)

      await deFarmSeeds.connect(user2).sellSeeds(manager.address, balanceBefore)

      totalSupply -= balanceBefore
      const balanceAfter = await deFarmSeeds.seedsBalance(manager.address, user2.address)

      expect(await deFarmSeeds.seedsSupply(manager.address)).to.equal(totalSupply)
      expect(balanceAfter).to.equal(0)
    })

    it("User2 is unable sell more", async function () {
      const balanceBefore = await deFarmSeeds.seedsBalance(manager.address, user2.address)
      expect(balanceBefore).to.eq(0)

      const amount = BigInt(randomInt(1, 100))

      expect(deFarmSeeds.connect(user2).sellSeeds(manager.address, amount)).to.rejected
    })

    it("The manager is unable to sell all the seeds", async function () {
      const balance = await deFarmSeeds.seedsBalance(manager.address, manager.address)
      await expect(deFarmSeeds.connect(manager).sellSeeds(manager.address, balance)).to.be.reverted;
    })

    it("Manager sells a seed", async function () {
      const balanceBefore = await deFarmSeeds.seedsBalance(manager.address, manager.address)
      const _tx = await deFarmSeeds.connect(manager).sellSeeds(manager.address, 1)
      totalSupply--

      expect(await deFarmSeeds.seedsSupply(manager.address)).to.equal(totalSupply)
      expect(await deFarmSeeds.seedsBalance(manager.address, manager.address)).to.equal(balanceBefore - BigInt(1))
    })

    it("Manager sells N seeds", async function () {
      const balanceBefore = await deFarmSeeds.seedsBalance(manager.address, manager.address)

      const amount = balanceBefore - BigInt(1)
      await deFarmSeeds.connect(manager).sellSeeds(manager.address, amount)
      totalSupply -= amount

      const balanceAfter = await deFarmSeeds.seedsBalance(manager.address, manager.address)

      expect(balanceAfter).to.equal(1)
    })

    it("Manager is unable to sell the first seed", async function () {
      const balance = await deFarmSeeds.seedsBalance(manager.address, manager.address)
      expect(balance).to.equal(BigInt(1))
      await expect(deFarmSeeds.connect(manager).sellSeeds(manager.address, 1)).to.be.reverted;
    })
  })
});
