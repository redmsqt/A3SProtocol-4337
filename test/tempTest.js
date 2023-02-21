const hre = require("hardhat");

const event_1 = "BuyTicket(uint256,address,uint256,uint256,uint256)";
const event_2 = "ClaimReward(uint256,address,uint256,uint256)";

async function main() {
    const hash1 = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes(event_1));
    const hash2 = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes(event_2));

    console.log("BuyTicket:", hash1);
    console.log("ClaimReward:", hash2);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

