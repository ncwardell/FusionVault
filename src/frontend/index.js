import { AuthClient } from "@dfinity/auth-client";
import { Actor, HttpAgent } from "@dfinity/agent";

// State
let authClient;
let identity;
let agent;
let vaultFactoryActor;
let currentPage = 0;
const PAGE_SIZE = 10;

// Get canister IDs from environment
const VAULT_FACTORY_CANISTER_ID = process.env.CANISTER_ID_VAULT_FACTORY;
const II_URL = process.env.DFX_NETWORK === "local"
  ? `http://localhost:4943?canisterId=${process.env.CANISTER_ID_INTERNET_IDENTITY}`
  : "https://identity.ic0.app";

// IDL Interface for VaultFactory
const idlFactory = ({ IDL }) => {
  const AssetType = IDL.Variant({
    'ICP': IDL.Record({ 'ledger': IDL.Principal }),
    'ckBTC': IDL.Record({ 'ledger': IDL.Principal }),
    'ckETH': IDL.Record({ 'ledger': IDL.Principal }),
    'Bitcoin': IDL.Null,
    'Ethereum': IDL.Null,
    'ICRC1': IDL.Record({ 'ledger': IDL.Principal, 'symbol': IDL.Text }),
  });

  const CreateVaultArgs = IDL.Record({
    'name': IDL.Text,
    'symbol': IDL.Text,
    'description': IDL.Text,
    'supportedAssets': IDL.Vec(AssetType),
    'initialDeposit': IDL.Opt(IDL.Record({
      'assetType': AssetType,
      'amount': IDL.Nat,
    })),
  });

  const VaultMetadata = IDL.Record({
    'canisterId': IDL.Principal,
    'name': IDL.Text,
    'symbol': IDL.Text,
    'decimals': IDL.Nat8,
    'totalSupply': IDL.Nat,
    'fee': IDL.Nat,
    'createdAt': IDL.Int,
    'creator': IDL.Principal,
    'btcAddress': IDL.Opt(IDL.Text),
    'ethAddress': IDL.Opt(IDL.Text),
    'totalValueLocked': IDL.Nat,
  });

  return IDL.Service({
    'createVault': IDL.Func([CreateVaultArgs], [IDL.Variant({ 'ok': IDL.Principal, 'err': IDL.Text })], []),
    'getVault': IDL.Func([IDL.Principal], [IDL.Opt(VaultMetadata)], ['query']),
    'listVaults': IDL.Func([IDL.Nat, IDL.Nat], [IDL.Record({ 'vaults': IDL.Vec(VaultMetadata), 'total': IDL.Nat })], ['query']),
    'getVaultsByCreator': IDL.Func([IDL.Principal], [IDL.Vec(VaultMetadata)], ['query']),
    'searchVaults': IDL.Func([IDL.Text], [IDL.Vec(VaultMetadata)], ['query']),
    'getFactoryStats': IDL.Func([], [IDL.Record({
      'totalVaults': IDL.Nat,
      'createdAt': IDL.Int,
      'creationFee': IDL.Nat,
    })], ['query']),
  });
};

// Initialize on page load
document.addEventListener('DOMContentLoaded', async () => {
  await init();
});

async function init() {
  setupEventListeners();
  await initAuth();
}

function setupEventListeners() {
  // Auth
  document.getElementById('login-btn').addEventListener('click', login);
  document.getElementById('logout-btn').addEventListener('click', logout);

  // Vault creation
  document.getElementById('create-vault-form').addEventListener('submit', handleCreateVault);

  // Vault listing
  document.getElementById('refresh-my-vaults').addEventListener('click', loadMyVaults);
  document.getElementById('search-btn').addEventListener('click', searchVaults);
  document.getElementById('prev-page').addEventListener('click', () => changePage(-1));
  document.getElementById('next-page').addEventListener('click', () => changePage(1));

  // Modal
  document.querySelector('.close').addEventListener('click', closeModal);
  window.addEventListener('click', (e) => {
    if (e.target.id === 'vault-modal') closeModal();
  });
}

async function initAuth() {
  authClient = await AuthClient.create();

  if (await authClient.isAuthenticated()) {
    await handleAuthenticated();
  }
}

async function login() {
  showLoading(true);

  try {
    await authClient.login({
      identityProvider: II_URL,
      onSuccess: async () => {
        await handleAuthenticated();
        showLoading(false);
      },
      onError: (error) => {
        console.error('Login error:', error);
        showLoading(false);
        showError('Login failed. Please try again.');
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    showLoading(false);
    showError('Login failed. Please try again.');
  }
}

async function logout() {
  await authClient.logout();
  identity = null;
  agent = null;
  vaultFactoryActor = null;

  // Update UI
  document.getElementById('login-btn').classList.remove('hidden');
  document.getElementById('user-info').classList.add('hidden');
  document.getElementById('login-required').classList.remove('hidden');
  document.getElementById('main-content').classList.add('hidden');
}

async function handleAuthenticated() {
  identity = authClient.getIdentity();

  // Create agent
  agent = new HttpAgent({
    identity,
    host: process.env.DFX_NETWORK === "local" ? "http://localhost:4943" : "https://ic0.app"
  });

  // Fetch root key for local development
  if (process.env.DFX_NETWORK === "local") {
    await agent.fetchRootKey();
  }

  // Create actor
  vaultFactoryActor = Actor.createActor(idlFactory, {
    agent,
    canisterId: VAULT_FACTORY_CANISTER_ID,
  });

  // Update UI
  const principal = identity.getPrincipal().toString();
  document.getElementById('user-principal').textContent = `${principal.slice(0, 8)}...${principal.slice(-6)}`;
  document.getElementById('login-btn').classList.add('hidden');
  document.getElementById('user-info').classList.remove('hidden');
  document.getElementById('login-required').classList.add('hidden');
  document.getElementById('main-content').classList.remove('hidden');

  // Load data
  await Promise.all([
    loadMyVaults(),
    loadAllVaults()
  ]);
}

async function handleCreateVault(e) {
  e.preventDefault();

  const name = document.getElementById('vault-name').value.trim();
  const symbol = document.getElementById('vault-symbol').value.trim().toUpperCase();
  const description = document.getElementById('vault-description').value.trim();

  if (!name || !symbol) {
    showResultMessage('create-result', 'Please fill in all required fields', 'error');
    return;
  }

  showLoading(true);

  try {
    const args = {
      name,
      symbol,
      description: description || `${name} - Multi-asset vault`,
      supportedAssets: [
        { 'ICP': { ledger: 'ryjl3-tyaaa-aaaaa-aaaba-cai' } }, // ICP Ledger placeholder
      ],
      initialDeposit: [],
    };

    const result = await vaultFactoryActor.createVault(args);

    if ('ok' in result) {
      showResultMessage('create-result',
        `Vault created successfully! Canister ID: ${result.ok.toString()}`,
        'success'
      );

      // Reset form
      document.getElementById('create-vault-form').reset();

      // Reload vaults
      setTimeout(() => {
        loadMyVaults();
        loadAllVaults();
      }, 1000);
    } else {
      showResultMessage('create-result', `Error: ${result.err}`, 'error');
    }
  } catch (error) {
    console.error('Create vault error:', error);
    showResultMessage('create-result', `Failed to create vault: ${error.message}`, 'error');
  } finally {
    showLoading(false);
  }
}

async function loadMyVaults() {
  if (!vaultFactoryActor || !identity) return;

  const container = document.getElementById('my-vaults');
  container.innerHTML = '<p class="loading">Loading your vaults...</p>';

  try {
    const principal = identity.getPrincipal();
    const vaults = await vaultFactoryActor.getVaultsByCreator(principal);

    if (vaults.length === 0) {
      container.innerHTML = '<p class="loading">You haven\'t created any vaults yet. Create one above!</p>';
      return;
    }

    container.innerHTML = vaults.map(vault => createVaultCard(vault)).join('');
  } catch (error) {
    console.error('Load my vaults error:', error);
    container.innerHTML = '<p class="loading">Error loading vaults</p>';
  }
}

async function loadAllVaults() {
  if (!vaultFactoryActor) return;

  const container = document.getElementById('all-vaults');
  container.innerHTML = '<p class="loading">Loading vaults...</p>';

  try {
    const result = await vaultFactoryActor.listVaults(currentPage * PAGE_SIZE, PAGE_SIZE);

    if (result.vaults.length === 0) {
      container.innerHTML = '<p class="loading">No vaults found</p>';
      return;
    }

    container.innerHTML = result.vaults.map(vault => createVaultCard(vault)).join('');

    // Update pagination
    const totalPages = Math.ceil(Number(result.total) / PAGE_SIZE);
    document.getElementById('page-info').textContent = `Page ${currentPage + 1} of ${totalPages}`;
    document.getElementById('prev-page').disabled = currentPage === 0;
    document.getElementById('next-page').disabled = currentPage >= totalPages - 1;
  } catch (error) {
    console.error('Load all vaults error:', error);
    container.innerHTML = '<p class="loading">Error loading vaults</p>';
  }
}

async function searchVaults() {
  const query = document.getElementById('search-input').value.trim();

  if (!query) {
    await loadAllVaults();
    return;
  }

  const container = document.getElementById('all-vaults');
  container.innerHTML = '<p class="loading">Searching...</p>';

  try {
    const vaults = await vaultFactoryActor.searchVaults(query);

    if (vaults.length === 0) {
      container.innerHTML = '<p class="loading">No vaults found matching your search</p>';
      return;
    }

    container.innerHTML = vaults.map(vault => createVaultCard(vault)).join('');
  } catch (error) {
    console.error('Search error:', error);
    container.innerHTML = '<p class="loading">Error searching vaults</p>';
  }
}

function changePage(delta) {
  currentPage += delta;
  if (currentPage < 0) currentPage = 0;
  loadAllVaults();
}

function createVaultCard(vault) {
  const tvl = formatAmount(Number(vault.totalValueLocked));
  const supply = formatAmount(Number(vault.totalSupply));

  return `
    <div class="vault-card" onclick="openVaultModal('${vault.canisterId}')">
      <h3>${vault.name}</h3>
      <p class="symbol">${vault.symbol}</p>
      <div class="stats">
        <div class="stat">
          <span class="stat-label">Total Supply</span>
          <span class="stat-value">${supply}</span>
        </div>
        <div class="stat">
          <span class="stat-label">TVL</span>
          <span class="stat-value">${tvl}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Fee</span>
          <span class="stat-value">${formatAmount(Number(vault.fee))}</span>
        </div>
      </div>
    </div>
  `;
}

async function openVaultModal(canisterId) {
  showLoading(true);

  try {
    const vault = await vaultFactoryActor.getVault(canisterId);

    if (!vault || vault.length === 0) {
      showError('Vault not found');
      return;
    }

    const vaultData = vault[0];

    // Populate modal
    document.getElementById('vault-modal-title').textContent = vaultData.name;
    document.getElementById('vault-symbol-display').textContent = vaultData.symbol;
    document.getElementById('vault-supply').textContent = formatAmount(Number(vaultData.totalSupply));
    document.getElementById('vault-tvl').textContent = formatAmount(Number(vaultData.totalValueLocked));

    // For now, show 0 balance (would need to query vault canister)
    document.getElementById('vault-balance').textContent = '0';

    // Show addresses if available
    const addressesDiv = document.getElementById('chain-addresses');
    let addressesHTML = '';

    if (vaultData.btcAddress && vaultData.btcAddress.length > 0) {
      addressesHTML += `<div class="chain-address"><strong>BTC:</strong> ${vaultData.btcAddress[0]}</div>`;
    }

    if (vaultData.ethAddress && vaultData.ethAddress.length > 0) {
      addressesHTML += `<div class="chain-address"><strong>ETH:</strong> ${vaultData.ethAddress[0]}</div>`;
    }

    if (addressesHTML) {
      addressesDiv.innerHTML = addressesHTML;
    }

    // Show modal
    document.getElementById('vault-modal').classList.remove('hidden');
  } catch (error) {
    console.error('Error loading vault:', error);
    showError('Failed to load vault details');
  } finally {
    showLoading(false);
  }
}

function closeModal() {
  document.getElementById('vault-modal').classList.add('hidden');
  document.getElementById('modal-deposit-result').innerHTML = '';
}

// Utility functions
function showLoading(show) {
  const overlay = document.getElementById('loading-overlay');
  if (show) {
    overlay.classList.remove('hidden');
  } else {
    overlay.classList.add('hidden');
  }
}

function showResultMessage(elementId, message, type) {
  const element = document.getElementById(elementId);
  element.innerHTML = `<div class="result-message ${type}">${message}</div>`;

  // Auto-clear after 5 seconds
  setTimeout(() => {
    element.innerHTML = '';
  }, 5000);
}

function showError(message) {
  alert(message); // Simple for now, could enhance with custom modal
}

function formatAmount(amount) {
  if (amount >= 100000000) {
    return (amount / 100000000).toFixed(4);
  }
  return amount.toLocaleString();
}

// Make functions available globally for onclick handlers
window.openVaultModal = openVaultModal;
