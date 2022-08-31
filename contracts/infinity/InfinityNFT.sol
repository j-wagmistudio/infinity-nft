// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../utils/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract InfinityNFT is ERC721, Ownable {
using Address for address payable;

    //UTILS

    enum Status {
        Pause,
        WhitelistSale,
        PublicSale
    }

    Status public contractStatus;

    //PRICES AND WITHDRAW ADDRESS

    AggregatorV3Interface private usdByEthFeed;

    AggregatorV3Interface private usdByEuroFeed;

    address public fundsReceiver = 0x8900a924E4B942F64F23b014687cB2b2B1624FAB;

    uint256 public priceInEuro = 1000;

    //SUPPLIES

    uint256 public saleSupply;

    uint256 public SALE_MAX_SUPPLY = 4960;

    uint256 public artistSupply;

    uint256 public ARTIST_MAX_SUPPLY = 40;

    uint256 public MAX_SUPPLY = SALE_MAX_SUPPLY + ARTIST_MAX_SUPPLY;

    //WHITELIST MINT RESTRICTIONS

    bytes32 public merkleRoot;

    mapping(bytes32 => bool) private usedTokens;

    //metadatas
    string public baseURI = "https://server.wagmi-studio.com/metadata/test/infTest/";

    /*
     * @param - usdByEthFeedAddress : chainlink usd/eth converter address
     * @param – usdByEuroFeedAddress: chainlink usd/euro converter address
     */
    constructor(address usdByEthFeedAddress, address usdByEuroFeedAddress)
    ERC721("InfTest 1", "INF")
        {
            usdByEthFeed = AggregatorV3Interface(usdByEthFeedAddress);
            usdByEuroFeed = AggregatorV3Interface(usdByEuroFeedAddress);
        }

    //SALE MINT FUNCTIONS

    function publicMint(address to, uint256 quantity) external payable {
        require(contractStatus == Status.PublicSale, "Public sale not enabled");
        require(balanceOf(to)+quantity<=3, "Mint limit reached");
        saleMint(to, quantity);
    }

    function whiteListAddressMint(uint256 quantity, bytes32[] calldata _proof) external payable {
        require(contractStatus == Status.WhitelistSale, "Whitelist sale not enabled");
        require(isWhitelistedAddress(msg.sender, _proof), "Invalid merkle proof");
        require(balanceOf(msg.sender)+quantity<=3, "Mint limit reached");
        saleMint(msg.sender, quantity);
    }

    function whiteListTokenMint(uint256 quantity, bytes32 token, bytes32[] calldata _proof) external payable {
        require(contractStatus == Status.WhitelistSale, "Whitelist sale not enabled");
        require(isWhitelistedToken(token, _proof), "Invalid merkle proof");
        require(!usedTokens[token], "Token already used");
        require(balanceOf(msg.sender)+quantity<=3, "Mint limit reached");
        usedTokens[token] = true;
        saleMint(msg.sender, quantity);
    }

    function saleMint(address to, uint256 quantity) private {
        require(quantity>0, "quantity must be positive");
        require(quantity+saleSupply<=SALE_MAX_SUPPLY, "sale max supply reached");
        uint256 priceInWei = getNftWeiPrice() * quantity;
        uint256 minPrice = (priceInWei * 995) / 1000;
        uint256 maxPrice = (priceInWei * 1005) / 1000;
        require(msg.value >= minPrice, "Not enough ETH");
        require(msg.value <= maxPrice, "Too much ETH");
        uncheckedSaleMint(to, quantity);
    }

    function uncheckedSaleMint(address to, uint256 quantity) private {
        unchecked {
            for(uint256 i = 0;i<quantity;i++){
                 uint256 index = saleSupply+i;
                _owners[index] = to;
                emit Transfer(address(0), to, index);
            }
            _balances[to] = _balances[to] + quantity;
            saleSupply = saleSupply + quantity;
        }
    }

    //ARTIST DROP FUNCTIONS

    function artistDrop(address artistAddress, uint256 quantity) external onlyOwner {
        require(quantity>0, "quantity must be positive");
        require(quantity<=3, "cannot mint more than 3");
        require(quantity+artistSupply<=ARTIST_MAX_SUPPLY, "artist max supply reached");
        uncheckedArtistMint(artistAddress, quantity);
    }

    function uncheckedArtistMint(address to, uint256 quantity) private {
        unchecked {
            for(uint256 i = 0;i<quantity;i++){
                uint256 index = artistSupply+i+SALE_MAX_SUPPLY;
                _owners[index] = to;
                emit Transfer(address(0), to, index);
            }
            _balances[to] = _balances[to] + quantity;
            artistSupply = artistSupply + quantity;
        }
    }

    //TOTAL SUPPLY REQUIRED FUNCTION
        
    function totalSupply() external view returns(uint256) {
        return saleSupply+artistSupply;
    }

    //ADMIN SETTERS
 
    function setStatus(uint256 step) external onlyOwner {
        contractStatus = Status(step);
    }

    function setMerkleRoot(bytes32 root) external onlyOwner {
        merkleRoot = root;
    }

    function setBaseURI(string memory uri) external onlyOwner {
        baseURI = uri;
    }
    
    function setPriceInEuro(uint256 price) external onlyOwner {
        priceInEuro = price;
    }

    function setUsdByEthFeed(address usdByEthFeedAddress) external onlyOwner {
        usdByEthFeed = AggregatorV3Interface(usdByEthFeedAddress);
    }

    function setUsdByEuroFeed(address usdByEuroFeedAddress) external onlyOwner {
        usdByEuroFeed = AggregatorV3Interface(usdByEuroFeedAddress);
    }

    //METADATA URI BUILDER

    function tokenURI(uint256 tokenId) public view override
        returns (string memory)
    {
        require(_exists(tokenId), "URI query for nonexistent token");
        // Concatenate the baseURI and the tokenId as the tokenId should
        // just be appended at the end to access the token metadata
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json"));
    }

    //PRICE CALCULATOR FUNCTIONS

    function getUsdByEth() private view returns (uint256) {
        (, int256 price, , , ) = usdByEthFeed.latestRoundData();
        return uint256(price);
    }

    function getUsdByEuro() private view returns (uint256) {
        (, int256 price, , , ) = usdByEuroFeed.latestRoundData();
        return uint256(price);
    }

    function getNftWeiPrice() public view returns (uint256) {
        uint256 priceInDollar = (priceInEuro * getUsdByEuro() * 10**18) / 10**usdByEuroFeed.decimals();
        uint256 weiPrice = (priceInDollar * 10**usdByEthFeed.decimals()) / getUsdByEth();
        return weiPrice;
    }

    //MERKLE TREE FUNCTIONS

    function isWhitelistedToken(bytes32 token, bytes32[] calldata _proof) private view returns(bool) {
        bytes32 tokenHash = keccak256(abi.encodePacked(token));
        return MerkleProof.verifyCalldata(_proof, merkleRoot, tokenHash);
    }
    
    function isWhitelistedAddress(address _address, bytes32[] calldata _proof) private view returns(bool) {
        bytes32 addressHash = keccak256(abi.encodePacked(_address));
        return MerkleProof.verifyCalldata(_proof, merkleRoot, addressHash);
    }

    //FUNDS WITHDRAW FUNCTION

    function retrieveFunds() external {
        require(
            msg.sender == owner() ||
            msg.sender == fundsReceiver,
            "Not allowed"
        );
        payable(fundsReceiver).sendValue(address(this).balance);
    }
}