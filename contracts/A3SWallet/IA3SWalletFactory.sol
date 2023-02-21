//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IA3SWalletFactory {
    event MintWallet(address from, address to, address wallet, uint256 tokenId);

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata tokenIds
    ) external;

    function safeBatchMint(address to, bytes32[] calldata salts) external payable;

    function safeMint(address to, bytes32 salt) external payable;

    function getWalletOwnerOf(address wallet) external view returns (address);
}