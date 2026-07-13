// TrustFundX Web3 Integration
const NODE_URL = "https://fullnode.devnet.aptoslabs.com/v1";

let walletAddress = null;
let isConnected = false;

// Initialize app when window loads
window.addEventListener("load", () => {
    initApp();
});

function initApp() {
    setupEventListeners();
    logConsole("System", "Ready to connect. Install Petra Wallet or Welldone Wallet.");
    
    // Auto-fetch vault state for default addresses on load
    fetchVaultState();
}

function setupEventListeners() {
    const connectBtn = document.getElementById("connectBtn");
    connectBtn.addEventListener("click", toggleConnection);

    // Refresh data if contract address or vault address fields are edited
    document.getElementById("contractAddr").addEventListener("change", fetchVaultState);
    document.getElementById("vaultAddr").addEventListener("change", fetchVaultState);
}

// Log utility for custom console
function logConsole(type, message, txHash = null) {
    const consoleBox = document.getElementById("logConsole");
    const timestamp = new Date().toLocaleTimeString();
    let lineClass = "system";
    
    if (type === "Success") lineClass = "success";
    if (type === "Error") lineClass = "error";
    if (txHash) lineClass = "tx";

    let content = `[${timestamp}] [${type}] ${message}`;
    if (txHash) {
        content += ` <a href="https://explorer.aptoslabs.com/txn/${txHash}?network=devnet" target="_blank" class="tx-link">View Tx <i class="fa-solid fa-up-right-from-square"></i></a>`;
    }

    const line = document.createElement("div");
    line.className = `console-line ${lineClass}`;
    line.innerHTML = content;
    
    consoleBox.appendChild(line);
    consoleBox.scrollTop = consoleBox.scrollHeight;
}

// Toggle connection state with Aptos wallet
async function toggleConnection() {
    if (isConnected) {
        disconnectWallet();
    } else {
        await connectWallet();
    }
}

async function connectWallet() {
    // Detect browser wallet provider (Petra is standard)
    const wallet = window.aptos || window.welldone?.aptos;
    if (!wallet) {
        logConsole("Error", "No Aptos wallet detected. Please install Petra Wallet.");
        alert("Aptos wallet standard provider not found. Please install Petra Wallet or Welldone Wallet.");
        return;
    }

    try {
        logConsole("System", "Connecting to wallet...");
        const response = await wallet.connect();
        walletAddress = response.address;
        isConnected = true;
        
        // Update connection state UI
        document.getElementById("connectBtnText").innerText = `${walletAddress.slice(0, 6)}...${walletAddress.slice(-4)}`;
        document.getElementById("connectBtn").classList.add("connected");
        
        logConsole("Success", `Connected to wallet: ${walletAddress}`);
        
        // Enable claim button
        document.getElementById("claimBtn").removeAttribute("disabled");
        document.getElementById("claimStatusText").innerText = "Wallet connected. Click Claim if you have an active allocation.";
        
        // Fetch new balances with user context
        fetchVaultState();
    } catch (error) {
        logConsole("Error", `Wallet connection failed: ${error.message || error}`);
    }
}

function disconnectWallet() {
    walletAddress = null;
    isConnected = false;
    
    // Update connection state UI
    document.getElementById("connectBtnText").innerText = "Connect Wallet";
    document.getElementById("connectBtn").classList.remove("connected");
    
    logConsole("System", "Wallet disconnected.");
    
    document.getElementById("claimBtn").setAttribute("disabled", "true");
    document.getElementById("claimStatusText").innerText = "Connect wallet to view your allocations.";
}

// Utility function to copy inputs
function copyValue(elementId) {
    const input = document.getElementById(elementId);
    input.select();
    navigator.clipboard.writeText(input.value);
    logConsole("System", `Copied value to clipboard.`);
}

// REST view call handler
async function callViewFunction(funcName, args = []) {
    const contractAddr = document.getElementById("contractAddr").value.trim();
    
    try {
        const response = await fetch(`${NODE_URL}/view`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                function: `${contractAddr}::vault::${funcName}`,
                type_arguments: [],
                arguments: args
            })
        });

        if (!response.ok) {
            const errData = await response.json().catch(() => ({}));
            if (errData.message && errData.message.includes("can't be found")) {
                console.warn(`Module/Function not found on-chain: ${funcName}. Likely not deployed yet.`);
            }
            return null;
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error(`Network or parsing error for view call ${funcName}:`, error);
        return null;
    }
}

// Fetch balances and state from on-chain vault
async function fetchVaultState() {
    const vaultAddr = document.getElementById("vaultAddr").value.trim();
    if (!vaultAddr.startsWith("0x")) return;

    let isDeployed = true;

    // First check if vault exists
    const existsRes = await callViewFunction("vault_exists", [vaultAddr]);
    if (existsRes && existsRes[0] === true) {
        document.getElementById("logConsole").querySelector(".system").innerText = "[System] Vault detected on-chain. Ready.";
    } else {
        isDeployed = false;
        logConsole("System", "Vault/Contract not detected at this address. Please publish and initialize your vault.");
        document.getElementById("totalDeposited").innerHTML = `Not Deployed`;
        document.getElementById("availableBalance").innerHTML = `Not Deployed`;
        document.getElementById("allocatedBalance").innerHTML = `Not Deployed`;
        return;
    }

    // 1. Get Total deposited
    const totalRes = await callViewFunction("get_total_balance", [vaultAddr]);
    if (totalRes) {
        const totalApt = parseInt(totalRes[0]) / 100000000;
        document.getElementById("totalDeposited").innerHTML = `${totalApt.toFixed(2)} <span class="unit">APT</span>`;
    }

    // 2. Get Available balance
    const availRes = await callViewFunction("get_available_balance", [vaultAddr]);
    if (availRes) {
        const availApt = parseInt(availRes[0]) / 100000000;
        document.getElementById("availableBalance").innerHTML = `${availApt.toFixed(2)} <span class="unit">APT</span>`;
    }

    // 3. Get Allocated balance
    const allocRes = await callViewFunction("get_allocated_balance", [vaultAddr]);
    if (allocRes) {
        const allocApt = parseInt(allocRes[0]) / 100000000;
        document.getElementById("allocatedBalance").innerHTML = `${allocApt.toFixed(2)} <span class="unit">APT</span>`;
    }

    // 4. Get User Claimable allocation
    if (walletAddress) {
        const userClaimRes = await callViewFunction("get_claimable_balance", [vaultAddr, walletAddress]);
        if (userClaimRes) {
            const userApt = parseInt(userClaimRes[0]) / 100000000;
            document.getElementById("claimableAmount").innerHTML = `${userApt.toFixed(2)} <span class="unit">APT</span>`;
            if (userApt > 0) {
                document.getElementById("claimStatusText").innerText = "Active allocation detected. Claimable now!";
            } else {
                document.getElementById("claimStatusText").innerText = "No active allocation (or already claimed).";
            }
        }
    }
}

// Transaction execution handler
async function executeTransaction(payload) {
    const wallet = window.aptos || window.welldone?.aptos;
    if (!wallet) {
        logConsole("Error", "Connect your wallet first.");
        return null;
    }

    try {
        logConsole("System", "Submitting transaction...");
        const transaction = await wallet.signAndSubmitTransaction(payload);
        
        // Wait for transaction resolution
        logConsole("System", "Waiting for block confirmation...", transaction.hash);
        const receipt = await waitForTransaction(transaction.hash);
        
        if (receipt.success) {
            logConsole("Success", "Transaction committed successfully!", transaction.hash);
            fetchVaultState(); // Refresh UI values
            return receipt;
        } else {
            throw new Error(receipt.vm_status || "Execution failed");
        }
    } catch (error) {
        logConsole("Error", `Transaction failed: ${error.message || error}`);
        return null;
    }
}

// Block receipt confirmation polling helper
async function waitForTransaction(hash) {
    let attempts = 0;
    while (attempts < 10) {
        try {
            const response = await fetch(`${NODE_URL}/transactions/by_hash/${hash}`);
            if (response.status === 200) {
                const txData = await response.json();
                return txData;
            }
        } catch (e) {}
        await new Promise((r) => setTimeout(r, 1500));
        attempts++;
    }
    throw new Error("Transaction timeout.");
}

// Action: Deposit
async function handleDeposit() {
    const contractAddr = document.getElementById("contractAddr").value.trim();
    const vaultAddr = document.getElementById("vaultAddr").value.trim();
    const amount = parseFloat(document.getElementById("depositAmount").value);

    if (isNaN(amount) || amount <= 0) {
        logConsole("Error", "Enter a valid amount to deposit.");
        return;
    }

    const octasAmount = Math.round(amount * 100000000);
    const payload = {
        type: "entry_function_payload",
        function: `${contractAddr}::vault::deposit_tokens`,
        type_arguments: [],
        arguments: [vaultAddr, octasAmount.toString()]
    };

    await executeTransaction(payload);
}

// Action: Allocate
async function handleAllocate() {
    const contractAddr = document.getElementById("contractAddr").value.trim();
    const vaultAddr = document.getElementById("vaultAddr").value.trim();
    const recipient = document.getElementById("allocateRecipient").value.trim();
    const amount = parseFloat(document.getElementById("allocateAmount").value);

    if (!recipient.startsWith("0x")) {
        logConsole("Error", "Enter a valid beneficiary address.");
        return;
    }
    if (isNaN(amount) || amount <= 0) {
        logConsole("Error", "Enter a valid amount to allocate.");
        return;
    }

    const octasAmount = Math.round(amount * 100000000);
    const payload = {
        type: "entry_function_payload",
        function: `${contractAddr}::vault::allocate_tokens`,
        type_arguments: [],
        arguments: [vaultAddr, recipient, octasAmount.toString()]
    };

    await executeTransaction(payload);
}

// Action: Withdraw
async function handleWithdraw() {
    const contractAddr = document.getElementById("contractAddr").value.trim();
    const vaultAddr = document.getElementById("vaultAddr").value.trim();
    const amount = parseFloat(document.getElementById("withdrawAmount").value);

    if (isNaN(amount) || amount <= 0) {
        logConsole("Error", "Enter a valid amount to withdraw.");
        return;
    }

    const octasAmount = Math.round(amount * 100000000);
    const payload = {
        type: "entry_function_payload",
        function: `${contractAddr}::vault::withdraw_tokens`,
        type_arguments: [],
        arguments: [vaultAddr, octasAmount.toString()]
    };

    await executeTransaction(payload);
}

// Action: Claim
async function handleClaim() {
    const contractAddr = document.getElementById("contractAddr").value.trim();
    const vaultAddr = document.getElementById("vaultAddr").value.trim();

    const payload = {
        type: "entry_function_payload",
        function: `${contractAddr}::vault::claim_tokens`,
        type_arguments: [],
        arguments: [vaultAddr]
    };

    await executeTransaction(payload);
}

// Action: Transfer Admin Control
async function handleTransferAdmin() {
    const contractAddr = document.getElementById("contractAddr").value.trim();
    const vaultAddr = document.getElementById("vaultAddr").value.trim();
    const newAdmin = document.getElementById("newAdminAddr").value.trim();

    if (!newAdmin.startsWith("0x")) {
        logConsole("Error", "Enter a valid new admin address.");
        return;
    }

    const payload = {
        type: "entry_function_payload",
        function: `${contractAddr}::vault::transfer_admin`,
        type_arguments: [],
        arguments: [vaultAddr, newAdmin]
    };

    await executeTransaction(payload);
}
