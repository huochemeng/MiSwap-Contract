import hre from "hardhat";
import { upgrades, defender } from '@openzeppelin/hardhat-upgrades';
import { expect } from "chai";
import { Side, SaleKind} from "./common"
import { ZeroHash, parseEther, MaxUint256 } from "ethers";


describe("MiSwap Test", function () {
    // ✅ 连接和API在整个describe中只赋值一次，可用let在before中初始化
    let connection;
    let upgradesApi;
    let ethers;

    // ✅ 每个测试用例都会重新部署，必须用 let
    let owner, addr1, addr2, addrs;
    let msVault, msDex;
    let mockERC721, libOrderWrapper;
    let block;
    let msVaultAddress, msDexAddress;

    before(async function () {
        connection = await hre.network.create();
        upgradesApi = await upgrades(hre, connection);
    });

    beforeEach(async function () {
        ({ ethers } = connection);
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
        msVaultAddress = await msVault.getAddress();

        msDex = await upgradesApi.deployProxy(msDexFactory, [protocolShare, msVaultAddress, "MiSwapOrderBook", "1"], { initializer: 'initialize' });
        
        const nft = await mockERC721.getAddress();
        await mockERC721.mint(owner.address, 0);
        await mockERC721.mint(owner.address, 1);
        await mockERC721.mint(owner.address, 2);
        await mockERC721.mint(owner.address, 3);

        msDexAddress = await msDex.getAddress();
        // await mockERC721.setApprovalForAll(msDexAddress, true);
        // 授权给msVault
        await mockERC721.setApprovalForAll(msVaultAddress, true);
        await msVault.setOrderBook(msDexAddress);

        // ✅ 直接通过 ethers provider 获取链上时间戳，无需任何额外导入
        block = await ethers.provider.getBlock("latest");

    });
    

    describe("should initialize successfully", () => { 
        it("should initialize successfully", async function () { 
            const info = await msDex.eip712Domain();
            expect(info.name).to.equal("MiSwapOrderBook");
            expect(info.version).to.equal("1");
        });
    });

    describe("should create order successfully", () => { 
        it("should make list/sell order successfully", async () => { 
            // const now = await time.latest(); // 直接拿到链上 block.timestamp（秒）
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 0n;
            const nftAmount = 1n; 
            const salt = 1n;

            const order = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, nftAmount],              
                price: ethers.parseEther("0.01"),                  
                expiry: expiry,                                
                salt: salt,
            }

            const orders = [order];

            // orderKeys = await msDex.callStatic.makeOrders(orders)
            const orderKeys = await msDex.makeOrders.staticCall(orders);
            expect(orderKeys[0]).to.not.equal(ZeroHash);

            // tx = await esDex.makeOrders(orders)
            // txRec = await tx.wait()
            // console.log("txRec: ", txRec.logs)

            await expect(await msDex.makeOrders(orders))
                .to.emit(msDex, "LogMake");

            const orderHash = await libOrderWrapper.getOrderHash(order);
            // console.log("orderHash: ", orderHash)

            const dbOrder = await msDex.orders(orderHash);
            // console.log("dbOrder: ", dbOrder)
            expect(dbOrder.order.maker).to.equal(owner.address)
            expect(await mockERC721.ownerOf(0)).to.equal(msVaultAddress)

        })

        it("should make list/sell order and return orders successfully", async () => { 
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 0n;
            const nftAmount = 1n; 
            const salt = 1n;

            const order = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, nftAmount],              
                price: ethers.parseEther("0.01"),                  
                expiry: expiry,                                
                salt: salt,
            }
            const orders = [order];
            const orderKeys = await msDex.makeOrders.staticCall(orders);
            expect(orderKeys[0]).to.not.equal(ZeroHash);
            console.log("ZeroHash:",ZeroHash)
        })


        it("should make bid/buy order successfully", async function () {
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 0n;
            const salt = 1n;
            const order = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: salt,
            }
            const orders = [order];
            const orderKeys = await msDex.makeOrders.staticCall(orders, {value: parseEther("0.02")});
            expect(orderKeys[0]).to.not.equal(ZeroHash);

            await expect(await msDex.makeOrders(orders, { value: parseEther("0.02") }))
                .to.changeEtherBalances(ethers, [owner, msVault], [parseEther("-0.01"), parseEther("0.01")]);

            const orderHash = await libOrderWrapper.getOrderHash(order);

            const dbOrder = await msDex.orders(orderHash);
            expect(dbOrder.order.maker).to.equal(owner.address);
        });

        it("should make two side order successfully", async function () { 
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 0n;
            const nftAmount = 1n; 
            const salt = 1n;

            const listOrder = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, nftAmount],              
                price: ethers.parseEther("0.01"),                  
                expiry: expiry,                                
                salt: salt,
            }

            const bidOrder = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: 2n,
            }
            const orders = [listOrder, bidOrder];
        
            // msDex先存入充足ETH。[之前bid循环创建逻辑有误，导致msDex中没有足够的ETH进行订单创建，已经修复]
            // await owner.sendTransaction({
            //         to: await msDex.getAddress(),
            //         value: parseEther("1"),
            //         });
                
            await expect(await msDex.makeOrders(orders, {value: parseEther("0.02") }))
                .to.changeEtherBalances(ethers, [owner, msVault], [parseEther("-0.01"), parseEther("0.01")])

            const listOrderHash = await libOrderWrapper.getOrderHash(listOrder);
            console.log("listOrderHash: ", listOrderHash);
            const dbOrder = await msDex.orders(listOrderHash);
            expect(dbOrder.order.maker).to.equal(owner.address);
            expect(await mockERC721.ownerOf(0)).to.equal(await msVault.getAddress());
            
            const bidOrderHash = await libOrderWrapper.getOrderHash(bidOrder);
            const dbOrder2 = await msDex.orders(bidOrderHash);
            expect(dbOrder2.order.maker).to.equal(owner.address);
        });

    });

    describe("should cancel order successfully", () => {
        it("should cancel list order successfully", async function () { 
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 0n;
            const nftAmount = 1n; 
            const salt = 1n;

            const order = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, nftAmount],              
                price: ethers.parseEther("0.01"),                  
                expiry: expiry,                                
                salt: salt,
            }

            const orders = [order];
            await expect(await msDex.makeOrders(orders)).to.emit(msDex, "LogMake");

            const orderHash = await libOrderWrapper.getOrderHash(order);
            const dbOrder = await msDex.orders(orderHash);
            const successes = await msDex.cancelOrders.staticCall([orderHash]);
            expect(successes[0]).to.equal(true);

            await expect(await msDex.cancelOrders([orderHash]))
                .to.emit(msDex, "LogCancel")
            
            const stat = await msDex.filledAmount(orderHash);
            expect(stat).to.equal(MaxUint256);
        });

        it("should cancel bid order successfully", async function () { 
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 0n;
            const salt = 1n;
            const order = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 5],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: salt,
            }
            const orders = [order];
            await expect(await msDex.makeOrders(orders, {value: parseEther("0.07") }))
                .to.changeEtherBalances(ethers, [owner, msVault], [parseEther("-0.05"), parseEther("0.05")]);

            const orderHash = await libOrderWrapper.getOrderHash(order);
            const dbOrder = await msDex.orders(orderHash);
            expect(dbOrder.order.maker).to.equal(owner.address);

            const successes = await msDex.cancelOrders.staticCall([orderHash]);
            expect(successes[0]).to.equal(true);

            await expect(await msDex.cancelOrders([orderHash]))
                .to.changeEtherBalances(ethers, [owner, msVault], [parseEther("0.05"), parseEther("-0.05")]);

            const stat = await msDex.filledAmount(orderHash);
            expect(stat).to.equal(MaxUint256);
        });

        async function preparePartlyFilledOrder() { 
            // bid order
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 1n;
            const salt = 1n;
            const buyOrder = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: addr1.address,
                nft: [tokenId, nftAddress, 4],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: salt,
            };
            await expect(await msDex.connect(addr1).makeOrders([buyOrder], {value: parseEther("0.04") }))
                .to.emit(msDex, "LogMake");
            const buyOrderHash = await libOrderWrapper.getOrderHash(buyOrder);
            // maker sell
            const sellOrder = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: salt,
            };
            await expect(await msDex.matchOrder(sellOrder, buyOrder))
                .to.changeEtherBalances(ethers, [msDex, owner, msVault], [parseEther("0.0002"), parseEther("0.0098"), parseEther("-0.01")]);
            expect(await mockERC721.ownerOf(1)).to.equal(addr1.address);
            return buyOrderHash;     
        }

        it("should cancel partly filled order successfully", async function () { 
            const buyOrderHash = await preparePartlyFilledOrder();
            await expect(await msDex.connect(addr1).cancelOrders([buyOrderHash]))
                .to.emit(msDex, "LogCancel");
            const stat = await msDex.filledAmount(buyOrderHash);
            expect(stat).to.equal(MaxUint256);

            const newETHBalance = await msVault.ETHBalance(buyOrderHash);
            expect(newETHBalance).to.equal(parseEther("0"));
        });
    });

    describe("should edit orders successfully", () => { 
        it("should edit list order successfully", async function () { 
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 1n;
            const order = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: 1n,
            };
            const order2 = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [2, nftAddress, 1],
                price: parseEther("0.02"),
                expiry: expiry,
                salt: 1n,
            };
            const orders = [order, order2];
            await expect(await msDex.makeOrders(orders)).to.emit(msDex, "LogMake");
            const orderHash = await libOrderWrapper.getOrderHash(order);
            const orderHash2 = await libOrderWrapper.getOrderHash(order2);

            const dbOrder = await msDex.orders(orderHash);
            expect(dbOrder.order.maker).to.equal(owner.address);
            const dbOrder2 = await msDex.orders(orderHash2);
            expect(dbOrder2.order.maker).to.equal(owner.address);

            //edit order
            const newOrder = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: parseEther("0.02"),
                expiry: expiry,
                salt: 1n,
            };

            const newOrder2 = {
                side: Side.List,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [2, nftAddress, 1],
                price: parseEther("0.04"),
                expiry: expiry,
                salt: 1n,
            };
            const editDetail1 = {
                oldOrderKey: orderHash,
                newOrder: newOrder
            }

            const editDetail2 = {
                oldOrderKey: orderHash2,
                newOrder: newOrder2
            }

            const editDetails = [editDetail1, editDetail2];
            let newOrderKeys = await msDex.editOrders.staticCall(editDetails);
            expect(newOrderKeys[0]).to.not.equal(ZeroHash);
            expect(newOrderKeys[1]).to.not.equal(ZeroHash);

            // 边界条件测试，验证重复/无效编辑请求的幂等性处理。1）验证“已消费”订单的防重放机制；2）验证批量操作的原子性和隔离性
            const editDetailsSkip = [editDetail1, editDetail1, editDetail2];
            newOrderKeys = await msDex.editOrders.staticCall(editDetailsSkip);
            expect(newOrderKeys[0]).to.not.equal(ZeroHash);
            expect(newOrderKeys[1]).to.equal(ZeroHash);
            expect(newOrderKeys[2]).to.not.equal(ZeroHash);

            await msDex.editOrders(editDetails);

            const newOrderHash = await libOrderWrapper.getOrderHash(newOrder);
            const newNFTBalance = await msVault.NFTBalance(newOrderHash);
            expect(newNFTBalance).to.equal(1);
            const oldNFTBalance = await msVault.NFTBalance(orderHash);
            expect(oldNFTBalance).to.equal(0);

            const newOrderHash2 = await libOrderWrapper.getOrderHash(newOrder2);
            const newNFTBalance2 = await msVault.NFTBalance(newOrderHash2);
            expect(newNFTBalance2).to.equal(2);
            const oldNFTBalance2 = await msVault.NFTBalance(orderHash2);
            expect(oldNFTBalance2).to.equal(0);

            const newStat = await msDex.filledAmount(newOrderHash);
            // 编辑后的新订单是全新的，没有任何成交，所以状态应该为0
            expect(newStat).to.equal(0);
            const oldStat = await msDex.filledAmount(orderHash);
            // 编辑后的旧订单应该被取消，状态是最大值
            expect(oldStat).to.equal(MaxUint256);

            const newStat2 = await msDex.filledAmount(newOrderHash2);
            expect(newStat2).to.equal(0);
            const oldStat2 = await msDex.filledAmount(orderHash2);
            expect(oldStat2).to.equal(MaxUint256);
        });

        it("should edit bid order successfully, all new price > old price", async () => { 
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 1n;
            const order1 = { 
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: 1n,
            };
            const order2 = { 
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [2, nftAddress, 1],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: 2n,
            };

            const orders = [order1, order2];
            await expect(await msDex.makeOrders(orders, {value: parseEther("0.04")}))
             .to.changeEtherBalances(ethers,[owner, msVault], [parseEther("-0.02"), parseEther("0.02")]);

            const orderHash1 = await libOrderWrapper.getOrderHash(order1); 
            const orderHash2 = await libOrderWrapper.getOrderHash(order2);
            const dbOrder1 = await msDex.orders(orderHash1);
            expect(dbOrder1.order.maker).to.equal(owner.address);
            const dbOrder2 = await msDex.orders(orderHash2);
            expect(dbOrder2.order.maker).to.equal(owner.address);

            // edit order
            const newOrder1 = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 2],
                price: parseEther("0.02"),
                expiry: expiry,
                salt: 1n,
            }

            const newOrder2 = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [2n, nftAddress, 2],
                price: parseEther("0.03"),
                expiry: expiry,
                salt: 2n,
            }

            const editDetail1 = {
                oldOrderKey: orderHash1,
                newOrder: newOrder1
            }
            const editDetail2 = {
                oldOrderKey: orderHash2,
                newOrder: newOrder2
            }
            const editDetails = [editDetail1, editDetail2]
            const newOrderKeys = await msDex.editOrders.staticCall(editDetails, {value: parseEther("0.09")});
            expect(newOrderKeys[0]).to.not.equal(ZeroHash);
            expect(newOrderKeys[1]).to.not.equal(ZeroHash);

            await expect(await msDex.editOrders(editDetails, {value: parseEther("0.1")}))
             .to.changeEtherBalances(ethers,[owner, msVault], [parseEther("-0.08"), parseEther("0.08")]);

            const newOrderHash1 = await libOrderWrapper.getOrderHash(newOrder1);
            const newStat = await msDex.filledAmount(newOrderHash1);
            expect(newStat).to.equal(0);
            const oldStat = await msDex.filledAmount(orderHash1);
            expect(oldStat).to.equal(MaxUint256);

            const newETHBalance = await msVault.ETHBalance(newOrderHash1);
            expect(newETHBalance).to.equal(parseEther("0.04"));
            const oldETHBalance = await msVault.ETHBalance(orderHash1);
            expect(oldETHBalance).to.equal(parseEther("0"));
        });

        it.only("should edit bid order successfully, all new price < old price", async () => { 
            const now = block.timestamp;
            const expiry = BigInt(now) + 100_000n;
            const nftAddress = await mockERC721.getAddress();
            const tokenId = 1n;
            const order1 = { 
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 1],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: 1n,
            };
            const order2 = { 
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [2, nftAddress, 1],
                price: parseEther("0.01"),
                expiry: expiry,
                salt: 2n,
            };

            const orders = [order1, order2];
            await expect(await msDex.makeOrders(orders, {value: parseEther("0.04")}))
             .to.changeEtherBalances(ethers,[owner, msVault], [parseEther("-0.02"), parseEther("0.02")]);

            const orderHash1 = await libOrderWrapper.getOrderHash(order1); 
            const orderHash2 = await libOrderWrapper.getOrderHash(order2);
            const dbOrder1 = await msDex.orders(orderHash1);
            expect(dbOrder1.order.maker).to.equal(owner.address);
            const dbOrder2 = await msDex.orders(orderHash2);
            expect(dbOrder2.order.maker).to.equal(owner.address);

            // edit order
            const newOrder1 = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [tokenId, nftAddress, 2],
                price: parseEther("0.003"),
                expiry: expiry,
                salt: 1n,
            }

            const newOrder2 = {
                side: Side.Bid,
                saleKind: SaleKind.FixedPriceForItem,
                maker: owner.address,
                nft: [2n, nftAddress, 2],
                price: parseEther("0.005"),
                expiry: expiry,
                salt: 2n,
            }

            const editDetail1 = {
                oldOrderKey: orderHash1,
                newOrder: newOrder1
            }
            const editDetail2 = {
                oldOrderKey: orderHash2,
                newOrder: newOrder2
            }
            const editDetails = [editDetail1, editDetail2]
            const newOrderKeys = await msDex.editOrders.staticCall(editDetails, {value: parseEther("0")});
            expect(newOrderKeys[0]).to.not.equal(ZeroHash);
            expect(newOrderKeys[1]).to.not.equal(ZeroHash);

            await expect(await msDex.editOrders(editDetails, {value: parseEther("0")}))
             .to.changeEtherBalances(ethers,[owner, msVault], [parseEther("0.004"), parseEther("-0.004")]);

            const newOrderHash1 = await libOrderWrapper.getOrderHash(newOrder1);
            const newStat = await msDex.filledAmount(newOrderHash1);
            expect(newStat).to.equal(0);
            const oldStat = await msDex.filledAmount(orderHash1);
            expect(oldStat).to.equal(MaxUint256);

            const newETHBalance = await msVault.ETHBalance(newOrderHash1);
            expect(newETHBalance).to.equal(parseEther("0.006"));
            const oldETHBalance = await msVault.ETHBalance(orderHash1);
            expect(oldETHBalance).to.equal(parseEther("0"));
        });
    })

});