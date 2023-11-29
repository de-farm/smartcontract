import { ethers, upgrades, run, network } from "hardhat";
import { getChainConfig } from "../../config/seasonalFarm.config";

async function main() {
  const seasonalFarmConfig = getChainConfig(network.name);

  const SeasonalFarm = await ethers.getContractFactory("SeasonalFarm");
  const seasonalFarm = await SeasonalFarm.deploy();
  console.log(`Seasonal Farm deployed to ${await seasonalFarm.getAddress()}`);
  if(network.name !== "localhost") {
    await run("verify:verify", {
      address: await seasonalFarm.getAddress(),
    });
  }

  const FarmManagement = await ethers.getContractFactory("FarmManagement");
  const farmManagerment = await FarmManagement.deploy();
  console.log(`Farm Management deployed to ${await farmManagerment.getAddress()}`);
  if(network.name !== "localhost") {
    await run("verify:verify", {
      address: await farmManagerment.getAddress(),
    });
  }

  const AssetHandler = await ethers.getContractFactory("AssetHandler");
  const assetHandler = await upgrades.deployProxy(
    AssetHandler,
    [
      seasonalFarmConfig.whitelistedTokens
    ]
  );
  // await assetHandler.deployed();
  console.log(`AssetHandler deployed to ${await assetHandler.getAddress()}`);

  if(network.name !== "localhost") {
    await run("verify:verify", {
      address: await assetHandler.getAddress(),
    });
  }

  if(network.name === 'arbitrumGoerli') {
    const AssetSimulator = await ethers.getContractFactory("AssetSimulator");
    const assetSimulator = await upgrades.deployProxy(
      AssetSimulator,
      [
        seasonalFarmConfig.whitelistedTokens
      ]
    );
    console.log(`AssetSimulator deployed to ${await assetSimulator.getAddress()}`);

    await run("verify:verify", {
      address: await assetSimulator.getAddress(),
    });
  }

  const VertexHandler = await ethers.getContractFactory("VertexHandler");
  const vertexHandler = await upgrades.deployProxy(
    VertexHandler, [ seasonalFarmConfig.vertexQuerier ]
  );
  console.log(`DexHandler deployed to ${await vertexHandler.getAddress()}`);

  if(network.name !== "localhost") {
    await run("verify:verify", {
      address: await vertexHandler.getAddress(),
    });
  }

  if(network.name === 'arbitrumGoerli') {
    const DexSimulator = await ethers.getContractFactory("DexSimulator");
    const dexSimulator = await upgrades.deployProxy(
      DexSimulator,
      []
    );
    console.log(`DexSimulator deployed to ${await dexSimulator.getAddress()}`);

    await run("verify:verify", {
      address: await dexSimulator.getAddress()
    });
  }

  const whitelistedTokens = seasonalFarmConfig.whitelistedTokens.map((token) => token.asset)
  const FarmFactory = await ethers.getContractFactory("SeasonalFarmFactory");
  const farmFactory = await upgrades.deployProxy(FarmFactory, [
    await assetHandler.getAddress(),
    await vertexHandler.getAddress(),
    whitelistedTokens,
    await seasonalFarm.getAddress(),
    await farmManagerment.getAddress()
  ]);
  console.log(`FarmFactory deployed to ${await farmFactory.getAddress()}`);

  if(network.name !== "localhost") {
    await run("verify:verify", {
      address: await farmFactory.getAddress(),
    });
  }

  if(seasonalFarmConfig.maker) {
    await farmFactory.setMaker(seasonalFarmConfig.maker);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
