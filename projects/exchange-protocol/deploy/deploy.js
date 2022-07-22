const hre = require("hardhat");
const path = require("path");
const Utils = require("../Utils");

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

module.exports = async ({ getUnnamedAccounts, deployments, ethers, network }) => {
  try {
    const config = {
      presaleFactory: false,
      createPresale: false,
      presaleFactory: undefined,
    };

    if (config.presale) {
      Utils.infoMsg("Deploying ObitalPresale implementation");
      let deployed = await deploy("ObitalPresale", {
        from: account,
        args: [],
        log: false,
      });

      let implementation = deployed.address;
      Utils.successMsg(`Implementation Address(ObitalPresale): ${implementation}`);

      Utils.infoMsg("Deploying PresaleFactory contract");
      deployed = await deploy("PresaleFactory", {
        from: account,
        args: [implementation],
        log: false,
      });

      let deployedAddress = deployed.address;
      Utils.successMsg(`PresaleFactory Contract Address: ${deployedAddress}`);

      // // verify
      // await sleep(60)
      // await hre.run("verify:verify", {
      //     address: deployedAddress,
      //     contract: "contracts/ObitalPresale.sol:ObitalPresale",
      //     constructorArguments: [],
      // })

      // await hre.run("verify:verify", {
      //     address: deployedAddress,
      //     contract: "contracts/PresaleFactory.sol:PresaleFactory",
      //     constructorArguments: [implementation],
      // })
    }

    if (config.createPresale) {
      if (!config.presaleFactory) {
        Utils.infoMsg("Set presale factory address");
        return;
      }

      Utils.infoMsg("Creating ObitalPresale implementation");
      let contractInstance = await ethers.getContractAt("PresaleFactory", config.presaleFactory);
      const res = contractInstance.createPresale(
        account, // presale owner
        "", // swap router
        "", // presale token
        {
          token: "",
          price: 0,
          listing_price: 0,
          liquidity_percent: 0,
          hardcap: 0,
          softcap: 0,
          min_contribution: 0,
          max_contribution: 0,
          startTime: 0,
          endTime: 0,
          liquidity_lockup_time: 0,
        },
        0 // fee type
      );

      Utils.successMsg(`Presale created`);

      // // verify
      // await sleep(60)
      // await hre.run("verify:verify", {
      //     address: deployedAddress,
      //     contract: "contracts/ObitalPresale.sol:ObitalPresale",
      //     constructorArguments: [],
      // })

      // await hre.run("verify:verify", {
      //     address: deployedAddress,
      //     contract: "contracts/PresaleFactory.sol:PresaleFactory",
      //     constructorArguments: [implementation],
      // })
    }
  } catch (e) {
    console.log(e, e.stack);
  }
};
