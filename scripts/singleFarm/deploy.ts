import { ethers, upgrades, run, network } from "hardhat";
import { getSingleFarmConfig } from "../../config/singleFarm.config";

async function main() {
  const singleFarmConfig = getSingleFarmConfig(network.name);

  console.log('SingleFarm config: ', singleFarmConfig);

  const SingleFarm = await ethers.getContractFactory("SingleFarm");
  const singleFarm = await SingleFarm.deploy()
  if(network.name !== "localhost") {
    await run("verify:verify", {
      address: await singleFarm.getAddress(),
    });
  }

  const singleFarmFactory = await ethers.getContractFactory("SingleFarmFactory");
  const factory = await upgrades.deployProxy(
    singleFarmFactory, [
      singleFarmConfig.dexHandler,
      await singleFarm.getAddress(),
      singleFarmConfig.capacityPerFarm,
      singleFarmConfig.minInvestmentAmount,
      singleFarmConfig.maxInvestmentAmount,
      singleFarmConfig.maxLeverage,
      singleFarmConfig.usdToken,
    ]
  )

  console.log(
    `SingleFarmFactory deployed to ${await factory.getAddress()}`
  );

  if(network.name !== "localhost") {
    await run("verify:verify", {
      address: await factory.getAddress(),
    });
  }

  if(singleFarmConfig.admin) {
    await factory.setAdmin(singleFarmConfig.admin);
  }

  if(singleFarmConfig.baseTokens.length > 0)
    await factory.addTokens(singleFarmConfig.baseTokens)
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
