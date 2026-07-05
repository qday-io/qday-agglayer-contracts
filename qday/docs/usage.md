# QDAY zkRollup 合约部署指南

## 目录

1. [概述](#1-概述)
2. [POL 代币说明](#2-pol-代币说明)
3. [部署者地址（重要）](#3-部署者地址重要)
4. [环境准备](#4-环境准备)
5. [参数配置](#5-参数配置)
6. [执行部署](#6-执行部署)
7. [部署后检查](#7-部署后检查)
8. [合约验证](#8-合约验证)
9. [分步手动部署](#9-分步手动部署)
10. [常见问题](#10-常见问题)

---

## 1. 概述

将 zkRollup (PolygonZkEVMEtrog fork12) 合约部署到已有 L1 节点上。

### 部署的合约

| 合约 | 说明 |
|------|------|
| PolygonZkEVMDeployer | Create2 确定性部署工厂 |
| PolygonZkEVMTimelock | 时间锁 |
| PolygonZkEVMBridgeV2 | L1↔L2 跨链桥 |
| PolygonZkEVMGlobalExitRootV2 | 全局退出根管理器 |
| AggLayerGateway | 聚合层验证密钥网关 |
| PolygonRollupManager | Rollup 管理器 |
| Verifier | ZK 证明验证器 |
| PolygonZkEVMEtrog | zkRollup 共识合约 |

### 部署流程

```
编译 → 检查余额+充Sequencer/Aggregator各1000 ETH → 部署POL+充Sequencer 100,000 POL → 生成Genesis → 部署Deployer → 部署L1核心合约 → 创建Rollup
```

---

## 2. POL 代币说明

POL 是 Polygon 生态的原生代币，RollupManager 部署时必须指定 `polTokenAddress`。

### Sepolia 测试网

**不需要手动提供 POL 地址**。`deploy.sh` 会自动：

1. 检查部署者 ETH 余额，确认足够后：
   - 向 **Sequencer** 转账 **1000 ETH**
   - 向 **Aggregator** 转账 **1000 ETH**
2. 部署测试 POL 代币（ERC20PermitMock）
3. 向 **Sequencer** 转账 **100,000 POL**
4. 自动将 POL 地址写入 `deploy_parameters.json`

### 以太坊主网

主网 POL 地址已知，需要**手动填入** `qday/deploy_parameters.json`：

```json
// Ethereum 主网 POL 代币地址:
"polTokenAddress": "0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6"
```

主网上 Sequencer/Aggregator 需要**提前准备好**：
- 有足够 ETH 支付 Gas 费
- 有足够 POL 作为 Rollup 押金

---

## 3. 部署者地址（重要）

部署时所用 Gas 来自**部署者地址**，其来源按以下优先级确定：

| 优先级 | 来源 | 说明 |
|--------|------|------|
| 1 | `qday/deploy_parameters.json` → `deployerPvtKey` | 如果填写了私钥，则以此为部署者 |
| 2 | `.env` → `MNEMONIC` 第一个账户 | 派生路径 `m/44'/60'/0'/0/0` |
| 3 | Hardhat 默认 Signer | 仅本地 hardhat 网络使用 |

**验证部署者地址**：

```bash
source .env 2>/dev/null
npx hardhat console --network sepolia <<< "
const w = ethers.HDNodeWallet.fromMnemonic(
  ethers.Mnemonic.fromPhrase(process.env.MNEMONIC),
  'm/44'/60'/0'/0/0'
);
console.log('Deployer:', w.address);
"
```

> :warning: **部署前务必确认**：部署者地址在目标网络上有足够 ETH 支付 Gas 费。所有 L1 合约部署、POL 代币部署、账户充值等操作都将从这个地址发起。

---

## 4. 环境准备

### 4.1 系统要求

- Node.js >= 18.x, npm >= 9.x
- 已安装依赖: `npm install`

### 4.2 配置环境变量

```bash
cp qday/.env.example .env
```

编辑 `.env`：

```env
MNEMONIC="your twelve word mnemonic phrase here"
INFURA_PROJECT_ID="your-infura-project-id"
ETHERSCAN_API_KEY="your-etherscan-api-key"
```

---

## 5. 参数配置

### 5.1 deploy_parameters.json

```bash
vim qday/deploy_parameters.json
```

| 字段 | Sepolia | Mainnet | 说明 |
|------|---------|---------|------|
| `salt` | 自定 | 自定 | Create2 盐值 |
| `polTokenAddress` | **留空** | **必须填写** | Sepolia 自动部署，Mainnet 必须手动填 |
| `initialZkEVMDeployerOwner` | 填写 | 填写 | Deployer 工厂 Owner |
| `admin` | 填写 | 填写 | 超级管理员 |
| `trustedAggregator` | 填写 | 填写 | 可信聚合者 |
| `emergencyCouncilAddress` | 填写 | 填写 | 紧急委员会 |
| `timelockAdminAddress` | 填写 | 填写 | 时间锁管理员（建议多签） |
| `realVerifier` | `true` | `true` | 生产用真实验证器 |
| `ppVKey` | 填写 | 填写 | 悲观证明验证密钥 |
| `ppVKeySelector` | `0x00000001` | `0x00000001` | 悲观证明选择器 |

### 5.2 create_rollup_parameters.json

```bash
vim qday/create_rollup_parameters.json
```

| 字段 | 说明 |
|------|------|
| `trustedSequencerURL` | Sequencer RPC 地址 |
| `networkName` | L2 网络名 |
| `trustedSequencer` | 可信 Sequencer 地址 |
| `chainID` | L2 链 ID（需唯一） |
| `adminZkEVM` | L2 管理员 |
| `forkID` | `12`（无需修改） |
| `gasTokenAddress` | Gas 代币地址（`""` = ETH） |

---

## 6. 执行部署

### Sepolia 测试网

```bash
./qday/deploy.sh sepolia
```

### 以太坊主网

```bash
# 先填写 polTokenAddress
vim qday/deploy_parameters.json

./qday/deploy.sh mainnet
```

脚本执行步骤：

| Sepolia | Mainnet |
|---------|---------|
| 编译 | 编译 |
| 复制参数文件 | 复制参数文件 |
| **检查余额 + 充 Sequencer 1000 ETH + Aggregator 1000 ETH** | same |
| **部署 POL + 充 Sequencer 100,000 POL** | 校验 polTokenAddress 非空 |
| 生成 Genesis | 生成 Genesis |
| 部署 ZkEVMDeployer | 部署 ZkEVMDeployer |
| 部署 L1 核心合约 | 部署 L1 核心合约 |
| 创建 Rollup | 创建 Rollup |
| 收集输出 → `qday/output/` | 收集输出 → `qday/output/` |

---

## 7. 部署后检查

```bash
# 查看输出文件
ls -la qday/output/

# L1 合约地址
cat qday/output/deploy_output.json | python3 -m json.tool

# Rollup 详情
cat qday/output/create_rollup_output.json | python3 -m json.tool
```

| 文件 | 说明 | 用途 |
|------|------|------|
| `genesis.json` | L2 Genesis 配置（状态根、预部署合约） | **zkEVM 节点启动必需**，初始化 L2 链状态 |
| `deploy_output.json` | 所有 L1 合约地址 | 配置 zkEVM 节点指向正确的 L1 合约 |
| `create_rollup_output.json` | Rollup 地址 + 初始批次数据 | 配置 Sequencer 同步起始点 |

---

## 8. 合约验证

```bash
# Sepolia
npm run verify:v2:sepolia

# Mainnet
npm run verify:ZkEVM:mainnet
```

---

## 9. 分步手动部署

如需逐步调试，可单独执行每一步：

```bash
# Step 0: 编译
npx hardhat compile

# Step 1: 复制参数
cp qday/deploy_parameters.json deployment/v2/deploy_parameters.json
cp qday/create_rollup_parameters.json deployment/v2/create_rollup_parameters.json

# Step 2: 检查余额 + 为 Sequencer/Aggregator 各充 1000 ETH
npx hardhat run qday/pre_deploy_check.ts --network sepolia

# Step 3: 准备测试网 (部署 POL + 向 Sequencer 充 100,000 POL)
npx hardhat run deployment/testnet/prepareTestnet.ts --network sepolia

# Step 4: 生成 Genesis
npx ts-node deployment/v2/1_createGenesis.ts

# Step 5: 部署 ZkEVMDeployer
npx hardhat run deployment/v2/2_deployPolygonZKEVMDeployer.ts --network sepolia

# Step 6: 部署 L1 核心合约
npx hardhat run deployment/v2/3_deployContracts.ts --network sepolia

# Step 7: 创建 Rollup
npx hardhat run deployment/v2/4_createRollup.ts --network sepolia

# Step 8: 收集输出
mkdir -p qday/output
cp deployment/v2/deploy_output.json qday/output/
cp deployment/v2/genesis.json qday/output/
cp deployment/v2/create_rollup_output_*.json qday/output/create_rollup_output.json
```

---

## 10. 常见问题

### 9.1 Sequencer/Aggregator 资金不足？

`deploy.sh` 会自动检查并充值：

```
Sequencer: 1000 ETH + 100,000 POL
Aggregator: 1000 ETH
```

部署者地址需持有至少 2000 ETH（Sequencer 1000 + Aggregator 1000），否则部署会在 [STEP 2] 报错退出。

主网需手动确保余额充足。

### 9.2 部署失败如何重试？

```bash
rm -f deployment/v2/deploy_ongoing.json .openzeppelin/sepolia.json
./qday/deploy.sh sepolia
```

### 9.3 如何更换 Salt 重新部署？

修改 `qday/deploy_parameters.json` 中的 `salt`。**相同 salt 会产生相同 Create2 地址，无法重复部署。**

### 9.4 "zkEVM deployer contract is not deployed"

Sepolia 需先执行步骤 4。Mainnet Deployer 已部署：`0xCB19eDdE626906eB1EE52357a27F62dd519608C2`。

### 9.5 Mainnet 部署要点

- `polTokenAddress` 必须填写
- `realVerifier` 必须为 `true`
- `test` 必须为 `false`
- 部署账户余额需足够支付 Gas
- Sequencer / Aggregator 需提前准备好 ETH + POL
