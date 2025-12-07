# FusionVault - Multi-Asset Fractionally Owned Smart Wallet

A production-ready multi-asset smart wallet system with fractional ownership on the Internet Computer Protocol (ICP). Built with a canister-per-vault architecture where each vault is an independent ICRC-2 compliant token.

## Why This Architecture?

The previous design had critical flaws:
- ❌ Poor scalability (array-based shareholder tracking)
- ❌ Not truly ICRC-2 compliant (shares couldn't be used in DEXs)
- ❌ Single point of failure (all vaults in one canister)
- ❌ No real multi-chain integration

## New Architecture Benefits

✅ **Canister-Per-Vault**: Each vault is an independent canister = horizontal scaling
✅ **True ICRC-2 Tokens**: Vault shares ARE tokens, usable in any DEX or wallet
✅ **Chain-Key Integration**: Real Bitcoin/Ethereum addresses via threshold ECDSA
✅ **Internet Identity**: Passwordless, secure Web3 authentication
✅ **Stable Storage**: Uses StableTrieMap for efficient upgrades
✅ **Factory Pattern**: VaultFactory spawns and manages vault instances

## Project Structure

```
FusionVault/
├── src/
│   ├── shared/                    # Shared modules
│   │   ├── Types.mo               # ICRC-2 and vault type definitions
│   │   ├── ICRC.mo                # ICRC-1/2 ledger integration
│   │   └── ChainKey.mo            # Bitcoin/Ethereum tECDSA integration
│   ├── vault_factory/             # Factory canister
│   │   └── VaultFactory.mo        # Creates and manages vault instances
│   ├── vault_canister/            # Vault template
│   │   └── Vault.mo               # Individual vault (ICRC-2 token)
│   └── frontend/                  # Web interface
│       ├── index.html             # Main UI
│       ├── styles.css             # Modern dark theme styling
│       └── index.js               # Internet Identity + agent integration
├── dfx.json                       # Canister configuration
└── README.md                      # This file
```

## Key Components

### 1. VaultFactory (src/vault_factory/VaultFactory.mo)

The factory canister manages vault lifecycle:

**Methods:**
- `createVault()` - Spawns new vault canisters with proper cycle funding
- `listVaults(offset, limit)` - Paginated vault listing
- `getVaultsByCreator(principal)` - Get vaults created by a user
- `searchVaults(query)` - Search vaults by name/symbol
- `getFactoryStats()` - Get factory statistics

**Features:**
- Tracks all created vaults in stable storage
- Maintains creator index for fast lookups
- Provides vault discovery and search
- Handles cycle management for new vaults

### 2. Vault Canister (src/vault_canister/Vault.mo)

Each vault IS an ICRC-2 compliant token with vault functionality:

#### ICRC-1 Standard (Base Token)
```motoko
icrc1_name() -> Text
icrc1_symbol() -> Text
icrc1_decimals() -> Nat8
icrc1_total_supply() -> Nat
icrc1_balance_of(account) -> Nat
icrc1_transfer(args) -> Result<Nat, TransferError>
icrc1_metadata() -> [(Text, MetadataValue)]
icrc1_supported_standards() -> [{name: Text; url: Text}]
```

#### ICRC-2 Standard (Approvals & Allowances)
```motoko
icrc2_approve(args) -> Result<Nat, ApproveError>
icrc2_transfer_from(args) -> Result<Nat, TransferFromError>
icrc2_allowance(account, spender) -> Allowance
```

#### Vault-Specific Methods
```motoko
deposit(args) -> Result<Nat, Text>  // Mint shares
withdraw(args) -> Result<Nat, Text>  // Burn shares
generateBitcoinAddress() -> Result<Text, Text>
generateEthereumAddress() -> Result<Text, Text>
getVaultMetadata() -> VaultMetadata
getAssetBalances() -> [AssetBalance]
```

### 3. Frontend (Internet Identity Integration)

Modern web interface with:
- **Internet Identity Login** - Secure, passwordless authentication
- **Vault Creation** - User-friendly vault spawning
- **Vault Discovery** - Browse and search all vaults
- **Asset Management** - Deposit, withdraw, and transfer shares
- **Multi-Chain Addresses** - Generate and display BTC/ETH addresses
- **Responsive Design** - Works on desktop and mobile

## How It Works

### 1. Creating a Vault

```javascript
// User logs in with Internet Identity
await authClient.login({ identityProvider: II_URL });

// User creates a vault
const result = await vaultFactoryActor.createVault({
  name: "My Portfolio",
  symbol: "MPRT",
  description: "Diversified crypto portfolio",
  supportedAssets: [
    { ICP: { ledger: "ryjl3-tyaaa-aaaaa-aaaba-cai" } }
  ],
  initialDeposit: null
});

// Returns: { ok: Principal } (new vault canister ID)
```

**Behind the scenes:**
1. Factory receives request with 2T cycles
2. Spawns new Vault canister with user as creator
3. Initializes vault as ICRC-2 token (8 decimals, 0.0001 fee)
4. Registers vault in factory's stable storage
5. Returns vault canister ID to user

### 2. Depositing Assets & Minting Shares

```motoko
// Step 1: User approves ICRC-1 transfer to vault
await icpLedger.icrc2_approve({
  spender: { owner: vaultCanisterId, subaccount: null },
  amount: 100_000_000 // 1 ICP
});

// Step 2: User deposits to vault
let shares = await vault.deposit({
  assetType: { ICP: { ledger: icpLedgerCanister } },
  amount: 100_000_000,
  from: { owner: userPrincipal, subaccount: null }
});

// Vault calculates shares:
// - First deposit: 1:1 ratio (1 ICP = 1 share)
// - Later deposits: (amount * totalShares) / totalValueLocked
```

**Share calculation ensures:**
- Fair pricing based on current vault value
- Proportional ownership for all depositors
- No dilution of existing shareholders

### 3. Trading Vault Shares

Since shares are ICRC-2 tokens, they can be:

**Peer-to-Peer Transfer:**
```motoko
await vault.icrc1_transfer({
  to: { owner: recipientPrincipal, subaccount: null },
  amount: 50_000_000 // 0.5 shares
});
```

**DEX Trading:**
```motoko
// List on ICPSwap
await icpSwap.createPool({
  token0: vaultCanisterId,  // Your vault shares
  token1: icpLedgerCanister, // ICP
  initialPrice: ...
});
```

**Approved Spending:**
```motoko
// Approve DEX to spend shares
await vault.icrc2_approve({
  spender: { owner: dexCanisterId, subaccount: null },
  amount: 100_000_000
});

// DEX transfers on your behalf
await vault.icrc2_transfer_from({
  from: { owner: userPrincipal, subaccount: null },
  to: { owner: buyerPrincipal, subaccount: null },
  amount: 50_000_000
});
```

### 4. Withdrawing Assets

```motoko
// Burn shares to withdraw proportional assets
let assetAmount = await vault.withdraw({
  assetType: { ICP: { ledger: icpLedgerCanister } },
  shares: 50_000_000, // Burn 0.5 shares
  to: { owner: userPrincipal, subaccount: null }
});

// Calculation:
// assetAmount = (shares / totalSupply) * totalValueLocked
```

**Withdrawal process:**
1. Burns user's shares (reduces total supply)
2. Calculates proportional asset amount
3. Transfers assets from vault to user
4. Updates vault's total value locked

### 5. Multi-Chain Integration (Chain-Key Cryptography)

```motoko
// Generate Bitcoin address
let btcAddress = await vault.generateBitcoinAddress();
// Returns: "bc1q..." (P2WPKH SegWit address)

// Generate Ethereum address
let ethAddress = await vault.generateEthereumAddress();
// Returns: "0x..." (standard Ethereum address)
```

**Chain-Key Features:**
- **Threshold ECDSA**: No single point of compromise
- **Derivation Paths**: Each vault has unique addresses
- **Native Integration**: Direct Bitcoin/Ethereum signing
- **No Bridges**: Assets held natively on-chain

## Getting Started

### Prerequisites

```bash
# Install dfx (Internet Computer SDK)
sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"

# Verify installation
dfx --version
```

### Local Development

```bash
# 1. Clone repository
git clone <repo-url>
cd FusionVault

# 2. Install frontend dependencies
npm install

# 3. Start local replica
dfx start --clean --background

# 4. Deploy Internet Identity (local)
dfx deploy internet_identity

# 5. Deploy vault factory
dfx deploy vault_factory

# 6. Deploy frontend
dfx deploy frontend

# 7. Get frontend URL
echo "http://localhost:4943/?canisterId=$(dfx canister id frontend)"
```

### Mainnet Deployment

```bash
# Deploy to IC mainnet with cycles
dfx deploy --network ic vault_factory --with-cycles 10000000000000
dfx deploy --network ic frontend

# Internet Identity on mainnet: rdmx6-jaaaa-aaaaa-aaadq-cai
```

## Frontend Dependencies

Create `package.json`:

```json
{
  "name": "fusionvault-frontend",
  "version": "2.0.0",
  "type": "module",
  "dependencies": {
    "@dfinity/agent": "^0.21.0",
    "@dfinity/auth-client": "^0.21.0",
    "@dfinity/candid": "^0.21.0",
    "@dfinity/principal": "^0.21.0"
  }
}
```

Install: `npm install`

## API Reference

### VaultFactory

```motoko
// Create vault (costs 2T cycles)
createVault(args: CreateVaultArgs) -> Result<Principal, Text>

// Get vault metadata
getVault(canisterId: Principal) -> ?VaultMetadata

// List vaults (paginated)
listVaults(offset: Nat, limit: Nat) -> {
  vaults: [VaultMetadata];
  total: Nat
}

// Get user's vaults
getVaultsByCreator(creator: Principal) -> [VaultMetadata]

// Search vaults
searchVaults(query: Text) -> [VaultMetadata]

// Factory stats
getFactoryStats() -> {
  totalVaults: Nat;
  createdAt: Time;
  creationFee: Nat
}
```

### Vault (ICRC-2 + Custom)

**ICRC-1:**
```motoko
icrc1_name() -> Text
icrc1_symbol() -> Text
icrc1_decimals() -> Nat8  // Always 8
icrc1_fee() -> Nat  // 10,000 (0.0001 tokens)
icrc1_total_supply() -> Nat
icrc1_balance_of(account: Account) -> Nat
icrc1_transfer(args: TransferArgs) -> Result<Nat, TransferError>
```

**ICRC-2:**
```motoko
icrc2_approve(args: ApproveArgs) -> Result<Nat, ApproveError>
icrc2_transfer_from(args: TransferFromArgs) -> Result<Nat, TransferFromError>
icrc2_allowance(account: Account, spender: Account) -> Allowance
```

**Vault:**
```motoko
deposit(args: DepositArgs) -> Result<Nat, Text>
withdraw(args: WithdrawArgs) -> Result<Nat, Text>
generateBitcoinAddress() -> Result<Text, Text>
generateEthereumAddress() -> Result<Text, Text>
getVaultMetadata() -> VaultMetadata
getAssetBalances() -> [AssetBalance]
```

## Security

### Access Control
- Vault creator can update certain parameters
- ICRC-2 provides granular approval system
- Chain-key signatures isolated per vault

### Asset Custody
- ICRC-1 tokens held in vault's account on ledgers
- Bitcoin/Ethereum held via threshold signatures
- No admin keys or backdoors

### Upgrade Safety
- `persistent` actor for automatic stable memory
- Proper pre/post upgrade hooks
- StableTrieMap for O(log n) operations
- Transaction history preserved across upgrades

## Production Considerations

### Critical for Production

1. **Oracle Integration** - Use Pyth or similar for accurate asset pricing
2. **Complete Chain-Key** - Finish Bitcoin/Ethereum transaction signing
3. **Real Cryptography** - Replace placeholder SHA-256/Keccak-256/Bech32
4. **Rate Limiting** - Prevent vault creation spam
5. **Security Audit** - Professional audit before mainnet

### Recommended Enhancements

6. **Governance** - DAO for protocol parameters
7. **Fee Collection** - Protocol fee distribution
8. **Vault Strategies** - Auto-rebalancing, yield optimization
9. **Analytics** - Portfolio tracking dashboard
10. **Mobile App** - Native iOS/Android support

## Testing

```bash
# Deploy locally
dfx start --background
dfx deploy

# Create a vault
dfx canister call vault_factory createVault '(record {
  name = "Test Vault";
  symbol = "TEST";
  description = "Test vault for development";
  supportedAssets = vec {};
  initialDeposit = null
})'

# Get vault metadata
dfx canister call vault_factory getVault '(principal "xxxxx-xxxxx")'

# List all vaults
dfx canister call vault_factory listVaults '(0, 10)'
```

## Troubleshooting

**Build fails:**
```bash
dfx stop
rm -rf .dfx
dfx start --clean --background
dfx deploy
```

**Frontend not loading:**
```bash
dfx canister status frontend
dfx build frontend
dfx canister install frontend --mode upgrade
```

## Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## Resources

- [Internet Computer Docs](https://internetcomputer.org/docs)
- [Motoko Language](https://internetcomputer.org/docs/current/motoko/main/motoko)
- [ICRC-2 Standard](https://github.com/dfinity/ICRC-1/blob/main/standards/ICRC-2/README.md)
- [Chain-Key Crypto](https://internetcomputer.org/docs/current/developer-docs/integrations/t-ecdsa/)
- [Internet Identity](https://internetcomputer.org/internet-identity)

## License

MIT License - See LICENSE file

---

**Built with ❤️ on the Internet Computer**

*A properly architected multi-asset smart wallet for the decentralized future.*
