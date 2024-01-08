// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma experimental ABIEncoderV2;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract BoinkToken is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public constant deadAddress = address(0xdead);

    bool private swapping;

    address public treasuryWallet;
    address public gameRewardsContract;
    address public boinkStakingContract;
    address public nftStakingContract;

    uint256 public maxTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;

    bool public blacklistRenounced = false;

    // Anti-bot and anti-whale mappings and variables
    mapping(address => bool) blacklisted;

    uint256 public buyTotalFees;
    uint256 public buyStakingFee;
    uint256 public buyLiquidityFee;
    uint256 public buyTreasuryFee;
    uint256 public buyGameRewardsFee;

    uint256 public sellTotalFees;
    uint256 public sellStakingFee;
    uint256 public sellLiquidityFee;
    uint256 public sellTreasuryFee;
    uint256 public sellGameRewardsFee;

    uint256 public tokensForStaking;
    uint256 public tokensForLiquidity;
    uint256 public tokensForTreasury;
    uint256 public tokensForGameRewards;

    /******************/

    // exclude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    bool public preMigrationPhase = true;
    mapping(address => bool) public preMigrationTransferrable;

    bool private inSwap; // Added

    modifier lockTheSwap() {
        // Added
        inSwap = true;
        _;
        inSwap = false;
    }

    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event nftStakingContractUpdated(
        address indexed newAddress,
        address indexed oldAddress
    );

    event treasuryWalletUpdated(
        address indexed newAddress,
        address indexed oldAddress
    );

    event boinkStakingContractUpdated(
        address indexed newAddress,
        address indexed oldAddress
    );

    event gameRewardsContractUpdated(
        address indexed newGameRewardsContract,
        address indexed oldGameRewardsContract
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    constructor(
        IUniswapV2Router02 _uniswapV2Router,
        address _nftStakingContract,
        address _treasuryWallet,
        address _gameRewardsContract,
        address _boinkStakingContract
    ) ERC20("Boink Token", "BOINK") {

        require(
            _treasuryWallet != address(0),
            "Invalid address for treasuryWallet"
        );

        require(
            _gameRewardsContract != address(0),
            "Invalid address for gameRewardsContract"
        );

        uniswapV2Router = _uniswapV2Router;
        treasuryWallet = owner();
        nftStakingContract = _nftStakingContract;
        gameRewardsContract = _gameRewardsContract;
        boinkStakingContract = _boinkStakingContract;
        
        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        uint256 _buyStakingFee = 2;
        uint256 _buyLiquidityFee = 0;
        uint256 _buyTreasuryFee = 1;
        uint256 _buyGameRewardsFee = 2;

        uint256 _sellStakingFee = 2;
        uint256 _sellLiquidityFee = 0;
        uint256 _sellTreasuryFee = 1;
        uint256 _sellGameRewardsFee = 2;

        uint256 totalSupply = 1_000_000 * 1e18; // 1 mil

        maxTransactionAmount = 10_000 * 1e18; // 1% of total
        maxWallet = 10_000 * 1e18; // 1% of total
        swapTokensAtAmount = (totalSupply * 5) / 10000; // 0.05%
        treasuryWallet = msg.sender;

        buyStakingFee = _buyStakingFee;
        buyLiquidityFee = _buyLiquidityFee;
        buyTreasuryFee = _buyTreasuryFee;
        buyGameRewardsFee = _buyGameRewardsFee;
        buyTotalFees =
            buyStakingFee +
            buyLiquidityFee +
            buyTreasuryFee +
            buyGameRewardsFee;

        sellStakingFee = _sellStakingFee;
        sellLiquidityFee = _sellLiquidityFee;
        sellTreasuryFee = _sellTreasuryFee;
        sellGameRewardsFee = _sellGameRewardsFee;
        sellTotalFees =
            sellStakingFee +
            sellLiquidityFee +
            sellTreasuryFee +
            sellGameRewardsFee;

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
        excludeFromFees(address(_nftStakingContract), true);
        excludeFromFees(address(_gameRewardsContract), true);
        excludeFromFees(address(_boinkStakingContract), true);

        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);
        excludeFromMaxTransaction(address(_nftStakingContract), true);
        excludeFromMaxTransaction(address(_boinkStakingContract), true);
        excludeFromMaxTransaction(address(_gameRewardsContract), true);

        preMigrationTransferrable[owner()] = true;
        preMigrationTransferrable[address(_nftStakingContract)] = true;
        preMigrationTransferrable[address(_boinkStakingContract)] = true;
        preMigrationTransferrable[address(_gameRewardsContract)] = true;

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(msg.sender, totalSupply);
    }

    receive() external payable {}
    
    function getMaxWallet() external view returns (uint256) {
        return maxWallet;
    }

    // Enables trading and ends the pre-migration phase
    function enableTrading() external onlyOwner {
        tradingActive = true;
        swapEnabled = true;
        preMigrationPhase = false;
    }

    // Disables the transaction and wallet limits
    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        return true;
    }

    // Updates the threshold at which tokens are swapped for other assets
    function updateSwapTokensAtAmount(uint256 newAmount)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newAmount >= (totalSupply() * 1) / 100000,
            "Swap amount cannot be lower than 0.001% total supply."
        );
        require(
            newAmount <= (totalSupply() * 5) / 1000,
            "Swap amount cannot be higher than 0.5% total supply."
        );
        swapTokensAtAmount = newAmount;
        return true;
    }

    // Updates the maximum amount of tokens that can be transacted
    function updateMaxTxnAmount(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 5) / 1000) / 1e18,
            "Cannot set maxTransactionAmount lower than 0.5%"
        );
        maxTransactionAmount = newNum * (10**18);
    }

    // Updates the maximum amount of tokens a wallet can hold
    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 10) / 1000) / 1e18,
            "Cannot set maxWallet lower than 1.0%"
        );
        maxWallet = newNum * (10**18);
    }

    // Updates whether a given address is excluded from the max transaction amount
    function excludeFromMaxTransaction(address updAds, bool isEx)
        public
        onlyOwner
    {
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    // Toggles whether swapping is enabled (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    // Updates the fees applied to buy transactions
    function updateBuyFees(
        uint256 _stakingFee,
        uint256 _liquidityFee,
        uint256 _treasuryFee,
        uint256 _gameRewardsFee
    ) external onlyOwner {
        buyStakingFee = _stakingFee;
        buyLiquidityFee = _liquidityFee;
        buyTreasuryFee = _treasuryFee;
        buyGameRewardsFee = _gameRewardsFee; // Set the new fee
        buyTotalFees =
            buyStakingFee +
            buyLiquidityFee +
            buyTreasuryFee +
            buyGameRewardsFee;
        require(buyTotalFees <= 5, "Buy fees must be <= 5.");
    }

    // Updates the fees applied to sell transactions
    function updateSellFees(
        uint256 _stakingFee,
        uint256 _liquidityFee,
        uint256 _treasuryFee,
        uint256 _gameRewardsFee // New parameter
    ) external onlyOwner {
        sellStakingFee = _stakingFee;
        sellLiquidityFee = _liquidityFee;
        sellTreasuryFee = _treasuryFee;
        sellGameRewardsFee = _gameRewardsFee; // Set the new fee
        sellTotalFees =
            sellStakingFee +
            sellLiquidityFee +
            sellTreasuryFee +
            sellGameRewardsFee;
        require(sellTotalFees <= 5, "Sell fees must be <= 5.");
    }

    // Updates whether a given address is excluded from fees
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    // Sets whether a given pair is an automated market maker pair
    function setAutomatedMarketMakerPair(address pair, bool value)
        public
        onlyOwner
    {
        require(
            pair != uniswapV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    // Helper function to set whether a given pair is an automated market maker pair
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }
    
    // Updates the UniV2 router, as well as creating a new pair thus all transfer/swapback logic will
    // now only interact with the new router/pair  (ONLY USE THIS IN EMERGENCIES!)
    function updateUniswapV2Router(IUniswapV2Router02 _uniswapV2Router) external onlyOwner {
        require(address(_uniswapV2Router) != address(0), "Invalid address");
        emit UpdateUniswapV2Router(address(_uniswapV2Router), address(uniswapV2Router));
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
    }

    // Updates the staking address (receives ETH)
    function updateNftStakingContract(address newAddress) external onlyOwner {
        emit nftStakingContractUpdated(newAddress, nftStakingContract); 
        nftStakingContract = newAddress;
    }

    // Updates the treasury wallet address (receives ETH)
    function updatetreasuryWallet(address newAddress) external onlyOwner {
        emit treasuryWalletUpdated(newAddress, treasuryWallet);
        treasuryWallet = newAddress;
    }

    // Updates the boink staking contract address (only for max tx/limit exceptions)
    function updateBoinkStakingContract(address newAddress) external onlyOwner {
        emit boinkStakingContractUpdated(newAddress, boinkStakingContract);
        boinkStakingContract = newAddress;
    }

    // Updates the game rewards contract address
    function updateGameRewardsContract(address newGameRewardsContract)
        external
        onlyOwner
    {
        require(
            newGameRewardsContract != address(0),
            "Invalid address for gameRewardsContract"
        );
        emit gameRewardsContractUpdated(
            newGameRewardsContract,
            gameRewardsContract
        );
        gameRewardsContract = newGameRewardsContract;
    }

    // Checks if a given address is excluded from fees
    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    // Checks if a given address is blacklisted
    function isBlacklisted(address account) public view returns (bool) {
        return blacklisted[account];
    }

    // Handles transfers, applying fees and restrictions as necessary
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!blacklisted[from], "Sender blacklisted");
        require(!blacklisted[to], "Receiver blacklisted");

        if (preMigrationPhase) {
            require(
                preMigrationTransferrable[from],
                "Not authorized to transfer pre-migration."
            );
        }

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !swapping
            ) {
                if (!tradingActive) {
                    require(
                        _isExcludedFromFees[from] || _isExcludedFromFees[to],
                        "Trading is not active."
                    );
                }

                //when buy
                if (
                    automatedMarketMakerPairs[from] &&
                    !_isExcludedMaxTransactionAmount[to]
                ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Buy transfer amount exceeds the maxTransactionAmount."
                    );
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
                //when sell
                else if (
                    automatedMarketMakerPairs[to] &&
                    !_isExcludedMaxTransactionAmount[from]
                ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Sell transfer amount exceeds the maxTransactionAmount."
                    );
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;

            swapBack();

            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            // On sell
            if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                fees = amount.mul(sellTotalFees).div(100);
                tokensForLiquidity += (fees * sellLiquidityFee) / sellTotalFees;
                tokensForTreasury += (fees * sellTreasuryFee) / sellTotalFees;
                tokensForStaking += (fees * sellStakingFee) / sellTotalFees;
                tokensForGameRewards +=
                    (fees * sellGameRewardsFee) /
                    sellTotalFees; // New fee calculation
            }
            // On buy
            else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = amount.mul(buyTotalFees).div(100);
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFees;
                tokensForTreasury += (fees * buyTreasuryFee) / buyTotalFees;
                tokensForStaking += (fees * buyStakingFee) / buyTotalFees;
                tokensForGameRewards +=
                    (fees * buyGameRewardsFee) /
                    buyTotalFees; // New fee calculation
            }
            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function sendETHToStaking(uint256 amount) private {
        Address.sendValue(payable(address(nftStakingContract)), amount);
    }

    // Swaps tokens for ETH
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }
    
    // Adds liquidity to the Uniswap pair
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    // Swaps tokens for ETH and adds liquidity/sends to designated addresses
    function swapBack() private lockTheSwap {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForLiquidity +
            tokensForStaking +
            tokensForTreasury +
            tokensForGameRewards;
        bool success;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        // Halve the amount of liquidity tokens
        uint256 liquidityTokens = (contractBalance * tokensForLiquidity) /
            totalTokensToSwap /
            2;
        uint256 amountToSwapForETH = contractBalance.sub(liquidityTokens);
        uint256 initialETHBalance = address(this).balance;

        swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance.sub(initialETHBalance);
        uint256 ethForStaking = ethBalance.mul(tokensForStaking).div(
            totalTokensToSwap - (tokensForLiquidity / 2)
        );
        uint256 ethForTreasury = ethBalance.mul(tokensForTreasury).div(
            totalTokensToSwap - (tokensForLiquidity / 2)
        );
        uint256 ethForGameRewards = ethBalance.mul(tokensForGameRewards).div(
            totalTokensToSwap - (tokensForLiquidity / 2)
        );
        uint256 ethForLiquidity = ethBalance -
            ethForStaking -
            ethForTreasury -
            ethForGameRewards;

        tokensForLiquidity = 0;
        tokensForStaking = 0;
        tokensForTreasury = 0;
        tokensForGameRewards = 0;

        (success, ) = address(treasuryWallet).call{value: ethForTreasury}("");
        (success, ) = address(gameRewardsContract).call{
            value: ethForGameRewards
        }("");

        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            addLiquidity(liquidityTokens, ethForLiquidity);
            emit SwapAndLiquify(
                amountToSwapForETH,
                ethForLiquidity,
                tokensForLiquidity
            );
        }

        sendETHToStaking(ethForStaking); // Updated line
    }

    // Allows the owner to withdraw tokens accidentally sent to the contract
    function withdrawStuckBoink() external onlyOwner {
        uint256 balance = IERC20(address(this)).balanceOf(address(this));
        IERC20(address(this)).transfer(msg.sender, balance);
        payable(msg.sender).transfer(address(this).balance);
    }

    // Allows the owner to withdraw a specified token accidentally sent to the contract
    function withdrawStuckToken(address _token, address _to)
        external
        onlyOwner
    {
        require(_token != address(0), "_token address cannot be 0");
        uint256 _contractBalance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(_to, _contractBalance);
    }

    // Allows the owner to withdraw stuck ETH from the contract
    function withdrawStuckEth(address toAddr) external onlyOwner {
        (bool success, ) = toAddr.call{value: address(this).balance}("");
        require(success);
    }

    // Allows the owner to renounce the ability to blacklist addresses
    function renounceBlacklist() public onlyOwner {
        blacklistRenounced = true;
    }

    // Allows the owner to blacklist a specified address
    function blacklist(address _addr) public onlyOwner {
        require(!blacklistRenounced, "Treasury has revoked blacklist rights");
        require(
            _addr != address(uniswapV2Pair) &&
                _addr != address(uniswapV2Router), // Updated this line
            "Cannot blacklist token's v2 router or v2 pool."
        );
        blacklisted[_addr] = true;
    }

    // Allows the owner to blacklist a specified liquidity pool address
    function blacklistLiquidityPool(address lpAddress) public onlyOwner {
        require(!blacklistRenounced, "Treasury has revoked blacklist rights");
        require(
            lpAddress != address(uniswapV2Pair) &&
                lpAddress != address(uniswapV2Router), // Updated this line
            "Cannot blacklist token's v2 router or v2 pool."
        );
        blacklisted[lpAddress] = true;
    }

    // Allows the owner to remove an address from the blacklist
    function unblacklist(address _addr) public onlyOwner {
        blacklisted[_addr] = false;
    }

    // Sets whether a given address is authorized to transfer tokens during the pre-migration phase
    function setPreMigrationTransferable(address _addr, bool isAuthorized)
        public
        onlyOwner
    {
        preMigrationTransferrable[_addr] = isAuthorized;
        excludeFromFees(_addr, isAuthorized);
        excludeFromMaxTransaction(_addr, isAuthorized);
    }
}
