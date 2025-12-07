# Fusion Vault - Multi-Chain Tokenized Vaults on ICP

A decentralized multi-chain vault system built on the Internet Computer Protocol (ICP) that enables users to create tokenized vaults with support for Bitcoin, Ethereum, and other assets. Vault ownership is represented by ICRC-2 compliant tokens, and users can perform in-kind redemptions.

## Features

- **Multi-Vault System**: Create unlimited independent vaults
- **ICRC-2 Token Standard**: Each vault issues ownership tokens following ICRC-2
- **Multi-Chain Support**: Support for BTC, ETH, ICP, USDC, USDT via ICP's chain-key cryptography
- **Proportional Ownership**: Receive tokens based on your contribution to the vault
- **In-Kind Redemptions**: Redeem your shares for proportional amounts of all assets in the vault
- **Simple Web Interface**: Easy-to-use UI for all vault operations
- **ICP.Ninja Compatible**: Standard canister implementation for easy testing

## Architecture

### Vault Canister
The main canister written in Motoko that handles:
- Vault creation and management
- Asset deposits and tracking
- Share minting and burning
- ICRC-2 token operations
- Multi-chain address generation (via threshold signatures)
- In-kind redemptions

### Frontend
Simple HTML/CSS/JavaScript interface that provides:
- Vault creation
- Asset deposits
- Share redemption
- Share transfers
- Multi-chain address generation
- Balance viewing

## Getting Started

### Prerequisites

1. Install the DFINITY Canister SDK:
```bash
sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"
```

2. Verify installation:
```bash
dfx --version
```

### Local Development

1. Clone the repository:
```bash
git clone <repository-url>
cd FusionWallet
```

2. Start the local Internet Computer replica:
```bash
dfx start --clean --background
```

3. Deploy the canisters:
```bash
dfx deploy
```

4. The deployment will output the canister IDs. Note the frontend URL:
```
Frontend canister via browser:
  frontend: http://127.0.0.1:4943/?canisterId=<canister-id>
```

5. Open the frontend URL in your browser to use the application.

### Testing with ICP.Ninja

[ICP.Ninja](https://icp.ninja) is an online IDE for testing ICP canisters (similar to Remix for Ethereum).

1. Build your canister:
```bash
dfx build vault
```

2. Get the Candid interface:
```bash
cat .dfx/local/canisters/vault/vault.did
```

3. Go to [ICP.Ninja](https://icp.ninja)

4. Create a new project and paste your Motoko code or upload the `.wasm` file

5. Deploy and interact with your canister directly in the browser

## Usage Guide

### Creating a Vault

1. Connect your wallet (Internet Identity or Plug Wallet)
2. Enter a name for your vault
3. Click "Create Vault"
4. Note the Vault ID for future reference

### Depositing Assets

1. Select a vault from the list
2. Choose the asset type (ICP, BTC, ETH, USDC, USDT)
3. Enter the amount in the smallest unit (e.g., satoshis for BTC, wei for ETH)
4. Click "Deposit & Mint Shares"
5. Shares will be minted proportionally to your deposit

**Note**: For the first deposit in a vault, shares are minted 1:1 with the amount. For subsequent deposits, shares are calculated based on the vault's total value.

### Redeeming Shares

1. Select a vault where you hold shares
2. Enter the number of shares to redeem
3. Click "Redeem In-Kind"
4. You'll receive a proportional amount of all assets in the vault

### Transferring Shares

1. Select a vault
2. Enter the recipient's Principal ID
3. Enter the number of shares to transfer
4. Click "Transfer"
5. A small fee (0.0001 tokens) will be deducted

### Generating Multi-Chain Addresses

1. Select a vault
2. Click "Generate BTC Address" or "Generate ETH Address"
3. The address will be displayed and can be used to receive funds

**Note**: In the current implementation, address generation uses placeholders. For production, these would use ICP's threshold ECDSA/Schnorr signatures.

## ICRC-2 Token Standard

Each vault implements the ICRC-2 token standard for its ownership shares:

- **icrc1_name()**: Returns the vault's token name
- **icrc1_symbol()**: Returns "VST" (Vault Share Token)
- **icrc1_decimals()**: Returns 8 (like Bitcoin)
- **icrc1_fee()**: Returns 10,000 (0.0001 tokens)
- **icrc1_total_supply()**: Returns total shares in the vault
- **icrc1_balance_of()**: Returns shares held by an account
- **icrc1_transfer()**: Transfers shares between accounts
- **icrc1_metadata()**: Returns token metadata

## API Reference

### Vault Management

```motoko
// Create a new vault
createVault(name: Text): async Result<VaultId, Text>

// Get vault information
getVault(vaultId: VaultId): async ?Vault

// List all vaults
listVaults(): async [Vault]
```

### Asset Operations

```motoko
// Deposit assets and mint shares
deposit(vaultId: VaultId, assetType: AssetType, amount: Nat): async Result<Nat, Text>

// Redeem shares for in-kind assets
redeem(vaultId: VaultId, shares: Nat): async Result<[AssetBalance], Text>
```

### Multi-Chain

```motoko
// Generate Bitcoin address for vault
generateBtcAddress(vaultId: VaultId): async Result<Text, Text>

// Generate Ethereum address for vault
generateEthAddress(vaultId: VaultId): async Result<Text, Text>
```

### ICRC-2 Functions

```motoko
// Get balance of shares
icrc1_balance_of(vaultId: VaultId, account: Account): async Nat

// Transfer shares
icrc1_transfer(vaultId: VaultId, args: TransferArgs): async Result<Nat, TransferError>

// Get total supply
icrc1_total_supply(vaultId: VaultId): async Nat
```

## Asset Types

The vault supports the following asset types:
- **ICP**: Internet Computer Protocol token
- **BTC**: Bitcoin (via threshold ECDSA)
- **ETH**: Ethereum (via threshold ECDSA)
- **USDC**: USD Coin
- **USDT**: Tether USD

## Example Workflow

```bash
# 1. Create a vault
dfx canister call vault createVault '("My Multi-Chain Vault")'
# Returns: (variant { ok = 0 })

# 2. Deposit 1 ICP (100,000,000 e8s)
dfx canister call vault deposit '(0, variant { ICP }, 100_000_000)'
# Returns: (variant { ok = 100_000_000 }) - 100M shares minted

# 3. Generate BTC address
dfx canister call vault generateBtcAddress '(0)'
# Returns: (variant { ok = "bc1q0placeholder" })

# 4. Check balance
dfx canister call vault icrc1_balance_of '(0, record { owner = principal "xxxxx-xxxxx"; subaccount = null })'
# Returns: (100_000_000 : nat)

# 5. Redeem 50M shares
dfx canister call vault redeem '(0, 50_000_000)'
# Returns: (variant { ok = vec { record { assetType = variant { ICP }; amount = 50_000_000 } } })
```

## Development Roadmap

### Phase 1 (Current)
- [x] Basic vault creation and management
- [x] ICRC-2 token implementation
- [x] Deposit and redemption functionality
- [x] Simple web interface
- [x] Multi-chain address placeholders

### Phase 2 (Next)
- [ ] Integrate ICP's threshold ECDSA for real BTC addresses
- [ ] Integrate threshold Schnorr signatures for ETH addresses
- [ ] Implement actual cross-chain asset transfers
- [ ] Add Internet Identity integration
- [ ] Enhanced UI with wallet connection

### Phase 3 (Future)
- [ ] Support for additional chains (Solana, Cardano, etc.)
- [ ] Advanced vault strategies (auto-rebalancing, yield farming)
- [ ] Governance tokens for vault management
- [ ] Multi-signature vault operations
- [ ] Integration with DEXs for asset swaps

## Security Considerations

This is a prototype implementation. For production use:

1. **Threshold Signatures**: Implement real threshold ECDSA/Schnorr for address generation
2. **Asset Custody**: Use proper asset custody mechanisms (not simulated)
3. **Access Control**: Add comprehensive access controls and permissions
4. **Audit**: Get a professional security audit
5. **Testing**: Extensive testing on testnets before mainnet deployment
6. **Upgradability**: Implement proper canister upgrade mechanisms
7. **Rate Limiting**: Add rate limiting for sensitive operations

## Troubleshooting

### Canister deployment fails
```bash
# Clean and restart
dfx stop
dfx start --clean --background
dfx deploy
```

### Frontend not loading
```bash
# Check canister status
dfx canister status frontend

# Rebuild frontend
dfx build frontend
dfx canister install frontend --mode reinstall
```

### Can't connect wallet
- Ensure you're using a compatible wallet (Plug, Internet Identity)
- Check that the canister ID is whitelisted
- Verify you're on the correct network (local vs. mainnet)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Resources

- [Internet Computer Documentation](https://internetcomputer.org/docs)
- [Motoko Programming Language](https://internetcomputer.org/docs/current/motoko/main/motoko)
- [ICRC-2 Token Standard](https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-2/README.md)
- [ICP.Ninja](https://icp.ninja)
- [Threshold ECDSA](https://internetcomputer.org/docs/current/developer-docs/integrations/t-ecdsa/)

## Support

For questions and support:
- Create an issue in this repository
- Join the [Internet Computer Developer Forum](https://forum.dfinity.org/)
- Check the [ICP Developer Discord](https://discord.gg/jnjVVQaE2C)

---

Built with ❤️ on the Internet Computer
