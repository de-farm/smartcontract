import { ethers, upgrades, run, network } from "hardhat";
import { getSingleFarmConfig } from "../../config/singleFarm.config";
import { Contract } from "ethers";

async function main() {
  const singleFarmConfig = getSingleFarmConfig(network.name);

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
      await singleFarm.getAddress(),
      singleFarmConfig.capacityPerFarm,
      singleFarmConfig.minInvestmentAmount,
      singleFarmConfig.maxInvestmentAmount,
      singleFarmConfig.maxLeverage,
      singleFarmConfig.usdToken,
      singleFarmConfig.defarmSeeds
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

  if(singleFarmConfig.maker) {
    await factory.setMaker(singleFarmConfig.maker);
  }

  singleFarmConfig.baseTokens.forEach(async (baseToken: string) => {
    await factory.addToken(baseToken);
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
