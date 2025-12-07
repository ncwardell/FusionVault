import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Blob "mo:base/Blob";

module {
  // ICRC-1/2 Standard Types
  public type Subaccount = Blob;

  public type Account = {
    owner: Principal;
    subaccount: ?Subaccount;
  };

  public type Timestamp = Nat64;

  public type TransferArgs = {
    from_subaccount: ?Subaccount;
    to: Account;
    amount: Nat;
    fee: ?Nat;
    memo: ?Blob;
    created_at_time: ?Timestamp;
  };

  public type TransferError = {
    #BadFee: { expected_fee: Nat };
    #BadBurn: { min_burn_amount: Nat };
    #InsufficientFunds: { balance: Nat };
    #TooOld;
    #CreatedInFuture: { ledger_time: Timestamp };
    #Duplicate: { duplicate_of: Nat };
    #TemporarilyUnavailable;
    #GenericError: { error_code: Nat; message: Text };
  };

  public type ApproveArgs = {
    from_subaccount: ?Subaccount;
    spender: Account;
    amount: Nat;
    expected_allowance: ?Nat;
    expires_at: ?Timestamp;
    fee: ?Nat;
    memo: ?Blob;
    created_at_time: ?Timestamp;
  };

  public type ApproveError = {
    #BadFee: { expected_fee: Nat };
    #InsufficientFunds: { balance: Nat };
    #AllowanceChanged: { current_allowance: Nat };
    #Expired: { ledger_time: Nat64 };
    #TooOld;
    #CreatedInFuture: { ledger_time: Nat64 };
    #Duplicate: { duplicate_of: Nat };
    #TemporarilyUnavailable;
    #GenericError: { error_code: Nat; message: Text };
  };

  public type TransferFromArgs = {
    spender_subaccount: ?Subaccount;
    from: Account;
    to: Account;
    amount: Nat;
    fee: ?Nat;
    memo: ?Blob;
    created_at_time: ?Timestamp;
  };

  public type TransferFromError = {
    #BadFee: { expected_fee: Nat };
    #BadBurn: { min_burn_amount: Nat };
    #InsufficientFunds: { balance: Nat };
    #InsufficientAllowance: { allowance: Nat };
    #TooOld;
    #CreatedInFuture: { ledger_time: Timestamp };
    #Duplicate: { duplicate_of: Nat };
    #TemporarilyUnavailable;
    #GenericError: { error_code: Nat; message: Text };
  };

  public type Allowance = {
    allowance: Nat;
    expires_at: ?Timestamp;
  };

  public type MetadataValue = {
    #Nat: Nat;
    #Int: Int;
    #Text: Text;
    #Blob: Blob;
  };

  // Asset Types
  public type AssetType = {
    #ICP: { ledger: Principal }; // ICRC-1 ledger canister
    #ckBTC: { ledger: Principal }; // Chain-key Bitcoin
    #ckETH: { ledger: Principal }; // Chain-key Ethereum
    #Bitcoin; // Native BTC via tECDSA
    #Ethereum; // Native ETH via tECDSA
    #ICRC1: { ledger: Principal; symbol: Text }; // Any ICRC-1 token
  };

  public type AssetBalance = {
    assetType: AssetType;
    balance: Nat;
    lastUpdated: Time.Time;
  };

  // Vault Configuration
  public type VaultConfig = {
    name: Text;
    symbol: Text;
    description: Text;
    supportedAssets: [AssetType];
    depositEnabled: Bool;
    withdrawEnabled: Bool;
    transferEnabled: Bool;
  };

  // Vault Metadata
  public type VaultMetadata = {
    canisterId: Principal;
    name: Text;
    symbol: Text;
    decimals: Nat8;
    totalSupply: Nat;
    fee: Nat;
    createdAt: Time.Time;
    creator: Principal;
    btcAddress: ?Text;
    ethAddress: ?Text;
    totalValueLocked: Nat; // In smallest unit
  };

  // Transaction Types
  public type TxIndex = Nat;

  public type Transaction = {
    kind: {
      #mint: { to: Account; amount: Nat };
      #burn: { from: Account; amount: Nat; spender: ?Account };
      #transfer: { from: Account; to: Account; amount: Nat; spender: ?Account };
      #approve: { from: Account; spender: Account; amount: Nat; expected_allowance: ?Nat };
    };
    timestamp: Timestamp;
    memo: ?Blob;
  };

  // Chain-Key Signature Types
  public type ECDSAPublicKey = {
    canister_id: ?Principal;
    derivation_path: [Blob];
    key_id: { curve: { #secp256k1 }; name: Text };
  };

  public type ECDSAPublicKeyResponse = {
    public_key: Blob;
    chain_code: Blob;
  };

  public type SignWithECDSA = {
    message_hash: Blob;
    derivation_path: [Blob];
    key_id: { curve: { #secp256k1 }; name: Text };
  };

  public type SignWithECDSAResponse = {
    signature: Blob;
  };

  // Deposit/Withdraw Types
  public type DepositArgs = {
    assetType: AssetType;
    amount: Nat;
    from: Account;
  };

  public type WithdrawArgs = {
    assetType: AssetType;
    shares: Nat;
    to: Account;
  };

  // Factory Types
  public type CreateVaultArgs = {
    name: Text;
    symbol: Text;
    description: Text;
    supportedAssets: [AssetType];
    initialDeposit: ?{
      assetType: AssetType;
      amount: Nat;
    };
  };
}
