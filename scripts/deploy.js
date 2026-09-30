import hre from "hardhat";
import { upgrades } from '@openzeppelin/hardhat-upgrades';

async function main() { 
    const connection = await hre.network.create();
    const upgradesApi = await upgrades(hre, connection);
    const ethers = connection.ethers;
    const [deployer] = await ethers.getSigners();
    console.log("deployer:", deployer.address);

    // const msVaultFactory = await ethers.getContractFactory("MiSwapVault");
    // const msVault = await upgradesApi.deployProxy(msVaultFactory, [], { initializer: 'initialize' });
    // 等待部署交易被打包并确认
    // await msVault.waitForDeployment();
    // const msVaultAddress = await msVault.getAddress();
    // console.log("msVault deployed to:", msVaultAddress);

    // msVault deployed to: 0xA466143aA2D3c309e04a06c251DB574ce261417E
    const msVaultAddressDeployed = "0xA466143aA2D3c309e04a06c251DB574ce261417E";
    // const msDexFactory = await ethers.getContractFactory("MiSwapOrderBook");
    // const msDex = await upgradesApi.deployProxy(msDexFactory, [200, msVaultAddressDeployed, "MiSwapOrderBook", "1"], { initializer: 'initialize' });
    // 等待部署交易被打包并确认
    // await msDex.waitForDeployment();
    // const msDexAddress = await msDex.getAddress();
    // console.log("msDex deployed to:", msDexAddress);
    //msDex deployed to: 0x6119a211B580F9c6cF65Ee82EaeD7489EdF3de3E
    const msDexAddressDeployed = "0x6119a211B580F9c6cF65Ee82EaeD7489EdF3de3E";
    const msVault = await ethers.getContractAt("MiSwapVault", msVaultAddressDeployed);
    // 调用合约方法
    const tx = await msVault.setOrderBook(msDexAddressDeployed);
    await tx.wait();// 等待交易确认
    console.log("setOrderBook tx:", tx.hash);
    //setOrderBook tx: 0x03aca0635ff1563cbbd0369082e42d6da5d9716343392745f4b8356c5056125f
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });