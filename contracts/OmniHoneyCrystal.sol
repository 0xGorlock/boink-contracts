// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ONFT721 } from "@layerzerolabs/solidity-examples/contracts/token/onft721/ONFT721.sol";

contract OmniHoneyCrystal is ONFT721 {
    string public baseTokenURI;
    uint256 public constant maxMint = 4000;
    uint256 public totalMinted;
    uint256 public mintPrice;

    constructor(
        string memory baseURI,
        string memory _name,
        string memory _symbol,
        uint256 _minGasToTransfer,
        address _lzEndpoint
    ) ONFT721(_name, _symbol, _minGasToTransfer, _lzEndpoint) {
        setBaseURI(baseURI);
    }

    function walletOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        uint256[] memory tokensId = new uint256[](tokenCount);

        if (tokenCount == 0) {
            return tokensId;
        }

        uint256 key = 0;
        for (uint256 i = 0; i < maxMint; i++) {
            if (ownerOf(i) == _owner) {
                tokensId[key] = i;
                key++;
                if (key == tokenCount) {
                    break;
                }
            }
        }

        return tokensId;
    }

    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function mint() external payable {
        require(msg.value >= mintPrice, "Not enough ether sent");
        require(totalMinted < maxMint, "Max supply reached");

        uint256 tokenId = totalMinted + 1;
        totalMinted++;
        _safeMint(msg.sender, tokenId);
    }

    function estimateGasBridgeFee(
        uint16 _dstChainId,
        bool _useZro,
        bytes memory _adapterParams
    ) public view virtual returns (uint256 nativeFee, uint256 zroFee) {
        bytes memory payload = abi.encode(msg.sender, 0);
        return lzEndpoint.estimateFees(_dstChainId, payable(address(this)), payload, _useZro, _adapterParams);
    }

    function bridgeGas(
        uint16 _dstChainId,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) public payable {
        _checkGasLimit(_dstChainId, FUNCTION_TYPE_SEND, _adapterParams, dstChainIdToTransferGas[_dstChainId]);
        _lzSend(
            _dstChainId,
            abi.encode(msg.sender, 0),
            payable(address(this)),
            _zroPaymentAddress,
            _adapterParams,
            msg.value
        );
    }

    function setPrice(uint256 _price) external onlyOwner {
        mintPrice = _price;
    }

    function withdrawFees() external onlyOwner {
        require(address(this).balance > 0, "No fees to withdraw");
        payable(owner()).transfer(address(this).balance);
    }
}
