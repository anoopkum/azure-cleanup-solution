# Backfill Creator and CreatedDate Tags using Log Analytics
# Includes users, service principals, and managed identities
# Corrects CreatedDate to actual creation time from Activity Logs

param(
    [switch]$WhatIf = $false
)

$tenantId = "e2e605ca-a105-4b19-bcb9-5b1ca2d5ce71"
$workspaceId = "48a05772-1646-4298-9598-e2699a746891"

Write-Host "Logging in to Azure tenant: $tenantId" -ForegroundColor Cyan
Connect-AzAccount -TenantId $tenantId

Write-Host "`nBackfill Creator & CreatedDate Tags using Log Analytics" -ForegroundColor Cyan
if ($WhatIf) { Write-Host "WHATIF MODE - No changes will be made" -ForegroundColor Yellow }

# Step 1: Query ALL creators and creation times from Log Analytics
Write-Host "`n[1/4] Querying Log Analytics for resource creators and creation times..." -ForegroundColor Yellow

Set-AzContext -SubscriptionId "27320543-d2ea-4fd5-b361-0145cc56934b" -WarningAction SilentlyContinue | Out-Null

$query = @"
AzureActivity
| where OperationNameValue has '/WRITE'
| where ActivityStatusValue in ('Success', 'Succeeded')
| where isnotempty(Caller)
| summarize CreatedTime=min(TimeGenerated), Creator=arg_min(TimeGenerated, Caller) by ResourceId=tolower(_ResourceId)
| project ResourceId, Creator=Caller, CreatedTime
"@

$laResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $query
$resourceInfo = @{}
$spIds = @{}

foreach ($row in $laResults.Results) {
    $caller = $row.Creator
    $resourceInfo[$row.ResourceId.ToLower()] = @{
        Creator = $caller
        CreatedTime = $row.CreatedTime
    }
    if ($caller -notmatch '@' -and $caller -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
        $spIds[$caller] = $true
    }
}
Write-Host "  Found info for $($resourceInfo.Count) resources" -ForegroundColor Green
Write-Host "  Found $($spIds.Count) unique service principals/MIs to resolve" -ForegroundColor Green

# Step 2: Resolve SP/MI names from Azure AD
Write-Host "`n[2/4] Resolving service principal and managed identity names..." -ForegroundColor Yellow

$spNames = @{}
foreach ($spId in $spIds.Keys) {
    try {
        $sp = Get-AzADServicePrincipal -ObjectId $spId -ErrorAction SilentlyContinue
        if ($sp) {
            $spNames[$spId] = $sp.DisplayName
            Write-Host "  $spId -> $($sp.DisplayName)" -ForegroundColor DarkGray
        }
    } catch { }
}
Write-Host "  Resolved $($spNames.Count) service principals/MIs" -ForegroundColor Green

# Step 3: Get all RGs and resources needing tags
Write-Host "`n[3/4] Finding resources needing Creator or CreatedDate correction..." -ForegroundColor Yellow

$subscriptions = @(
    "ebf0db91-bfb3-4b64-a25a-c3342eb9cbc8",
    "79c55d71-21c7-42c2-958c-0f8f744cfee3",
    "f43b1ca7-0345-4069-8be5-ad3b3edaab85",
    "8395734e-4998-4955-8336-56d2f18a8732",
    "27320543-d2ea-4fd5-b361-0145cc56934b",
    "3c31025e-bee4-4e89-9b66-5b0413992606",
    "1c31a1ec-7511-4413-b012-7a9cdc68228f",
    "44511bd8-e2f9-48d0-bfe0-ee653035e34d",
    "33ae5b48-3339-4aa3-bb5a-22695a65db5f",
    "5ed9830b-9ef4-4764-bfeb-f5aaa29bdd97"
)

$toTag = @()
$today = (Get-Date).ToString("yyyy-MM-dd")

foreach ($subId in $subscriptions) {
    Write-Host "  Scanning: $subId"
    Set-AzContext -SubscriptionId $subId -WarningAction SilentlyContinue | Out-Null
    
    Get-AzResourceGroup | ForEach-Object {
        $needsCreator = -not $_.Tags.Creator
        $needsDate = $false
        # Check if CreatedDate is today (set by policy remediation, not actual date)
        if ($_.Tags.CreatedDate) {
            $tagDate = $_.Tags.CreatedDate.Substring(0,10)
            if ($tagDate -eq $today) { $needsDate = $true }
        }
        if ($needsCreator -or $needsDate) {
            $toTag += [PSCustomObject]@{ Type='RG'; Id=$_.ResourceId; Name=$_.ResourceGroupName; SubId=$subId; Tags=$_.Tags; NeedsCreator=$needsCreator; NeedsDate=$needsDate }
        }
    }
    
    Get-AzResource | Where-Object { $_.ResourceType -notlike "*deployments*" } | ForEach-Object {
        $needsCreator = -not $_.Tags.Creator
        $needsDate = $false
        if ($_.Tags.CreatedDate) {
            $tagDate = $_.Tags.CreatedDate.Substring(0,10)
            if ($tagDate -eq $today) { $needsDate = $true }
        }
        if ($needsCreator -or $needsDate) {
            $toTag += [PSCustomObject]@{ Type='Res'; Id=$_.ResourceId; Name=$_.Name; SubId=$subId; Tags=$_.Tags; NeedsCreator=$needsCreator; NeedsDate=$needsDate }
        }
    }
}
Write-Host "  Found $($toTag.Count) items needing updates" -ForegroundColor Green

# Step 4: Apply tags
Write-Host "`n[4/4] Applying tags..." -ForegroundColor Yellow

$creatorTagged = 0; $dateFixed = 0; $notFound = 0
$currentSub = ""

foreach ($item in $toTag) {
    if ($currentSub -ne $item.SubId) {
        $currentSub = $item.SubId
        Set-AzContext -SubscriptionId $currentSub -WarningAction SilentlyContinue | Out-Null
    }
    
    $info = $resourceInfo[$item.Id.ToLower()]
    $creator = $info.Creator
    $createdTime = $info.CreatedTime
    
    # Resolve SP/MI name
    if ($creator -and $spNames.ContainsKey($creator)) {
        $creator = $spNames[$creator]
    }
    
    $prefix = if ($item.Type -eq 'RG') { "  RG: " } else { "    Res: " }
    Write-Host "$prefix$($item.Name)" -NoNewline
    
    $updated = $false
    $tags = $item.Tags; if (-not $tags) { $tags = @{} }
    
    if ($item.NeedsCreator -and $creator) {
        $tags['Creator'] = $creator
        Write-Host " Creator=$creator" -ForegroundColor Green -NoNewline
        $creatorTagged++
        $updated = $true
    } elseif ($item.NeedsCreator) {
        Write-Host " Creator=NotFound" -ForegroundColor DarkGray -NoNewline
        $notFound++
    }
    
    if ($item.NeedsDate -and $createdTime) {
        $tags['CreatedDate'] = $createdTime
        Write-Host " CreatedDate=$createdTime" -ForegroundColor Cyan -NoNewline
        $dateFixed++
        $updated = $true
    } elseif ($item.NeedsDate) {
        Write-Host " Date=NotFound" -ForegroundColor DarkGray -NoNewline
    }
    
    Write-Host ""
    
    if ($updated -and -not $WhatIf) {
        try {
            if ($item.Type -eq 'RG') {
                Set-AzResourceGroup -Name $item.Name -Tag $tags | Out-Null
            } else {
                Set-AzResource -ResourceId $item.Id -Tag $tags -Force | Out-Null
            }
        } catch { Write-Host "    [Failed to update]" -ForegroundColor Red }
    }
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Creator tags added: $creatorTagged"
Write-Host "CreatedDate corrected: $dateFixed"
Write-Host "Not found in LA: $notFound"
