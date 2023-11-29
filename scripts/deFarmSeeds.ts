import { ethers, upgrades, run, network } from "hardhat";

async function main() {
  const DeFarmSeeds = await ethers.getContractFactory("DeFarmSeeds");
  const deFarmSeeds = await upgrades.deployProxy(
    DeFarmSeeds, [
    ]
  );

  console.log(
    `DeFarmSeeds deployed to ${await deFarmSeeds.getAddress()}`
  );

  if(network.name !== "localhost") {
    await run("verify:verify", {
      address: await deFarmSeeds.getAddress(),
    });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
