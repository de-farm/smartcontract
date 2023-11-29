import { ethers, upgrades, run, network } from "hardhat";

async function main() {
  const VertexHandler = await ethers.getContractFactory("VertexHandler");
  const vertexHandler = await upgrades.deployProxy(
    VertexHandler, ['0xFc69d0f1d70825248C9F9582d13F93D60b6b56De'
    ]
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
