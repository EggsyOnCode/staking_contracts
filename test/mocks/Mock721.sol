// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MyNFT is ERC721, ERC721Enumerable, Ownable {
    uint256 private _tokenId;

    IERC20 public USDC;

    uint256 public constant MAX_NFTS = 7777;
    uint256 public maxPerTx = 20;
    uint256 public price = 500 ether; // 500 USDC

    string private baseTokenURI;

    event MyNFTMinted(uint256 tokenId);

    constructor(string memory baseURI, address _USDC) ERC721("MyNFT", "NFT") Ownable(msg.sender) {
        setBaseURI(baseURI);
        USDC = IERC20(_USDC);
    }

    // Get token Ids of all tokens owned by _owner
    function walletOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokensId;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    function setPrice(uint256 _newPrice) public onlyOwner {
        price = _newPrice;
    }

    function withdrawAll() public onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    function withdrawToken() public onlyOwner {
        uint256 balance = IERC20(address(USDC)).balanceOf(address(this));
        IERC20(address(USDC)).transfer(msg.sender, balance);
    }

    function mint(uint256 _count) external {
        require(_count > 0 && _count <= maxPerTx, "Min & Max NFT count per transaction");
        require(totalSupply() + _count <= MAX_NFTS, "Transaction will exceed maximum supply of NFTs");
        require(USDC.balanceOf(msg.sender) >= price * _count, "[MINT] Insufficient funds to mint!");

        uint256 _amount = price * _count;
        USDC.transferFrom(msg.sender, address(this), _amount);

        address _to = msg.sender;
        for (uint256 i = 0; i < _count; i++) {
            _mint(_to);
        }
    }

    function premintNFTs(address _to, uint256 _count) external onlyOwner {
        _preMint(_to, _count);
    }

    function safeTransferNFTs(uint256[] memory _tokenIds, address _to) external {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (ownerOf(_tokenIds[i]) == msg.sender) {
                _safeTransfer(msg.sender, _to, _tokenIds[i], "");
            }
        }
    }

    function _mint(address _to) private {
        _tokenId++;
        uint256 tokenId = _tokenId;
        _safeMint(_to, tokenId);
        emit MyNFTMinted(tokenId);
    }

    function _preMint(address _to, uint256 _preCount) private {
        for (uint256 i = 0; i < _preCount; i++) {
            _mint(_to);
        }
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
