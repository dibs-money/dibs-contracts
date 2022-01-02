module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const pairAddress = '0x9bEBe118018d0De55b00787B5eeABB9EDa8A9e0A'; // DIBS/WBNB PancakeSwap address

  await deploy('Oracle', {
    from: deployer,
    args: [pairAddress, 21600, 1641135600],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ['Oracle'];
