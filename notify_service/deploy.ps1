# deploy.ps1 — Run this in PowerShell from the notify_service/ folder
# Deploys the Python notify service to Railway and wires it to Supabase.

param(
    [string]$SupabaseDbUrl = "postgresql://postgres:cxg0rRa8mJKwBLjl@db.rcldmmanvvtkkrbwpkgk.supabase.co:5432/postgres"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "`n=== Salud Visual — Notify Service Deploy ===" -ForegroundColor Cyan

# 1. Railway login
Write-Host "`n[1/5] Logging in to Railway..." -ForegroundColor Yellow
railway login
if ($LASTEXITCODE -ne 0) { Write-Error "Railway login failed"; exit 1 }

# 2. Create Railway project
Write-Host "`n[2/5] Initializing Railway project..." -ForegroundColor Yellow
railway init --name "salud-visual-notify"
if ($LASTEXITCODE -ne 0) { Write-Error "Railway init failed"; exit 1 }

# 3. Set environment variables in Railway
Write-Host "`n[3/5] Setting environment variables in Railway..." -ForegroundColor Yellow

# Read values from local .env
$envFile = Join-Path $PSScriptRoot ".env"
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match "^([A-Z_]+)=(.+)$") {
        $envVars[$matches[1]] = $matches[2].Trim()
    }
}

$requiredVars = @(
    "WA_ACCESS_TOKEN", "WA_PHONE_NUMBER_ID", "WA_API_VERSION",
    "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "WEBHOOK_SECRET",
    "DEFAULT_TZ"
)
foreach ($var in $requiredVars) {
    $val = $envVars[$var]
    if ($val) {
        railway variables --set "$var=$val"
        Write-Host "  ✓ $var" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ $var is empty — set it in Railway dashboard after deploy" -ForegroundColor DarkYellow
    }
}

# Optional vars
foreach ($var in @("WA_TEMPLATE_NAME", "RESEND_API_KEY", "NOTIFY_FROM_EMAIL")) {
    $val = $envVars[$var]
    if ($val) {
        railway variables --set "$var=$val"
        Write-Host "  ✓ $var" -ForegroundColor Green
    }
}

# 4. Deploy
Write-Host "`n[4/5] Deploying to Railway..." -ForegroundColor Yellow
railway up --detach
if ($LASTEXITCODE -ne 0) { Write-Error "Railway deploy failed"; exit 1 }

# 5. Get the public URL and update Supabase Vault
Write-Host "`n[5/5] Getting service URL and updating Supabase..." -ForegroundColor Yellow
Start-Sleep -Seconds 10  # wait for deploy to register

$serviceUrl = (railway domain 2>&1) -replace "`n",""
if (-not $serviceUrl -or $serviceUrl -notmatch "^https://") {
    Write-Host "  ⚠ Could not auto-detect URL. Run 'railway domain' after deploy." -ForegroundColor DarkYellow
    Write-Host "  Then run the Supabase SQL below manually." -ForegroundColor DarkYellow
} else {
    $serviceUrl = "https://$serviceUrl"
    Write-Host "  Service URL: $serviceUrl" -ForegroundColor Green

    # Update Supabase Vault with the real URL
    $sql = "select vault.update_secret((select id from vault.secrets where name = 'notify_service_url'), '$serviceUrl');"
    $result = & psql $SupabaseDbUrl -c $sql 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Supabase Vault updated with service URL" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ psql not found. Run this SQL in Supabase dashboard manually:" -ForegroundColor DarkYellow
        Write-Host ""
        Write-Host "  select vault.update_secret(" -ForegroundColor White
        Write-Host "    (select id from vault.secrets where name = 'notify_service_url')," -ForegroundColor White
        Write-Host "    '$serviceUrl');" -ForegroundColor White
    }
}

Write-Host "`n=== Deploy complete! ===" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Open Railway dashboard and verify the service is running" -ForegroundColor White
Write-Host "  2. Test: curl `$serviceUrl/health" -ForegroundColor White
Write-Host "  3. Fill WA_ACCESS_TOKEN + WA_PHONE_NUMBER_ID in Railway dashboard" -ForegroundColor White
Write-Host "     (get these from Meta Developer Portal)" -ForegroundColor White
