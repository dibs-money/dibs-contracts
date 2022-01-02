// eslint-disable-next-line node/no-unpublished-require
const { ethers } = require('hardhat');

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const dshare = await ethers.getContract('DShare');

  await deploy('DShareRewardPool', {
    from: deployer,
    args: [dshare.address, 1641135600], // exactly genesis time
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ['DShareRewardPool'];
