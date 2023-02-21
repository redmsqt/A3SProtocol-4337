const { expect } = require("chai");
const { ethers } = require("hardhat");

const salt = "0x1234432155000000000000000000000000000000000000000000000000000000"; //bytes32 salt
const executeCaseABI = [
    "function getData() external view returns(uint256)",
    "function subData(uint256) external returns(uint256)",
    "function addData(uint256) external returns(uint256)",
    "function setData(uint256) external returns(uint256)"
];
const A3SWalletABI = [
    "function executeUserOp(address to, uint256 value, bytes data) external"
];
const Test20ABI = [
    "function approve(address spender, uint256 amount) public returns (bool)"
];

describe("EntryPoint", () => {
    let a3sWalletFactory;
    let entryPoint2;
    let entryPointProxy;

    let predictAddress;
    let UserOp;

    let executeCase;
    let testHelper;
    let Test20;
    let feedMock;

    let paymaster;
    let paymasterRequest;

    beforeEach(async () => {
        //deployment
        [deployer, user1, user2] = await ethers.getSigners();
        const A3SWalletFactory = await ethers.getContractFactory("A3SWalletFactory");
        a3sWalletFactory = await A3SWalletFactory.deploy();

        const EntryPoint = await ethers.getContractFactory("EntryPoint");
        const entryPoint = await EntryPoint.deploy(10, a3sWalletFactory.address);

        const EntryPointProxy = await ethers.getContractFactory("EntryPointProxy");
        entryPointProxy = await EntryPointProxy.deploy(entryPoint.address, "0x");

        const A3SWallet = await ethers.getContractFactory("A3SWallet");
        const a3sWallet = await A3SWallet.deploy(entryPointProxy.address, a3sWalletFactory.address);

        await a3sWalletFactory.setLogicAddress(a3sWallet.address);

        const ExecuteCase = await ethers.getContractFactory("executeCase");
        executeCase = await ExecuteCase.deploy();

        entryPoint2 = await ethers.getContractAt("EntryPoint", entryPointProxy.address, deployer)

        const TestHelper = await ethers.getContractFactory("testHelper");
        testHelper = await TestHelper.deploy();

        const TEST20 = await ethers.getContractFactory("Test20");
        Test20 = await TEST20.deploy();

        await Test20.transfer(deployer.address, 1000);
        await Test20.transfer(user1.address, 1000);

        //set FiatToken Detail
        await a3sWalletFactory.setFiatToken(Test20.address);
        await a3sWalletFactory.setFiatTokenFee(1);
        await a3sWalletFactory.setPlatfromTokenFee(1);
        await a3sWalletFactory.setWithdrawer(deployer.address);

        //assemble basic UserOp
        //predict A3SWallet address
        predictAddress = await a3sWalletFactory.predictWalletAddress(deployer.address, salt);

        //init callData
        const executeCaseIface = new ethers.utils.Interface(executeCaseABI);
        const a3sWalletIface = new ethers.utils.Interface(A3SWalletABI);

        const executeCasePayload = executeCaseIface.encodeFunctionData("setData", [1314]);
        const a3sWalletPayload = a3sWalletIface.encodeFunctionData("executeUserOp", [executeCase.address, 0, executeCasePayload]);

        //assemble
        UserOp = {
            sender: predictAddress,
            nonce: 0,
            initCode: salt,
            callData: a3sWalletPayload,
            callGasLimit: 10000000,
            verificationGasLimit: 1000000,
            preVerificationGas: 100000,
            maxFeePerGas: 300,
            maxPriorityFeePerGas: 10,
            paymasterAndData: "0x",
            signature: "0x"
        };

        const hash = await testHelper.testHash(UserOp);
        const chainId = await deployer.getChainId();
        const messageHash = ethers.utils.solidityKeccak256(
            ["bytes32", "address", "uint256"],
            [hash, entryPointProxy.address, chainId]
        );

        const sig = await deployer.signMessage(
            ethers.utils.arrayify(messageHash)
        );
        UserOp.signature = sig;

    });

    describe("Has no paymaster", () => {
        it("Func - _verifyOp/_createWalletIfNecessary: should be reverted for incorrect initCode", async () => {
            const salt1 = "0x1234";
            const salt2 = "0x12344321550000000000000000000000000000000000000000000000000000001234";
            UserOp.initCode = salt1;
            await expect(entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 })).revertedWith("A3SEntryPoint: initCode must be bytes32.");
            UserOp.initCode = salt2;
            await expect(entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 })).revertedWith("A3SEntryPoint: initCode must be bytes32.");
        });

        it("Func - _verifyOp/_validateWallet: should be reverted for wrong wallet ownership", async () => {
            await a3sWalletFactory.safeMint(deployer.address, salt);
            UserOp.initCode = "0x";
            const hash = await testHelper.testHash(UserOp);

            const chainId = await user1.getChainId();
            const requestHash = ethers.utils.solidityKeccak256(
                ["bytes32", "address", "uint256"],
                [hash, entryPointProxy.address, chainId]
            );

            const sig = await user1.signMessage(
                ethers.utils.arrayify(requestHash)
            );
            UserOp.signature = sig;

            await expect(entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 })).revertedWith("A3SEntryPoint: Invalid signature");
        });

        it("Func - _verifyOp/_validateWallet/validateUserOp[A3SWallet.sol]: should be reverted for wrong nonce.", async () => {
            //testQuestion
            await Test20.transfer(entryPointProxy.address, 1000);

            UserOp.nonce = 10;

            const hash = await testHelper.testHash(UserOp);
            const chainId = await deployer.getChainId();
            const requestHash = ethers.utils.solidityKeccak256(
                ["bytes32", "address", "uint256"],
                [hash, entryPointProxy.address, chainId]
            );

            const sig = await deployer.signMessage(
                ethers.utils.arrayify(requestHash)
            );
            UserOp.signature = sig;

            await expect(entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 })).revertedWith("A3SWallet: Invalid nonce");
        });

        it("Func - _verifyOp/_validateWallet/validateUserOp[A3SWallet.sol]: should be reverted for refund fail", async () => {
            //testQuestion
            await Test20.transfer(entryPointProxy.address, 1000);

            await expect(entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 })).revertedWith("Address: insufficient balance");
        });

        it("Func - _executeOp: execution should be run successfully", async () => {
            const transferTx = {
                to: predictAddress,
                value: ethers.utils.parseEther("0.02")
            }
            await deployer.sendTransaction(transferTx);
            //testQuestion
            await Test20.transfer(entryPointProxy.address, 1000);

            await entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 });

            expect(await executeCase.getData()).to.equal(1314);
        });
    });

    describe("Has a paymaster", () => {
        beforeEach(async () => {
            //paymasterAndData = paymasterAddr + Fee + paymasterMode + token + AggregatorV3Interface_feed + signature
            //deploy paymaster, paymaster's owner to deployer.address
            const Paymaster = await ethers.getContractFactory("Paymaster");
            paymaster = await Paymaster.deploy(entryPointProxy.address, deployer.address);

            const FeedMock = await ethers.getContractFactory("feedMock");
            feedMock = await FeedMock.deploy();

            const Fee = 1;
            const token = Test20.address;
            const feed = feedMock.address;

            paymasterRequest = await testHelper.testEncodePaymasterRequest(UserOp, paymaster.address, Fee, token, feed);
            const paymasterSignature = await deployer.signMessage(
                ethers.utils.arrayify(paymasterRequest)
            );

            const paymasterData = await testHelper.testPaymasterData(Fee, token, feed, paymasterSignature);
            const paymasterAndData = paymaster.address + paymasterData.substring(2,);

            UserOp.paymasterAndData = paymasterAndData;

            const hash = await testHelper.testHash(UserOp);
            const chainId = await deployer.getChainId();
            const messageHash = ethers.utils.solidityKeccak256(
                ["bytes32", "address", "uint256"],
                [hash, entryPointProxy.address, chainId]
            );

            const sig = await deployer.signMessage(
                ethers.utils.arrayify(messageHash)
            );

            UserOp.signature = sig;

            await Test20.transfer(entryPointProxy.address, 1000);
        });

        it("Func - _verifyOp/_validatePaymaster: should be reverted with no stake in EntryPoint", async () => {
            await expect(entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 })).revertedWith("A3SEntryPoint: Not staked.");
        });

        it("Func - _verifyOp/_validatePaymaster: should be reverted with insufficient stake in EntryPoint", async () => {
            await entryPoint2.addStake(15, paymaster.address, { value: ethers.utils.parseEther("0.00000000001") });

            await expect(entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 })).revertedWith("Staking: Insufficient stake");
        });

        it("Func - _verifyOp/_validatePaymaster/validatePaymasterUserOp[Paymaster.sol]: should be reverted with wrong verifyingSigner", async () => {
            const Fee = 1;
            const token = Test20.address;
            const feed = feedMock.address;

            const paymasterSignature = await user1.signMessage(
                ethers.utils.arrayify(paymasterRequest)
            );

            const paymasterData = await testHelper.testPaymasterData(Fee, token, feed, paymasterSignature);
            const paymasterAndData = paymaster.address + paymasterData.substring(2,);

            UserOp.paymasterAndData = paymasterAndData;

            const hash = await testHelper.testHash(UserOp);
            const chainId = await deployer.getChainId();
            const messageHash = ethers.utils.solidityKeccak256(
                ["bytes32", "address", "uint256"],
                [hash, entryPointProxy.address, chainId]
            );

            const sig = await deployer.signMessage(
                ethers.utils.arrayify(messageHash)
            );

            UserOp.signature = sig;

            await entryPoint2.addStake(15, paymaster.address, { value: ethers.utils.parseEther("0.01") });

            await expect(entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 })).revertedWith("Paymaster: Invalid signature");
        });

        it("Func - _verifyOp/validatePaymaster/validatePaymasterUserOp[Paymaster.sol]: should be reverted with insufficient A3SWallet's deposit in Paymaster", async () => {
            await entryPoint2.addStake(15, paymaster.address, { value: ethers.utils.parseEther("0.01") });

            await Test20.approve(paymaster.address, 1000);
            await paymaster.addDepositFor(Test20.address, predictAddress, 10);

            await expect(entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 })).revertedWith("Paymaster: Not enough deposit");
        });

        it("Func - _executePostOp/postOp[Paymaster.sol]: should be refund ERC20Token successfully when A3SWallet has enough token", async () => {
            //A3SWallet approve paymaster some token
            const Test20Iface = new ethers.utils.Interface(Test20ABI);
            const a3sWalletIface = new ethers.utils.Interface(A3SWalletABI);

            const Test20Payload = Test20Iface.encodeFunctionData("approve", [paymaster.address, 100]);

            const a3sWalletPayload = a3sWalletIface.encodeFunctionData(
                "executeUserOp", [Test20.address, 0, Test20Payload]
            );

            let preUserOp = Object.assign({}, UserOp);
            preUserOp.callData = a3sWalletPayload;
            preUserOp.paymasterAndData = "0x";

            const hash = await testHelper.testHash(preUserOp);
            const chainId = await deployer.getChainId();
            const messageHash = ethers.utils.solidityKeccak256(
                ["bytes32", "address", "uint256"],
                [hash, entryPointProxy.address, chainId]
            );

            const sig = await deployer.signMessage(
                ethers.utils.arrayify(messageHash)
            );

            preUserOp.signature = sig;

            const transferTx = {
                to: predictAddress,
                value: ethers.utils.parseEther("0.02")
            }
            await deployer.sendTransaction(transferTx);

            await entryPoint2.handleOps([preUserOp], deployer.address, { gasLimit: 15000000 });

            expect(await Test20.allowance(predictAddress, paymaster.address)).to.equal(100);

            //execute another UserOp for main call
            await entryPoint2.addStake(15, paymaster.address, { value: ethers.utils.parseEther("0.01") });

            await Test20.approve(paymaster.address, 1000);
            await paymaster.addDepositFor(Test20.address, predictAddress, 500);

            await Test20.transfer(predictAddress, 1000);

            UserOp.nonce += 1;
            UserOp.initCode = "0x";

            const Fee = 1;
            const token = Test20.address;
            const feed = feedMock.address;

            const newPaymasterRequest = await testHelper.testEncodePaymasterRequest(UserOp, paymaster.address, Fee, token, feed);
            const paymasterSignature = await deployer.signMessage(
                ethers.utils.arrayify(newPaymasterRequest)
            );

            const paymasterData = await testHelper.testPaymasterData(Fee, token, feed, paymasterSignature);
            const paymasterAndData = paymaster.address + paymasterData.substring(2,);

            UserOp.paymasterAndData = paymasterAndData;

            const hash2 = await testHelper.testHash(UserOp);
            const chainId2 = await deployer.getChainId();
            const messageHash2 = ethers.utils.solidityKeccak256(
                ["bytes32", "address", "uint256"],
                [hash2, entryPointProxy.address, chainId2]
            );

            const sig2 = await deployer.signMessage(
                ethers.utils.arrayify(messageHash2)
            );
        
            UserOp.signature = sig2;

            await entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 });
            expect(await executeCase.getData()).to.equal(1314);


            const balanceOfPaymasterOwner = await paymaster.getDepositInfo(Test20.address, deployer.address);
            expect(balanceOfPaymasterOwner.amount).to.equal(2);

            expect(await Test20.balanceOf(predictAddress)).to.equal(998);
        });

        it("Func - _executePostOp/postOp[Paymaster.sol]: should be refund ERC20Token successfully when A3SWallet has insufficient token", async () => {
            await entryPoint2.addStake(15, paymaster.address, { value: ethers.utils.parseEther("0.01") });

            await Test20.approve(paymaster.address, 1000);
            await paymaster.addDepositFor(Test20.address, predictAddress, 500);

            await entryPoint2.handleOps([UserOp], deployer.address, { gasLimit: 15000000 });
            expect(await executeCase.getData()).to.equal(1314);

            const balanceOfPaymasterOwner = await paymaster.getDepositInfo(Test20.address, deployer.address);
            expect(balanceOfPaymasterOwner.amount).to.equal(8);
        });
    });
});
