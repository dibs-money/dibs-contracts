module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const wethAddress = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c';

  await deploy('Zap', {
    from: deployer,
    args: [wethAddress],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ['Zap'];
