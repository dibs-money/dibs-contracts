module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer, dao, dev } = await getNamedAccounts();

  await deploy('DShare', {
    from: deployer,
    args: [1641135600, dao, dev],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ['DShare'];
