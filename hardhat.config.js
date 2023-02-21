require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();
require("@nomiclabs/hardhat-ethers");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },

  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },

    mumbai: {
      url: process.env.MUMABI_URL,
      accounts: [process.env.TEST1_PRIVATE_KEY],
      allowUnlimitedContractSize: true,
    },

    goerli: {
      url: process.env.GOERLI_URL,
      accounts: [process.env.TEST1_PRIVATE_KEY],
      allowUnlimitedContractSize: true,
    },
  }, 

  etherscan: {
    apiKey: {
      polygonMumbai: process.env.POLYSCAN_API_KEY,
      goerli: process.env.ETHERSCAN_API_KEY,
    },
  },
};
