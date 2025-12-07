import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Option "mo:base/Option";

actor VaultManager {

  // Types
  type VaultId = Nat;
  type AccountId = Blob;
  type Subaccount = Blob;

  // Asset types supported
  type AssetType = {
    #ICP;
    #BTC;
    #ETH;
    #USDC;
    #USDT;
  };

  // Asset balance
  type AssetBalance = {
    assetType: AssetType;
    amount: Nat;
  };

  // Vault structure
  type Vault = {
    id: VaultId;
    name: Text;
    owner: Principal;
    totalShares: Nat;
    shareHolders: [(Principal, Nat)]; // Principal -> share balance
    assets: [AssetBalance];
    btcAddress: ?Text;
    ethAddress: ?Text;
    icpAddress: ?AccountId;
    createdAt: Time.Time;
  };

  // ICRC-2 Token types
  type Account = {
    owner: Principal;
    subaccount: ?Subaccount;
  };

  type TransferArgs = {
    from_subaccount: ?Subaccount;
    to: Account;
    amount: Nat;
    fee: ?Nat;
    memo: ?Blob;
    created_at_time: ?Nat64;
  };

  type TransferError = {
    #BadFee: { expected_fee: Nat };
    #BadBurn: { min_burn_amount: Nat };
    #InsufficientFunds: { balance: Nat };
    #TooOld;
    #CreatedInFuture: { ledger_time: Nat64 };
    #Duplicate: { duplicate_of: Nat };
    #TemporarilyUnavailable;
    #GenericError: { error_code: Nat; message: Text };
  };

  // State
  private stable var nextVaultId: Nat = 0;
  private var vaults = HashMap.HashMap<VaultId, Vault>(10, Nat.equal, Hash.hash);
  private stable var vaultsEntries: [(VaultId, Vault)] = [];

  // Token decimals (8 decimals like BTC)
  private let DECIMALS: Nat8 = 8;
  private let FEE: Nat = 10_000; // 0.0001 tokens

  // System functions for upgrades
  system func preupgrade() {
    vaultsEntries := Iter.toArray(vaults.entries());
  };

  system func postupgrade() {
    vaults := HashMap.fromIter<VaultId, Vault>(
      vaultsEntries.vals(),
      10,
      Nat.equal,
      Hash.hash
    );
    vaultsEntries := [];
  };

  // Helper functions
  private func accountId(p: Principal, subaccount: ?Subaccount): AccountId {
    // Simplified - in production, use proper account identifier derivation
    let sub = Option.get(subaccount, Text.encodeUtf8(""));
    Principal.toBlob(p);
  };

  private func findAssetBalance(assets: [AssetBalance], assetType: AssetType): Nat {
    switch (Array.find<AssetBalance>(assets, func(a) { a.assetType == assetType })) {
      case (?asset) { asset.amount };
      case null { 0 };
    };
  };

  private func updateAssetBalance(assets: [AssetBalance], assetType: AssetType, newAmount: Nat): [AssetBalance] {
    let buffer = Buffer.Buffer<AssetBalance>(assets.size());
    var found = false;

    for (asset in assets.vals()) {
      if (asset.assetType == assetType) {
        buffer.add({ assetType = assetType; amount = newAmount });
        found := true;
      } else {
        buffer.add(asset);
      };
    };

    if (not found) {
      buffer.add({ assetType = assetType; amount = newAmount });
    };

    Buffer.toArray(buffer);
  };

  // Create a new vault
  public shared(msg) func createVault(name: Text): async Result.Result<VaultId, Text> {
    let vaultId = nextVaultId;
    nextVaultId += 1;

    let vault: Vault = {
      id = vaultId;
      name = name;
      owner = msg.caller;
      totalShares = 0;
      shareHolders = [];
      assets = [];
      btcAddress = null; // Will be generated via threshold ECDSA
      ethAddress = null; // Will be generated via threshold ECDSA
      icpAddress = ?accountId(msg.caller, null);
      createdAt = Time.now();
    };

    vaults.put(vaultId, vault);
    #ok(vaultId);
  };

  // Get vault info
  public query func getVault(vaultId: VaultId): async ?Vault {
    vaults.get(vaultId);
  };

  // List all vaults
  public query func listVaults(): async [Vault] {
    Iter.toArray(vaults.vals());
  };

  // Deposit assets to vault and mint shares
  public shared(msg) func deposit(
    vaultId: VaultId,
    assetType: AssetType,
    amount: Nat
  ): async Result.Result<Nat, Text> {
    switch (vaults.get(vaultId)) {
      case null { #err("Vault not found") };
      case (?vault) {
        // Calculate shares to mint
        // If first deposit, shares = amount
        // Otherwise, shares = (amount * totalShares) / totalAssetValue
        let currentAssetAmount = findAssetBalance(vault.assets, assetType);
        let newAssetAmount = currentAssetAmount + amount;

        let sharesToMint = if (vault.totalShares == 0) {
          amount // First deposit: 1:1 ratio
        } else {
          // Simplified: in production, calculate based on total vault value
          // For now, proportional to the specific asset
          if (currentAssetAmount == 0) {
            amount
          } else {
            (amount * vault.totalShares) / currentAssetAmount
          };
        };

        // Update vault assets
        let updatedAssets = updateAssetBalance(vault.assets, assetType, newAssetAmount);

        // Update shareholder balances
        let updatedShareHolders = updateShareHolderBalance(vault.shareHolders, msg.caller, sharesToMint);

        // Update vault
        let updatedVault: Vault = {
          id = vault.id;
          name = vault.name;
          owner = vault.owner;
          totalShares = vault.totalShares + sharesToMint;
          shareHolders = updatedShareHolders;
          assets = updatedAssets;
          btcAddress = vault.btcAddress;
          ethAddress = vault.ethAddress;
          icpAddress = vault.icpAddress;
          createdAt = vault.createdAt;
        };

        vaults.put(vaultId, updatedVault);
        #ok(sharesToMint);
      };
    };
  };

  private func updateShareHolderBalance(
    shareHolders: [(Principal, Nat)],
    holder: Principal,
    additionalShares: Nat
  ): [(Principal, Nat)] {
    let buffer = Buffer.Buffer<(Principal, Nat)>(shareHolders.size());
    var found = false;

    for ((principal, shares) in shareHolders.vals()) {
      if (Principal.equal(principal, holder)) {
        buffer.add((principal, shares + additionalShares));
        found := true;
      } else {
        buffer.add((principal, shares));
      };
    };

    if (not found) {
      buffer.add((holder, additionalShares));
    };

    Buffer.toArray(buffer);
  };

  // Redeem shares for in-kind assets
  public shared(msg) func redeem(
    vaultId: VaultId,
    shares: Nat
  ): async Result.Result<[AssetBalance], Text> {
    switch (vaults.get(vaultId)) {
      case null { #err("Vault not found") };
      case (?vault) {
        // Check if caller has enough shares
        let callerShares = getShareHolderBalance(vault.shareHolders, msg.caller);
        if (callerShares < shares) {
          return #err("Insufficient shares");
        };

        // Calculate proportional asset amounts to return
        let proportion = shares * 1_000_000 / vault.totalShares; // Using fixed point math
        let assetsToReturn = Buffer.Buffer<AssetBalance>(vault.assets.size());
        let remainingAssets = Buffer.Buffer<AssetBalance>(vault.assets.size());

        for (asset in vault.assets.vals()) {
          let amountToReturn = (asset.amount * proportion) / 1_000_000;
          let remainingAmount = asset.amount - amountToReturn;

          assetsToReturn.add({
            assetType = asset.assetType;
            amount = amountToReturn;
          });

          if (remainingAmount > 0) {
            remainingAssets.add({
              assetType = asset.assetType;
              amount = remainingAmount;
            });
          };
        };

        // Update shareholder balances
        let updatedShareHolders = updateShareHolderBalance(
          vault.shareHolders,
          msg.caller,
          -shares // Subtract shares
        );

        // Filter out shareholders with 0 shares
        let filteredShareHolders = Array.filter<(Principal, Nat)>(
          updatedShareHolders,
          func((_, s)) { s > 0 }
        );

        // Update vault
        let updatedVault: Vault = {
          id = vault.id;
          name = vault.name;
          owner = vault.owner;
          totalShares = vault.totalShares - shares;
          shareHolders = filteredShareHolders;
          assets = Buffer.toArray(remainingAssets);
          btcAddress = vault.btcAddress;
          ethAddress = vault.ethAddress;
          icpAddress = vault.icpAddress;
          createdAt = vault.createdAt;
        };

        vaults.put(vaultId, updatedVault);

        // In production, actually transfer the assets to the caller
        // For now, just return what they would receive
        #ok(Buffer.toArray(assetsToReturn));
      };
    };
  };

  private func getShareHolderBalance(
    shareHolders: [(Principal, Nat)],
    holder: Principal
  ): Nat {
    switch (Array.find<(Principal, Nat)>(shareHolders, func((p, _)) { Principal.equal(p, holder) })) {
      case (?(_, shares)) { shares };
      case null { 0 };
    };
  };

  // ICRC-2 Token Standard Functions

  // Get balance of shares for a specific vault
  public query func icrc1_balance_of(vaultId: VaultId, account: Account): async Nat {
    switch (vaults.get(vaultId)) {
      case null { 0 };
      case (?vault) {
        getShareHolderBalance(vault.shareHolders, account.owner);
      };
    };
  };

  // Get total supply of shares for a vault
  public query func icrc1_total_supply(vaultId: VaultId): async Nat {
    switch (vaults.get(vaultId)) {
      case null { 0 };
      case (?vault) { vault.totalShares };
    };
  };

  // Transfer shares between accounts
  public shared(msg) func icrc1_transfer(
    vaultId: VaultId,
    args: TransferArgs
  ): async Result.Result<Nat, TransferError> {
    switch (vaults.get(vaultId)) {
      case null {
        #err(#GenericError({ error_code = 404; message = "Vault not found" }));
      };
      case (?vault) {
        let from = msg.caller;
        let to = args.to.owner;
        let amount = args.amount;

        // Check balance
        let fromBalance = getShareHolderBalance(vault.shareHolders, from);
        if (fromBalance < amount + FEE) {
          return #err(#InsufficientFunds({ balance = fromBalance }));
        };

        // Update balances
        var updatedShareHolders = updateShareHolderBalance(
          vault.shareHolders,
          from,
          -(amount + FEE) // Subtract amount + fee
        );

        updatedShareHolders := updateShareHolderBalance(
          updatedShareHolders,
          to,
          amount
        );

        // Update vault
        let updatedVault: Vault = {
          id = vault.id;
          name = vault.name;
          owner = vault.owner;
          totalShares = vault.totalShares - FEE; // Fee is burned
          shareHolders = updatedShareHolders;
          assets = vault.assets;
          btcAddress = vault.btcAddress;
          ethAddress = vault.ethAddress;
          icpAddress = vault.icpAddress;
          createdAt = vault.createdAt;
        };

        vaults.put(vaultId, updatedVault);
        #ok(0); // Transaction index (simplified)
      };
    };
  };

  // Get token metadata
  public query func icrc1_metadata(vaultId: VaultId): async [(Text, { #Nat: Nat; #Text: Text })] {
    switch (vaults.get(vaultId)) {
      case null { [] };
      case (?vault) {
        [
          ("icrc1:name", #Text("Vault Share Token - " # vault.name)),
          ("icrc1:symbol", #Text("VST")),
          ("icrc1:decimals", #Nat(Nat8.toNat(DECIMALS))),
          ("icrc1:fee", #Nat(FEE)),
        ];
      };
    };
  };

  public query func icrc1_name(vaultId: VaultId): async Text {
    switch (vaults.get(vaultId)) {
      case null { "Unknown Vault" };
      case (?vault) { "Vault Share Token - " # vault.name };
    };
  };

  public query func icrc1_symbol(): async Text {
    "VST";
  };

  public query func icrc1_decimals(): async Nat8 {
    DECIMALS;
  };

  public query func icrc1_fee(): async Nat {
    FEE;
  };

  // Multi-chain address generation (placeholder for threshold signatures)
  // In production, these would call ecdsa_public_key and sign_with_ecdsa

  public shared(msg) func generateBtcAddress(vaultId: VaultId): async Result.Result<Text, Text> {
    switch (vaults.get(vaultId)) {
      case null { #err("Vault not found") };
      case (?vault) {
        // TODO: Implement actual BTC address generation using threshold ECDSA
        // For now, return a placeholder
        let btcAddr = "bc1q" # Nat.toText(vaultId) # "placeholder";

        let updatedVault: Vault = {
          id = vault.id;
          name = vault.name;
          owner = vault.owner;
          totalShares = vault.totalShares;
          shareHolders = vault.shareHolders;
          assets = vault.assets;
          btcAddress = ?btcAddr;
          ethAddress = vault.ethAddress;
          icpAddress = vault.icpAddress;
          createdAt = vault.createdAt;
        };

        vaults.put(vaultId, updatedVault);
        #ok(btcAddr);
      };
    };
  };

  public shared(msg) func generateEthAddress(vaultId: VaultId): async Result.Result<Text, Text> {
    switch (vaults.get(vaultId)) {
      case null { #err("Vault not found") };
      case (?vault) {
        // TODO: Implement actual ETH address generation using threshold ECDSA
        // For now, return a placeholder
        let ethAddr = "0x" # Nat.toText(vaultId) # "placeholder";

        let updatedVault: Vault = {
          id = vault.id;
          name = vault.name;
          owner = vault.owner;
          totalShares = vault.totalShares;
          shareHolders = vault.shareHolders;
          assets = vault.assets;
          btcAddress = vault.btcAddress;
          ethAddress = ?ethAddr;
          icpAddress = vault.icpAddress;
          createdAt = vault.createdAt;
        };

        vaults.put(vaultId, updatedVault);
        #ok(ethAddr);
      };
    };
  };

  // Get all balances for a user across all vaults
  public query func getUserBalances(user: Principal): async [(VaultId, Nat)] {
    let buffer = Buffer.Buffer<(VaultId, Nat)>(10);

    for ((vaultId, vault) in vaults.entries()) {
      let balance = getShareHolderBalance(vault.shareHolders, user);
      if (balance > 0) {
        buffer.add((vaultId, balance));
      };
    };

    Buffer.toArray(buffer);
  };
};
