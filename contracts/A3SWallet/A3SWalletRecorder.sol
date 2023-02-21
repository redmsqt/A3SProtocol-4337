//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

abstract contract A3SWalletRecorder is ERC721 {
    // Mapping from token ID to wallet address
    mapping(uint256 => address) private _wallets;

    // Mapping from  wallet address to token ID
    mapping(address => uint256) private _walletsId;

    /**
     * @notice Set mapping relationship between wallet address and responding token id
     * @param tokenId The token id of the wallet
     * @param wallet The address of the wallet
     */
    function _setWalletRecord(uint256 tokenId, address wallet) internal {
        require(tokenId != 0, "A3S: token id can not be 0");
        require(wallet != address(0), "A3S: wallet address can not be 0");

        _wallets[tokenId] = wallet;
        _walletsId[wallet] = tokenId;
    }

    /**
     * @notice Return the wallet address of the tokenId
     */
    function walletOf(uint256 tokenId) public view virtual returns (address) {
        return _wallets[tokenId];
    }

    /**
     * @notice Return the tokenId of the wallet
     */
    function walletIdOf(address wallet) public view virtual returns (uint256) {
        return _walletsId[wallet];
    }

    /**
     * @notice Return the owner of the wallet
     */
    function walletOwnerOf(address wallet)
        public
        view
        virtual
        returns (address)
    {
        return ownerOf(walletIdOf(wallet));
    }
}
