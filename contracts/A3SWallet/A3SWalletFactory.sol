//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./A3SFeeHandler.sol";
import "./A3SWalletRecorder.sol";
import "./A3SWalletDeployer.sol";
import "./IA3SWalletFactory.sol";

contract A3SWalletFactory is
    IA3SWalletFactory,
    ERC721,
    A3SFeeHandler,
    A3SWalletRecorder,
    A3SWalletDeployer
{
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    constructor() ERC721("A3SProtocol", "A3S") {}

    /**
     * @notice Mint a new A3SWalletProxy NFT
     * @param to The receiver's address
     * @param salt The customize variable to influence the final A3SWalletProxy address
     */
    function safeMint(address to, bytes32 salt) external payable enoughtFee(1) {
        _safeMintWallet(to, salt);
    }

    /**
     * @notice Mint multiple A3SWalletProxy NFTs
     * @param to The receiver's address
     * @param salts The customize variable to influence the final A3SWalletProxies's address
     */
    function safeBatchMint(address to, bytes32[] calldata salts) external payable enoughtFee(salts.length)
    {
        uint256 amount = salts.length;
        for (uint256 index = 0; index < amount; index++) {
            _safeMintWallet(to, salts[index]);
        }
    }

    function getWalletOwnerOf(address wallet) external view returns (address) {
        return walletOwnerOf(wallet);
    }

    /**
     * @notice Deploy a new A3SWalletProxy (NFT) and assign it to the given receiver
     * @param to The receiver's address
     * @param salt The customize variable to influence the final A3SWalletProxy address
     */
    function _safeMintWallet(address to, bytes32 salt) internal {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        bytes32 mutantSalt = keccak256(abi.encodePacked(to, salt));
        address wallet = _createWallet(mutantSalt);
        _safeMint(to, tokenId);
        _setWalletRecord(tokenId, wallet);

        emit MintWallet(_msgSender(), to, wallet, tokenId);
    }

    /**
     * @notice Transfer multiple A3SWalletProxies from owner to receiver with given traget token ids
     * @dev If there is any tokenId is not vaild, the entire transaction will revert.
     * @param from The owner's address
     * @param to The receiver's address
     * @param tokenIds The ids of the A3SWalletProxies that will be transferred
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata tokenIds
    ) external {
        require(tokenIds.length <= balanceOf(from), "Not enough tokens");
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            safeTransferFrom(from, to, tokenIds[i]);
        }
    }
}
