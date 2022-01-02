// eslint-disable-next-line node/no-unpublished-require
const { ethers } = require('hardhat');

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const dibs = await ethers.getContract('Dibs');

  await deploy('BananaGenesisRewardPool', {
    from: deployer,
    args: [dibs.address, 1641135600],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ['DibsGenesisRewardPool'];

