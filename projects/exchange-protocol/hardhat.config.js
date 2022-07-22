require('hardhat-deploy');
require("@nomiclabs/hardhat-ethers");
require('@openzeppelin/hardhat-upgrades');
require("@nomiclabs/hardhat-etherscan");

const {  
  infuraProjectId,
  accountPrivateKey,
  APIKey,
  // alchemyApi
} = require(__dirname+'/.secrets.js');

module.exports = {
  paths: {
    sources: `./contracts`
  },
  networks: {
    hardhat: {
      accounts: [
        {privateKey: `0x${accountPrivateKey}`, balance: "99991229544000000000000"},
      ],
      // forking: {
      //     url: "https://eth-kovan.alchemyapi.io/v2/"+alchemyApi
      // },

      chainId: 31337,
      loggingEnabled: false,
      mining: {
        auto: true,
        interval: [1000, 5000]
      },
      
      allowUnlimitedContractSize: true
    },

    kovan: {
      url: `https://kovan.infura.io/v3/${infuraProjectId}`,
      chainId: 42,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`]
    },  

    ropsten: {
      url: `https://ropsten.infura.io/v3/${infuraProjectId}`,
      chainId: 3,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`]
    },  

    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${infuraProjectId}`,
      chainId: 4,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`]
    },  

    eth_mainnet: {
      url: `https://mainnet.infura.io/v3/${infuraProjectId}`,
      chainId: 1,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`]
    },    

    bsc_mainnet: {
      url:  `https://bsc-dataseed.binance.org/`,
      chainId: 56,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`]
    }, 
    
    bsc_testnet: {
      url:  `https://data-seed-prebsc-1-s1.binance.org:8545/`,
      chainId: 97,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`]
    },

    matic: {
      url:  `https://polygon-rpc.com`,
      chainId: 137,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`]
   }
  },

  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: APIKey
  },

  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.6.12',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.6.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.5.16",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.4.18",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ]
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
}
