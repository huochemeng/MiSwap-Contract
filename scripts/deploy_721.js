import hre from "hardhat";

async function main() { 
    const connection = await hre.network.create();
    const ethers = connection.ethers;
    const [deployer] = await ethers.getSigners();
    console.log("deployer:", deployer.address);
    // const mockERC721Factory = await ethers.getContractFactory("MockERC721");
    // const mockERC721 = await mockERC721Factory.deploy();
    // await mockERC721.waitForDeployment();
    // const mockERC721Address = await mockERC721.getAddress();
    // console.log("mockERC721 deployed to:", mockERC721Address);
    // mockERC721 deployed to: 0x7De6c17550929034B7E1907b6907e4452c5beb7e
    const mockERC721AddressDeployed = "0x7De6c17550929034B7E1907b6907e4452c5beb7e";
    const mockERC721 = await ethers.getContractAt("MockERC721", mockERC721AddressDeployed);
    const tx = await mockERC721.mint(deployer.address, 50);
    await tx.wait();
    console.log("mint tx:", tx.hash);
    //mint tx: 0x7edcbf43ec06bed19a045e1cf676f7fb0ccf0066974e52d3dbde0c0e74c6c93e

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });