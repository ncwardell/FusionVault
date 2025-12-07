import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Types "Types";

module {
  // ICRC-1 Ledger Interface
  public type ICRC1 = actor {
    icrc1_name: query () -> async Text;
    icrc1_symbol: query () -> async Text;
    icrc1_decimals: query () -> async Nat8;
    icrc1_fee: query () -> async Nat;
    icrc1_metadata: query () -> async [(Text, Types.MetadataValue)];
    icrc1_total_supply: query () -> async Nat;
    icrc1_minting_account: query () -> async ?Types.Account;
    icrc1_balance_of: query (Types.Account) -> async Nat;
    icrc1_transfer: (Types.TransferArgs) -> async Result.Result<Nat, Types.TransferError>;
    icrc1_supported_standards: query () -> async [{
      name: Text;
      url: Text;
    }];
  };

  // ICRC-2 Ledger Interface (extends ICRC-1)
  public type ICRC2 = actor {
    // ICRC-1 methods
    icrc1_name: query () -> async Text;
    icrc1_symbol: query () -> async Text;
    icrc1_decimals: query () -> async Nat8;
    icrc1_fee: query () -> async Nat;
    icrc1_metadata: query () -> async [(Text, Types.MetadataValue)];
    icrc1_total_supply: query () -> async Nat;
    icrc1_minting_account: query () -> async ?Types.Account;
    icrc1_balance_of: query (Types.Account) -> async Nat;
    icrc1_transfer: (Types.TransferArgs) -> async Result.Result<Nat, Types.TransferError>;
    icrc1_supported_standards: query () -> async [{
      name: Text;
      url: Text;
    }];

    // ICRC-2 methods
    icrc2_approve: (Types.ApproveArgs) -> async Result.Result<Nat, Types.ApproveError>;
    icrc2_transfer_from: (Types.TransferFromArgs) -> async Result.Result<Nat, Types.TransferFromError>;
    icrc2_allowance: query ({
      account: Types.Account;
      spender: Types.Account;
    }) -> async Types.Allowance;
  };

  // Helper to get ICRC-1 ledger actor
  public func getLedger(canisterId: Principal): ICRC1 {
    actor (Principal.toText(canisterId)) : ICRC1
  };

  // Helper to get ICRC-2 ledger actor
  public func getLedger2(canisterId: Principal): ICRC2 {
    actor (Principal.toText(canisterId)) : ICRC2
  };

  // Transfer tokens from caller to vault
  public func transferToVault(
    ledger: Principal,
    from: Types.Account,
    vaultAccount: Types.Account,
    amount: Nat,
    memo: ?Blob
  ): async Result.Result<Nat, Types.TransferError> {
    let ledgerActor = getLedger(ledger);

    await ledgerActor.icrc1_transfer({
      from_subaccount = from.subaccount;
      to = vaultAccount;
      amount = amount;
      fee = null;
      memo = memo;
      created_at_time = null;
    })
  };

  // Transfer tokens from vault to recipient (using transferFrom with approval)
  public func transferFromVault(
    ledger: Principal,
    vaultAccount: Types.Account,
    to: Types.Account,
    amount: Nat,
    memo: ?Blob
  ): async Result.Result<Nat, Types.TransferFromError> {
    let ledgerActor = getLedger2(ledger);

    await ledgerActor.icrc2_transfer_from({
      spender_subaccount = null;
      from = vaultAccount;
      to = to;
      amount = amount;
      fee = null;
      memo = memo;
      created_at_time = null;
    })
  };

  // Get balance of account
  public func getBalance(
    ledger: Principal,
    account: Types.Account
  ): async Nat {
    let ledgerActor = getLedger(ledger);
    await ledgerActor.icrc1_balance_of(account)
  };

  // Get token metadata
  public func getMetadata(ledger: Principal): async {
    name: Text;
    symbol: Text;
    decimals: Nat8;
    fee: Nat;
  } {
    let ledgerActor = getLedger(ledger);
    let name = await ledgerActor.icrc1_name();
    let symbol = await ledgerActor.icrc1_symbol();
    let decimals = await ledgerActor.icrc1_decimals();
    let fee = await ledgerActor.icrc1_fee();

    { name; symbol; decimals; fee }
  };

  // Approve spending from vault account
  public func approve(
    ledger: Principal,
    spender: Types.Account,
    amount: Nat,
    fromSubaccount: ?Types.Subaccount
  ): async Result.Result<Nat, Types.ApproveError> {
    let ledgerActor = getLedger2(ledger);

    await ledgerActor.icrc2_approve({
      from_subaccount = fromSubaccount;
      spender = spender;
      amount = amount;
      expected_allowance = null;
      expires_at = null;
      fee = null;
      memo = null;
      created_at_time = null;
    })
  };

  // Check allowance
  public func getAllowance(
    ledger: Principal,
    account: Types.Account,
    spender: Types.Account
  ): async Types.Allowance {
    let ledgerActor = getLedger2(ledger);
    await ledgerActor.icrc2_allowance({ account; spender })
  };
}
