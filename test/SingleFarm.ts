import { time } from "@nomicfoundation/hardhat-network-helpers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { Contract, ContractTransactionReceipt, getBytes, hashMessage, parseEther, parseUnits } from "ethers";
import { getSingleFarmConfig } from "../config/singleFarm.config";
import { SingleFarmFactory, SingleFarm, DexSimulator, IDeFarmSeedsActions } from "../types";

enum Status {
  NOT_OPENED,
  OPENED,
  CLOSED,
  LIQUIDATED,
  CANCELLED
}

const deFarmSeedsAddress = '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0'
const USDC_DECIMALS = 6
const BTC_DECIMALS = 18
const ETH_DECIMALS = 18
const DEFAULT_MANAGER_FEE = parseUnits('70', 18)
const DEFAULT_PROTOCOL_FEE = parseUnits('1', 18)
const FEE_DENOMINATOR = parseUnits('100', 18)
const DEFAULT_ETH_FEE = parseUnits('1', 15)
const singleTradeConfig = getSingleFarmConfig(network.name);

describe("Single Farm", function () {
  let owner: HardhatEthersSigner
  let admin: HardhatEthersSigner
  let maker: HardhatEthersSigner
  let treasury: HardhatEthersSigner
  let manager: HardhatEthersSigner
  let user: HardhatEthersSigner
  let operator: HardhatEthersSigner
  let anyAddress: HardhatEthersSigner

  let usd: any
  let btcToken: any
  let ethToken: any
  let singleFarm: SingleFarm
  let singleFarmFactory: SingleFarmFactory
  let dexSimulator: DexSimulator

  before(async function () {
    [owner, admin, maker, treasury, manager, user, operator, anyAddress] = await ethers.getSigners();

    /// MOCK TOKENS
    const MockERC20 = await ethers.getContractFactory("MockERC20")

    usd = await MockERC20.deploy('USDC', 'USDC', USDC_DECIMALS)
    await usd.mint(await manager.getAddress(), parseEther("1000000"));
    await usd.mint(await user.getAddress(), parseEther("1000000"));

    btcToken = await MockERC20.deploy('BTC', 'BTC', BTC_DECIMALS)
    ethToken = await MockERC20.deploy('ETH', 'ETH', ETH_DECIMALS)

    // deploy Dex Simulator
    const DexSimulator = await ethers.getContractFactory("DexSimulator");
    dexSimulator = await upgrades.deployProxy(
      DexSimulator, []
    ) as unknown as DexSimulator;
    await dexSimulator.setPaymentFee(
      await usd.getAddress(),
      parseUnits('1', USDC_DECIMALS)
    )

    const SingleFarm = await ethers.getContractFactory("SingleFarm");
    const SingleFarmFactory = await ethers.getContractFactory("SingleFarmFactory");

    const singleFarmImplementation = await SingleFarm.deploy();

    singleFarmFactory = await upgrades.deployProxy(
      SingleFarmFactory,
      [
        await dexSimulator.getAddress(),
        await singleFarmImplementation.getAddress(), // Template
        singleTradeConfig.capacityPerFarm, // _capacityPerFarm
        singleTradeConfig.minInvestmentAmount, // min
        singleTradeConfig.maxInvestmentAmount, // max
        singleTradeConfig.maxLeverage,
        await usd.getAddress(),
        deFarmSeedsAddress
      ]
    ) as unknown as SingleFarmFactory;

    await singleFarmFactory.setAdmin(admin.address);
    await singleFarmFactory.setTreasury(treasury.address);
    // Add the base tokens into the factory
    await singleFarmFactory.addTokens(
      [
        await btcToken.getAddress(),
        await ethToken.getAddress()
      ]
    )

    await singleFarmFactory.addOperator(operator)
  })

  it("Should set the right configs", async function () {
    expect(await singleFarmFactory.owner()).to.equal(owner.address);
    expect(await singleFarmFactory.admin()).to.equal(admin.address);
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
    expect(baseTokens).to.contains(await btcToken.getAddress())
    expect(baseTokens).to.contains(await ethToken.getAddress())

    expect(await singleFarmFactory.dexHandler()).to.equal(await dexSimulator.getAddress())
    expect(await singleFarmFactory.deFarmSeeds()).to.equal(deFarmSeedsAddress)
  });

  it("Update operators", async function () {
    expect(await singleFarmFactory.getOperators()).to.not.contains(anyAddress.address)

    await singleFarmFactory.addOperator(anyAddress.address)
    expect(await singleFarmFactory.getOperators()).to.contains(anyAddress.address)

    await singleFarmFactory.removeOperator(anyAddress.address)
    expect(await singleFarmFactory.getOperators()).to.not.contains(anyAddress.address)
  })

  it("Update tokens", async function () {
    await singleFarmFactory.removeTokens([await btcToken.getAddress()])
    expect(await singleFarmFactory.getTokens()).to.not.contains(await btcToken.getAddress())

    await singleFarmFactory.addTokens([await btcToken.getAddress()])
    expect(await singleFarmFactory.getTokens()).to.contains(await btcToken.getAddress())
  })

  it("Update dex handler", async function () {
    const currentDexHandler = await singleFarmFactory.dexHandler()

    await singleFarmFactory.setDexHandler(anyAddress.address)
    expect(await singleFarmFactory.dexHandler()).to.equal(anyAddress.address)

    await singleFarmFactory.setDexHandler(currentDexHandler)
    expect(await singleFarmFactory.dexHandler()).to.equal(currentDexHandler)
  })

  it("Admin: set SingleFarm Implementation", async function () {
    const current = await singleFarmFactory.singleFarmImplementation()

    await singleFarmFactory.connect(admin).setSfImplementation(anyAddress.address)
    expect(await singleFarmFactory.singleFarmImplementation()).to.equal(anyAddress.address)

    await singleFarmFactory.connect(admin).setSfImplementation(current)
    expect(await singleFarmFactory.singleFarmImplementation()).to.equal(current)
  })

  it("Owner: set DeFarmSeeds", async function () {
    const current = await singleFarmFactory.deFarmSeeds()

    await singleFarmFactory.connect(owner).setDeFarmSeeds(anyAddress.address)
    expect(await singleFarmFactory.deFarmSeeds()).to.equal(anyAddress.address)

    await singleFarmFactory.connect(owner).setDeFarmSeeds(current)
    expect(await singleFarmFactory.deFarmSeeds()).to.equal(current)
  })

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
      managerFee: parseUnits("10", 18),
      isPrivate: true
    }

    before(async function () {
      const hash = await singleFarmFactory.getCreateFarmDigest(operator.address, manager.address);
      const message = getBytes(hash)
      const signature = await maker.signMessage(message);

      const ethFee = await singleFarmFactory.ethFee()

      // Enable seeds
      const deFarmSeeds = await ethers.getContractAt("IDeFarmSeedsActions", deFarmSeedsAddress) as unknown as IDeFarmSeedsActions
      const balanceOfDeFarmSeeds = await deFarmSeeds.balanceOf(manager.address, manager.address)
      if(balanceOfDeFarmSeeds === 0n) {
        await deFarmSeeds.connect(manager).buySeeds(manager.address, 1, 36000)
      }

      const tx = await singleFarmFactory.connect(manager).createFarm(
        {
          baseToken: await btcToken.getAddress(),
          tradeDirection: farmInfo.tradeDirection,
          fundraisingPeriod: farmInfo.fundraisingPeriod,
          entryPrice: farmInfo.entryPrice,
          targetPrice: farmInfo.targetPrice,
          liquidationPrice: farmInfo.liquidationPrice,
          leverage: farmInfo.leverage
        },
        farmInfo.managerFee,
        farmInfo.isPrivate,
        {value: ethFee}
      );

      expect(tx).to.emit(singleFarmFactory, "FarmCreated").withArgs(
        [
          undefined,
          await btcToken.getAddress(),
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

      const SingleFarm = await ethers.getContractFactory("SingleFarm");

      const receipt: ContractTransactionReceipt | null = await tx.wait();
      const events = await singleFarmFactory.queryFilter(singleFarmFactory.filters.FarmCreated(), receipt?.blockHash, receipt?.blockNumber)
      const farmAddress = events[0].args.farm
      // console.log(farmEventArgs)
      // singleFarm = SingleFarm.attach(await singleFarmFactory.deployedFarms(0)) as unknown as SingleFarm;
      singleFarm = SingleFarm.attach(farmAddress) as unknown as SingleFarm;

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
      expect(await singleFarm.isPrivate()).to.equals(farmInfo.isPrivate);

      const sf = await singleFarm.sf();
      expect(sf.baseToken).to.equals(await btcToken.getAddress());
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
          const deFarmSeeds = await ethers.getContractAt("IDeFarmSeedsActions", deFarmSeedsAddress) as unknown as SingleFarm
          const price = await deFarmSeeds.getBuyPriceAfterFee(manager.address, 1)
          await deFarmSeeds.connect(user).buySeeds(manager.address, 1, 36000, { value: price})

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

        it("Should let the manager close the fundraising", async function () {
          await time.increase(farmInfo.fundraisingPeriod)

          const tx = await singleFarm.connect(manager).closeFundraising();

          expect(tx).to.emit(singleFarm, "FundraisingClosed").exist

          expect(await singleFarm.status()).to.equals(Status.NOT_OPENED);
          expect(await singleFarm.endTime()).to.equals(await time.latest());

        });

        /* describe("Should let the admin liquidate the farm", function () {
          let snapshotId: any
          this.beforeAll(async function () {
            snapshotId = await network.provider.send('evm_snapshot');
          })
          it("Should let the admin liquidate the farm", async function () {
            await dexSimulator.setBalance(await singleFarm.getAddress(), 0)
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
        */
/*
        describe("Should let the manager close position with loss", function () {
          it("Should let the manager close position", async function () {
            expect(await singleFarm.status()).to.equals(Status.OPENED);

            const loss = (await singleFarm.totalRaised())/BigInt(10)

            const dexBalanceBefore = await dexSimulator.balances(await singleFarm.getAddress())
            const remainingBalance = dexBalanceBefore - loss
            const managerBalanceBefore = await usd.balanceOf(manager.address)
            const treasuryBalanceBefore = await usd.balanceOf(treasury.address)
            const contractBalanceBefore = await usd.balanceOf(await singleFarm.getAddress())

            expect(dexBalanceBefore).to.greaterThan(0)
            expect(contractBalanceBefore).to.equals(0)

            await usd.connect(operator).approve(await singleFarm.getAddress(), remainingBalance)

            const tx = await singleFarm.connect(manager).closePosition(remainingBalance);

            expect(await singleFarm.status()).to.equals(Status.CLOSED);

            expect(tx).to.emit(singleFarm, "PositionClosed").exist

            const dexBalanceAfter = await dexSimulator.balances(await singleFarm.getAddress())
            const managerBalanceAfter = await usd.balanceOf(manager.address)
            const treasuryBalanceAfter = await usd.balanceOf(treasury.address)
            const contractBalanceAfter = await usd.balanceOf(await singleFarm.getAddress())

            expect(dexBalanceAfter).to.equals(loss)
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
          }); */
        })

        /* this.afterAll(async function () {
          await network.provider.send("evm_revert", [snapshotId]);
        }) */
      })
/*
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
          // const tx = await singleFarm.connect(manager).openPosition(hash);
          const tx = await singleFarm.connect(manager).openPosition(hash);

          expect(tx).to.emit(singleFarm, "PositionOpened").exist

          expect(await singleFarm.status()).to.equals(Status.OPENED);

          // Protocol Fee
          const [numeratorProtocolFee, denominatorProtocolFee] = await singleFarmFactory.getProtocolFee()
          const expectedProtocolFee = totalRaised*numeratorProtocolFee/denominatorProtocolFee
          const remaining = totalRaised - expectedProtocolFee

          const operatorBalanceAfter = await usd.balanceOf(operator.address)
          const dexBalanceAfter = await dexSimulator.balances(await singleFarm.getAddress())
          const treasuryBalanceAfter = await usd.balanceOf(treasury.address)

          expect(operatorBalanceAfter + dexBalanceAfter).to.equals(operatorBalanceBefore + remaining)
          expect(treasuryBalanceAfter).to.equals(treasuryBalanceBefore + expectedProtocolFee)
        });

        it("Should let the manager close position with profit", async function () {
          const dexBalanceBefore = await dexSimulator.balances(await singleFarm.getAddress())
          expect(dexBalanceBefore).to.greaterThan(0)

          const profit = parseUnits("100", USDC_DECIMALS)
          await usd.connect(owner).mint(await dexSimulator.getAddress(), profit)
          await dexSimulator.setBalance(await singleFarm.getAddress(), dexBalanceBefore + profit)

          const managerBalanceBefore = await usd.balanceOf(manager.address)
          // const treasuryBalanceBefore = await usd.balanceOf(treasury.address)
          const contractBalanceBefore = await usd.balanceOf(await singleFarm.getAddress())

          expect(contractBalanceBefore).to.equals(0)

          await usd.connect(operator).approve(await singleFarm.getAddress(), dexBalanceBefore)

          const tx = await singleFarm.connect(manager).closePosition(dexBalanceBefore + profit);

          expect(await singleFarm.status()).to.equals(Status.CLOSED);

          expect(tx).to.emit(singleFarm, "PositionClosed").exist

          const [numeratorManagerFee, denominatorManagerFee] = await singleFarm.getManagerFee()
          const expectedManagerFee = profit*numeratorManagerFee/denominatorManagerFee

          // const expectedContractBalance = operatorBalanceBefore.sub(expectedManagerFee).sub(expectedProtocolFee)
          const expectedContractBalance = dexBalanceBefore + profit - expectedManagerFee

          const dexBalanceAfter = await dexSimulator.balances(await singleFarm.getAddress())
          const managerBalanceAfter = await usd.balanceOf(manager.address)
          // const treasuryBalanceAfter = await usd.balanceOf(treasury.address)
          const contractBalanceAfter = await usd.balanceOf(await singleFarm.getAddress())

          expect(dexBalanceAfter).to.equals(0)
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
    }) */
  })
})