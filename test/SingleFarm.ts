import { time } from "@nomicfoundation/hardhat-network-helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { Contract, getBytes, hashMessage, parseEther, parseUnits } from "ethers";
import { getSingleFarmConfig } from "../config/singleFarm.config";
import { SingleFarmFactory, SingleFarm } from "../types";

enum Status {
  NOT_OPENED,
  OPENED,
  CLOSED,
  LIQUIDATED,
  CANCELLED
}

const USDC_DECIMALS = 6
const BTC_DECIMALS = 18
const DEFAULT_MANAGER_FEE = parseUnits('15', 18)
const DEFAULT_PROTOCOL_FEE = parseUnits('5', 18)
const FEE_DENOMINATOR = parseUnits('100', 18)
const DEFAULT_ETH_FEE = parseUnits('1', 16)
const singleTradeConfig = getSingleFarmConfig(network.name);

describe("Single Farm", function () {
  let owner: HardhatEthersSigner
  let admin: HardhatEthersSigner
  let maker: HardhatEthersSigner
  let treasury: HardhatEthersSigner
  let manager: HardhatEthersSigner
  let user: HardhatEthersSigner
  let operator: HardhatEthersSigner

  let usd: any
  let baseToken: any
  let singleFarm: SingleFarm
  let singleFarmFactory: SingleFarmFactory

  before(async function () {
    [owner, admin, maker, treasury, manager, user, operator] = await ethers.getSigners();

    /// MOCK TOKENS
    const MockERC20 = await ethers.getContractFactory("MockERC20")

    usd = await MockERC20.deploy('USDC', 'USDC', USDC_DECIMALS)
    await usd.mint(await manager.getAddress(), parseEther("1000000"));
    await usd.mint(await user.getAddress(), parseEther("1000000"));

    baseToken = await MockERC20.deploy('BTC', 'BTC', BTC_DECIMALS)

    const DeFarmSeeds = await ethers.getContractFactory("DeFarmSeeds");
    const deFarmSeeds = await upgrades.deployProxy(
      DeFarmSeeds, []
    );

    const SingleFarm = await ethers.getContractFactory("SingleFarm");
    const SingleFarmFactory = await ethers.getContractFactory("SingleFarmFactory");

    const singleFarmImplementation = await SingleFarm.deploy();

    singleFarmFactory = await upgrades.deployProxy(
      SingleFarmFactory,
      [
        await singleFarmImplementation.getAddress(), // Template
        singleTradeConfig.capacityPerFarm, // _capacityPerFarm
        singleTradeConfig.minInvestmentAmount, // min
        singleTradeConfig.maxInvestmentAmount, // max
        singleTradeConfig.maxLeverage,
        await usd.getAddress(),
        await deFarmSeeds.getAddress()
      ]
    ) as unknown as SingleFarmFactory;

    await singleFarmFactory.setAdmin(admin.address);
    await singleFarmFactory.setMaker(maker.address);
    await singleFarmFactory.setTreasury(treasury.address);
    // Add the base tokens into the factory
    await singleFarmFactory.addToken(await baseToken.getAddress())
  })

  it("Should set the right configs", async function () {
    expect(await singleFarmFactory.owner()).to.equal(owner.address);
    expect(await singleFarmFactory.admin()).to.equal(admin.address);
    expect(await singleFarmFactory.maker()).to.equal(maker.address);
    expect(await singleFarmFactory.treasury()).to.equal(treasury.address);
    expect(await singleFarmFactory.USDC()).to.equal(await usd.getAddress());

    expect(await singleFarmFactory.capacityPerFarm()).to.equal(singleTradeConfig.capacityPerFarm);
    expect(await singleFarmFactory.minInvestmentAmount()).to.equal(singleTradeConfig.minInvestmentAmount);
    expect(await singleFarmFactory.maxInvestmentAmount()).to.equal(singleTradeConfig.maxInvestmentAmount);
    expect(await singleFarmFactory.minLeverage()).to.equal(1e6);
    expect(await singleFarmFactory.maxLeverage()).to.equal(singleTradeConfig.maxLeverage);
    expect(await singleFarmFactory.maxFundraisingPeriod()).to.equal(7*24*60*60);

    const [numeratorManagerFee, denominatorManagerFee] = await singleFarmFactory.getMaxManagerFee();
    expect(numeratorManagerFee).to.equal(DEFAULT_MANAGER_FEE);
    expect(denominatorManagerFee).to.equal(FEE_DENOMINATOR);

    const [numeratorProtocolFee, denominatorProtocolFee] = await singleFarmFactory.getProtocolFee()
    expect(numeratorProtocolFee).to.equal(DEFAULT_PROTOCOL_FEE);
    expect(denominatorProtocolFee).to.equal(FEE_DENOMINATOR);

    expect(await singleFarmFactory.ethFee()).to.equal(DEFAULT_ETH_FEE);

    const baseTokens = await singleFarmFactory.getTokens()
    expect(baseTokens).to.contains(await baseToken.getAddress())
  });

  describe("Should create a farm", function () {
    // create a vault in before function
    const farmInfo = {
      farmCreatedAt: 0,
      fundraisingPeriod: 24*60*60,
      tradeDirection: true,
      entryPrice: 27,
      targetPrice: 30,
      liquidationPrice: 100,
      leverage: 1e6,
      managerFee: parseUnits("10", 18)
    }

    before(async function () {
      const hash = await singleFarmFactory.getCreateFarmDigest(operator.address, manager.address);
      const message = getBytes(hash)
      const signature = await maker.signMessage(message);

      const ethFee = await singleFarmFactory.ethFee()

      const operatorBalanceBefore = await ethers.provider.getBalance(operator.address)

      // Enable seeds
      const deFarmSeeds = await ethers.getContractAt("DeFarmSeeds", await singleFarmFactory.deFarmSeeds())
      await deFarmSeeds.connect(manager).buySeeds(manager.address, 1)

      const tx = await singleFarmFactory.connect(manager).createFarm(
        {
          baseToken: await baseToken.getAddress(),
          tradeDirection: farmInfo.tradeDirection,
          fundraisingPeriod: farmInfo.fundraisingPeriod,
          entryPrice: farmInfo.entryPrice,
          targetPrice: farmInfo.targetPrice,
          liquidationPrice: farmInfo.liquidationPrice,
          leverage: farmInfo.leverage
        },
        farmInfo.managerFee,
        operator.address,
        signature,
        {value: ethFee}
      );

      expect(tx).to.emit(singleFarmFactory, "FarmCreated").withArgs(
        [
          undefined,
          await baseToken.getAddress(),
          farmInfo.fundraisingPeriod,
          farmInfo.entryPrice,
          farmInfo.targetPrice,
          farmInfo.liquidationPrice,
          farmInfo.leverage,
          farmInfo.tradeDirection,
          manager.address,
          farmInfo.managerFee,
          FEE_DENOMINATOR,
          operator.address
        ]
      )

      const operatorBalanceAfter = await ethers.provider.getBalance(operator.address)
      expect(operatorBalanceAfter).to.equals(operatorBalanceBefore + ethFee)

      const SingleFarm = await ethers.getContractFactory("SingleFarm");
      singleFarm = SingleFarm.attach(await singleFarmFactory.deployedFarms(0)) as unknown as SingleFarm;

      farmInfo.farmCreatedAt = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber()))?.timestamp!
    });

    it("Should has a valid farm", async function () {
      expect(await singleFarmFactory.isFarm(await singleFarm.getAddress())).to.be.true;

      expect(await singleFarm.status()).to.equals(Status.NOT_OPENED);
      expect(await singleFarm.factory()).to.equals(await singleFarmFactory.getAddress());
      expect(await singleFarm.manager()).to.equals(manager.address);

      const [numeratorManagerFee, denominatorManagerFee] = await singleFarm.getManagerFee()
      expect(numeratorManagerFee).to.equals(farmInfo.managerFee);
      expect(denominatorManagerFee).to.equals(FEE_DENOMINATOR);

      expect(await singleFarm.operator()).to.equals(operator.address);
      expect(await singleFarm.endTime()).to.equals(farmInfo.farmCreatedAt + farmInfo.fundraisingPeriod);
      expect(await singleFarm.fundDeadline()).to.equals(72*60*60);
      expect(await singleFarm.USDC()).to.equals(await usd.getAddress());

      const sf = await singleFarm.sf();
      expect(sf.baseToken).to.equals(await baseToken.getAddress());
      expect(sf.tradeDirection).to.equals(farmInfo.tradeDirection);
      expect(sf.fundraisingPeriod).to.equals(farmInfo.fundraisingPeriod);
      expect(sf.entryPrice).to.equals(farmInfo.entryPrice);
      expect(sf.targetPrice).to.equals(farmInfo.targetPrice);
      expect(sf.liquidationPrice).to.equals(farmInfo.liquidationPrice);
      expect(sf.leverage).to.equals(farmInfo.leverage);
    });

    describe("Should deposit to farm", function () {
      it("Should let the manager deposit", async function () {
        const farmBalanaceBefore = await usd.balanceOf(await singleFarm.getAddress())
        const totalRaisedBefore = await singleFarm.totalRaised()
        const actualTotalRaisedBefore = await singleFarm.actualTotalRaised()
        const userAmountBefore = await singleFarm.userAmount(manager.address)

        const depositAmount = singleTradeConfig.minInvestmentAmount
        await usd.connect(manager).approve(await singleFarm.getAddress(), depositAmount)
        const tx = await singleFarm.connect(manager).deposit(depositAmount);

        expect(tx).to.emit(singleFarm, "Deposited").withArgs(
          [
            manager.address,
            depositAmount
          ]
        )

        const farmBalanaceAfter = await usd.balanceOf(await singleFarm.getAddress())
        const totalRaisedAfter = await singleFarm.totalRaised()
        const actualTotalRaisedAfter = await singleFarm.actualTotalRaised()
        const userAmountAfter = await singleFarm.userAmount(manager.address)

        expect(farmBalanaceAfter).to.equals(farmBalanaceBefore + depositAmount);
        expect(totalRaisedAfter).to.equals(totalRaisedBefore + depositAmount);
        expect(actualTotalRaisedAfter).to.equals(actualTotalRaisedBefore + depositAmount);
        expect(userAmountAfter).to.equals(userAmountBefore + depositAmount);
      });

      describe("Should let any users deposit", function () {
        const firstDepositAmount = singleTradeConfig.minInvestmentAmount
        const secondDepositAmount = singleTradeConfig.minInvestmentAmount + BigInt(1);
        it("Should allow any user to deposit", async function () {
          const farmBalanaceBefore = await usd.balanceOf(await singleFarm.getAddress())
          const totalRaisedBefore = await singleFarm.totalRaised()
          const actualTotalRaisedBefore = await singleFarm.actualTotalRaised()
          const userAmountBefore = await singleFarm.userAmount(user.address)

          // Buy seeds
          const deFarmSeeds = await ethers.getContractAt("DeFarmSeeds", await singleFarmFactory.deFarmSeeds())
          const price = await deFarmSeeds.getBuyPriceAfterFee(manager.address, 1)
          await deFarmSeeds.connect(user).buySeeds(manager.address, 1, {value: price})

          await usd.connect(user).approve(await singleFarm.getAddress(), firstDepositAmount)
          const tx = await singleFarm.connect(user).deposit(firstDepositAmount);

          expect(tx).to.emit(singleFarm, "Deposited").withArgs(
            [
              user.address,
              firstDepositAmount
            ]
          )

          const farmBalanaceAfter = await usd.balanceOf(await singleFarm.getAddress())
          const totalRaisedAfter = await singleFarm.totalRaised()
          const actualTotalRaisedAfter = await singleFarm.actualTotalRaised()
          const userAmountAfter = await singleFarm.userAmount(user.address)

          expect(farmBalanaceAfter).to.equals(farmBalanaceBefore + firstDepositAmount);
          expect(totalRaisedAfter).to.equals(totalRaisedBefore + firstDepositAmount);
          expect(actualTotalRaisedAfter).to.equals(actualTotalRaisedBefore + firstDepositAmount);
          expect(userAmountAfter).to.equals(userAmountBefore + firstDepositAmount);

          expect(farmBalanaceAfter).to.equals(farmBalanaceBefore + firstDepositAmount);
        });

        it("Should allow any user to deposit more", async function () {
          const farmBalanaceBefore = await usd.balanceOf(await singleFarm.getAddress())
          const totalRaisedBefore = await singleFarm.totalRaised()
          const actualTotalRaisedBefore = await singleFarm.actualTotalRaised()
          const userAmountBefore = await singleFarm.userAmount(user.address)

          await usd.connect(user).approve(await singleFarm.getAddress(), secondDepositAmount)
          const tx = await singleFarm.connect(user).deposit(secondDepositAmount);

          expect(tx).to.emit(singleFarm, "Deposited").withArgs(
            [
              user.address,
              secondDepositAmount
            ]
          )

          const farmBalanaceAfter = await usd.balanceOf(await singleFarm.getAddress())
          const totalRaisedAfter = await singleFarm.totalRaised()
          const actualTotalRaisedAfter = await singleFarm.actualTotalRaised()
          const userAmountAfter = await singleFarm.userAmount(user.address)

          expect(farmBalanaceAfter).to.equals(farmBalanaceBefore + secondDepositAmount);
          expect(totalRaisedAfter).to.equals(totalRaisedBefore + secondDepositAmount);
          expect(actualTotalRaisedAfter).to.equals(actualTotalRaisedBefore + secondDepositAmount);
          expect(userAmountAfter).to.equals(userAmountBefore + secondDepositAmount);

          expect(farmBalanaceAfter).to.equals(farmBalanaceBefore + secondDepositAmount);
        });
      })

      describe("Should be able to cancel the farms", function () {
        let snapshotId: any
        this.beforeAll(async function () {
          snapshotId = await network.provider.send('evm_snapshot');
        })
        it("Should let the manager cancel farm", async function () {
          const tx = await singleFarm.connect(manager).cancelByManager();
          expect(await singleFarm.status()).to.equals(Status.CANCELLED);
          expect(await singleFarm.endTime()).to.equals(0);

          expect(tx).to.emit(singleFarm, "Cancelled").exist;
        });
        it("Should allow users to claim after the farm was canceled", async function () {
          expect(await singleFarm.status()).to.equals(Status.CANCELLED);

          const userBalanceBefore = await usd.balanceOf(user.address)
          const claimableAmount= await singleFarm.claimableAmount(user.address)

          const tx = await singleFarm.connect(user).claim();

          expect(tx).to.emit(singleFarm, "Deposited").withArgs(
            [
              user.address,
              claimableAmount
            ]
          )

          const userBalanceAfter = await usd.balanceOf(user.address)

          expect(userBalanceAfter).to.equals(userBalanceBefore + claimableAmount)
        });
        this.afterAll(async function () {
          await network.provider.send("evm_revert", [snapshotId]);
        })
      })

      it("Should let the admin cancel farm", async function () {
        let snapshotId = await network.provider.send('evm_snapshot');

        await time.increaseTo((await singleFarm.endTime()) + (await singleFarm.fundDeadline()) + BigInt(1));

        const tx = await singleFarm.connect(admin).cancelByAdmin();
        expect(await singleFarm.status()).to.equals(Status.CANCELLED);

        expect(tx).to.emit(singleFarm, "Cancelled").exist

        await network.provider.send("evm_revert", [snapshotId]);
      });

      describe("Should let the manager close the fundraising and open the position in one transaction", function () {
        let snapshotId: any
        this.beforeAll(async function () {
          snapshotId = await network.provider.send('evm_snapshot');
        })

        it("Should let the manager close the fundraising and open position in one transaction", async function () {
          await time.increase(farmInfo.fundraisingPeriod)

          const operatorBalanceBefore = await usd.balanceOf(operator.address)
          const treasuryBalanceBefore = await usd.balanceOf(treasury.address)
          const totalRaised = await singleFarm.totalRaised()

          const hash = hashMessage("limit")
          const tx = await singleFarm.connect(manager).closeFundraisingAndOpenPosition(hash);

          expect(tx).to.emit(singleFarm, "FundraisingClosedAndPositionOpened").exist

          expect(await singleFarm.status()).to.equals(Status.OPENED);
          expect(await singleFarm.endTime()).to.equals(await time.latest());

          // Protocol Fee
          const [numeratorProtocolFee, denominatorProtocolFee] = await singleFarmFactory.getProtocolFee()
          const expectedProtocolFee = totalRaised*numeratorProtocolFee/denominatorProtocolFee
          const remaining = totalRaised - expectedProtocolFee

          const operatorBalanceAfter = await usd.balanceOf(operator.address)
          const treasuryBalanceAfter = await usd.balanceOf(treasury.address)

          expect(operatorBalanceAfter).to.equals(operatorBalanceBefore + remaining)
          expect(treasuryBalanceAfter).to.equals(treasuryBalanceBefore + expectedProtocolFee)
        });

        describe("Should let the manager liquidate the farm", function () {
          let snapshotId: any
          this.beforeAll(async function () {
            snapshotId = await network.provider.send('evm_snapshot');
          })
          it("Should let the admin liquidate the farm", async function () {
            const tx = await singleFarm.connect(admin).liquidate();

            expect(tx).to.emit(singleFarm, "Liquidated").exist

            expect(await singleFarm.status()).to.equals(Status.LIQUIDATED);
          });

          it("Should be not able to claim when the farm was liquidated", async function () {
            expect(await singleFarm.status()).to.equals(Status.LIQUIDATED);
            let claimableAmount = await singleFarm.claimableAmount(user.address)
            expect(claimableAmount).to.equals(0)
            claimableAmount = await singleFarm.claimableAmount(manager.address)
            expect(claimableAmount).to.equals(0)

            await expect(singleFarm.connect(user).claim())
              .to.be.revertedWithCustomError(singleFarm, 'NotFinalised')
          });

          this.afterAll(async function () {
            await network.provider.send("evm_revert", [snapshotId]);
          })
        })

        describe("Should let the manager close position with loss", function () {
          it("Should let the manager close position", async function () {
            expect(await singleFarm.status()).to.equals(Status.OPENED);

            const loss = (await singleFarm.totalRaised())/BigInt(10)

            const operatorBalanceBefore = await usd.balanceOf(operator.address)
            const remainingBalance = operatorBalanceBefore - loss
            const managerBalanceBefore = await usd.balanceOf(manager.address)
            const treasuryBalanceBefore = await usd.balanceOf(treasury.address)
            const contractBalanceBefore = await usd.balanceOf(await singleFarm.getAddress())

            expect(operatorBalanceBefore).to.greaterThan(0)
            expect(contractBalanceBefore).to.equals(0)

            await usd.connect(operator).approve(await singleFarm.getAddress(), remainingBalance)

            const tx = await singleFarm.connect(manager).closePosition();

            expect(await singleFarm.status()).to.equals(Status.CLOSED);

            expect(tx).to.emit(singleFarm, "PositionClosed").exist

            const operatorBalanceAfter = await usd.balanceOf(operator.address)
            const managerBalanceAfter = await usd.balanceOf(manager.address)
            const treasuryBalanceAfter = await usd.balanceOf(treasury.address)
            const contractBalanceAfter = await usd.balanceOf(await singleFarm.getAddress())

            expect(operatorBalanceAfter).to.equals(loss)
            expect(treasuryBalanceAfter).to.equals(treasuryBalanceBefore)
            expect(managerBalanceAfter).to.equals(managerBalanceBefore)
            expect(contractBalanceAfter).to.equals(contractBalanceBefore + remainingBalance)
          });

          it("Should allow users to claim after the farm was closed", async function () {
            expect(await singleFarm.status()).to.equals(Status.CLOSED);

            const userBalanceBefore = await usd.balanceOf(manager.address)
            const claimableAmount = await singleFarm.claimableAmount(manager.address)
            expect(claimableAmount).to.greaterThan(0)

            const tx = await singleFarm.connect(manager).claim();

            expect(tx).to.emit(singleFarm, "Claimed").withArgs([
              manager.address,
              claimableAmount
            ])

            const userBalanceAfter = await usd.balanceOf(manager.address)

            expect(userBalanceAfter).to.equals(userBalanceBefore + claimableAmount)
          });
        })

        this.afterAll(async function () {
          await network.provider.send("evm_revert", [snapshotId]);
        })
      })

      describe("Should let the manager close the fundraising and open position", function () {
        it("Should let the manager close the fundraising", async function () {
          await time.increase(farmInfo.fundraisingPeriod)

          const tx = await singleFarm.connect(manager).closeFundraising();
          expect(await singleFarm.status()).to.equals(Status.NOT_OPENED);
          expect(await singleFarm.endTime()).to.equals(await time.latest());

          expect(tx).to.emit(singleFarm, "FundraisingClosed").exist
        });

        it("Should let the manager open position", async function () {
          const operatorBalanceBefore = await usd.balanceOf(operator.address)
          const treasuryBalanceBefore = await usd.balanceOf(treasury.address)
          const totalRaised = await singleFarm.totalRaised()

          const hash = hashMessage("limit")
          const tx = await singleFarm.connect(manager).openPosition(hash);

          expect(tx).to.emit(singleFarm, "PositionOpened").exist

          expect(await singleFarm.status()).to.equals(Status.OPENED);

          // Protocol Fee
          const [numeratorProtocolFee, denominatorProtocolFee] = await singleFarmFactory.getProtocolFee()
          const expectedProtocolFee = totalRaised*numeratorProtocolFee/denominatorProtocolFee
          const remaining = totalRaised - expectedProtocolFee

          const operatorBalanceAfter = await usd.balanceOf(operator.address)
          const treasuryBalanceAfter = await usd.balanceOf(treasury.address)

          expect(operatorBalanceAfter).to.equals(operatorBalanceBefore + remaining)
          expect(treasuryBalanceAfter).to.equals(treasuryBalanceBefore + expectedProtocolFee)
        });

        it("Should let the manager close position with profit", async function () {
          const profit = parseUnits("100", USDC_DECIMALS)
          await usd.connect(owner).mint(operator.address, profit)

          const operatorBalanceBefore = await usd.balanceOf(operator.address)
          const managerBalanceBefore = await usd.balanceOf(manager.address)
          // const treasuryBalanceBefore = await usd.balanceOf(treasury.address)
          const contractBalanceBefore = await usd.balanceOf(await singleFarm.getAddress())

          expect(operatorBalanceBefore).to.greaterThan(0)
          expect(contractBalanceBefore).to.equals(0)

          await usd.connect(operator).approve(await singleFarm.getAddress(), operatorBalanceBefore)

          const tx = await singleFarm.connect(manager).closePosition();

          expect(await singleFarm.status()).to.equals(Status.CLOSED);

          expect(tx).to.emit(singleFarm, "PositionClosed").exist

          const [numeratorManagerFee, denominatorManagerFee] = await singleFarm.getManagerFee()
          const expectedManagerFee = profit*numeratorManagerFee/denominatorManagerFee

          /* const [numeratorProtocolFee, denominatorProtocolFee] = await singleFarmFactory.getProtocolFee()
          const expectedProtocolFee = profit.mul(numeratorProtocolFee).div(denominatorProtocolFee) */

          // const expectedContractBalance = operatorBalanceBefore.sub(expectedManagerFee).sub(expectedProtocolFee)
          const expectedContractBalance = operatorBalanceBefore - expectedManagerFee

          const operatorBalanceAfter = await usd.balanceOf(operator.address)
          const managerBalanceAfter = await usd.balanceOf(manager.address)
          // const treasuryBalanceAfter = await usd.balanceOf(treasury.address)
          const contractBalanceAfter = await usd.balanceOf(await singleFarm.getAddress())

          expect(operatorBalanceAfter).to.equals(0)
          // expect(treasuryBalanceAfter).to.equals(treasuryBalanceBefore.add(expectedProtocolFee))
          expect(managerBalanceAfter).to.equals(managerBalanceBefore + expectedManagerFee)
          expect(contractBalanceAfter).to.equals(contractBalanceBefore + expectedContractBalance)
        });

        it("Should allow users to claim after the farm was closed", async function () {
          expect(await singleFarm.status()).to.equals(Status.CLOSED);

          const userBalanceBefore = await usd.balanceOf(manager.address)
          const claimableAmount = await singleFarm.claimableAmount(manager.address)
          expect(claimableAmount).to.greaterThan(0)

          const tx = await singleFarm.connect(manager).claim();

          expect(tx).to.emit(singleFarm, "Claimed").withArgs([
            manager.address,
            claimableAmount
          ])

          const userBalanceAfter = await usd.balanceOf(manager.address)

          expect(userBalanceAfter).to.equals(userBalanceBefore + claimableAmount)
        });
      });
    })
  })
})