import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Char "mo:base/Char";
import Option "mo:base/Option";
import Types "Types";

module {
  // Management canister interface for threshold ECDSA
  public type ManagementCanister = actor {
    ecdsa_public_key: (Types.ECDSAPublicKey) -> async Types.ECDSAPublicKeyResponse;
    sign_with_ecdsa: (Types.SignWithECDSA) -> async Types.SignWithECDSAResponse;
  };

  private let IC_MANAGEMENT : ManagementCanister = actor "aaaaa-aa";

  // Key IDs for mainnet
  public let BTC_MAINNET_KEY_ID = { curve = #secp256k1; name = "key_1" };
  public let ETH_MAINNET_KEY_ID = { curve = #secp256k1; name = "key_1" };

  // For testnet (uncomment when testing)
  // public let BTC_TESTNET_KEY_ID = { curve = #secp256k1; name = "test_key_1" };
  // public let ETH_TESTNET_KEY_ID = { curve = #secp256k1; name = "test_key_1" };

  // Bitcoin address generation
  public func deriveBitcoinAddress(canisterId: Principal, derivationPath: [Blob]): async Text {
    let publicKeyResult = await IC_MANAGEMENT.ecdsa_public_key({
      canister_id = ?canisterId;
      derivation_path = derivationPath;
      key_id = BTC_MAINNET_KEY_ID;
    });

    let publicKeyBytes = Blob.toArray(publicKeyResult.public_key);

    // Generate P2WPKH (Native SegWit) address
    // Format: bc1q + bech32 encoded public key hash
    let pubkeyHash = hash160(publicKeyBytes);
    let address = encodeBech32("bc", pubkeyHash);

    address
  };

  // Ethereum address generation
  public func deriveEthereumAddress(canisterId: Principal, derivationPath: [Blob]): async Text {
    let publicKeyResult = await IC_MANAGEMENT.ecdsa_public_key({
      canister_id = ?canisterId;
      derivation_path = derivationPath;
      key_id = ETH_MAINNET_KEY_ID;
    });

    let publicKeyBytes = Blob.toArray(publicKeyResult.public_key);

    // Ethereum address is last 20 bytes of keccak256(public_key)
    // For now, we'll use a simplified version - in production use proper keccak256
    let addressBytes = keccak256Simplified(publicKeyBytes);
    let ethAddress = Array.subArray(addressBytes, 12, 20); // Last 20 bytes

    "0x" # bytesToHex(ethAddress)
  };

  // Sign a Bitcoin transaction
  public func signBitcoinTransaction(
    canisterId: Principal,
    derivationPath: [Blob],
    messageHash: Blob
  ): async Blob {
    let signResult = await IC_MANAGEMENT.sign_with_ecdsa({
      message_hash = messageHash;
      derivation_path = derivationPath;
      key_id = BTC_MAINNET_KEY_ID;
    });

    signResult.signature
  };

  // Sign an Ethereum transaction
  public func signEthereumTransaction(
    canisterId: Principal,
    derivationPath: [Blob],
    messageHash: Blob
  ): async Blob {
    let signResult = await IC_MANAGEMENT.sign_with_ecdsa({
      message_hash = messageHash;
      derivation_path = derivationPath;
      key_id = ETH_MAINNET_KEY_ID;
    });

    signResult.signature
  };

  // Helper: SHA-256 hash (simplified - in production use crypto library)
  private func sha256(data: [Nat8]): [Nat8] {
    // Placeholder - use proper SHA-256 implementation
    // In production, use the ic-certification library or similar
    data // Simplified for now
  };

  // Helper: RIPEMD-160 hash
  private func ripemd160(data: [Nat8]): [Nat8] {
    // Placeholder - use proper RIPEMD-160 implementation
    // In production, use appropriate crypto library
    Array.subArray(data, 0, 20) // Simplified for now
  };

  // Helper: Hash160 (SHA-256 then RIPEMD-160)
  private func hash160(data: [Nat8]): [Nat8] {
    let sha = sha256(data);
    ripemd160(sha)
  };

  // Helper: Keccak-256 (simplified)
  private func keccak256Simplified(data: [Nat8]): [Nat8] {
    // Placeholder - use proper Keccak-256 implementation
    // In production, use appropriate crypto library
    let padded = Array.append(data, Array.tabulate<Nat8>(32, func(_) { 0 }));
    Array.subArray(padded, 0, 32) // Simplified for now
  };

  // Helper: Convert bytes to hex string
  private func bytesToHex(bytes: [Nat8]): Text {
    let hexChars = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
    var hex = "";
    for (byte in bytes.vals()) {
      let high = Nat8.toNat(byte / 16);
      let low = Nat8.toNat(byte % 16);
      hex #= Text.fromChar(hexChars[high]);
      hex #= Text.fromChar(hexChars[low]);
    };
    hex
  };

  // Helper: Bech32 encoding (simplified)
  private func encodeBech32(hrp: Text, data: [Nat8]): Text {
    // Simplified Bech32 encoding
    // In production, use proper Bech32 implementation
    hrp # "1q" # bytesToHex(data) // Placeholder
  };

  // Create derivation path from principal and index
  public func createDerivationPath(principal: Principal, index: Nat): [Blob] {
    let principalBlob = Principal.toBlob(principal);
    let indexBlob = Blob.fromArray([
      Nat8.fromNat((index / 16777216) % 256), // index >> 24
      Nat8.fromNat((index / 65536) % 256),    // index >> 16
      Nat8.fromNat((index / 256) % 256),      // index >> 8
      Nat8.fromNat(index % 256),
    ]);
    [principalBlob, indexBlob]
  };

  // Verify ECDSA signature
  public func verifyECDSA(_publicKey: Blob, _message: Blob, _signature: Blob): Bool {
    // Placeholder - in production, implement proper ECDSA verification
    // This would typically be done off-chain or with a crypto library
    true // Simplified for now
  };
}
