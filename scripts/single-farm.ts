import { ethers, upgrades, run, network } from "hardhat";
import { getSingleFarmConfig } from "../config/singleFarm.config";

async function main() {
  const singleFarmConfig = getSingleFarmConfig(network.name);

  console.log('SingleFarm config: ', singleFarmConfig);

  const SingleFarm = await ethers.getContractFactory("SingleFarm");
  const singleFarm = await SingleFarm.deploy()
  if(network.name !== "localhost") {
    console.log(
      `SingleFarm deployed to ${await singleFarm.getAddress()}`
    );
    // sleep for 60 seconds to avoid the error: 'contract does not exist'
    console.log("Sleeping for 60 seconds...");
    await new Promise((resolve) => setTimeout(resolve, 60000));
    await run("verify:verify", {
      address: await singleFarm.getAddress(),
    });
  }

  const singleFarmFactory = await ethers.getContractFactory("SingleFarmFactory");
  const factory = await upgrades.deployProxy(
    singleFarmFactory, [
      singleFarmConfig.thrusterRouter,
      await singleFarm.getAddress(),
      singleFarmConfig.capacityPerFarm,
      singleFarmConfig.minInvestmentAmount,
      singleFarmConfig.maxInvestmentAmount,
      singleFarmConfig.maxLeverage,
      singleFarmConfig.usdToken,
      singleFarmConfig.deFarmSeeds
    ]
  )

  console.log(
    `SingleFarmFactory deployed to ${await factory.getAddress()}`
  );

  console.log("Sleeping for 30 seconds...");
  await new Promise((resolve) => setTimeout(resolve, 30000));

  if(singleFarmConfig.admin) {
    await factory.setAdmin(singleFarmConfig.admin);
  }

  if(singleFarmConfig.baseTokens.length > 0)
    await factory.addTokens(singleFarmConfig.baseTokens)

  if(network.name !== "localhost") {
    // sleep for 60 seconds to avoid the error: 'contract does not exist'
    console.log("Sleeping for 60 seconds...");
    await new Promise((resolve) => setTimeout(resolve, 60000));
    await run("verify:verify", {
      address: await factory.getAddress(),
    });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
