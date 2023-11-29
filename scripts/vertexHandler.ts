import { ethers, upgrades, run, network } from "hardhat";

import { getChainConfig } from "../config/vertexHandler.config";

async function main() {
  const config = getChainConfig(network.name);

  const VertexHandler = await ethers.getContractFactory("VertexHandler");
  const vertexHandler = await upgrades.deployProxy(
    VertexHandler, [config.quote, config.endpoint, config.querier]
  );

  console.log(
    `VertexHandler deployed to ${await vertexHandler.getAddress()}`
  );

  if(network.name !== "localhost") {
    await run("verify:verify", {
      address: await vertexHandler.getAddress(),
    });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
