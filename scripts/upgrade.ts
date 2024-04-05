import { ethers, upgrades, run, network } from "hardhat";

async function main() {
  const SingleFarmFactory = await ethers.getContractFactory("SingleFarmFactory");

  const factory = await upgrades.upgradeProxy('proxySingleFarmAddress', SingleFarmFactory)

  console.log(
    `SingleFarmFactory deployed to ${await factory.getAddress()}`
  );

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
