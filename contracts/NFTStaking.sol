// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface INFTStaking {
    function isEligibleForStaking(address nftAddress) external view returns (bool);
    function whitelistNFT(address nftAddress) external;
    function removeWhitelistNFT(address nftAddress) external;
    function getPendingRewards(address account) external view returns (uint256);
    function stake(address[] calldata nftAddresses, uint256[] calldata tokenIds) external;
    function unstake(address[] calldata nftAddresses, uint256[] calldata tokenIds) external;
    function claim() external returns (uint256);
}

/// @title NFT Staking Contract
/// @notice Manages the staking of NFTs for rewards
/// @dev Implements IERC721Receiver for handling safe transfers of NFTs
contract NFTStaking is INFTStaking, IERC721Receiver, ReentrancyGuard, Ownable { 
    mapping(address => bool) public whitelistedNFTs;
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    uint256 private constant MULTIPLIER = 1e18;
    uint256 private rewardIndex;
    
    mapping(address => uint256) private rewardIndexOf;
    mapping(address => uint256) private earned;
    mapping(address => uint256) private totalClaimedRewards;
    mapping(address => StakedNFT[]) private stakedNFTs;

    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event Claimed(address indexed user, uint256 amount);
    event Received(uint256 amount, uint256 rewardIndex);

    struct StakedNFT {
        address nftAddress;
        uint256 tokenId;
    }

    struct UserInfo {
        uint256 stakedNFTCount;
        uint256 pendingRewards;
        uint256 totalClaimedRewards;
    }

    /// @notice Receives ETH and updates the reward index
    receive() external payable {
        if (totalSupply > 0) {
            rewardIndex += (msg.value * MULTIPLIER) / totalSupply;
        }
        emit Received(msg.value, rewardIndex);
    }

    /// @notice Returns user information including staked NFT count and rewards
    /// @param user Address of the user
    /// @return UserInfo containing staked NFT count, pending rewards, and total claimed rewards
    function getUserInfo(address user) public view returns (UserInfo memory) {
        return UserInfo({
            stakedNFTCount: balanceOf[user],
            pendingRewards: _calculateRewards(user) + earned[user],
            totalClaimedRewards: earned[user]
        });
    }

    /// @notice Checks if an NFT address is eligible for staking
    /// @param nftAddress The address of the NFT contract
    /// @return True if the NFT is eligible for staking, false otherwise
    function isEligibleForStaking(address nftAddress) public view returns (bool) {
        return whitelistedNFTs[nftAddress];
    }

    /// @notice Returns the staked NFTs of a user
    /// @param _user Address of the user
    /// @return Array of StakedNFTs owned by the user
    function viewStakedNFTs(address _user) public view returns (StakedNFT[] memory) {
        return stakedNFTs[_user];
    }

    /// @notice Returns the count of staked NFTs for a user
    /// @param _user Address of the user
    /// @return The count of staked NFTs
    function countStakedNFTs(address _user) public view returns (uint256) {
        return stakedNFTs[_user].length;
    }

    /// @notice Whitelists an NFT contract for staking
    /// @param nftAddress The address of the NFT contract to whitelist
    function whitelistNFT(address nftAddress) external onlyOwner {
        whitelistedNFTs[nftAddress] = true;
    }

    /// @notice Removes an NFT contract from the whitelist
    /// @param nftAddress The address of the NFT contract to remove
    function removeWhitelistNFT(address nftAddress) external onlyOwner {
        whitelistedNFTs[nftAddress] = false;
    }

    /// @notice Returns the pending rewards for an account
    /// @param account The address of the account
    /// @return The amount of pending rewards
    function getPendingRewards(address account) external view returns (uint256) {
        uint256 calculatedRewards = _calculateRewards(account);
        return earned[account] + calculatedRewards;
    }

    /// @notice Returns the total claimed rewards for a user
    /// @param user The address of the user
    /// @return The total amount of rewards claimed by the user
    function getTotalClaimedRewards(address user) external view returns (uint256) {
        return totalClaimedRewards[user];
    }

    /// @notice Calculates the rewards accumulated for a given account
    /// @param account The address of the account
    /// @return The calculated amount of rewards
    function _calculateRewards(address account) private view returns (uint256) {
        uint256 nftCount = balanceOf[account];
        return (nftCount * (rewardIndex - rewardIndexOf[account])) / MULTIPLIER;
    }

    /// @notice Updates the reward calculation for an account
    /// @param account The address of the account
    function _updateRewards(address account) private {
        earned[account] += _calculateRewards(account);
        rewardIndexOf[account] = rewardIndex;
    }
    
    /// @notice Removes a staked NFT from the user's staked NFT list
    /// @dev Iterates over the user's staked NFT list to find and remove the specified NFT
    /// @param user Address of the user who is unstaking the NFT
    /// @param nftAddress Address of the NFT contract
    /// @param tokenId Token ID of the NFT being unstaked    
    function _removeStakedNFT(address user, address nftAddress, uint256 tokenId) private {
        uint256 length = stakedNFTs[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (stakedNFTs[user][i].nftAddress == nftAddress && stakedNFTs[user][i].tokenId == tokenId) {
                stakedNFTs[user][i] = stakedNFTs[user][length - 1];
                stakedNFTs[user].pop();
                break;
            }
        }
    }

    /// @notice Handles ERC721 token reception
    /// @dev Required by the IERC721Receiver interface
    /// @param operator The address which called `safeTransferFrom` function
    /// @param tokenId The NFT token ID being transferred
    /// @return bytes4 indicating the function's success
    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) public override returns (bytes4) {
        require(operator == address(this), "NFT must be staked through the stake function");
        require(isEligibleForStaking(msg.sender), "NFT is not eligible for staking");

        return this.onERC721Received.selector;
    }

    /// @notice Allows users to stake their NFTs
    /// @param nftAddresses Array of NFT contract addresses
    /// @param tokenIds Array of token IDs corresponding to the NFT addresses
    function stake(address[] calldata nftAddresses, uint256[] calldata tokenIds) external nonReentrant {
        require(nftAddresses.length == tokenIds.length, "Mismatched arrays length");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(whitelistedNFTs[nftAddresses[i]], "NFT contract not whitelisted");
            IERC721 nftContract = IERC721(nftAddresses[i]);
            require(nftContract.ownerOf(tokenIds[i]) == msg.sender, "Not the owner of the NFT");
            nftContract.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
            stakedNFTs[msg.sender].push(StakedNFT(nftAddresses[i], tokenIds[i]));
            emit Staked(msg.sender, tokenIds[i]);
        }

        _updateRewards(msg.sender);
        balanceOf[msg.sender] += tokenIds.length;
        totalSupply += tokenIds.length;
    }

    /// @notice Allows users to unstake their NFTs
    /// @param nftAddresses Array of NFT contract addresses
    /// @param tokenIds Array of token IDs corresponding to the NFT addresses
    function unstake(address[] calldata nftAddresses, uint256[] calldata tokenIds) external nonReentrant {
        require(nftAddresses.length == tokenIds.length, "Mismatched arrays length");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721 nftContract = IERC721(nftAddresses[i]);
            require(nftContract.ownerOf(tokenIds[i]) == address(this), "NFT is not staked here");
            nftContract.safeTransferFrom(address(this), msg.sender, tokenIds[i]);
            _removeStakedNFT(msg.sender, nftAddresses[i], tokenIds[i]);
            emit Unstaked(msg.sender, tokenIds[i]);
        }

        _updateRewards(msg.sender);
        balanceOf[msg.sender] -= tokenIds.length;
        totalSupply -= tokenIds.length;
    }

    /// @notice Allows users to claim their staking rewards
    /// @return The amount of rewards claimed
    function claim() external nonReentrant returns (uint256) {
        _updateRewards(msg.sender);

        uint256 reward = earned[msg.sender];
        if (reward > 0) {
            earned[msg.sender] = 0;
            totalClaimedRewards[msg.sender] += reward;
            payable(msg.sender).transfer(reward);
            
            emit Claimed(msg.sender, reward);
        }

        return reward;
    }
}
