// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Interface for Boink token
interface IStakingToken is IERC20 {
    function getMaxWallet() external view returns (uint256);
}

interface IBoinkRewardStaking {
    function initialize(address _stakingToken, address _rewardToken, address _gameContract) external;
    function getPendingRewards(address account) external view returns (uint256);
    function getTotalClaimedRewards(address user) external view returns (uint256);
    function depositRewards(uint256 amount) external;
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claim() external returns (uint256);
    function emergencyWithdrawEth() external;
}

/// @title Boink Reward Staking Contract
/// @notice Handles staking, unstaking, and reward distribution for the Boink game
/// @dev Inherits from ReentrancyGuard and Ownable for security purposes
contract BoinkRewardStaking is IBoinkRewardStaking, ReentrancyGuard, Ownable { 
    IStakingToken public stakingToken;
    address public gameContract;
    IERC20 public rewardToken;

    bool public initialized = false;

    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    uint256 private constant MULTIPLIER = 1e18;
    uint256 private rewardIndex;
    mapping(address => uint256) private rewardIndexOf;
    mapping(address => uint256) private earned;
    mapping(address => uint256) private rewardsClaimed;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
    event RewardsDeposited(address indexed user, uint256 amount);

    /// @notice Checks if the contract is initialized before executing functions
    modifier onlyInitialized() {
        require(initialized, "Contract not initialized");
        _;
    }

    /// @notice Checks if the caller is the game contract
    modifier onlyGameContract() {
        require(msg.sender == gameContract, "Caller is not the game contract");
        _;
    }
    
    /// @notice Initializes the staking contract with tokens and game contract address
    /// @param _stakingToken Token used for staking
    /// @param _rewardToken Token used for rewards
    /// @param _gameContract Address of the game contract
    function initialize(
        address _stakingToken,
        address _rewardToken,
        address _gameContract
    ) external onlyOwner {
        require(!initialized, "Contract already initialized");
        stakingToken = IStakingToken(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        gameContract = _gameContract;
        initialized = true;
    }

    /// @notice Returns pending rewards for an account
    /// @param account The address of the account to check
    /// @return The amount of pending rewards for the account
    function getPendingRewards(address account) external view returns (uint256) {
        uint256 calculatedRewards = _calculateRewards(account);
        return earned[account] + calculatedRewards;
    }

    /// @notice Returns total claimed rewards for a user
    /// @param user The address of the user to check
    /// @return The total amount of rewards claimed by the user
    function getTotalClaimedRewards(address user) external view returns (uint256) {
        return rewardsClaimed[user];
    }

    /// @notice Calculates the rewards accumulated for a given account
    /// @dev This function computes the rewards based on the current reward index and the account's stake
    /// @param account The address of the account for which to calculate rewards
    /// @return The calculated amount of rewards for the account
    function _calculateRewards(address account) private view returns (uint256) {
        uint256 shares = balanceOf[account];
        return (shares * (rewardIndex - rewardIndexOf[account])) / MULTIPLIER;
    }

    /// @notice Calculates and updates rewards for an account
    /// @param account The address of the account to update
    function _updateRewards(address account) private {
        earned[account] += _calculateRewards(account);
        rewardIndexOf[account] = rewardIndex;
    }
    
    /// @notice Deposits rewards into the contract
    /// @param amount The amount of rewards to deposit
    function depositRewards(uint256 amount) external onlyGameContract {
        require(amount > 0, "Amount must be greater than 0");
        rewardToken.transferFrom(msg.sender, address(this), amount);
        if (totalSupply > 0) {
            rewardIndex += (amount * MULTIPLIER) / totalSupply;
        }
        _updateRewards;
        emit RewardsDeposited(msg.sender, amount);
    }

    /// @notice Allows users to stake tokens
    /// @param amount The amount of tokens to stake
    function stake(uint256 amount) external nonReentrant onlyInitialized {
        require(amount > 0, "amount = 0");
        require(balanceOf[_msgSender()] + amount <= stakingToken.getMaxWallet(), "Exceeds maxWallet limit");

        _updateRewards(msg.sender);

        balanceOf[msg.sender] += amount;
        totalSupply += amount;

        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        emit Staked(msg.sender, amount);
    }

    /// @notice Allows users to unstake tokens
    /// @param amount The amount of tokens to unstake
    function unstake(uint256 amount) external nonReentrant onlyInitialized {
        _updateRewards(msg.sender);

        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;

        stakingToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /// @notice Allows users to claim their rewards
    /// @return The amount of rewards claimed
    function claim() external nonReentrant onlyInitialized returns (uint256) {
        _updateRewards(msg.sender);

        uint256 reward = earned[msg.sender];
        if (reward > 0) {
            earned[msg.sender] = 0;
            rewardsClaimed[msg.sender] += reward;
            rewardToken.transfer(msg.sender, reward);
            
            emit Claimed(msg.sender, reward);
        }

        return reward;
    }

    /// @notice TESTNET ONLY. Allows the owner to withdraw ETH in case of emergency
    function emergencyWithdrawEth() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        payable(owner()).transfer(balance);
    }
}
