# MiSwapOrderBook
🚀 高性能、非托管的 NFT 链上订单簿撮合引擎
MiSwapOrderBook 是 MiSwap 协议的核心撮合组件，专为 NFT 资产的高效、安全交易而设计。它采用业界标准的 Vault-Orderbook 分离架构，将资产保管与订单撮合逻辑彻底解耦，在保障资金安全的同时，实现了灵活的费率配置与极致的 Gas 优化。
## ✨ 核心特性
### 🔒 资产安全隔离
Orderbook 合约仅负责订单状态管理与签名验证，不直接持有任何 NFT 或 ERC-20 资产。所有资产由独立的 Vault 合约统一托管，从架构层面杜绝了撮合逻辑漏洞导致的资产风险。
### ⚡ BPS 高精度费率体系
采用 TOTAL_SHARE = 10000 的基点（Basis Points）标准，支持最低 0.01% 的费率精度。兼容 Uniswap、OpenSea 等主流生态的费率惯例，确保协议手续费、创作者版税及收益分配的精确计算与无缝对接。
### 📝 链下签名 + 链上撮合
Maker 通过 EIP-712 标准化签名在链下创建订单，Taker 在链上提交匹配。订单数据不上链，仅在结算时验证签名有效性，大幅降低挂单 Gas 成本，同时保留链上结算的最终性与透明性。
### 🧩 模块化支付结算
内置 _shareToAmount 通用比例换算模块，支持协议费用、版税、分成等多维度收益的灵活配置。结算路径确定为 Vault ↔ User，Orderbook 仅作为指令调度器，确保资金流转可预测、可审计。
### 🛡️ 防御性设计
Orderbook 刻意不实现 onERC721Received，防止无主 NFT 误入导致的状态污染与攻击面扩大。所有资产入口收敛至 Vault，实现单一可信来源的资金管控。
## 🏗️ 架构概览
┌─────────────┐     EIP-712 Sign      ┌──────────────────┐
│    Maker     │ ─────────────────────► │                  │
└─────────────┘                        │  MiSwapOrderBook │ ◄── 订单匹配 / 签名验证
┌─────────────┐     matchOrder()       │  (No Asset Custody)│
│    Taker     │ ─────────────────────► │                  │
└─────────────┘                        └────────┬─────────┘
                                                 │ settle instruction
                                                 ▼
                                       ┌──────────────────┐
                                       │      Vault       │ ◄── NFT / Token Custody
                                       │  onERC721Received│     withdrawNFT / batchTransfer
                                       └──────────────────┘
## 📐 关键设计决策
| 设计点 | 选择 | 理由 |
| :--- | :--- | :--- |
| 资产托管 | Vault 独立合约 | 关注点分离，最小化 Orderbook 攻击面 |
| 费率基数 | 10000 (BPS) | 0.01% 精度，DeFi 行业标准，避免浮点模拟 |
| NFT 接收 | Orderbook 不实现 | 防止资产与订单状态脱节，杜绝误收风险 |
| 比例计算 | 先乘后除 `(total * share) / BASE` | 避免整数除法截断，保留最大精度 |

## 🛠️ 基于 Hardhat 3 的现代化工程体系
本项目基于 Hardhat 3 构建，充分利用其全新 API 提升订单簿合约的开发与测试效率：
- 统一 Ethers 访问：通过 await hre.ethers 异步获取 ethers 实例，告别全局隐式注入，支持多网络/多 provider 并行测试，签名构造与合约部署更安全可控。
- 轻量级网络管理：通过 hre.network.connect() 按需创建隔离 EVM 实例，Maker/Taker 撮合测试可独立运行，状态互不污染。

## 测试脚本
整个测试脚本放置在 `test` 目录下，`MiSwap.test.js`文件，运行即可
```shell
npx hardhat test
```
## 部署脚本
整个部署脚本放置在 `scripts` 目录下，`deploy.js`文件，运行即可
```shell
npx hardhat run scripts/deploy.js --network sepolia
```
> 说明：部署脚本中是分步调试进行部署的，所以保留了每个步骤的结果信息，硬编码的方式把已经部署的合约地址添加到代码中。
## 运行结果
msVault deployed to: 0xA466143aA2D3c309e04a06c251DB574ce261417E
msDex deployed to: 0x6119a211B580F9c6cF65Ee82EaeD7489EdF3de3E
mockERC721 deployed to: 0x7De6c17550929034B7E1907b6907e4452c5beb7e
可以通过[区块链浏览器](https://sepolia.etherscan.io/)查看