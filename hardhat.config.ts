import hardhatToolboxMochaEthersPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers";
import { configVariable, defineConfig } from "hardhat/config";
import hardhatUpgrades from "@openzeppelin/hardhat-upgrades";

export default defineConfig({
  plugins: [hardhatToolboxMochaEthersPlugin,hardhatUpgrades],
  solidity: {
    profiles: {
      default: {
        version: "0.8.34",
        settings: { // ✅ 临时将优化加入 default，方便直接 npx hardhat test
          optimizer: { enabled: true, runs: 200 },
          viaIR: true 
        },
      },
      production: {
        version: "0.8.34",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,// 降低 runs 值可进一步减小部署字节码（牺牲少量运行时 gas）
          },
          viaIR: true // ✅ 关键：启用 IR 管道，配合 yul 优化可大幅缩减体积
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
});
