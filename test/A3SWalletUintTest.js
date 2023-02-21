const { expect } = require("chai");
const { ethers } = require("hardhat");

const executeCaseABI = [
    "function getData() external view returns(uint256)",
    "function subData(uint256) external returns(uint256)",
    "function addData(uint256) external returns(uint256)",
    "function setData(uint256) external returns(uint256)",
    "function callERC1271isValidSignature(address, bytes32, bytes) external view"
];

const SALT = "0x1234432100000000000000000000000000000000000000000000000000000000";

describe("A3SWallet", () => {
    let predictWalletAddress;
    let Test20;
    let UserOp;
    let testHelper;
    let requestId;

    beforeEach(async () => {
        //deployment
        [deployer, walletOwner, entryPointProxy, user1, user2] = await ethers.getSigners();

        const A3SWalletFactory = await ethers.getContractFactory("A3SWalletFactory");
        const a3sWalletFactory = await A3SWalletFactory.deploy();

        const A3SWallet = await ethers.getContractFactory("A3SWallet");
        const a3sWallet = await A3SWallet.deploy(entryPointProxy.address, a3sWalletFactory.address);

        await a3sWalletFactory.setLogicAddress(a3sWallet.address);

        //test contract deploy
        const TEST20 = await ethers.getContractFactory("Test20");
        Test20 = await TEST20.deploy();

        const TestHelper = await ethers.getContractFactory("testHelper");
        testHelper = await TestHelper.deploy();

        //mint an A3SWallet to walletOwner
        //set detail about A3SFeeHandler
        await a3sWalletFactory.setFiatToken(Test20.address);
        await a3sWalletFactory.setFiatTokenFee(1);
        await a3sWalletFactory.setPlatfromTokenFee(1);
        await a3sWalletFactory.setWithdrawer(deployer.address);
        
        predictWalletAddress = await a3sWalletFactory.predictWalletAddress(walletOwner.address, SALT);

        await a3sWalletFactory.safeMint(walletOwner.address, SALT);

        //assemble basic UserOp
        UserOp = {
            sender: predictWalletAddress,
            nonce: 0,
            initCode: "0x",
            callData: "0x",
            callGasLimit: 10000000,
            verificationGasLimit: 1000000,
            preVerificationGas: 100000,
            maxFeePerGas: 300,
            maxPriorityFeePerGas: 10,
            paymasterAndData: "0x",
            signature: "0x"
        };

        const hash = await testHelper.testHash(UserOp);
        const chainId = await walletOwner.getChainId();
        requestId = ethers.utils.solidityKeccak256(
            ["bytes32", "address", "uint256"],
            [hash, entryPointProxy.address, chainId]
        );

        const sig = await walletOwner.signMessage(
            ethers.utils.arrayify(requestId)
        );
        UserOp.signature = sig;
    });

    describe("Support the circulation of multiple cryptocurrencies", () => {
        it("Func - ETH", async() => {
            const transferETHTx = {
                to: predictWalletAddress,
                value: ethers.utils.parseEther("1.0")
            }

            expect(await deployer.sendTransaction(transferETHTx)).to.changeEtherBalance(predictWalletAddress, ethers.utils.parseEther("1.0"));
        });

        it("Func - ERC20 Token", async() => {
            const transferAmount = 100;

            expect(await Test20.transfer(predictWalletAddress, transferAmount)).to.changeTokenBalance(Test20, predictWalletAddress, transferAmount);
        });

        it("Func - ERC721 Token", async() => {
            const TEST721 = await ethers.getContractFactory("Test721");
            const Test721 = await TEST721.deploy("Test721", "T721");

            await Test721.mintTo(predictWalletAddress);
            const tokenId = await Test721.getCurrentTokenId();

            expect(await Test721.ownerOf(tokenId)).to.equal(predictWalletAddress);
        });
    });

    describe("validateUserOp Function", () => {
        it("Func - only EntryPoint can call", async() => {
            const a3sWalletProxy = await ethers.getContractAt("A3SWallet", predictWalletAddress, walletOwner);

            const missingWalletFunds = 0;

            await expect(a3sWalletProxy.validateUserOp(UserOp, requestId, missingWalletFunds)).revertedWith("A3SWallet: Sender must be entrypoint");
        });

        it("Func - nonce check", async() => {
            UserOp.nonce = 1;
            const a3sWalletProxy = await ethers.getContractAt("A3SWallet", predictWalletAddress, walletOwner);

            const missingWalletFunds = 0;

            await expect(a3sWalletProxy.connect(entryPointProxy).validateUserOp(UserOp, requestId, missingWalletFunds)).revertedWith("A3SWallet: Invalid nonce");
        });

        it("Func - signature check", async() => {
            const sig = await user1.signMessage(
                ethers.utils.arrayify(requestId)
            );
            UserOp.signature = sig;

            const a3sWalletProxy = await ethers.getContractAt("A3SWallet", predictWalletAddress, walletOwner);

            const missingWalletFunds = 0;

            await expect(a3sWalletProxy.connect(entryPointProxy).validateUserOp(UserOp, requestId, missingWalletFunds)).revertedWith("A3SWallet: Invalid signature");
        });

        it("Func - missingWalletFunds send successfully", async() => {
            const missingWalletFunds = 10;
            const transferETHTx = {
                to: predictWalletAddress,
                value: ethers.utils.parseEther(missingWalletFunds.toString())
            }
            await deployer.sendTransaction(transferETHTx);

            const a3sWalletProxy = await ethers.getContractAt("A3SWallet", predictWalletAddress, walletOwner);

            expect(await a3sWalletProxy.connect(entryPointProxy).validateUserOp(UserOp, requestId, ethers.utils.parseEther(missingWalletFunds.toString()))).to.changeEtherBalance(entryPointProxy, ethers.utils.parseEther(missingWalletFunds.toString()));
        });
    });

    describe("executeUserOp Function", () => {
        it("Func - only EntryPoint can call", async() => {
            const a3sWalletProxy = await ethers.getContractAt("A3SWallet", predictWalletAddress, walletOwner);

            const to = "0x0000000000000000000000000000000000000000";
            const value = 0;
            const data = "0x";

            await expect(a3sWalletProxy.executeUserOp(to, value, data)).revertedWith("A3SWallet: Sender must be entrypoint");
        });

        it("Func - execute successfully", async() => {
            const a3sWalletProxy = await ethers.getContractAt("A3SWallet", predictWalletAddress, walletOwner);

            const ExecuteCase = await ethers.getContractFactory("executeCase");
            const executeCase = await ExecuteCase.deploy();

            const executeCaseIface = new ethers.utils.Interface(executeCaseABI);
            const newData = 1024;
            const executeCasePayload = executeCaseIface.encodeFunctionData("setData",[newData]);

            await a3sWalletProxy.connect(entryPointProxy).executeUserOp(executeCase.address, 0, executeCasePayload);
            expect(await executeCase.getData()).to.equal(newData);
        });
    });

    describe("isValidSignature Function", () => {
        it("Func - support ERC1271 signature", async() => {
            const a3sWalletProxy = await ethers.getContractAt("A3SWallet", predictWalletAddress, walletOwner);

            const ExecuteCase = await ethers.getContractFactory("executeCase");
            const executeCase = await ExecuteCase.deploy();

            const TIMESTAMP = 1669607286;
            const hash = ethers.utils.solidityKeccak256(
                ["bytes", "uint256", "address"],
                [ethers.utils.toUtf8Bytes("A3S-ERC1271Verify"), TIMESTAMP, predictWalletAddress]
            );
            const ERC1271Hash = ethers.utils.solidityKeccak256(
                ["bytes", "bytes"],
                [ethers.utils.toUtf8Bytes("\x19Ethereum Signed Message:\n32"), hash]
            )
            const ERC1271Signature = await user1.signMessage(
                ethers.utils.arrayify(hash)
            );

            const executeCaseIface = new ethers.utils.Interface(executeCaseABI);
            const executeCasePayload = executeCaseIface.encodeFunctionData("callERC1271isValidSignature",[predictWalletAddress, ERC1271Hash, ERC1271Signature]);

            await expect(a3sWalletProxy.connect(entryPointProxy).executeUserOp(executeCase.address, 0, executeCasePayload)).to.be.revertedWith("A3SWallet: Invalid signature");

            console.log("walletOwner.address:", walletOwner.address);
            const newERC1271Signature = await walletOwner.signMessage(
                ethers.utils.arrayify(hash)
            );
            const newExecuteCasePayload = executeCaseIface.encodeFunctionData("callERC1271isValidSignature",[predictWalletAddress, ERC1271Hash, newERC1271Signature]);

            await a3sWalletProxy.connect(entryPointProxy).executeUserOp(executeCase.address, 0, newExecuteCasePayload)
        });
    });
});
