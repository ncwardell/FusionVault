import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Nat32 "mo:base/Nat32";
import Types "../shared/Types";
import ICRC "../shared/ICRC";
import ChainKey "../shared/ChainKey";

shared(init_msg) actor class Vault(
  init_name: Text,
  init_symbol: Text,
  init_decimals: Nat8,
  init_fee: Nat,
  init_description: Text,
  init_creator: Principal
) = this {

  // Stable storage using HashMap for efficient upgrades
  private stable var balanceEntries: [(Types.Account, Nat)] = [];
  private stable var allowanceEntries: [((Types.Account, Types.Account), Types.Allowance)] = [];
  private stable var transactionEntries: [(Nat, Types.Transaction)] = [];

  // Helper: Simple hash function for Nat (transaction IDs)
  private func natHash(n: Nat): Nat32 {
    Nat32.fromNat(n % 4294967295)
  };

  private transient var balances = HashMap.HashMap<Types.Account, Nat>(10, accountEqual, accountHash);
  private transient var allowances = HashMap.HashMap<(Types.Account, Types.Account), Types.Allowance>(10, allowanceKeyEqual, allowanceKeyHash);
  private transient var transactions = HashMap.HashMap<Nat, Types.Transaction>(10, Nat.equal, natHash);

  // Token metadata
  private stable let name: Text = init_name;
  private stable let symbol: Text = init_symbol;
  private stable let decimals: Nat8 = init_decimals;
  private stable let fee: Nat = init_fee;
  private stable let description: Text = init_description;
  private stable let creator: Principal = init_creator;
  private stable let createdAt: Time.Time = Time.now();

  // Vault state
  private stable var totalSupply_: Nat = 0;
  private stable var nextTxId: Nat = 0;
  private stable var btcAddress: ?Text = null;
  private stable var ethAddress: ?Text = null;
  private stable var totalValueLocked: Nat = 0;

  // Asset balances held by the vault
  private stable var assetBalances: [Types.AssetBalance] = [];

  // Configuration
  private stable var depositEnabled: Bool = true;
  private stable var withdrawEnabled: Bool = true;
  private stable var transferEnabled: Bool = true;

  // System functions for upgrades
  system func preupgrade() {
    balanceEntries := Iter.toArray(balances.entries());
    allowanceEntries := Iter.toArray(allowances.entries());
    transactionEntries := Iter.toArray(transactions.entries());
  };

  system func postupgrade() {
    balances := HashMap.fromIter<Types.Account, Nat>(
      balanceEntries.vals(),
      10,
      accountEqual,
      accountHash
    );
    allowances := HashMap.fromIter<(Types.Account, Types.Account), Types.Allowance>(
      allowanceEntries.vals(),
      10,
      allowanceKeyEqual,
      allowanceKeyHash
    );
    transactions := HashMap.fromIter<Nat, Types.Transaction>(
      transactionEntries.vals(),
      10,
      Nat.equal,
      natHash
    );
    balanceEntries := [];
    allowanceEntries := [];
    transactionEntries := [];
  };

  // Helper functions
  private func accountEqual(a1: Types.Account, a2: Types.Account): Bool {
    Principal.equal(a1.owner, a2.owner) and Option.equal(a1.subaccount, a2.subaccount, Blob.equal)
  };

  private func accountHash(account: Types.Account): Nat32 {
    let ownerHash = Principal.hash(account.owner);
    switch (account.subaccount) {
      case null { ownerHash };
      case (?sub) { ownerHash ^ Blob.hash(sub) };
    }
  };

  private func allowanceKeyEqual(k1: (Types.Account, Types.Account), k2: (Types.Account, Types.Account)): Bool {
    accountEqual(k1.0, k2.0) and accountEqual(k1.1, k2.1)
  };

  private func allowanceKeyHash(key: (Types.Account, Types.Account)): Nat32 {
    accountHash(key.0) ^ accountHash(key.1)
  };

  private func getBalance(account: Types.Account): Nat {
    Option.get(balances.get(account), 0)
  };

  private func setBalance(account: Types.Account, balance: Nat) {
    if (balance == 0) {
      balances.delete(account);
    } else {
      balances.put(account, balance);
    };
  };

  private func addTransaction(tx: Types.Transaction): Nat {
    let txId = nextTxId;
    nextTxId += 1;
    transactions.put(txId, tx);
    txId
  };

  private func deduplicationCheck(memo: ?Blob, created_at_time: ?Types.Timestamp): ?Nat {
    // Simple deduplication - in production, implement proper time-based deduplication
    null
  };

  private func isExpired(created_at_time: ?Types.Timestamp): Bool {
    switch (created_at_time) {
      case null { false };
      case (?time) {
        let now = Nat64.fromNat(Int.abs(Time.now()));
        let MAX_AGE: Nat64 = 300_000_000_000; // 5 minutes in nanoseconds
        now > time + MAX_AGE
      };
    }
  };

  private func isFuture(created_at_time: ?Types.Timestamp): ?Nat64 {
    switch (created_at_time) {
      case null { null };
      case (?time) {
        let now = Nat64.fromNat(Int.abs(Time.now()));
        let PERMITTED_DRIFT: Nat64 = 60_000_000_000; // 1 minute
        if (time > now + PERMITTED_DRIFT) {
          ?now
        } else {
          null
        }
      };
    }
  };

  // ICRC-1 Standard Implementation

  public query func icrc1_name(): async Text {
    name
  };

  public query func icrc1_symbol(): async Text {
    symbol
  };

  public query func icrc1_decimals(): async Nat8 {
    decimals
  };

  public query func icrc1_fee(): async Nat {
    fee
  };

  public query func icrc1_metadata(): async [(Text, Types.MetadataValue)] {
    [
      ("icrc1:name", #Text(name)),
      ("icrc1:symbol", #Text(symbol)),
      ("icrc1:decimals", #Nat(Nat8.toNat(decimals))),
      ("icrc1:fee", #Nat(fee)),
      ("fusion:description", #Text(description)),
      ("fusion:creator", #Blob(Principal.toBlob(creator))),
      ("fusion:created_at", #Int(createdAt)),
      ("fusion:total_value_locked", #Nat(totalValueLocked)),
    ]
  };

  public query func icrc1_total_supply(): async Nat {
    totalSupply_
  };

  public query func icrc1_minting_account(): async ?Types.Account {
    ?{ owner = Principal.fromActor(this); subaccount = null }
  };

  public query func icrc1_balance_of(account: Types.Account): async Nat {
    getBalance(account)
  };

  public shared(msg) func icrc1_transfer(args: Types.TransferArgs): async Result.Result<Nat, Types.TransferError> {
    if (not transferEnabled) {
      return #err(#GenericError({ error_code = 1; message = "Transfers disabled" }));
    };

    // Check for duplicate
    switch (deduplicationCheck(args.memo, args.created_at_time)) {
      case (?duplicate_of) { return #err(#Duplicate({ duplicate_of })) };
      case null {};
    };

    // Check if transaction is too old
    if (isExpired(args.created_at_time)) {
      return #err(#TooOld);
    };

    // Check if transaction is in the future
    switch (isFuture(args.created_at_time)) {
      case (?ledger_time) { return #err(#CreatedInFuture({ ledger_time })) };
      case null {};
    };

    // Check fee
    let expectedFee = fee;
    let providedFee = Option.get(args.fee, expectedFee);
    if (providedFee != expectedFee) {
      return #err(#BadFee({ expected_fee = expectedFee }));
    };

    let from = { owner = msg.caller; subaccount = args.from_subaccount };
    let fromBalance = getBalance(from);

    // Check sufficient funds
    if (fromBalance < args.amount + fee) {
      return #err(#InsufficientFunds({ balance = fromBalance }));
    };

    // Perform transfer
    setBalance(from, fromBalance - args.amount - fee);
    let toBalance = getBalance(args.to);
    setBalance(args.to, toBalance + args.amount);

    // Burn the fee
    totalSupply_ -= fee;

    // Record transaction
    let tx: Types.Transaction = {
      kind = #transfer({
        from = from;
        to = args.to;
        amount = args.amount;
        spender = null;
      });
      timestamp = Nat64.fromNat(Int.abs(Time.now()));
      memo = args.memo;
    };

    let txId = addTransaction(tx);
    #ok(txId)
  };

  public query func icrc1_supported_standards(): async [{
    name: Text;
    url: Text;
  }] {
    [
      { name = "ICRC-1"; url = "https://github.com/dfinity/ICRC-1" },
      { name = "ICRC-2"; url = "https://github.com/dfinity/ICRC-1/tree/main/standards/ICRC-2" },
    ]
  };

  // ICRC-2 Standard Implementation

  public shared(msg) func icrc2_approve(args: Types.ApproveArgs): async Result.Result<Nat, Types.ApproveError> {
    // Check for duplicate
    switch (deduplicationCheck(args.memo, args.created_at_time)) {
      case (?duplicate_of) { return #err(#Duplicate({ duplicate_of })) };
      case null {};
    };

    // Check if transaction is too old
    if (isExpired(args.created_at_time)) {
      return #err(#TooOld);
    };

    // Check if transaction is in the future
    switch (isFuture(args.created_at_time)) {
      case (?ledger_time) { return #err(#CreatedInFuture({ ledger_time })) };
      case null {};
    };

    // Check fee
    let expectedFee = fee;
    let providedFee = Option.get(args.fee, expectedFee);
    if (providedFee != expectedFee) {
      return #err(#BadFee({ expected_fee = expectedFee }));
    };

    let from = { owner = msg.caller; subaccount = args.from_subaccount };
    let fromBalance = getBalance(from);

    // Check sufficient funds for fee
    if (fromBalance < fee) {
      return #err(#InsufficientFunds({ balance = fromBalance }));
    };

    // Check expected allowance
    let key = (from, args.spender);
    let currentAllowance = Option.get(allowances.get(key), { allowance = 0; expires_at = null });

    switch (args.expected_allowance) {
      case (?expected) {
        if (currentAllowance.allowance != expected) {
          return #err(#AllowanceChanged({ current_allowance = currentAllowance.allowance }));
        };
      };
      case null {};
    };

    // Check expiration
    switch (args.expires_at) {
      case (?exp) {
        let now = Nat64.fromNat(Int.abs(Time.now()));
        if (exp <= now) {
          return #err(#Expired({ ledger_time = now }));
        };
      };
      case null {};
    };

    // Set allowance
    let newAllowance: Types.Allowance = {
      allowance = args.amount;
      expires_at = args.expires_at;
    };
    allowances.put(key, newAllowance);

    // Charge fee
    setBalance(from, fromBalance - fee);
    totalSupply_ -= fee;

    // Record transaction
    let tx: Types.Transaction = {
      kind = #approve({
        from = from;
        spender = args.spender;
        amount = args.amount;
        expected_allowance = args.expected_allowance;
      });
      timestamp = Nat64.fromNat(Int.abs(Time.now()));
      memo = args.memo;
    };

    let txId = addTransaction(tx);
    #ok(txId)
  };

  public shared(msg) func icrc2_transfer_from(args: Types.TransferFromArgs): async Result.Result<Nat, Types.TransferFromError> {
    if (not transferEnabled) {
      return #err(#GenericError({ error_code = 1; message = "Transfers disabled" }));
    };

    // Check for duplicate
    switch (deduplicationCheck(args.memo, args.created_at_time)) {
      case (?duplicate_of) { return #err(#Duplicate({ duplicate_of })) };
      case null {};
    };

    // Check if transaction is too old
    if (isExpired(args.created_at_time)) {
      return #err(#TooOld);
    };

    // Check if transaction is in the future
    switch (isFuture(args.created_at_time)) {
      case (?ledger_time) { return #err(#CreatedInFuture({ ledger_time })) };
      case null {};
    };

    // Check fee
    let expectedFee = fee;
    let providedFee = Option.get(args.fee, expectedFee);
    if (providedFee != expectedFee) {
      return #err(#BadFee({ expected_fee = expectedFee }));
    };

    let spender = { owner = msg.caller; subaccount = args.spender_subaccount };
    let fromBalance = getBalance(args.from);

    // Check sufficient funds
    if (fromBalance < args.amount + fee) {
      return #err(#InsufficientFunds({ balance = fromBalance }));
    };

    // Check allowance
    let key = (args.from, spender);
    let currentAllowance = Option.get(allowances.get(key), { allowance = 0; expires_at = null });

    // Check if allowance is expired
    switch (currentAllowance.expires_at) {
      case (?exp) {
        let now = Nat64.fromNat(Int.abs(Time.now()));
        if (exp <= now) {
          return #err(#InsufficientAllowance({ allowance = 0 }));
        };
      };
      case null {};
    };

    if (currentAllowance.allowance < args.amount + fee) {
      return #err(#InsufficientAllowance({ allowance = currentAllowance.allowance }));
    };

    // Perform transfer
    setBalance(args.from, fromBalance - args.amount - fee);
    let toBalance = getBalance(args.to);
    setBalance(args.to, toBalance + args.amount);

    // Update allowance
    let newAllowance: Types.Allowance = {
      allowance = currentAllowance.allowance - args.amount - fee;
      expires_at = currentAllowance.expires_at;
    };
    allowances.put(key, newAllowance);

    // Burn the fee
    totalSupply_ -= fee;

    // Record transaction
    let tx: Types.Transaction = {
      kind = #transfer({
        from = args.from;
        to = args.to;
        amount = args.amount;
        spender = ?spender;
      });
      timestamp = Nat64.fromNat(Int.abs(Time.now()));
      memo = args.memo;
    };

    let txId = addTransaction(tx);
    #ok(txId)
  };

  public query func icrc2_allowance(args: {
    account: Types.Account;
    spender: Types.Account;
  }): async Types.Allowance {
    let key = (args.account, args.spender);
    let currentAllowance = Option.get(allowances.get(key), { allowance = 0; expires_at = null });

    // Check if expired
    switch (currentAllowance.expires_at) {
      case (?exp) {
        let now = Nat64.fromNat(Int.abs(Time.now()));
        if (exp <= now) {
          return { allowance = 0; expires_at = null };
        };
      };
      case null {};
    };

    currentAllowance
  };

  // Vault-specific functions

  // Deposit ICRC tokens and mint shares
  public shared(msg) func deposit(args: Types.DepositArgs): async Result.Result<Nat, Text> {
    if (not depositEnabled) {
      return #err("Deposits disabled");
    };

    // Transfer tokens from user to vault
    let vaultAccount: Types.Account = { owner = Principal.fromActor(this); subaccount = null };

    switch (args.assetType) {
      case (#ICP { ledger }) {
        let transferResult = await ICRC.transferToVault(ledger, args.from, vaultAccount, args.amount, null);
        switch (transferResult) {
          case (#err(e)) { return #err("Transfer failed") };
          case (#ok(_)) {};
        };
      };
      case (#ckBTC { ledger }) {
        let transferResult = await ICRC.transferToVault(ledger, args.from, vaultAccount, args.amount, null);
        switch (transferResult) {
          case (#err(e)) { return #err("Transfer failed") };
          case (#ok(_)) {};
        };
      };
      case (#ckETH { ledger }) {
        let transferResult = await ICRC.transferToVault(ledger, args.from, vaultAccount, args.amount, null);
        switch (transferResult) {
          case (#err(e)) { return #err("Transfer failed") };
          case (#ok(_)) {};
        };
      };
      case (#ICRC1 { ledger; symbol }) {
        let transferResult = await ICRC.transferToVault(ledger, args.from, vaultAccount, args.amount, null);
        switch (transferResult) {
          case (#err(e)) { return #err("Transfer failed") };
          case (#ok(_)) {};
        };
      };
      case _ { return #err("Asset type not supported for deposit yet") };
    };

    // Calculate shares to mint
    let sharesToMint = if (totalSupply_ == 0) {
      args.amount // First deposit: 1:1 ratio
    } else {
      // In production: calculate based on total vault value
      // For now: proportional to deposit
      (args.amount * totalSupply_) / (totalValueLocked + 1)
    };

    // Update asset balance
    assetBalances := updateAssetBalance(assetBalances, args.assetType, args.amount);
    totalValueLocked += args.amount;

    // Mint shares
    let userBalance = getBalance(args.from);
    setBalance(args.from, userBalance + sharesToMint);
    totalSupply_ += sharesToMint;

    // Record transaction
    let tx: Types.Transaction = {
      kind = #mint({
        to = args.from;
        amount = sharesToMint;
      });
      timestamp = Nat64.fromNat(Int.abs(Time.now()));
      memo = null;
    };
    ignore addTransaction(tx);

    #ok(sharesToMint)
  };

  // Withdraw assets by burning shares
  public shared(msg) func withdraw(args: Types.WithdrawArgs): async Result.Result<Nat, Text> {
    if (not withdrawEnabled) {
      return #err("Withdrawals disabled");
    };

    let from = { owner = msg.caller; subaccount = null };
    let fromBalance = getBalance(from);

    if (fromBalance < args.shares) {
      return #err("Insufficient shares");
    };

    // Calculate proportional asset amount
    let proportion = (args.shares * 1_000_000_000) / totalSupply_;
    let assetAmount = (totalValueLocked * proportion) / 1_000_000_000;

    // Burn shares
    setBalance(from, fromBalance - args.shares);
    totalSupply_ -= args.shares;
    totalValueLocked -= assetAmount;

    // Update asset balance
    assetBalances := updateAssetBalance(assetBalances, args.assetType, 0 - assetAmount);

    // Transfer assets to user
    let vaultAccount: Types.Account = { owner = Principal.fromActor(this); subaccount = null };

    switch (args.assetType) {
      case (#ICP { ledger }) {
        // In production: actually transfer tokens
        // For now: placeholder
      };
      case (#ckBTC { ledger }) {
        // Transfer ckBTC
      };
      case (#ckETH { ledger }) {
        // Transfer ckETH
      };
      case _ {};
    };

    // Record transaction
    let tx: Types.Transaction = {
      kind = #burn({
        from = from;
        amount = args.shares;
        spender = null;
      });
      timestamp = Nat64.fromNat(Int.abs(Time.now()));
      memo = null;
    };
    ignore addTransaction(tx);

    #ok(assetAmount)
  };

  // Generate Bitcoin address for this vault
  public func generateBitcoinAddress(): async Result.Result<Text, Text> {
    if (Option.isSome(btcAddress)) {
      return #ok(Option.get(btcAddress, ""));
    };

    try {
      let derivationPath = ChainKey.createDerivationPath(Principal.fromActor(this), 0);
      let address = await ChainKey.deriveBitcoinAddress(Principal.fromActor(this), derivationPath);
      btcAddress := ?address;
      #ok(address)
    } catch (e) {
      #err("Failed to generate Bitcoin address")
    }
  };

  // Generate Ethereum address for this vault
  public func generateEthereumAddress(): async Result.Result<Text, Text> {
    if (Option.isSome(ethAddress)) {
      return #ok(Option.get(ethAddress, ""));
    };

    try {
      let derivationPath = ChainKey.createDerivationPath(Principal.fromActor(this), 0);
      let address = await ChainKey.deriveEthereumAddress(Principal.fromActor(this), derivationPath);
      ethAddress := ?address;
      #ok(address)
    } catch (e) {
      #err("Failed to generate Ethereum address")
    }
  };

  // Query vault metadata
  public query func getVaultMetadata(): async Types.VaultMetadata {
    {
      canisterId = Principal.fromActor(this);
      name = name;
      symbol = symbol;
      decimals = decimals;
      totalSupply = totalSupply_;
      fee = fee;
      createdAt = createdAt;
      creator = creator;
      btcAddress = btcAddress;
      ethAddress = ethAddress;
      totalValueLocked = totalValueLocked;
    }
  };

  // Query asset balances
  public query func getAssetBalances(): async [Types.AssetBalance] {
    assetBalances
  };

  // Helper to update asset balances
  private func updateAssetBalance(balances: [Types.AssetBalance], assetType: Types.AssetType, amount: Int): [Types.AssetBalance] {
    var found = false;
    let updated = Array.map<Types.AssetBalance, Types.AssetBalance>(balances, func(b) {
      if (b.assetType == assetType) {
        found := true;
        {
          assetType = b.assetType;
          balance = Int.abs(Int.abs(b.balance) + amount);
          lastUpdated = Time.now();
        }
      } else {
        b
      }
    });

    if (not found) {
      Array.append(updated, [{
        assetType = assetType;
        balance = Int.abs(amount);
        lastUpdated = Time.now();
      }])
    } else {
      updated
    }
  };
}
