# --- Config ---
$project = "fermentacraft"
$region  = "us-central1"

# Optional: set one of these. Leave BOTH empty to affect ALL functions in the region.
# Only touch these names (lowercase service names as shown in logs / Cloud Run):
$onlyThese   = @() # e.g. @("createcheckout","getstripeprices","createcheckouthttp","getstripepriceshttp","createbillingportal","stripewebhook")
# Never touch these (handy for internal/admin endpoints):
$excludeThese = @() # e.g. @("internaltaskrunner","admin-only")

# Optional: dry run to preview changes
$dryRun = $false

# --- Deploy Functions ---
Write-Host "Deploying Firebase functions..." -ForegroundColor Cyan
firebase deploy --only functions
if ($LASTEXITCODE -ne 0) { throw "Firebase deploy failed." }

# --- Fetch all Cloud Run services for this project/region (Gen-2 functions are services) ---
Write-Host "Discovering Cloud Run services in $project/$region..." -ForegroundColor Cyan
$serviceNames = (gcloud run services list `
  --project=$project `
  --region=$region `
  --format="value(metadata.name)")

if (-not $serviceNames) {
  Write-Host "No services found." -ForegroundColor Yellow
  exit 0
}

# Normalize to array
$services = @()
$serviceNames | ForEach-Object { if ($_) { $services += $_.Trim().ToLower() } }

# Apply optional filters
if ($onlyThese.Count -gt 0) {
  $onlySet = $onlyThese | ForEach-Object { $_.Trim().ToLower() }
  $services = $services | Where-Object { $onlySet -contains $_ }
}
if ($excludeThese.Count -gt 0) {
  $excludeSet = $excludeThese | ForEach-Object { $_.Trim().ToLower() }
  $services = $services | Where-Object { $excludeSet -notcontains $_ }
}

if ($services.Count -eq 0) {
  Write-Host "No matching services after filtering." -ForegroundColor Yellow
  exit 0
}

Write-Host "Services to update:`n - " ($services -join "`n - ") -ForegroundColor Green

# --- Grant invoker to allUsers (idempotent) ---
foreach ($s in $services) {
  Write-Host "Granting roles/run.invoker to allUsers on $s..." -ForegroundColor Cyan
  $cmd = @(
    "run","services","add-iam-policy-binding",$s,
    "--region=$region",
    "--member=allUsers",
    "--role=roles/run.invoker",
    "--project=$project"
  )

  if ($dryRun) {
    Write-Host "DRY RUN: gcloud $($cmd -join ' ')" -ForegroundColor Yellow
  } else {
    gcloud @cmd | Out-Host
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Failed to update IAM on $s (continuing)..." -ForegroundColor Red
    }
  }
}

Write-Host "Done." -ForegroundColor Green
