# BitLuck ($BTL) - Dual Reward System

A comprehensive DeFi token with innovative dual reward mechanisms, referral bonuses, and random lottery system built on Binance Smart Chain.

## Features

### 🎯 Core Functionality
- **ERC20 Token**: Standard compliant with 1 trillion total supply
- **4% Trading Tax**: Automatically collected on all trades
  - 3% → USD1 dividend pool  
  - 1% → Marketing & liquidity
- **Dual Reward System**:
  - USD1 dividends for all BTL holders
  - BTL rewards for stakers
- **Referral Program**: 10% bonus from first-time deposits
- **Random Lottery**: Weekly USD1 prizes for holders
- **Automated Processing**: Gas-efficient batch reward distribution

### 📊 Reward Distribution
- **70%** → USD1 dividends (proportional to BTL holdings)
- **25%** → BTL staking rewards  
- **5%** → Random lottery prizes

## Smart Contract Architecture

### Key Contracts
1. **BitLuck.sol** - Main token contract with all features
2. **MockUSDT.sol** - Test USDT implementation
3. **TokenDistributor.sol** - Helper for fee distribution

### Core Functions

#### Staking
```solidity
// Stake BTL tokens with optional referrer
function stakeBTL(uint256 amount, address referrer) external

// Unstake BTL tokens
function unstakeBTL(uint256 amount) external

// Claim BTL staking rewards
function claimBTLRewards() external
```

#### Dividends & Rewards
```solidity
// Claim USD1 dividends
function claimUSD1Dividends() external

// Claim all available rewards (BTL + USD1)
function claimAllRewards() external
```

#### View Functions
```solidity
// Get user's staking information
function getUserStakingInfo(address user) external view returns (
    uint256 stakedAmount,
    uint256 pendingBTLRewards, 
    uint256 pendingUSD1Dividends
)

// Get referral information
function getReferralInfo(address user) external view returns (
    address referrer,
    uint256 earnings,
    bool hasDeposited
)
```

## Configuration

### Network Parameters
- **BSC Testnet Router**: `0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3`
- **Test USDT**: Deployed via MockUSDT contract
- **Minimum Holding**: 0.1% of total supply for lottery eligibility
- **Draw Interval**: 1200 blocks (~30 minutes)

### Fee Structure
```solidity
uint256 public constant _buyUSD1Fee = 300;      // 3%
uint256 public constant _buyMarketingFee = 100;  // 1%
uint256 public constant _sellUSD1Fee = 300;     // 3%
uint256 public constant _sellMarketingFee = 100; // 1%
uint256 public constant REFERRAL_BONUS = 1000;  // 10%
```

## Development Setup

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 16+ (for frontend development)

### Installation
```bash
# Clone repository
git clone <repository-url>
cd BitLuck

# Install dependencies
forge install

# Compile contracts
forge build

# Run tests
forge test -vv
```

### Testing
The project includes comprehensive test coverage:
- **30 test cases** covering all functionality
- Staking mechanics with referral bonuses
- Dividend distribution systems
- Owner-only functions
- Edge cases and error conditions

```bash
# Run all tests
forge test

# Run specific test
forge test --match-test testStakingWithReferrer

# Run with gas reporting
forge test --gas-report
```

## Deployment

### BSC Testnet Deployment
```bash
# Set environment variables
export PRIVATE_KEY=<your-private-key>
export BSC_API_KEY=<bscscan-api-key>

# Deploy with mock USDT (testing)
forge script script/Deploy.s.sol:DeployScript --rpc-url bsc_testnet --broadcast

# Deploy with real USDT (production)
forge script script/Deploy.s.sol:DeployScript --sig "deployWithRealUSDT()" --rpc-url bsc_testnet --broadcast
```

### Verification
```bash
forge verify-contract <contract-address> src/BitLuck.sol:BitLuck --chain bsc-testnet
```

## Security Features

### Access Control
- Owner-only functions for critical parameters
- Multi-signature wallet support for tax collection
- Immutable core parameters (fees, token supply)

### Reentrancy Protection
- Mutex locks on critical functions
- Safe transfer patterns
- Gas limit checks for batch operations

### Randomness
- Uses `block.prevrandao` for lottery randomness
- Includes multiple entropy sources
- Nonce-based additional randomization

## Gas Optimization

### Batch Processing
- Configurable batch sizes for reward distribution
- Gas limit monitoring
- Checkpoint-based resumption

### Storage Efficiency
- Packed structs where possible
- Unchecked arithmetic for gas savings
- Minimal storage reads/writes

## Roadmap

### Q1 2024
- ✅ Smart contract development
- ✅ Comprehensive testing
- ✅ BSC Testnet deployment

### Q2 2024 (Planned)
- DApp frontend development
- Liquidity pool creation
- Security audit
- Mainnet deployment

### Q3 2024 (Planned)
- Solana cross-chain support
- Advanced staking features
- Governance implementation

### Q4 2024 (Planned)
- Ecosystem partnerships
- Mobile app development
- Additional reward mechanisms

## Links

- **Website**: https://www.btluck.fun/
- **Documentation**: https://bitluck.notion.site/
- **Twitter**: https://x.com/BitLuckBSC
- **Telegram**: https://t.me/BitLuckBSC

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## Disclaimer

This is experimental DeFi software. Please understand the risks:
- Smart contract risk
- Market volatility
- Regulatory uncertainty
- Potential total loss of funds

Always DYOR (Do Your Own Research) and never invest more than you can afford to lose.
