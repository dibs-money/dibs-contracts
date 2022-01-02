// eslint-disable-next-line node/no-unpublished-require
const { ethers } = require('hardhat');

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const dibs = await ethers.getContract('Dibs');
  const wbnbAddress = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';
  const pairAddress = '0x9bEBe118018d0De55b00787B5eeABB9EDa8A9e0A';

  await deploy('TaxOracle', {
    from: deployer,
    args: [dibs.address, wbnbAddress, pairAddress],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ['TaxOracle'];
