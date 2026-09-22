import hre from "hardhat";
import { upgrades, defender } from '@openzeppelin/hardhat-upgrades';
import { expect } from "chai";
import { time } from "@nomicfoundation/hardhat-network-helpers";


describe("MiSwap Test", function () {
    // ✅ 连接和API在整个describe中只赋值一次，可用let在before中初始化
    let connection;
    let upgradesApi;

    // ✅ 每个测试用例都会重新部署，必须用 let
    let owner, addr1, addr2, addrs;
    let msVault, msDex;
    let mockERC721, libOrderWrapper;

    before(async function () {
        connection = await hre.network.create();
        upgradesApi = await upgrades(hre, connection);
    });

    beforeEach(async function () {
        const { ethers } = connection;
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

        // ✅ 工厂用 const，因为它们在 beforeEach 内不会改变
        const msVaultFactory = await ethers.getContractFactory("MiSwapVault");
        const msDexFactory = await ethers.getContractFactory("MiSwapOrderBook");
        const mockERC721Factory = await ethers.getContractFactory("MockERC721");
        const libOrderWrapperFactory = await ethers.getContractFactory("LibOrderWrapper");

        // ✅ 部署实例赋值给外层 let 变量
        mockERC721 = await mockERC721Factory.deploy();
        libOrderWrapper = await libOrderWrapperFactory.deploy();

        msVault = await upgradesApi.deployProxy(msVaultFactory, [], { initializer: 'initialize' });
        

        const protocolShare = 200;
        const msVaultAddress = await msVault.getAddress();

        msDex = await upgradesApi.deployProxy(msDexFactory, [protocolShare, msVaultAddress, "MiSwapOrderBook", "1"], { initializer: 'initialize' });
        
        const nft = await mockERC721.getAddress();
        await mockERC721.mint(owner.address, 1);

        mockERC721.setApprovalForAll(msVault.getAddress(), true);
        await msVault.setOrderBook(msDex.getAddress());


    });
    
    // it("just only print owner address", async function () {
    //     console.log("msVault address:", await msVault.getAddress());
    //     console.log("msDex address:", await msDex.getAddress());
    //     console.log("owner address:", await owner.getAddress());
    // });

    describe("should initialize successfully", async () => { 
        it("should initialize successfully", async function () { 
            const info = await msDex.eip712Domain();
            expect(info.name).to.equal("MiSwapOrderBook");
            expect(info.version).to.equal("1");
        });
    });

});