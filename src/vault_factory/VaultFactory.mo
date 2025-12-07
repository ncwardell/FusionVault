import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Result "mo:base/Result";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Cycles "mo:base/ExperimentalCycles";
import Types "../shared/Types";
import Vault "../vault_canister/Vault";
import StableTrieMap "mo:StableTrieMap";

actor VaultFactory {

  // Stable storage for vault registry
  private stable var vaultEntries: [(Principal, Types.VaultMetadata)] = [];
  private var vaults = StableTrieMap.StableTrieMap<Principal, Types.VaultMetadata>(0, Principal.equal, Principal.hash);

  // Track vaults by creator
  private stable var creatorVaultsEntries: [(Principal, [Principal])] = [];
  private var creatorVaults = StableTrieMap.StableTrieMap<Principal, [Principal]>(0, Principal.equal, Principal.hash);

  // Factory statistics
  private stable var totalVaultsCreated: Nat = 0;
  private stable var factoryCreatedAt: Time.Time = Time.now();

  // Configuration
  private stable let VAULT_CREATION_FEE: Nat = 100_000_000; // 0.1 ICP in e8s
  private stable let CYCLES_PER_VAULT: Nat = 2_000_000_000_000; // 2T cycles

  // System functions for upgrades
  system func preupgrade() {
    vaultEntries := StableTrieMap.toArray(vaults);
    creatorVaultsEntries := StableTrieMap.toArray(creatorVaults);
  };

  system func postupgrade() {
    vaults := StableTrieMap.fromArray(vaultEntries, Principal.equal, Principal.hash);
    creatorVaults := StableTrieMap.fromArray(creatorVaultsEntries, Principal.equal, Principal.hash);
    vaultEntries := [];
    creatorVaultsEntries := [];
  };

  // Create a new vault
  public shared(msg) func createVault(args: Types.CreateVaultArgs): async Result.Result<Principal, Text> {
    // Validate input
    if (args.name == "") {
      return #err("Vault name cannot be empty");
    };

    if (args.symbol == "") {
      return #err("Vault symbol cannot be empty");
    };

    // Add cycles for the new canister
    Cycles.add<system>(CYCLES_PER_VAULT);

    try {
      // Create new vault canister
      let vault = await Vault.Vault(
        args.name,
        args.symbol,
        8, // decimals
        10_000, // fee (0.0001 tokens)
        args.description,
        msg.caller
      );

      let vaultPrincipal = Principal.fromActor(vault);

      // Get initial metadata
      let metadata = await vault.getVaultMetadata();

      // Register vault
      StableTrieMap.put(vaults, Principal.equal, Principal.hash, vaultPrincipal, metadata);

      // Track vault by creator
      let existingVaults = switch (StableTrieMap.get(creatorVaults, Principal.equal, Principal.hash, msg.caller)) {
        case null { [] };
        case (?vaultList) { vaultList };
      };
      let updatedVaults = Array.append(existingVaults, [vaultPrincipal]);
      StableTrieMap.put(creatorVaults, Principal.equal, Principal.hash, msg.caller, updatedVaults);

      totalVaultsCreated += 1;

      // Handle initial deposit if provided
      switch (args.initialDeposit) {
        case (?deposit) {
          // User would need to approve and transfer separately
          // This is just a placeholder for the flow
        };
        case null {};
      };

      #ok(vaultPrincipal)
    } catch (e) {
      #err("Failed to create vault canister")
    }
  };

  // Get vault metadata by canister ID
  public query func getVault(canisterId: Principal): async ?Types.VaultMetadata {
    StableTrieMap.get(vaults, Principal.equal, Principal.hash, canisterId)
  };

  // List all vaults
  public query func listVaults(offset: Nat, limit: Nat): async {
    vaults: [Types.VaultMetadata];
    total: Nat;
  } {
    let allVaults = StableTrieMap.toArray(vaults);
    let total = allVaults.size();

    let startIndex = if (offset >= total) { total } else { offset };
    let endIndex = if (startIndex + limit > total) { total } else { startIndex + limit };

    let vaultList = if (startIndex >= endIndex) {
      []
    } else {
      Array.map<(Principal, Types.VaultMetadata), Types.VaultMetadata>(
        Array.subArray(allVaults, startIndex, endIndex - startIndex),
        func((_, metadata)) { metadata }
      )
    };

    { vaults = vaultList; total = total }
  };

  // Get vaults created by a specific user
  public query func getVaultsByCreator(creator: Principal): async [Types.VaultMetadata] {
    switch (StableTrieMap.get(creatorVaults, Principal.equal, Principal.hash, creator)) {
      case null { [] };
      case (?vaultIds) {
        Array.mapFilter<Principal, Types.VaultMetadata>(vaultIds, func(id) {
          StableTrieMap.get(vaults, Principal.equal, Principal.hash, id)
        })
      };
    }
  };

  // Get vaults where user has shares
  public func getVaultsByHolder(holder: Principal): async [Types.VaultMetadata] {
    // This would require querying each vault - expensive operation
    // In production, maintain a separate index
    let allVaults = StableTrieMap.toArray(vaults);
    let vaultsWithBalance: [Types.VaultMetadata] = [];

    // For now, return empty array
    // In production: implement proper indexing or use a subquery
    vaultsWithBalance
  };

  // Search vaults by name (case-sensitive for now)
  public query func searchVaults(searchText: Text): async [Types.VaultMetadata] {
    let allVaults = StableTrieMap.toArray(vaults);

    Array.mapFilter<(Principal, Types.VaultMetadata), Types.VaultMetadata>(allVaults, func((_, metadata)) {
      if (Text.contains(metadata.name, #text searchText) or Text.contains(metadata.symbol, #text searchText)) {
        ?metadata
      } else {
        null
      }
    })
  };

  // Get factory statistics
  public query func getFactoryStats(): async {
    totalVaults: Nat;
    createdAt: Time.Time;
    creationFee: Nat;
  } {
    {
      totalVaults = totalVaultsCreated;
      createdAt = factoryCreatedAt;
      creationFee = VAULT_CREATION_FEE;
    }
  };

  // Update vault metadata (called by vault canisters)
  public shared(msg) func updateVaultMetadata(metadata: Types.VaultMetadata): async Result.Result<(), Text> {
    // Verify caller is a registered vault
    switch (StableTrieMap.get(vaults, Principal.equal, Principal.hash, msg.caller)) {
      case null { #err("Caller is not a registered vault") };
      case (?_) {
        StableTrieMap.put(vaults, Principal.equal, Principal.hash, msg.caller, metadata);
        #ok()
      };
    }
  };

  // Admin function to remove a vault (if needed)
  public shared(msg) func removeVault(canisterId: Principal): async Result.Result<(), Text> {
    // In production, add proper admin authorization
    switch (StableTrieMap.get(vaults, Principal.equal, Principal.hash, canisterId)) {
      case null { #err("Vault not found") };
      case (?metadata) {
        StableTrieMap.delete(vaults, Principal.equal, Principal.hash, canisterId);

        // Remove from creator's list
        switch (StableTrieMap.get(creatorVaults, Principal.equal, Principal.hash, metadata.creator)) {
          case null {};
          case (?vaultList) {
            let filtered = Array.filter<Principal>(vaultList, func(id) { id != canisterId });
            if (filtered.size() > 0) {
              StableTrieMap.put(creatorVaults, Principal.equal, Principal.hash, metadata.creator, filtered);
            } else {
              StableTrieMap.delete(creatorVaults, Principal.equal, Principal.hash, metadata.creator);
            };
          };
        };

        #ok()
      };
    }
  };
}
