// ICP Agent imports (will be loaded from CDN in production)
let actor;
let principal;
let currentVaultId = null;

// Asset type mapping
const AssetTypes = {
    'ICP': { ICP: null },
    'BTC': { BTC: null },
    'ETH': { ETH: null },
    'USDC': { USDC: null },
    'USDT': { USDT: null }
};

// Initialize the app
document.addEventListener('DOMContentLoaded', () => {
    setupEventListeners();
    checkConnection();
});

function setupEventListeners() {
    document.getElementById('connect-btn').addEventListener('click', connectWallet);
    document.getElementById('create-vault-btn').addEventListener('click', createVault);
    document.getElementById('refresh-vaults-btn').addEventListener('click', loadVaults);
    document.getElementById('deposit-btn').addEventListener('click', depositAssets);
    document.getElementById('redeem-btn').addEventListener('click', redeemShares);
    document.getElementById('transfer-btn').addEventListener('click', transferShares);
    document.getElementById('generate-btc-btn').addEventListener('click', () => generateAddress('BTC'));
    document.getElementById('generate-eth-btn').addEventListener('click', () => generateAddress('ETH'));
}

async function checkConnection() {
    // Check if already connected (for development)
    const canisterId = getCanisterId();
    if (canisterId) {
        showMessage('create-result', 'Using canister: ' + canisterId, 'info');
    }
}

function getCanisterId() {
    // This will be automatically populated by dfx when deploying
    // For ICP.Ninja, users can manually set this
    const params = new URLSearchParams(window.location.search);
    return params.get('canisterId') || process.env.VAULT_CANISTER_ID || '';
}

async function connectWallet() {
    try {
        const btn = document.getElementById('connect-btn');
        btn.disabled = true;
        btn.textContent = 'Connecting...';

        // For ICP.Ninja and testing, we'll use a simple approach
        // In production, integrate with Internet Identity or Plug Wallet

        // Check if running in ICP.Ninja or similar environment
        if (window.ic && window.ic.plug) {
            // Plug Wallet
            const connected = await window.ic.plug.requestConnect({
                whitelist: [getCanisterId()]
            });

            if (connected) {
                principal = await window.ic.plug.getPrincipal();
                actor = await window.ic.plug.createActor({
                    canisterId: getCanisterId(),
                    interfaceFactory: createIDL
                });
            }
        } else {
            // Mock connection for testing
            principal = 'xxxxx-xxxxx-xxxxx-xxxxx-xxx';
            showMessage('create-result', 'Demo mode - Mock principal created', 'info');
        }

        document.getElementById('principal-display').textContent = principal;
        btn.textContent = 'Connected';
        btn.classList.add('btn-secondary');

        loadVaults();
    } catch (error) {
        console.error('Connection error:', error);
        showMessage('create-result', 'Connection failed: ' + error.message, 'error');
        document.getElementById('connect-btn').disabled = false;
        document.getElementById('connect-btn').textContent = 'Connect Wallet';
    }
}

async function createVault() {
    const name = document.getElementById('vault-name').value.trim();

    if (!name) {
        showMessage('create-result', 'Please enter a vault name', 'error');
        return;
    }

    try {
        const btn = document.getElementById('create-vault-btn');
        btn.disabled = true;
        btn.textContent = 'Creating...';

        // Call canister method
        const result = await callCanister('createVault', [name]);

        if (result.ok !== undefined) {
            const vaultId = result.ok;
            showMessage('create-result', `Vault created successfully! ID: ${vaultId}`, 'success');
            document.getElementById('vault-name').value = '';
            setTimeout(() => loadVaults(), 1000);
        } else {
            showMessage('create-result', 'Error: ' + result.err, 'error');
        }

        btn.disabled = false;
        btn.textContent = 'Create Vault';
    } catch (error) {
        console.error('Create vault error:', error);
        showMessage('create-result', 'Failed to create vault: ' + error.message, 'error');
        document.getElementById('create-vault-btn').disabled = false;
        document.getElementById('create-vault-btn').textContent = 'Create Vault';
    }
}

async function loadVaults() {
    try {
        const btn = document.getElementById('refresh-vaults-btn');
        btn.disabled = true;
        btn.innerHTML = '<span class="loading"></span> Loading...';

        const vaults = await callCanister('listVaults', []);
        displayVaults(vaults);

        btn.disabled = false;
        btn.textContent = 'Refresh Vaults';
    } catch (error) {
        console.error('Load vaults error:', error);
        showMessage('create-result', 'Failed to load vaults: ' + error.message, 'error');
        document.getElementById('refresh-vaults-btn').disabled = false;
        document.getElementById('refresh-vaults-btn').textContent = 'Refresh Vaults';
    }
}

function displayVaults(vaults) {
    const container = document.getElementById('vault-list');

    if (!vaults || vaults.length === 0) {
        container.innerHTML = '<p style="color: #888; text-align: center; padding: 40px;">No vaults created yet. Create your first vault above!</p>';
        return;
    }

    container.innerHTML = vaults.map(vault => `
        <div class="vault-item" onclick="selectVault(${vault.id})">
            <h3>${vault.name}</h3>
            <p><strong>ID:</strong> ${vault.id}</p>
            <p><strong>Total Shares:</strong> ${formatAmount(vault.totalShares)}</p>
            <p><strong>Shareholders:</strong> ${vault.shareHolders.length}</p>
            ${vault.assets.length > 0 ? `
                <div class="asset-list">
                    <strong>Assets:</strong>
                    ${vault.assets.map(asset => `
                        <div class="asset-item">
                            <span class="asset-type">${Object.keys(asset.assetType)[0]}</span>
                            <span class="asset-amount">${formatAmount(asset.amount)}</span>
                        </div>
                    `).join('')}
                </div>
            ` : '<p><em>No assets deposited yet</em></p>'}
        </div>
    `).join('');
}

function selectVault(vaultId) {
    currentVaultId = vaultId;

    // Highlight selected vault
    document.querySelectorAll('.vault-item').forEach(item => {
        item.classList.remove('active');
    });
    event.target.closest('.vault-item').classList.add('active');

    // Load vault details
    loadVaultDetails(vaultId);

    // Show vault details section
    document.getElementById('vault-details').style.display = 'block';
    document.getElementById('vault-details').scrollIntoView({ behavior: 'smooth' });
}

async function loadVaultDetails(vaultId) {
    try {
        const vault = await callCanister('getVault', [vaultId]);

        if (!vault || vault.length === 0) {
            showMessage('deposit-result', 'Vault not found', 'error');
            return;
        }

        const vaultData = vault[0];

        // Display vault info
        const infoHTML = `
            <div class="stats-grid">
                <div class="stat-card">
                    <div class="stat-label">Vault ID</div>
                    <div class="stat-value">${vaultData.id}</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">Total Shares</div>
                    <div class="stat-value">${formatAmount(vaultData.totalShares)}</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">Shareholders</div>
                    <div class="stat-value">${vaultData.shareHolders.length}</div>
                </div>
                <div class="stat-card">
                    <div class="stat-label">Assets</div>
                    <div class="stat-value">${vaultData.assets.length}</div>
                </div>
            </div>
            <h3>${vaultData.name}</h3>
        `;

        document.getElementById('vault-info').innerHTML = infoHTML;

        // Display multi-chain addresses
        let addressesHTML = '';
        if (vaultData.btcAddress && vaultData.btcAddress.length > 0) {
            addressesHTML += `
                <div class="address-item">
                    <div class="address-label">BTC Address:</div>
                    <div>${vaultData.btcAddress[0]}</div>
                </div>
            `;
        }
        if (vaultData.ethAddress && vaultData.ethAddress.length > 0) {
            addressesHTML += `
                <div class="address-item">
                    <div class="address-label">ETH Address:</div>
                    <div>${vaultData.ethAddress[0]}</div>
                </div>
            `;
        }
        if (!addressesHTML) {
            addressesHTML = '<p style="color: #888;"><em>No addresses generated yet. Click the buttons below to generate.</em></p>';
        }

        document.getElementById('chain-addresses').innerHTML = addressesHTML;
    } catch (error) {
        console.error('Load vault details error:', error);
        showMessage('deposit-result', 'Failed to load vault details: ' + error.message, 'error');
    }
}

async function depositAssets() {
    if (currentVaultId === null) {
        showMessage('deposit-result', 'Please select a vault first', 'error');
        return;
    }

    const assetType = document.getElementById('asset-type').value;
    const amount = parseInt(document.getElementById('deposit-amount').value);

    if (!amount || amount <= 0) {
        showMessage('deposit-result', 'Please enter a valid amount', 'error');
        return;
    }

    try {
        const btn = document.getElementById('deposit-btn');
        btn.disabled = true;
        btn.textContent = 'Depositing...';

        const result = await callCanister('deposit', [
            currentVaultId,
            AssetTypes[assetType],
            amount
        ]);

        if (result.ok !== undefined) {
            showMessage('deposit-result',
                `Success! Minted ${formatAmount(result.ok)} shares. ` +
                `Assets deposited and ownership tokens have been issued.`,
                'success'
            );
            document.getElementById('deposit-amount').value = '';
            setTimeout(() => {
                loadVaults();
                loadVaultDetails(currentVaultId);
            }, 1000);
        } else {
            showMessage('deposit-result', 'Error: ' + result.err, 'error');
        }

        btn.disabled = false;
        btn.textContent = 'Deposit & Mint Shares';
    } catch (error) {
        console.error('Deposit error:', error);
        showMessage('deposit-result', 'Failed to deposit: ' + error.message, 'error');
        document.getElementById('deposit-btn').disabled = false;
        document.getElementById('deposit-btn').textContent = 'Deposit & Mint Shares';
    }
}

async function redeemShares() {
    if (currentVaultId === null) {
        showMessage('redeem-result', 'Please select a vault first', 'error');
        return;
    }

    const shares = parseInt(document.getElementById('redeem-shares').value);

    if (!shares || shares <= 0) {
        showMessage('redeem-result', 'Please enter a valid number of shares', 'error');
        return;
    }

    try {
        const btn = document.getElementById('redeem-btn');
        btn.disabled = true;
        btn.textContent = 'Redeeming...';

        const result = await callCanister('redeem', [currentVaultId, shares]);

        if (result.ok !== undefined) {
            const assets = result.ok;
            let message = `Successfully redeemed ${formatAmount(shares)} shares for:<br>`;
            assets.forEach(asset => {
                const assetName = Object.keys(asset.assetType)[0];
                message += `- ${formatAmount(asset.amount)} ${assetName}<br>`;
            });
            showMessage('redeem-result', message, 'success');
            document.getElementById('redeem-shares').value = '';
            setTimeout(() => {
                loadVaults();
                loadVaultDetails(currentVaultId);
            }, 1000);
        } else {
            showMessage('redeem-result', 'Error: ' + result.err, 'error');
        }

        btn.disabled = false;
        btn.textContent = 'Redeem In-Kind';
    } catch (error) {
        console.error('Redeem error:', error);
        showMessage('redeem-result', 'Failed to redeem: ' + error.message, 'error');
        document.getElementById('redeem-btn').disabled = false;
        document.getElementById('redeem-btn').textContent = 'Redeem In-Kind';
    }
}

async function transferShares() {
    if (currentVaultId === null) {
        showMessage('transfer-result', 'Please select a vault first', 'error');
        return;
    }

    const to = document.getElementById('transfer-to').value.trim();
    const amount = parseInt(document.getElementById('transfer-amount').value);

    if (!to) {
        showMessage('transfer-result', 'Please enter a recipient principal', 'error');
        return;
    }

    if (!amount || amount <= 0) {
        showMessage('transfer-result', 'Please enter a valid amount', 'error');
        return;
    }

    try {
        const btn = document.getElementById('transfer-btn');
        btn.disabled = true;
        btn.textContent = 'Transferring...';

        // Create transfer args
        const transferArgs = {
            from_subaccount: [],
            to: { owner: to, subaccount: [] },
            amount: amount,
            fee: [],
            memo: [],
            created_at_time: []
        };

        const result = await callCanister('icrc1_transfer', [currentVaultId, transferArgs]);

        if (result.ok !== undefined) {
            showMessage('transfer-result',
                `Successfully transferred ${formatAmount(amount)} shares to ${to}`,
                'success'
            );
            document.getElementById('transfer-to').value = '';
            document.getElementById('transfer-amount').value = '';
            setTimeout(() => loadVaultDetails(currentVaultId), 1000);
        } else {
            const errorKey = Object.keys(result.err)[0];
            showMessage('transfer-result', `Transfer failed: ${errorKey}`, 'error');
        }

        btn.disabled = false;
        btn.textContent = 'Transfer';
    } catch (error) {
        console.error('Transfer error:', error);
        showMessage('transfer-result', 'Failed to transfer: ' + error.message, 'error');
        document.getElementById('transfer-btn').disabled = false;
        document.getElementById('transfer-btn').textContent = 'Transfer';
    }
}

async function generateAddress(chain) {
    if (currentVaultId === null) {
        showMessage('deposit-result', 'Please select a vault first', 'error');
        return;
    }

    try {
        const method = chain === 'BTC' ? 'generateBtcAddress' : 'generateEthAddress';
        const result = await callCanister(method, [currentVaultId]);

        if (result.ok !== undefined) {
            showMessage('deposit-result',
                `${chain} address generated: ${result.ok}`,
                'success'
            );
            setTimeout(() => loadVaultDetails(currentVaultId), 1000);
        } else {
            showMessage('deposit-result', 'Error: ' + result.err, 'error');
        }
    } catch (error) {
        console.error('Generate address error:', error);
        showMessage('deposit-result', 'Failed to generate address: ' + error.message, 'error');
    }
}

// Helper functions

async function callCanister(method, args) {
    // In ICP.Ninja or with proper setup, this will use the actor
    if (actor) {
        return await actor[method](...args);
    }

    // Mock responses for testing UI
    console.log('Mock call:', method, args);

    // Return mock data based on method
    switch (method) {
        case 'createVault':
            return { ok: Math.floor(Math.random() * 1000) };
        case 'listVaults':
            return [];
        case 'getVault':
            return [];
        case 'deposit':
            return { ok: args[2] }; // Return same amount as shares
        case 'redeem':
            return { ok: [{ assetType: { ICP: null }, amount: 1000000 }] };
        case 'icrc1_transfer':
            return { ok: 0 };
        case 'generateBtcAddress':
            return { ok: 'bc1q' + Math.random().toString(36).substring(7) };
        case 'generateEthAddress':
            return { ok: '0x' + Math.random().toString(36).substring(2, 42) };
        default:
            throw new Error('Unknown method: ' + method);
    }
}

function showMessage(elementId, message, type) {
    const element = document.getElementById(elementId);
    element.innerHTML = `<div class="result-message ${type}">${message}</div>`;
}

function formatAmount(amount) {
    if (typeof amount === 'bigint' || amount > 1000000) {
        return (amount / 100000000).toFixed(8);
    }
    return amount.toLocaleString();
}

// IDL Interface for Plug Wallet
function createIDL({ IDL }) {
    const VaultId = IDL.Nat;
    const AssetType = IDL.Variant({
        'ICP': IDL.Null,
        'BTC': IDL.Null,
        'ETH': IDL.Null,
        'USDC': IDL.Null,
        'USDT': IDL.Null,
    });

    const AssetBalance = IDL.Record({
        'assetType': AssetType,
        'amount': IDL.Nat,
    });

    const Vault = IDL.Record({
        'id': VaultId,
        'name': IDL.Text,
        'owner': IDL.Principal,
        'totalShares': IDL.Nat,
        'shareHolders': IDL.Vec(IDL.Tuple(IDL.Principal, IDL.Nat)),
        'assets': IDL.Vec(AssetBalance),
        'btcAddress': IDL.Opt(IDL.Text),
        'ethAddress': IDL.Opt(IDL.Text),
        'icpAddress': IDL.Opt(IDL.Vec(IDL.Nat8)),
        'createdAt': IDL.Int,
    });

    return IDL.Service({
        'createVault': IDL.Func([IDL.Text], [IDL.Variant({ 'ok': VaultId, 'err': IDL.Text })], []),
        'getVault': IDL.Func([VaultId], [IDL.Opt(Vault)], ['query']),
        'listVaults': IDL.Func([], [IDL.Vec(Vault)], ['query']),
        'deposit': IDL.Func([VaultId, AssetType, IDL.Nat], [IDL.Variant({ 'ok': IDL.Nat, 'err': IDL.Text })], []),
        'redeem': IDL.Func([VaultId, IDL.Nat], [IDL.Variant({ 'ok': IDL.Vec(AssetBalance), 'err': IDL.Text })], []),
    });
}

// Make functions available globally
window.selectVault = selectVault;
