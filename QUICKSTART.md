# Quick Start Guide

Get your Fusion Vault running in 5 minutes!

## Prerequisites

Install the DFINITY Canister SDK:
```bash
sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"
```

## Local Development (5 Steps)

### 1. Start Local Replica
```bash
dfx start --clean --background
```

### 2. Deploy Canisters
```bash
dfx deploy
```

### 3. Open Frontend
The deploy command will output a URL like:
```
http://127.0.0.1:4943/?canisterId=xxxxx-xxxxx-xxxxx
```
Open this in your browser.

### 4. Create Your First Vault
1. Click "Connect Wallet" (in demo mode, it will auto-connect)
2. Enter a vault name like "My First Vault"
3. Click "Create Vault"

### 5. Make Your First Deposit
1. Click on your newly created vault
2. Select an asset type (e.g., ICP)
3. Enter an amount (e.g., 100000000 for 1 ICP)
4. Click "Deposit & Mint Shares"

Congratulations! You now have a tokenized multi-chain vault running locally! 🎉

## Testing with CLI

```bash
# Create a vault
dfx canister call vault createVault '("Test Vault")'

# Deposit assets
dfx canister call vault deposit '(0, variant { ICP }, 100_000_000)'

# Check your shares
dfx canister call vault icrc1_balance_of '(0, record { owner = principal "<your-principal>"; subaccount = null })'

# List all vaults
dfx canister call vault listVaults
```

## Next Steps

- Read the full [README.md](README.md) for detailed information
- Try depositing different asset types
- Transfer shares to another principal
- Redeem your shares for in-kind assets
- Generate BTC and ETH addresses for your vault

## Troubleshooting

**Issue**: `dfx` command not found
**Solution**: Make sure you've installed the SDK and restart your terminal

**Issue**: Deployment fails
**Solution**:
```bash
dfx stop
dfx start --clean --background
dfx deploy
```

**Issue**: Frontend won't load
**Solution**: Make sure you're using the correct canister ID from the deployment output

## Testing on ICP.Ninja

1. Build the canister:
   ```bash
   dfx build vault
   ```

2. Copy your Motoko code from `src/vault/main.mo`

3. Go to [icp.ninja](https://icp.ninja)

4. Paste the code and click "Deploy"

5. Interact with your canister directly in the browser!

---

Happy building! 🚀
