module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('TaxOfficeV2', {
    from: deployer,
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ['TaxOfficeV2'];
