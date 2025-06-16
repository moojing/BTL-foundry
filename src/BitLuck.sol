// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/*
DApp: https://www.btluck.fun/
Overview: https://bitluck.notion.site/
Twitter: https://x.com/BitLuckBSC
Telegram: https://t.me/BitLuckBSC

BitLuck ($BTL) Dual Reward System Contract
Features:
- 4% Trading Tax (3% USD1 dividends + 1% marketing/liquidity)
- BTL Staking with BTL rewards
- Referral system (10% bonus from first deposits)
- Random lottery system
- Automatic dividend distribution
*/

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event OwnershipRenounced(address indexed previousOwner);

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipRenounced(_owner);
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

contract TokenDistributor {
    constructor(address token) {
        IERC20(token).approve(msg.sender, type(uint256).max);
    }
}

contract BitLuck is Context, IERC20, Ownable {
    // ERC20 Basic Info
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;

    // Constants
    string private constant _name = unicode"BitLuck";
    string private constant _symbol = unicode"BTL";
    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1000000000000 * 10 ** _decimals; // 1 trillion

    // Trading Tax Configuration (4% total)
    uint256 public constant _buyUSD1Fee = 300; // 3% to USD1 dividends
    uint256 public constant _buyMarketingFee = 100; // 1% to marketing/liquidity
    uint256 public constant _sellUSD1Fee = 300; // 3% to USD1 dividends
    uint256 public constant _sellMarketingFee = 100; // 1% to marketing/liquidity

    // Addresses
    address payable private immutable _taxWallet = payable(_msgSender());
    address public immutable RouterAddress;

    /**
     * @dev USD1 代幣地址
     *
     * 設計說明：
     * - 此地址存儲用於支付分紅的穩定幣合約地址
     * - 設計上預期使用 World Coin 的 USD1 代幣
     * - 在測試環境中可能使用 USDT 等其他穩定幣作為代理
     * - 通過構造函數設置，支持不同網絡部署的靈活性
     */
    address public immutable _USD1;

    // Uniswap Integration
    IUniswapV2Router02 private immutable uniswapV2Router;
    mapping(address => bool) public _swapPairList;
    TokenDistributor public immutable _tokenDistributor;

    // Trading Control
    uint256 public startTradeBlock;
    bool private inSwap;
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    // USD1 Dividend System
    uint256 private constant ACC_PRECISION = 1e18;
    uint256 public totalUSD1DividendPerShare;
    uint256 private accUSD1DividendBalance;
    mapping(address => uint256) private lastUSD1DividendPerShare;
    mapping(address => uint256) public accumulatedUSD1;

    // BTL Staking System
    mapping(address => uint256) public stakedBTL;
    mapping(address => uint256) private lastBTLDividendPerShare;
    mapping(address => uint256) public accumulatedBTLRewards;
    uint256 public totalStakedBTL;
    uint256 public totalBTLDividendPerShare;
    uint256 private accBTLDividendBalance;

    // Referral System
    mapping(address => address) public referrers;
    mapping(address => bool) public hasDeposited;
    mapping(address => uint256) public referralEarnings;
    uint256 public constant REFERRAL_BONUS = 1000; // 10%

    // Lottery System
    uint256 public holderCondition = 1000000000 * 10 ** _decimals; // 0.1% minimum holding
    uint256 public drawIntervalBlocks = 1200; // 30 mins
    uint256 public lastDrawBlock;

    // Holder Management
    address[] public holders;
    mapping(address => uint256) holderIndex;
    uint256 public batchSize = 100;
    uint256 public minGas = 400000;
    uint256 public lastProcessedIndex = 0;

    // Random number generation
    uint256 private randNonce;

    // Events
    event BTLStaked(address indexed user, uint256 amount);
    event BTLUnstaked(address indexed user, uint256 amount);
    event BTLRewardClaimed(address indexed user, uint256 amount);
    event USD1DividendDistributed(address indexed user, uint256 amount);
    event USD1LotteryWon(address indexed winner, uint256 amount);
    event ReferralBonusPaid(
        address indexed referrer,
        address indexed referred,
        uint256 amount
    );
    event ReferralSet(address indexed user, address indexed referrer);

    constructor(address usd1Address, address routerAddress) {
        require(usd1Address != address(0), "Invalid USD1 address");
        require(routerAddress != address(0), "Invalid router address");

        _USD1 = usd1Address;
        RouterAddress = routerAddress;

        IUniswapV2Router02 swapRouter = IUniswapV2Router02(routerAddress);
        uniswapV2Router = swapRouter;

        IUniswapV2Factory swapFactory = IUniswapV2Factory(swapRouter.factory());
        address swapPair = swapFactory.createPair(address(this), _USD1);
        _swapPairList[swapPair] = true;

        _approve(address(this), address(swapRouter), type(uint256).max);
        _allowances[address(this)][address(swapRouter)] = type(uint256).max;
        IERC20(_USD1).approve(address(swapRouter), type(uint256).max);

        _balances[_msgSender()] = _tTotal;
        emit Transfer(address(0), _msgSender(), _tTotal);

        address deployer = _msgSender();
        _isExcludedFromFee[deployer] = true;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[address(swapRouter)] = true;
        _isExcludedFromFee[_taxWallet] = true;

        _tokenDistributor = new TokenDistributor(_USD1);
    }

    // ERC20 Implementation
    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            unchecked {
                _allowances[sender][msg.sender] =
                    _allowances[sender][msg.sender] -
                    amount;
            }
        }
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Staking Functions
    function stakeBTL(uint256 amount, address referrer) external {
        require(amount > 0, "Amount must be greater than 0");
        require(_balances[_msgSender()] >= amount, "Insufficient BTL balance");

        // Set referrer for first-time depositors
        if (
            !hasDeposited[_msgSender()] &&
            referrer != address(0) &&
            referrer != _msgSender()
        ) {
            referrers[_msgSender()] = referrer;
            emit ReferralSet(_msgSender(), referrer);
        }

        // Update pending rewards before changing stake
        _updateBTLRewards(_msgSender());

        // Calculate referral bonus for first-time deposits
        uint256 actualStakeAmount = amount;
        if (
            !hasDeposited[_msgSender()] && referrers[_msgSender()] != address(0)
        ) {
            uint256 referralBonus = (amount * REFERRAL_BONUS) / 10000;
            actualStakeAmount = amount - referralBonus;

            // Transfer bonus to referrer
            _balances[_msgSender()] -= referralBonus;
            _balances[referrers[_msgSender()]] += referralBonus;
            referralEarnings[referrers[_msgSender()]] += referralBonus;

            emit Transfer(_msgSender(), referrers[_msgSender()], referralBonus);
            emit ReferralBonusPaid(
                referrers[_msgSender()],
                _msgSender(),
                referralBonus
            );
        }

        // Transfer BTL from user to contract
        _balances[_msgSender()] -= actualStakeAmount;
        _balances[address(this)] += actualStakeAmount;

        // Update staking records
        stakedBTL[_msgSender()] += actualStakeAmount;
        totalStakedBTL += actualStakeAmount;
        hasDeposited[_msgSender()] = true;

        emit Transfer(_msgSender(), address(this), actualStakeAmount);
        emit BTLStaked(_msgSender(), actualStakeAmount);
    }

    function unstakeBTL(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(stakedBTL[_msgSender()] >= amount, "Insufficient staked BTL");

        // Update pending rewards before changing stake
        _updateBTLRewards(_msgSender());

        // Update staking records
        stakedBTL[_msgSender()] -= amount;
        totalStakedBTL -= amount;

        // Transfer BTL back to user
        _balances[address(this)] -= amount;
        _balances[_msgSender()] += amount;

        emit Transfer(address(this), _msgSender(), amount);
        emit BTLUnstaked(_msgSender(), amount);
    }

    function claimBTLRewards() external {
        _updateBTLRewards(_msgSender());
        uint256 rewards = accumulatedBTLRewards[_msgSender()];
        require(rewards > 0, "No BTL rewards to claim");

        accumulatedBTLRewards[_msgSender()] = 0;
        _balances[_msgSender()] += rewards;

        emit BTLRewardClaimed(_msgSender(), rewards);
    }

    function claimUSD1Dividends() external {
        _updateUSD1Rewards(_msgSender());
        uint256 dividends = accumulatedUSD1[_msgSender()];
        require(dividends > 0, "No USD1 dividends to claim");

        accumulatedUSD1[_msgSender()] = 0;
        safeTransfer(_USD1, _msgSender(), dividends);
        accUSD1DividendBalance -= dividends;

        emit USD1DividendDistributed(_msgSender(), dividends);
    }

    function claimAllRewards() external {
        // Claim BTL rewards
        _updateBTLRewards(_msgSender());
        uint256 btlRewards = accumulatedBTLRewards[_msgSender()];
        if (btlRewards > 0) {
            accumulatedBTLRewards[_msgSender()] = 0;
            _balances[_msgSender()] += btlRewards;
            emit BTLRewardClaimed(_msgSender(), btlRewards);
        }

        // Claim USD1 dividends
        _updateUSD1Rewards(_msgSender());
        uint256 usd1Dividends = accumulatedUSD1[_msgSender()];
        if (usd1Dividends > 0) {
            accumulatedUSD1[_msgSender()] = 0;
            safeTransfer(_USD1, _msgSender(), usd1Dividends);
            accUSD1DividendBalance -= usd1Dividends;
            emit USD1DividendDistributed(_msgSender(), usd1Dividends);
        }
    }

    // Internal reward update functions
    function _updateBTLRewards(address account) private {
        if (stakedBTL[account] == 0) return;

        uint256 owed = (stakedBTL[account] *
            (totalBTLDividendPerShare - lastBTLDividendPerShare[account])) /
            ACC_PRECISION;
        if (owed > 0) {
            accumulatedBTLRewards[account] += owed;
            accBTLDividendBalance -= owed;
        }
        lastBTLDividendPerShare[account] = totalBTLDividendPerShare;
    }

    function _updateUSD1Rewards(address account) private {
        uint256 balance = _balances[account];
        if (balance == 0) return;

        uint256 owed = (balance *
            (totalUSD1DividendPerShare - lastUSD1DividendPerShare[account])) /
            ACC_PRECISION;
        if (owed > 0) {
            accumulatedUSD1[account] += owed;
        }
        lastUSD1DividendPerShare[account] = totalUSD1DividendPerShare;
    }

    // Transfer function with fees and reward processing
    function _transfer(address from, address to, uint256 amount) private {
        uint256 balance = balanceOf(from);
        require(balance >= amount, "balanceNotEnough");

        bool takeFee;
        bool isSell;

        if (_swapPairList[from] || _swapPairList[to]) {
            if (!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
                require(startTradeBlock > 0, "Trading not started");

                if (_swapPairList[to]) {
                    if (!inSwap) {
                        uint256 contractTokenBalance = balanceOf(
                            address(this)
                        ) - totalStakedBTL;
                        if (contractTokenBalance > 0) {
                            uint256 swapFee = _buyUSD1Fee +
                                _buyMarketingFee +
                                _sellUSD1Fee +
                                _sellMarketingFee;
                            uint256 numTokensSellToFund = (amount * swapFee) /
                                5000;
                            if (numTokensSellToFund > contractTokenBalance) {
                                numTokensSellToFund = contractTokenBalance;
                            }
                            swapTokenForFund(numTokensSellToFund, swapFee);
                        }
                    }
                }
                takeFee = true;
            }
            if (_swapPairList[to]) {
                isSell = true;
            }
        }

        _tokenTransfer(from, to, amount, takeFee, isSell);

        if (from != address(this)) {
            // Update holder lists
            if (_swapPairList[to]) {
                addHolder(from);
            } else if (_swapPairList[from]) {
                addHolder(to);
            } else {
                addHolder(from);
                addHolder(to);
            }

            // Process rewards and lottery
            processReward();
        }
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 tAmount,
        bool takeFee,
        bool isSell
    ) internal {
        unchecked {
            _balances[sender] = _balances[sender] - tAmount;
        }

        uint256 feeAmount;
        if (takeFee) {
            uint256 swapFee;
            if (isSell) {
                swapFee = _sellUSD1Fee + _sellMarketingFee;
            } else {
                swapFee = _buyUSD1Fee + _buyMarketingFee;
            }

            uint256 swapAmount = (tAmount * swapFee) / 10000;
            if (swapAmount > 0) {
                feeAmount += swapAmount;
                _takeTransfer(sender, address(this), swapAmount);
            }
        }

        unchecked {
            _takeTransfer(sender, recipient, tAmount - feeAmount);
        }
    }

    function _takeTransfer(
        address sender,
        address to,
        uint256 tAmount
    ) private {
        unchecked {
            _balances[to] = _balances[to] + tAmount;
        }
        emit Transfer(sender, to, tAmount);
    }

    // Swap and fee distribution
    function swapTokenForFund(
        uint256 tokenAmount,
        uint256 swapFee
    ) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _USD1;

        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(_tokenDistributor),
            block.timestamp
        );

        IERC20 USD1 = IERC20(_USD1);
        uint256 USD1Balance = USD1.balanceOf(address(_tokenDistributor));

        // Calculate allocations: 3% to dividends, 1% to marketing
        uint256 marketingAmount = (USD1Balance *
            (_buyMarketingFee + _sellMarketingFee) *
            2) / swapFee;
        uint256 dividendAmount = USD1Balance - marketingAmount;

        // Transfer marketing funds
        USD1.transferFrom(
            address(_tokenDistributor),
            _taxWallet,
            marketingAmount
        );

        // Transfer dividend funds to contract
        USD1.transferFrom(
            address(_tokenDistributor),
            address(this),
            dividendAmount
        );
    }

    // Holder management
    function addHolder(address adr) private {
        if (adr == address(0)) return;

        if (balanceOf(adr) >= holderCondition && holderIndex[adr] == 0) {
            holderIndex[adr] = holders.length + 1;
            holders.push(adr);
        }
        if (balanceOf(adr) < holderCondition && holderIndex[adr] != 0) {
            uint index = holderIndex[adr] - 1;
            address lastHolder = holders[holders.length - 1];
            holders[index] = lastHolder;
            holderIndex[lastHolder] = index + 1;
            holders.pop();
            delete holderIndex[adr];
        }
    }

    // Reward processing and lottery
    function processReward() private {
        if (inSwap) return;
        if (block.number < lastDrawBlock + drawIntervalBlocks) return;

        IERC20 USD1 = IERC20(_USD1);
        uint256 balance = USD1.balanceOf(address(this));
        uint256 available = balance > accUSD1DividendBalance
            ? balance - accUSD1DividendBalance
            : 0;
        if (available == 0) return;

        inSwap = true;

        // Allocate rewards: 70% USD1 dividends, 25% BTL rewards, 5% lottery
        uint256 usd1DividendPool = (available * 70) / 100;
        uint256 btlRewardPool = (available * 25) / 100;
        uint256 lotteryPool = (available * 5) / 100;

        // Distribute USD1 dividends to all BTL holders
        if (usd1DividendPool > 0) {
            totalUSD1DividendPerShare +=
                (usd1DividendPool * ACC_PRECISION) /
                _tTotal;
            accUSD1DividendBalance += usd1DividendPool;
        }

        // Distribute BTL rewards to stakers
        if (btlRewardPool > 0 && totalStakedBTL > 0) {
            // Convert USD1 to BTL for staking rewards (simplified: assume 1:1 for demo)
            uint256 btlRewardAmount = btlRewardPool; // In real implementation, would swap USD1 to BTL
            totalBTLDividendPerShare +=
                (btlRewardAmount * ACC_PRECISION) /
                totalStakedBTL;
            accBTLDividendBalance += btlRewardAmount;
        }

        lastDrawBlock = block.number;

        // Process batch USD1 dividend updates
        uint256 len = holders.length;
        uint256 processed = 0;
        for (
            uint i = lastProcessedIndex;
            i < len && processed < batchSize && gasleft() > minGas;
            i++
        ) {
            _updateUSD1Rewards(holders[i]);
            processed++;
            lastProcessedIndex = i + 1;
        }
        if (lastProcessedIndex >= len) {
            lastProcessedIndex = 0;
        }

        // Lottery
        if (lotteryPool > 0 && len > 0) {
            uint256 randIndex = random(0) % len;
            address winner = holders[randIndex];
            safeTransfer(_USD1, winner, lotteryPool);
            accumulatedUSD1[winner] += lotteryPool;
            emit USD1LotteryWon(winner, lotteryPool);
        }

        inSwap = false;
    }

    // Random number generation
    function random(uint256 salt) internal returns (uint256) {
        randNonce++;
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.prevrandao,
                        block.timestamp,
                        salt,
                        randNonce
                    )
                )
            );
    }

    // Utility functions
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20(token).transfer.selector, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Transfer failed"
        );
    }

    // Trading control
    function openTrading() external onlyOwner {
        require(0 == startTradeBlock, "Trading has already started");
        lastDrawBlock = block.number;
        startTradeBlock = block.number;
    }

    // View functions
    function blocksUntilNextDraw() public view returns (uint256) {
        if (block.number >= lastDrawBlock + drawIntervalBlocks) return 0;
        return (lastDrawBlock + drawIntervalBlocks) - block.number;
    }

    function getUSD1Balance() external view returns (uint256) {
        IERC20 usd1Token = IERC20(_USD1);
        return usd1Token.balanceOf(address(this));
    }

    function getUserStakingInfo(
        address user
    )
        external
        view
        returns (
            uint256 stakedAmount,
            uint256 pendingBTLRewards,
            uint256 pendingUSD1Dividends
        )
    {
        stakedAmount = stakedBTL[user];

        // Calculate pending BTL rewards
        if (stakedAmount > 0) {
            pendingBTLRewards =
                (stakedAmount *
                    (totalBTLDividendPerShare -
                        lastBTLDividendPerShare[user])) /
                ACC_PRECISION;
            pendingBTLRewards += accumulatedBTLRewards[user];
        }

        // Calculate pending USD1 dividends
        uint256 balance = _balances[user];
        if (balance > 0) {
            pendingUSD1Dividends =
                (balance *
                    (totalUSD1DividendPerShare -
                        lastUSD1DividendPerShare[user])) /
                ACC_PRECISION;
            pendingUSD1Dividends += accumulatedUSD1[user];
        }
    }

    function getReferralInfo(
        address user
    )
        external
        view
        returns (address referrer, uint256 earnings, bool hasDeposited_)
    {
        referrer = referrers[user];
        earnings = referralEarnings[user];
        hasDeposited_ = hasDeposited[user];
    }

    // Emergency functions
    function recoverAssets(address token, uint256 amount) external {
        require(_msgSender() == _taxWallet, "Only tax wallet");
        uint256 toSend;

        if (token == address(0)) {
            uint256 ethBal = address(this).balance;
            require(ethBal > 0, "No ETH to recover");
            toSend = (amount == 0 || amount > ethBal) ? ethBal : amount;
            payable(_taxWallet).transfer(toSend);
        } else {
            uint256 bal = IERC20(token).balanceOf(address(this));
            require(bal > 0, "No token to recover");
            toSend = (amount == 0 || amount > bal) ? bal : amount;
            safeTransfer(token, _taxWallet, toSend);
        }
    }

    // Configuration functions (owner only)
    function setDrawInterval(uint256 _blocks) external onlyOwner {
        require(_blocks >= 100, "Interval too short");
        drawIntervalBlocks = _blocks;
    }

    function setBatchSize(uint256 _batchSize) external onlyOwner {
        require(_batchSize > 0 && _batchSize <= 500, "Invalid batch size");
        batchSize = _batchSize;
    }

    function setHolderCondition(uint256 _condition) external onlyOwner {
        require(_condition > 0, "Invalid condition");
        holderCondition = _condition;
    }

    fallback() external payable {}
    receive() external payable {}
}
