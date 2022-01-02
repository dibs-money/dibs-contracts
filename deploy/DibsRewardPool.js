// eslint-disable-next-line node/no-unpublished-require
const { ethers } = require('hardhat');

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const dibs = await ethers.getContract('Dibs');

  await deploy('DibsRewardPool', {
    from: deployer,
    args: [dibs.address, 1639764000], // Should be 1 day after Genesis pool starts
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ['DibsRewardPool'];
