# TrustFundX Devnet Auto-Deployer
$contractAddress = "0x110cafd6504243e9e61a29d502d452bb3332bb1fa5b7d91105d810c02a3bd62c"
$aptosPath = "$env:USERPROFILE\.aptoscli\bin\aptos.exe"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "          TrustFundX Deployment Suite         " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# 1. Initialize account with private key
Write-Host "[1/4] Configuring account key..." -ForegroundColor Yellow
Write-Host "Please enter the private key for address $contractAddress"
$privKey = Read-Host "Private Key (hex literal 0x...)"

if (-not $privKey.StartsWith("0x")) {
    $privKey = "0x" + $privKey
}

# Run init non-interactively by writing a temporary config or passing keys
& $aptosPath init --network devnet --private-key $privKey --assume-yes

# 2. Fund the account to cover publishing gas
Write-Host ""
Write-Host "[2/4] Funding account with test APT..." -ForegroundColor Yellow
& $aptosPath account fund-with-faucet --account default --amount 200000000

# 3. Publish module
Write-Host ""
Write-Host "[3/4] Publishing smart contract to Aptos Devnet..." -ForegroundColor Yellow
& $aptosPath move publish --assume-yes

# 4. Initialize Vault
Write-Host ""
Write-Host "[4/4] Initializing Vault on-chain..." -ForegroundColor Yellow
& $aptosPath move run --function-id "$($contractAddress)::vault::init_vault" --assume-yes

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "  Success! Your contract is now live on Devnet. " -ForegroundColor Green
Write-Host "  Refresh your browser dashboard to view state. " -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Read-Host "Press Enter to exit"
