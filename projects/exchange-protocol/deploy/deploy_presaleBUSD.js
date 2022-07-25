const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  if (deployer === undefined) throw new Error("Deployer is undefined.");

  console.log("Account balance:", (await deployer.getBalance()).toString());

  const ObitalPresaleBUSD = await hre.ethers.getContractFactory("ObitalPresaleBUSD");
  const ObitalPresaleBUSDDeployed = await ObitalPresaleBUSD.deploy(
    1658638129,
    1658848129,
    "0x1e957dec5960478f2dbef5cca2f82fe0bdd11911"
  );
  console.log("ObitalPresaleBUSDDeployed.address", ObitalPresaleBUSDDeployed.address);
  return ObitalPresaleBUSDDeployed.address;
}

main()
  .then((r) => {
    console.log("deployed address:", r);
    return r;
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// npx hardhat run --network bsc_testnet deploy/deploy_presaleBUSD.js
// npx hardhat verify --network bsc_testnet
