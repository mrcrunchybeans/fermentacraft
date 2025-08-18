param([switch]$Online)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
  throw "gcloud CLI not found. Install and run 'gcloud auth login' first."
}

# Small helper for PS5/PS7 compatibility
function Invoke-WebRequestCompat {
  param(
    [Parameter(Mandatory=$true)][string]$Uri,
    [ValidateSet('GET','POST')][string]$Method='GET',
    [hashtable]$Headers,
    [string]$Body
  )
  $p = @{ Uri = $Uri; Method = $Method }
  if ($Headers) { $p.Headers = $Headers }
  if ($Body)    { $p.Body    = $Body }
  if ($PSVersionTable.PSVersion.Major -lt 6) { $p.UseBasicParsing = $true }
  Invoke-WebRequest @p
}

$project = (gcloud config get-value project 2>$null).Trim()
Write-Host "GCP Project: $project" -ForegroundColor Cyan

$secrets = @(
  @{ Name='RC_SECRET_KEY';           Kind='RevenueCat';      Pattern='^sk_[A-Za-z0-9._-]{10,}$';       ExpectPrefix='sk_'     },
  @{ Name='STRIPE_SECRET';           Kind='Stripe';          Pattern='^sk_(live|test)_[A-Za-z0-9]+$';  ExpectPrefix='sk_'     },
  @{ Name='STRIPE_WEBHOOK_SECRET';   Kind='Stripe Webhook';  Pattern='^whsec_[A-Za-z0-9]+$';            ExpectPrefix='whsec_'  }
)

function Get-SecretPayload([string]$name) {
  $val = gcloud secrets versions access latest --secret=$name 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  return $val
}

function Inspect-Secret([string]$name, [string]$kind, [string]$pattern, [string]$expectPrefix) {
  $raw = Get-SecretPayload $name
  $bytes   = if ($null -ne $raw) { [Text.Encoding]::UTF8.GetBytes($raw) } else { @() }
  $len     = if ($null -ne $raw) { $raw.Length } else { 0 }
  $trim    = if ($null -ne $raw) { $raw.Trim() } else { $null }
  $lenTrim = if ($null -ne $trim) { $trim.Length } else { 0 }
  $hasWhitespace = ($len -ne $lenTrim)
  $hasCRLF = ($bytes.Length -ge 2 -and $bytes[-2] -eq 13 -and $bytes[-1] -eq 10)
  $starts = if ($raw) { $raw.Substring(0,[Math]::Min(6,$raw.Length)) } else { '' }
  $ends   = if ($raw -and $raw.Length -gt 4) { $raw.Substring($raw.Length-4) } else { '' }
  $patternOk = $false
  if ($trim) { $patternOk = [bool]([Regex]::IsMatch($trim, $pattern)) }

  $versions = gcloud secrets versions list $name --format="value(name,state)" 2>$null | ForEach-Object {
    $parts = $_ -split "\s+"
    [PSCustomObject]@{ Version=$parts[0]; State=$parts[1] }
  }

  [PSCustomObject]@{
    Name=$name
    Kind=$kind
    Present=[bool]$raw
    Prefix=$starts
    Suffix=$ends
    Length=$len
    LengthTrim=$lenTrim
    HasTrailingWhitespace=$hasWhitespace
    HasCRLF=$hasCRLF
    PatternOk=$patternOk
    ExpectedPrefix=$expectPrefix
    Versions=$versions
  }
}

$report = foreach ($s in $secrets) {
  Inspect-Secret -name $s.Name -kind $s.Kind -pattern $s.Pattern -expectPrefix $s.ExpectPrefix
}

$report |
  Select Name,Kind,Present,Prefix,Suffix,Length,LengthTrim,HasTrailingWhitespace,HasCRLF,PatternOk |
  Format-Table -AutoSize

foreach ($r in $report) {
  if (-not $r.Present) {
    Write-Warning "$($r.Name): not found or cannot read."
    continue
  }
  if ($r.HasCRLF -or $r.HasTrailingWhitespace) {
    Write-Warning "$($r.Name): trailing whitespace/newline detected. Recreate with:"
    Write-Host "Set-Content rc_key.txt -Value '<value>' -NoNewline; gcloud secrets versions add $($r.Name) --data-file=rc_key.txt; Remove-Item rc_key.txt"
  }
  if (-not $r.PatternOk) {
    Write-Warning "$($r.Name): value does not match the expected pattern for $($r.Kind) (prefix should be '$($r.ExpectedPrefix)')."
  }
}

Write-Host "`nSecret versions:" -ForegroundColor Cyan
$versionRows = $report | ForEach-Object {
  $enabled = $_.Versions | Where-Object { $_.State -eq 'enabled' } | Select-Object -Expand Version
  $latest  = ($_.Versions | Select-Object -Last 1).Version
  $isLatestEnabled = $enabled -contains $latest
  [PSCustomObject]@{
    Name=$_.Name
    EnabledVersions=($enabled -join ',')
    Latest=$latest
    LatestEnabled=$isLatestEnabled
  }
}
$versionRows | Format-Table -AutoSize

if ($Online) {
  Write-Host "`nOnline checks..." -ForegroundColor Cyan

  try {
    $rcKey = (gcloud secrets versions access latest --secret=RC_SECRET_KEY).Trim()
    if ($rcKey) {
      $rcResp = Invoke-WebRequestCompat -Method GET -Uri "https://api.revenuecat.com/v1/subscribers/sanity-check" `
        -Headers @{ Authorization = "Bearer $rcKey"; "Content-Type"="application/json" }
      Write-Host "RevenueCat: HTTP $($rcResp.StatusCode) $($rcResp.StatusDescription)" -ForegroundColor Green
    } else {
      Write-Warning "RevenueCat: key not readable."
    }
  } catch {
    Write-Warning "RevenueCat request failed: $($_.Exception.Message)"
  }

  try {
    $stripeKey = (gcloud secrets versions access latest --secret=STRIPE_SECRET).Trim()
    if ($stripeKey) {
      $stResp = Invoke-WebRequestCompat -Method GET -Uri "https://api.stripe.com/v1/products?limit=1" `
        -Headers @{ Authorization = "Bearer $stripeKey" }
      $stJson = $stResp.Content | ConvertFrom-Json
      Write-Host ("Stripe: HTTP {0}  items={1}  livemode={2}" -f $stResp.StatusCode, ($stJson.data.Count), $stJson.livemode) -ForegroundColor Green
    } else {
      Write-Warning "Stripe: key not readable."
    }
  } catch {
    Write-Warning "Stripe request failed: $($_.Exception.Message)"
  }

  try {
    $wh = (gcloud secrets versions access latest --secret=STRIPE_WEBHOOK_SECRET).Trim()
    if ($wh -and $wh -match '^whsec_') {
      Write-Host "Stripe Webhook secret format OK." -ForegroundColor Green
    } else {
      Write-Warning "Stripe Webhook secret missing or malformed (should start with 'whsec_')."
    }
  } catch {
    Write-Warning "Stripe Webhook secret read failed: $($_.Exception.Message)"
  }
}

Write-Host "`nDone." -ForegroundColor Cyan
