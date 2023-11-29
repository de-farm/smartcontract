import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, ContractTransaction, Wallet, getBytes, hashMessage, parseUnits, randomBytes, toBigInt } from "ethers";
import { ChainConfig } from "../config/seasonalFarm.config";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { randomInt } from "crypto";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { DexSimulator, AssetSimulator, FarmManagement, MockERC20, SeasonalFarm, SeasonalFarmFactory } from "../types";
import { IHasFeeInfo } from "../types/contracts/seasonal/SeasonalFarmFactory";
import { seasonal } from "../types/contracts";

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
    const [owner, admin, manager, investor, maker, treasury, operator] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20")

    // USDC
    const usdc = await MockERC20.deploy('USDC', 'USDC', USDC_DECIMALS)

    // BTC
    const btc = await MockERC20.deploy('BTC', 'BTC', BTC_DECIMALS)

    // ETH
    const eth = await MockERC20.deploy('ETH', 'ETH', ETH_DECIMALS)

    // mint assets to user
    await usdc.mint(investor.address, parseUnits('1000', USDC_DECIMALS))
    await btc.mint(investor.address, parseUnits('1000', BTC_DECIMALS))
    await eth.mint(investor.address, parseUnits('1000', ETH_DECIMALS))

    const chainConfig: ChainConfig = {
      whitelistedTokens: [
        {asset: await usdc.getAddress(), aggregator: await usdc.getAddress() },
        {asset: await btc.getAddress(), aggregator: await btc.getAddress() },
        {asset: await eth.getAddress(), aggregator: await eth.getAddress() }
      ]
    }

    // deploy Assset Simulator
    const AssetSimulatorContract = await ethers.getContractFactory("AssetSimulator");
    const assetSimulator = await upgrades.deployProxy(
      AssetSimulatorContract,
      [
        chainConfig.whitelistedTokens
      ]
    ) as unknown as AssetSimulator;

    // deploy Dex Simulator
    const DexSimulator = await ethers.getContractFactory("DexSimulator");
    const dexSimulator = await upgrades.deployProxy(
      DexSimulator, []
    ) as unknown as DexSimulator;

    const SeasonalFarm = await ethers.getContractFactory("SeasonalFarm");
    const seasonalFarm = await SeasonalFarm.deploy();

    const FarmManagement = await ethers.getContractFactory("FarmManagement");
    const farmManagerment = await FarmManagement.deploy();

    const seasonalFarmFactory = await ethers.getContractFactory("SeasonalFarmFactory");
    const farmFactory = (await upgrades.deployProxy(
      seasonalFarmFactory,
      [
        await assetSimulator.getAddress(),
        await dexSimulator.getAddress(),
        chainConfig.whitelistedTokens.map(token => token.asset),
        await seasonalFarm.getAddress(),
        await farmManagerment.getAddress()
      ]
    )) as unknown as SeasonalFarmFactory;

    return {
      owner, admin, manager, investor, maker, treasury, operator,
      usdc, btc, eth,
      usdcAddress: await usdc.getAddress(), btcAddress: await btc.getAddress(), ethAddress: await eth.getAddress(),
      farmFactory, assetHandler: assetSimulator, dexHandler: dexSimulator
    };
  }

  describe("Asset handler test", function () {
    it("Should be able to update the asset prices", async function () {
      const { assetHandler, owner, usdc, eth, btc } = await loadFixture(deployFixture);
      await assetHandler.connect(owner).updatePrice(await usdc.getAddress(), DEFAULT_USDC_PRICE)
      await assetHandler.connect(owner).updatePrice(await eth.getAddress(), DEFAULT_ETH_PRICE)
      await assetHandler.connect(owner).updatePrice(await btc.getAddress(), DEFAULT_BTC_PRICE)

      expect(await assetHandler.getUSDPrice(await usdc.getAddress())).to.equal(DEFAULT_USDC_PRICE)
      expect(await assetHandler.getUSDPrice(await eth.getAddress())).to.equal(DEFAULT_ETH_PRICE)
      expect(await assetHandler.getUSDPrice(await btc.getAddress())).to.equal(DEFAULT_BTC_PRICE)
    })

    it("Should be able to update the dex balance", async function () {
      const { dexHandler, owner, operator } = await loadFixture(deployFixture);
      await dexHandler.connect(owner).setBalance(operator.address, usdcTo18Decimals(ONE_USDC))
      expect(await dexHandler.getBalance(operator.address)).to.equal(ONE_DOLLAR)
    })
  })

  describe("Farm factory test", function () {
    it("Should be able to initialize farm factory", async function () {
      const { farmFactory, owner, admin, maker, treasury } = await loadFixture(deployFixture);
      expect(await farmFactory.owner()).to.equal(owner.address)

      expect(await farmFactory.admin()).to.equal(owner.address)
      await farmFactory.setAdmin(admin.address)
      expect(await farmFactory.admin()).to.equal(admin.address)

      expect(await farmFactory.maker()).to.equal(owner.address)
      await farmFactory.setMaker(maker.address)
      expect(await farmFactory.maker()).to.equal(maker.address)

      expect(await farmFactory.treasury()).to.equal(owner.address)
      await farmFactory.setTreasury(treasury.address)
      expect(await farmFactory.treasury()).to.equal(treasury.address)
    });

    it("Should be able to set protocol fee", async function () {
      const { farmFactory } = await loadFixture(deployFixture);
      const randomProtocolFee = BigInt(Math.floor(Math.random() * 10)*1e18)
      await farmFactory.setProtocolFee(randomProtocolFee)
      const [protocolFeeNumerator, protocolFeeDenominator] = await farmFactory.getProtocolFee();
      expect(protocolFeeNumerator).to.equal(randomProtocolFee)
      expect(protocolFeeDenominator).to.equal(FEE_DENOMINATOR)
    })

    it("Should be able to ETH fee", async function () {
      const { farmFactory } = await loadFixture(deployFixture);
      const newEthFee = parseUnits(randomInt(1000).toString(), 18);
      await farmFactory.setEthFee(newEthFee)
      const ethFee = await farmFactory.ethFee();
      expect(ethFee).to.equal(newEthFee)
    })

    it("Should be able to set asset and dex handler", async function () {
      const { farmFactory, owner } = await loadFixture(deployFixture);

      const randomAssetHandler = Wallet.createRandom();
      await farmFactory.setAssetHandler(randomAssetHandler.address)
      expect(await farmFactory.assetHandler()).to.equal(randomAssetHandler.address)

      const randomDexHandler = Wallet.createRandom();
      await farmFactory.setDexHandler(randomDexHandler.address)
      expect(await farmFactory.dexHandler()).to.equal(randomDexHandler.address)
    })
  });

  describe("Farm functions", function () {
    const farmConfig = {
      isPrivate: false,
      name: Math.random().toString(),
      symbol: Math.random().toString(),
      farmingPeriod: 30*24*60*60,
      minDeposit: parseUnits("10", 18),
      maxDeposit: parseUnits("1000", 18),
      initialLockupPeriod: 12*24*60*60
    }

    const fee: IHasFeeInfo.FeesStruct = {
      management: FEE_DENOMINATOR*BigInt(3)/BigInt(100),
      performance: FEE_DENOMINATOR*BigInt(10)/BigInt(100),
      entrance: FEE_DENOMINATOR*BigInt(1)/BigInt(100),
      exit: FEE_DENOMINATOR*BigInt(1)/BigInt(100),
    }

    /* let farmFactory: SeasonalFarmFactory
    let farm: SeasonalFarm, farmManagerment: FarmManagement
    let assetHandler: AssetSimulator, dexHandler: DexSimulator
    let owner: SignerWithAddress, admin: SignerWithAddress, treasury: SignerWithAddress
    let operator: SignerWithAddress, maker: SignerWithAddress
    let manager: SignerWithAddress, investor: SignerWithAddress */

    // let usdc: MockERC20, btc: MockERC20, eth: MockERC20
    // let usdcAddress: string, btcAddress: string, ethAddress: string

    async function deployFarm() {
      const context = await loadFixture(deployFixture)
      const {
        farmFactory, assetHandler,
        usdc, eth, btc,
        usdcAddress, ethAddress, btcAddress,
        owner, admin, maker, treasury, operator, manager
      } = context

      await farmFactory.connect(owner).setAdmin(admin.address)
      await farmFactory.connect(owner).setMaker(maker.address)
      await farmFactory.connect(owner).setTreasury(treasury.address)

      await assetHandler.connect(owner).updatePrice(usdcAddress, DEFAULT_USDC_PRICE)
      await assetHandler.connect(owner).updatePrice(ethAddress, DEFAULT_ETH_PRICE)
      await assetHandler.connect(owner).updatePrice(btcAddress, DEFAULT_BTC_PRICE)

      const hash = await farmFactory.getCreateFarmDigest(operator.address, manager.address);
      const message = getBytes(hash)
      const signature = await maker.signMessage(message);

      const tx = await farmFactory.connect(manager).createFarm(
        manager.address,
        farmConfig,
        [
          { asset: await usdc.getAddress(), isDeposit: true },
          { asset: await btc.getAddress(), isDeposit: true },
          { asset: await eth.getAddress(), isDeposit: false },
        ],
        fee,
        operator.address,
        signature
      )

      const block = await ethers.provider.getBlock(tx.blockNumber!);
      const startTime = block!.timestamp;

      const farmAddress = await farmFactory.deployedFarms(0);

      const SeasonalFarm = await ethers.getContractFactory("SeasonalFarm");
      const farm = SeasonalFarm.attach(farmAddress) as unknown as SeasonalFarm;

      const FarmManagement = await ethers.getContractFactory("FarmManagement");
      const farmManagement = FarmManagement.attach(await farm.farmManagement()) as unknown as FarmManagement;

      return { farm, farmManagement, startTime, ...context }
    }

    it("Should be able to create a farm", async function () {
      await ethers.provider.getBlockNumber()

      const {
        farmFactory, farm, farmManagement,
        usdcAddress, ethAddress, btcAddress,
        operator, manager,
        startTime
      }  = await loadFixture(deployFarm);

      expect(await farm.isPrivate()).to.equal(farmConfig.isPrivate)
      expect(await farm.name()).to.equal(farmConfig.name)
      expect(await farm.symbol()).to.equal(farmConfig.symbol)
      expect(await farm.minDeposit()).to.equal(farmConfig.minDeposit)
      expect(await farm.maxDeposit()).to.equal(farmConfig.maxDeposit)
      expect(await farm.initialLockupPeriod()).to.equal(farmConfig.initialLockupPeriod)

      expect([...await farmManagement.getManagementFee()]).to.have.members([fee.management, FEE_DENOMINATOR])
      expect([...await farmManagement.getPerformanceFee()]).to.have.members([fee.performance, FEE_DENOMINATOR])
      expect([...await farmManagement.getEntranceFee()]).to.have.members([fee.entrance, FEE_DENOMINATOR])
      expect([...await farmManagement.getExitFee()]).to.have.members([fee.exit, FEE_DENOMINATOR])

      expect(await farm.factory()).to.equal(await farmFactory.getAddress())
      expect(await farm.operator()).to.equal(operator.address)

      expect(await farmManagement.manager()).to.equal(manager.address)

      expect(await farmManagement.isSupportedAsset(usdcAddress)).to.equal(true)
      expect(await farmManagement.isSupportedAsset(btcAddress)).to.equal(true)
      expect(await farmManagement.isSupportedAsset(ethAddress)).to.equal(true)

      expect(await farmManagement.isDepositAsset(usdcAddress)).to.equal(true)

      // initialize values
      expect(await farm.startTime()).to.equal(startTime)
      expect(await farm.endTime()).to.equal(startTime + farmConfig.farmingPeriod)
      expect(await farm.tokenPriceAtLastPerformanceFeeMint()).to.equal(ONE_DOLLAR)
      expect(await farm.latestManagementFeeMintAt()).to.equal(startTime)
    })

    describe("Should be able to deposit and withdraw", function () {
      let farmFactory: SeasonalFarmFactory, farm: SeasonalFarm, farmManagement: FarmManagement
      let assetHandler: AssetSimulator, dexHandler: DexSimulator
      let usdc: MockERC20, btc: MockERC20, eth: MockERC20
      let usdcAddress: string, btcAddress: string, ethAddress: string
      let owner: SignerWithAddress, admin: SignerWithAddress, maker: SignerWithAddress, treasury: SignerWithAddress
      let operator: SignerWithAddress, manager: SignerWithAddress, investor: SignerWithAddress

      before(async () => {
        ({
          farmFactory, farm, farmManagement,
          assetHandler, dexHandler,
          usdc, eth, btc,
          usdcAddress, ethAddress, btcAddress,
          owner, admin, maker, treasury, operator, manager, investor
        } = await loadFixture(deployFarm));
      })

      const usdcDepositAmount = parseUnits("100", USDC_DECIMALS)
      // $100
      const btcDepositAmount = parseUnits("10", BTC_DECIMALS)
      const investAmount = usdcDepositAmount/BigInt(2)

      it("Should be able to deposit at the first", async function () {
        const investorSharesBefore = await farm.balanceOf(investor.address)
        const managerSharesBefore = await farm.balanceOf(manager.address)
        const treasurySharesBefore = await farm.balanceOf(farmFactory.treasury())
        const totalSupplyBefore = await farm.totalSupply()
        const totalFundValueBefore = await farmManagement.totalFundValue()

        const sharePriceBefore =  await farm.getSharePrice();

        // Calculate the amount of shares that will be received
        const assetPrice = await assetHandler.getUSDPrice(usdcAddress)
        const assetValueInDollar = await farmFactory.assetValue(usdcAddress, usdcDepositAmount)
        const expectedShares = await farm.assetValueToShares(assetValueInDollar, sharePriceBefore)
        const [entranceFeeNumerator, entranceFeeDenominator] = await farmManagement.getEntranceFee()
        const entranceFee = expectedShares*entranceFeeNumerator/entranceFeeDenominator
        const receivedShares = expectedShares - entranceFee

        await usdc.connect(investor).approve(await farm.getAddress(), usdcDepositAmount)
        await farm.connect(investor).deposit(
          usdcAddress,
          usdcDepositAmount,
          receivedShares,
        )

        const investorSharesAfter = await farm.balanceOf(investor.address)
        const managerSharesAfter = await farm.balanceOf(manager.address)
        const treasurySharesAfter = await farm.balanceOf(treasury.address)

        expect(investorSharesAfter - investorSharesBefore).to.equal(receivedShares)

        const [protocolFeeNumerator, protocolFeeDenominator] = await farmFactory.getProtocolFee();
        const protocolFee = entranceFee*protocolFeeNumerator/protocolFeeDenominator
        expect(treasurySharesAfter - treasurySharesBefore).to.equal(protocolFee)
        expect(managerSharesAfter - managerSharesBefore).to.equal(entranceFee - protocolFee)

        const totalFundValueAfter = await farmManagement.totalFundValue()
        expect(totalFundValueAfter).to.equal(totalFundValueBefore + assetValueInDollar)

        const totalSupplyAfter = await farm.totalSupply()
        expect(totalSupplyAfter).to.equal(totalSupplyBefore + expectedShares)

        const sharePriceAfter =  await farm.getSharePrice();

        expect(sharePriceAfter).to.equal(sharePriceBefore)
      })

      it("Should be able to deposit at the second", async function () {
        const before = await farm.balanceOf(investor.address)
        const sharePriceBefore =  await farm.getSharePrice();

        await usdc.connect(investor).approve(await farm.getAddress(), usdcDepositAmount)

        const assetValueInDollar = await farmFactory.assetValue(usdcAddress, usdcDepositAmount)
        const expectedShares = await farm.assetValueToShares(assetValueInDollar, sharePriceBefore)
        const [entranceFeeNumerator, entranceFeeDenominator] = await farmManagement.getEntranceFee()
        const entranceFee = expectedShares*entranceFeeNumerator/entranceFeeDenominator
        const receivedShares = expectedShares - entranceFee

        await farm.connect(investor).deposit(
          usdcAddress,
          usdcDepositAmount,
          receivedShares
        )

        const after = await farm.balanceOf(investor.address)

        const totalFundValue = await farmManagement.totalFundValue()

        const totalSupply = await farm.totalSupply()

        const sharePriceAfter =  await farm.getSharePrice();
        expect(sharePriceAfter).to.equal(sharePriceBefore)
      })

      it("Should allow deposit of different assets", async function () {
        const assetValue = await farmFactory.assetValue(btc, btcDepositAmount)

        await btc.connect(investor).approve(await farm.getAddress(), btcDepositAmount)
        await farm.connect(investor).deposit(
          btcAddress,
          btcDepositAmount,
          0
        )

        const after = await farm.balanceOf(investor.address)

        const sharePriceAfter =  await farm.getSharePrice();
      })

      it("Should be able to invest", async function () {
        const operatorEthBalanceBefore = await ethers.provider.getBalance(operator.address)
        const operatorUsdcBalanceBefore = await usdc.balanceOf(operator.address)
        const totalFundValueBefore = await farmManagement.totalFundValue()
        const balanceOnDexBefore = await farmManagement.totalBalanceOnDex()

        const ethFee = await farmFactory.ethFee()

        time.increase(3*24*60*60)
        const info = hashMessage("limit")
        const tx = await farm.connect(manager).invest(usdcAddress, investAmount, info, { value: ethFee})

        const operatorEthBalanceAfter = await ethers.provider.getBalance(operator.address)
        const operatorUsdcBalanceAfter = await usdc.balanceOf(operator.address)

        expect(operatorEthBalanceAfter - operatorEthBalanceBefore).to.equal(ethFee)
        expect(operatorUsdcBalanceAfter - operatorUsdcBalanceBefore).to.equal(investAmount)

        // Simulate the exchange, convert the decimal number to 18
        await usdc.connect(operator).burn(operator.address, investAmount)
        await dexHandler.setBalance(operator.address, usdcTo18Decimals(investAmount))

        const totalFundValueAfter = await farmManagement.totalFundValue()

        const balanceOnDexAfter = await farmManagement.totalBalanceOnDex()
        expect(balanceOnDexAfter - balanceOnDexBefore).to.equal(usdcTo18Decimals(investAmount))

        expect(totalFundValueAfter).to.equal(totalFundValueBefore)

        // Orders
        expect(tx).to.emit(farm, "Invested").withArgs(
          [
            await farm.getAddress(),
            manager.address,
            usdcAddress,
            usdcDepositAmount,
            info
          ]
        )
      })

      it("Should be able to devest", async function () {
        const farmUsdcBalanceBefore = await usdc.balanceOf(await farm.getAddress())

        time.increase(3*24*60*60)
        const info = hashMessage("limit")
        const devestAmount = parseUnits("1", USDC_DECIMALS)

        // Simulate the exchange, convert the decimal number to 18
        await dexHandler.setBalance(operator.address, 0)
        await usdc.mint(operator.address, devestAmount)
        await usdc.connect(operator).approve(await farm.getAddress(), devestAmount)

        const operatorUsdcBalanceBefore = await usdc.balanceOf(operator.address)

        const digest = await farmFactory.getDivestDigest(await farm.getAddress(), usdcAddress, info)
        const message = getBytes(digest)
        const signature = await operator.signMessage(message)
        const tx = await farm.connect(manager).divest(usdcAddress, info, signature)

        const operatorUsdcBalanceAfter = await usdc.balanceOf(operator.address)
        const farmUsdcBalanceAfter = await usdc.balanceOf(await farm.getAddress())

        expect(operatorUsdcBalanceBefore - operatorUsdcBalanceAfter).to.equal(devestAmount)
        expect(farmUsdcBalanceAfter - farmUsdcBalanceBefore).to.equal(devestAmount)

        // Orders
        expect(tx).to.emit(farm, "Divested").withArgs(
          [
            await farm.getAddress(),
            manager.address,
            usdcAddress,
            devestAmount,
            info
          ]
        )
      })

      it("Should be able to withdraw", async function () {
        const totalSupply = await farm.totalSupply()
        const investorSharedTokenBefore = await farm.balanceOf(investor.address)
        console.log('investorSharedTokenBefore', investorSharedTokenBefore/ONE_SHARE)

        const investorWithdrawalAmount = investorSharedTokenBefore/BigInt(10)

        const [exitFeeNumerator, exitFeeDenominator] = await farmManagement.getExitFee();
        const exitFee = investorWithdrawalAmount*exitFeeNumerator/exitFeeDenominator;

        // Penalty fee
        const duration = BigInt(await time.latest()) - await farm.startTime();
        const initialLockupPeriod = await farm.initialLockupPeriod()
        let penaltyFee = ZERO
        if(duration > 0 && duration < initialLockupPeriod) {
          let penaltyFeeNumerator: bigint = ZERO;
          let penaltyFeeDenomirator: bigint = ZERO;
          if(duration < initialLockupPeriod/BigInt(3)) {
              [penaltyFeeNumerator, penaltyFeeDenomirator] = await farmFactory.getPenaltyFee(0)
          }
          else if(duration < initialLockupPeriod*BigInt(2)/BigInt(3)) {
            [penaltyFeeNumerator, penaltyFeeDenomirator] = await farmFactory.getPenaltyFee(1);
          }
          else if(duration < initialLockupPeriod) {
            [penaltyFeeNumerator, penaltyFeeDenomirator] = await farmFactory.getPenaltyFee(2);
          }

          if(penaltyFeeNumerator > ZERO) {
              penaltyFee = exitFee*penaltyFeeNumerator/penaltyFeeDenomirator;
          }
        }

        // const remainingWithdrawalAmount = investorWithdrawalAmount - exitFee
        const portion = investorWithdrawalAmount*BigInt(10**18)/(totalSupply + exitFee + penaltyFee)
        const farmTotalFundValue = await farmManagement.totalFundValue();
        const valueInDollar = portion*farmTotalFundValue/BigInt(10**18);
        const expectedUsdcAmount = await farmFactory.convertValueToAsset(usdcAddress, valueInDollar)

        const farmUsdcBalanceBefore = await usdc.balanceOf(await farm.getAddress())

        console.log('portion', portion)
        console.log('investorWithdrawalAmount', investorWithdrawalAmount)
        console.log('totalSupply', totalSupply)

        const investorUsdcBalanceBefore = await usdc.balanceOf(investor.address)

        await farm.connect(investor).approve(await farm.getAddress(), investorWithdrawalAmount)
        const tx = await farm.connect(investor).withdraw(usdcAddress, investorWithdrawalAmount, expectedUsdcAmount)

        expect(tx).to.emit(farm, "Withdrawal").withArgs(
          [
            await farm.getAddress(),
            investor.address,
            usdcAddress,
            investorWithdrawalAmount,
            portion,
            expectedUsdcAmount,
          ]
        )

        const investorSharedTokenAfter = await farm.balanceOf(investor.address)
        expect(investorSharedTokenAfter).to.equal(investorSharedTokenBefore - investorWithdrawalAmount)

        const investorUsdcBalanceAfter = await usdc.balanceOf(investor.address)
        expect(investorUsdcBalanceAfter).to.equal(investorUsdcBalanceBefore + expectedUsdcAmount)
      })
    })
  });
});
