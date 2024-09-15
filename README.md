# Staking Rewards Contracts

This repository contains smart contracts for two types of staking protocols:

1. **Traditional Yield Farming**: Inspired by **MasterChef** and **Synthetix**, this contract allows users to stake tokens and earn rewards.
2. **Gamified NFT Staking**: A next-level staking system where users stake NFTs to earn rewards through a gamified approach, featuring multiple staking levels, badges, and boosted rewards.

## Features

### 1. Yield Farming Contract
- Staking mechanism inspired by **MasterChef** and **Synthetix** models.
- Users can stake ERC20 tokens to earn reward tokens.
- Configurable reward distribution rate.
  
### 2. Gamified NFT Staking
- **5 distinct staking levels**, each requiring a badge (purchasable via USDC or native blockchain tokens like WETH/WBNB).
- **Fixed APRs** based on the staking level.
- Reward boosts available by **locking reward tokens** for 3 weeks.
- Flexible configuration for **NFT attributes**, **badge requirements**, and **reward distribution**.
  
## Testing

This project comes with an extensive testing suite to ensure security, stability, and scalability:

- **Unit Testing**: Comprehensive unit tests to validate individual functions.
- **Integration Testing**: Ensures all contracts interact as expected.
- **Fork Testing**: Tests against live blockchain states, such as Ethereum mainnet, BSC, and more.
- **Fuzz Testing**: Randomized inputs to uncover edge cases.
- **Invariant Testing**: Verifies protocol invariants (e.g., no tokens are lost during staking/unstaking).

## Getting Started

### Prerequisites

- Foundry: Install Foundry by following the instructions at [foundry.sh](https://getfoundry.sh)
- Node.js (for JavaScript dependencies)

### Installation

1. Clone this repository:

```bash
git clone https://github.com/EggsyOnCode/staking-rewards
cd staking-rewards
```

2. Install dependencies:

```bash
forge install
```

3. Compile contracts:

```bash
forge build
```

### Running Tests

To run the entire test suite:

```bash
forge test
```

For fork testing against a specific chain (e.g., Binance Smart Chain):

```bash
forge test --fork-url https://bsc-rpc.publicnode.com
```

### Contract Configuration

- **APR Settings**: You can adjust APRs, boosted rewards, and badge configurations in the `NFTStakingManager.sol` contract.
- **Badges**: Each staking level requires a unique badge. Badge costs and staking prerequisites can be configured in the setup section.
- **Reward Boosting**: Users can lock their reward tokens to earn boosted rewards for a duration of 3 weeks.

### Deployment

You can deploy the contracts on any EVM-compatible chain (Ethereum, Binance Smart Chain, Polygon, etc.). Follow these steps for deployment:

1. Set up your private key and RPC URLs in `.env`.
2. Run the deployment script:

```bash
forge script scripts/Deploy.sol --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIVATE_KEY> --broadcast
```

## Folder Structure

- `contracts/`: Contains the staking contracts.
- `test/`: Includes all unit, integration, fork, fuzz, and invariant tests.
- `scripts/`: Deployment and setup scripts.

## Contributing

Feel free to fork the repository and create a pull request if you’d like to contribute!

## License

This project is licensed under the MIT License.
