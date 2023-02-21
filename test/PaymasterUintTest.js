const { expect } = require("chai");
const { ethers } = require("hardhat");

const SALT = "0x1234432112340000000000000000000000000000000000000000000000000000";
const REQUEST_ID = "0x1234000000000000000000000000000000000000000000000000000000000000";
const CALLDATA = "0x1234";

describe("Paymaster", () => {
    let paymaster;
    let Test20;
    let feedMock;
    let testHelper;
    let UserOp;
    let paymasterRequest;

    beforeEach(async () => {
        //deploy
        [deployer, entryPointProxy, verifyingSigner, walletOwner, A3SWallet, user1, user2] = await ethers.getSigners();

        const Paymaster = await ethers.getContractFactory("Paymaster");
        paymaster = await Paymaster.deploy(entryPointProxy.address, verifyingSigner.address);

        const TEST20 = await ethers.getContractFactory("Test20");
        Test20 = await TEST20.deploy();

        const TestHelper = await ethers.getContractFactory("testHelper");
        testHelper = await TestHelper.deploy();

        const FeedMock = await ethers.getContractFactory("feedMock");
        feedMock = await FeedMock.deploy();

        //assemble basic UserOp
        UserOp = {
            sender: A3SWallet.address,
            nonce: 0,
            initCode: SALT,
            callData: CALLDATA,
            callGasLimit: 10000000,
            verificationGasLimit: 1000000,
            preVerificationGas: 100000,
            maxFeePerGas: 300,
            maxPriorityFeePerGas: 10,
            paymasterAndData: "0x",
            signature: "0x"
        };
        //paymasterAndData = paymasterAddr + Fee + paymasterMode + token + AggregatorV3Interface_feed + signature
        const Fee = 1;
        const token = Test20.address;
        const feed = feedMock.address;

        paymasterRequest = await testHelper.testEncodePaymasterRequest(UserOp, paymaster.address, Fee, token, feed);

        const paymasterSignature = await verifyingSigner.signMessage(
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
    });

    describe("Support the circulation of multiple cryptocurrencies", () => {
        it("Func - ETH", async () => {
            const transferETHTx = {
                to: paymaster.address,
                value: ethers.utils.parseEther("1.0")
            }

            expect(await deployer.sendTransaction(transferETHTx)).to.changeEtherBalance(paymaster.address, ethers.utils.parseEther("1.0"));
        });

        it("Func - ERC20 Token", async () => {
            const transferAmount = 100;

            expect(await Test20.transfer(paymaster.address, transferAmount)).to.changeTokenBalance(Test20, paymaster.address, transferAmount);
        });
    });

    describe("addDepositFor", () => {
        it("Func - msg.sender has insufficient balance", async () => {
            await expect(paymaster.connect(user1).addDepositFor(Test20.address, user1.address, 100)).to.revertedWith("Paymaster: insufficient balance.");
        });

        it("Func - token.safeTransferFrom executes successfully", async () => {
            const transferAmount = 100;

            expect(await Test20.transfer(user1.address, transferAmount)).to.changeTokenBalance(Test20, user1.address, transferAmount);

            await Test20.connect(user1).approve(paymaster.address, transferAmount);
            expect(await paymaster.connect(user1).addDepositFor(Test20.address, user1.address, transferAmount)).to.changeTokenBalance(Test20, paymaster.address, transferAmount);
        });

        it("Func - execute lockTokenDeposit when account is msg.sender", async () => {
            const transferAmount = 100;

            await Test20.transfer(user1.address, transferAmount);

            await Test20.connect(user1).approve(paymaster.address, transferAmount);
            await paymaster.connect(user1).addDepositFor(Test20.address, user1.address, transferAmount);

            const depositInfo = await paymaster.connect(user1).getDepositInfo(Test20.address, user1.address);
            expect(depositInfo.amount).to.equal(transferAmount);
            expect(depositInfo._unlockBlock).to.equal(0);
        });
    });

    describe("withdrawTokensTo", () => {
        let transferAmount;

        beforeEach(async () => {
            transferAmount = 100;

            await Test20.transfer(user1.address, transferAmount);

            await Test20.connect(user1).approve(paymaster.address, transferAmount);
            await paymaster.connect(user1).addDepositFor(Test20.address, user1.address, transferAmount);
        });

        it("Func - must unlockTokenDeposit before withdraw", async () => {
            await expect(paymaster.connect(user1).withdrawTokensTo(Test20.address, user2.address, transferAmount)).to.revertedWith("Paymaster: must unlockTokenDeposit.");
        });

        it("Func - account has insufficient balance", async () => {
            await paymaster.connect(user1).unlockTokenDeposit();

            await expect(paymaster.connect(user1).withdrawTokensTo(Test20.address, user2.address, transferAmount * 2)).to.revertedWith("Paymaster: insufficient balance.");
        });

        it("Func - withdraw token successfully", async () => {
            await paymaster.connect(user1).unlockTokenDeposit();

            await expect(paymaster.connect(user1).withdrawTokensTo(Test20.address, user2.address, transferAmount)).to.changeTokenBalance(Test20, user2.address, transferAmount);
        });
    });

    describe("validatePaymasterUserOp", () => {
        let maxCost = 100000000000000; //1*e14

        it("Func - should be reverted with Invalid signature", async () => {
            const newPaymasterSignature = await user1.signMessage(
                ethers.utils.arrayify(paymasterRequest)
            );

            const Fee = 1;
            const token = Test20.address;
            const feed = feedMock.address;

            const paymasterData = await testHelper.testPaymasterData(Fee, token, feed, newPaymasterSignature);
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

            await expect(paymaster.validatePaymasterUserOp(UserOp, REQUEST_ID, maxCost)).to.revertedWith("Paymaster: Invalid signature");
        });

        it("Func - should be reverted with unlocked deposit", async () => {
            await paymaster.connect(A3SWallet).unlockTokenDeposit();

            await expect(paymaster.validatePaymasterUserOp(UserOp, REQUEST_ID, maxCost)).to.revertedWith("Paymaster: Deposit not locked");
        });

        it("Func - should be reverted with insufficient deposit", async () => {
            await paymaster.connect(A3SWallet).lockTokenDeposit();

            await expect(paymaster.validatePaymasterUserOp(UserOp, REQUEST_ID, maxCost)).to.revertedWith("Paymaster: Not enough deposit");
        });
    });

    describe("postOp", () => {
        let context;
        let actualGasCost;

        it("Func - sender must be entryPoint", async () => {
            context = "0x1234";
            actualGasCost = 100;

            await expect(paymaster.postOp(ethers.BigNumber.from("0"), context, actualGasCost)).to.revertedWith("Paymaster: Sender must be entrypoint");
        });

        it("Func - execute successfully when A3SWallet has enough balance", async () => {
            const feedReturn = await feedMock.latestRoundData();
            const rate = feedReturn.answer;
            const paymasterData = {
                fee: 1,
                mode: ethers.BigNumber.from("0"),
                token: Test20.address,
                feed: feedMock.address,
                signature: "0x1234"
            };

            const mode = ethers.BigNumber.from("0");
            context = await testHelper.testPaymasterContext(UserOp, paymasterData, rate);
            actualGasCost = 100;

            const totalTokenFee = await testHelper.testCalcTotalTokenFee(
                paymasterData.mode,
                rate,
                actualGasCost,
                paymasterData.fee
            );
            console.log("totalTokenFee:", totalTokenFee);

            await Test20.transfer(A3SWallet.address, totalTokenFee);
            await Test20.connect(A3SWallet).approve(paymaster.address, totalTokenFee);

            await expect(paymaster.connect(entryPointProxy).postOp(mode, context, actualGasCost)).to.changeTokenBalance(Test20, paymaster.address, totalTokenFee);
        });

        it("Func - execute successfully when A3SWallet has insufficient balance", async () => {
            const feedReturn = await feedMock.latestRoundData();
            const rate = feedReturn.answer;
            const paymasterData = {
                fee: 1,
                mode: ethers.BigNumber.from("0"),
                token: Test20.address,
                feed: feedMock.address,
                signature: "0x1234"
            };

            const mode = ethers.BigNumber.from("2");
            context = await testHelper.testPaymasterContext(UserOp, paymasterData, rate);
            actualGasCost = 100;

            const totalTokenFee = await testHelper.testCalcTotalTokenFee(
                paymasterData.mode,
                rate,
                actualGasCost,
                paymasterData.fee
            );
            console.log("totalTokenFee:", totalTokenFee);
            
            await Test20.approve(paymaster.address, totalTokenFee);
            await paymaster.addDepositFor(Test20.address, A3SWallet.address, totalTokenFee);

            await paymaster.connect(entryPointProxy).postOp(mode, context, actualGasCost);

            const depositInfo = await paymaster.getDepositInfo(Test20.address, verifyingSigner.address);
            expect(depositInfo.amount).to.equal(totalTokenFee);
        });
    });

    describe("set private variable", () => {
        it("Func - only owner can set private variable", async () => {
            const newEntryPointAddress = user1.address;
            const newVerifyingSignerAddress = user1.address;

            await expect(paymaster.connect(user1).setEntryPoint(newEntryPointAddress)).to.revertedWith("Ownable: caller is not the owner");
            await expect(paymaster.connect(user1).setVerifyingSigner(newVerifyingSignerAddress)).to.revertedWith("Ownable: caller is not the owner");

            await paymaster.connect(deployer).setEntryPoint(newEntryPointAddress);
            await paymaster.connect(deployer).setVerifyingSigner(newVerifyingSignerAddress);

            expect(await paymaster.getEntryPoint()).to.equal(newEntryPointAddress);
            expect(await paymaster.getVerifyingSigner()).to.equal(newVerifyingSignerAddress);
        });
    });
});