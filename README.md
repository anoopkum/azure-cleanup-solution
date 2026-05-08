# Azure Sandbox Resource Cleanup Solution

Automated solution for managing and cleaning up Azure sandbox resources based on age. This solution automatically deletes resource groups older than 15 days and sends warning emails to creators when resources are approaching deletion.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Components](#components)
- [Prerequisites](#prerequisites)
- [Step-by-Step Implementation](#step-by-step-implementation)
- [Configuration](#configuration)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

---

## Overview

### Problem Statement
In sandbox/development Azure environments, resources are often created for testing and forgotten, leading to:
- Unnecessary cloud costs
- Resource sprawl and management overhead
- Security risks from abandoned resources

### Solution
This automated cleanup solution:
1. **Tags resources** with Creator and CreatedDate when created
2. **Monitors resource age** across all subscriptions
3. **Sends warning emails** to creators when resources are 10-14 days old
4. **Automatically deletes** resource groups older than 15 days
5. **Sends admin reports** with cleanup summary and cost savings

### Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AZURE SANDBOX CLEANUP WORKFLOW                        │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   RESOURCE   │     │    AZURE     │     │    AZURE     │     │    LOGIC     │
│   CREATED    │────▶│   POLICY     │────▶│   FUNCTION   │────▶│     APP      │
│              │     │  (Tagging)   │     │ (Dynamic Tag)│     │  (Cleanup)   │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                            │                    │                    │
                            ▼                    ▼                    ▼
                     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
                     │ Adds tags:   │     │ Adds tags:   │     │ Actions:     │
                     │ - CreatedDate│     │ - Creator    │     │ - Query RGs  │
                     │   (if missing)│    │ - CreatedDate│     │ - Send Warn  │
                     └──────────────┘     │   (accurate) │     │ - Delete Old │
                                          └──────────────┘     │ - Send Report│
                                                               └──────────────┘
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AZURE TENANT                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │
│  │  Subscription 1 │    │  Subscription 2 │    │  Subscription N │          │
│  │  (Sandbox)      │    │  (Dev)          │    │  (Test)         │          │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘          │
│           │                      │                      │                    │
│           └──────────────────────┼──────────────────────┘                    │
│                                  │                                           │
│                                  ▼                                           │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    MANAGEMENT SUBSCRIPTION                             │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                   Resource Group: rg-resource-cleanup            │  │  │
│  │  │                                                                  │  │  │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │  │  │
│  │  │  │  Logic App   │  │   Azure      │  │  Event Grid  │           │  │  │
│  │  │  │  (Cleanup)   │  │  Function    │  │  (Triggers)  │           │  │  │
│  │  │  │              │  │  (Tagging)   │  │              │           │  │  │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘           │  │  │
│  │  │                                                                  │  │  │
│  │  │  ┌──────────────┐  ┌──────────────┐                             │  │  │
│  │  │  │    Azure     │  │   Office     │                             │  │  │
│  │  │  │   Workbook   │  │    365       │                             │  │  │
│  │  │  │  (Dashboard) │  │ Connection   │                             │  │  │
│  │  │  └──────────────┘  └──────────────┘                             │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Azure Policy (Tagging)
**Purpose:** Automatically adds `CreatedDate` tag to new resource groups

**How it works:**
- Policy is assigned at subscription or management group level
- When a resource group is created without `CreatedDate` tag, policy adds it
- Uses "Modify" effect to add tags without blocking resource creation

**Limitations:**
- Cannot capture the actual creator (only system can add tags via policy)
- Sets CreatedDate to remediation time, not actual creation time

### 2. Azure Function (Dynamic Tagging)
**Purpose:** Captures accurate Creator and CreatedDate from Event Grid events

**How it works:**
1. Event Grid subscription triggers on resource group creation
2. Function receives the event with caller information
3. Function adds both `Creator` and `CreatedDate` tags with accurate data

**Features:**
- Captures user email or service principal name
- Uses actual event timestamp for CreatedDate
- Handles both user and service principal creators

### 3. Logic App (Cleanup Workflow)
**Purpose:** Main cleanup orchestration - queries, warns, deletes, and reports

**Workflow Steps:**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LOGIC APP WORKFLOW                                   │
└─────────────────────────────────────────────────────────────────────────────┘

Step 1: INITIALIZE
├── Initialize variables (counters, HTML builders)
└── Get all subscriptions in tenant

Step 2: QUERY SUBSCRIPTIONS
├── Query Resource Graph for subscription summary
├── Get cost data per subscription
└── Build subscription summary table

Step 3: QUERY RESOURCE GROUPS
├── Query all RGs with CreatedDate tag
├── Filter: Age >= 10 days
└── Get cost and resource count per RG

Step 4: PROCESS EACH RESOURCE GROUP
│
├── IF Age 10-14 days (WARNING)
│   ├── Add to warning list
│   ├── Get resource list in RG
│   └── Send warning email to Creator
│
├── IF Age >= 15 days (DELETION)
│   ├── Check for resource locks
│   │   ├── IF LOCKED: Add to locked list, skip deletion
│   │   └── IF NOT LOCKED:
│   │       ├── Get resource list before deletion
│   │       ├── DELETE resource group
│   │       ├── Add to deleted list
│   │       ├── Update cost savings
│   │       └── Send deletion notification to Creator
│   │
│   └── IF DELETE FAILED: Add to failed list

Step 5: SEND ADMIN REPORT
├── Build HTML report with all tables
├── Include: Summary, Deleted, Failed, Warnings, Locked
└── Send to admin distribution list
```

### 4. Azure Workbook (Dashboard)
**Purpose:** Real-time visibility into sandbox resource status

**Features:**
- Summary tiles (Total, Deletion Candidates, Warnings, Safe)
- Breakdown by subscription
- Deletion candidates list with creator and age
- Warning list with days until deletion
- Top creators chart
- Age distribution visualization

### 5. Backfill Script (PowerShell)
**Purpose:** Add missing tags to existing resources using Log Analytics

**How it works:**
1. Queries Log Analytics for historical resource creation events
2. Extracts Creator (user/SP) and actual CreatedDate
3. Resolves service principal IDs to display names
4. Updates resources missing Creator or with incorrect CreatedDate

---

## Prerequisites

### Azure Resources Required
- [ ] Azure subscription(s) to manage
- [ ] Resource group for cleanup solution components
- [ ] Log Analytics workspace (for backfill script)
- [ ] Office 365 connection (for email notifications)

### Permissions Required
| Component | Required Permissions |
|-----------|---------------------|
| Logic App Managed Identity | Reader, Resource Group Cleanup (custom), Cost Management Reader |
| Azure Function | Tag Contributor on target subscriptions |
| Azure Policy | Policy Contributor at subscription/management group level |
| Backfill Script | Reader, Tag Contributor, Log Analytics Reader |

### Tools Required
- Azure CLI (`az`)
- PowerShell with Az module
- Git (for deployment)

---

## Step-by-Step Implementation

### Phase 1: Setup Infrastructure

#### Step 1.1: Create Resource Group
```bash
# Variables
RESOURCE_GROUP="rg-resource-cleanup"
LOCATION="eastus"
SUBSCRIPTION_ID="YOUR_SUBSCRIPTION_ID"

# Login to Azure
az login

# Set subscription
az account set --subscription $SUBSCRIPTION_ID

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION
```

#### Step 1.2: Create Custom Role
```bash
# Run the setup script
chmod +x scripts/setup-roles.sh
./scripts/setup-roles.sh
```

Or manually create the role:
```bash
# Create custom role definition
cat > custom-role.json << 'EOF'
{
  "Name": "Resource Group Cleanup",
  "Description": "Custom role for Logic App to cleanup resource groups",
  "Actions": [
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/delete",
    "Microsoft.ResourceGraph/resources/read"
  ],
  "NotActions": [],
  "AssignableScopes": [
    "/subscriptions/YOUR_SUBSCRIPTION_ID"
  ]
}
EOF

az role definition create --role-definition custom-role.json
```

### Phase 2: Deploy Azure Policy

#### Step 2.1: Create Policy Definition
```bash
# Create policy definition for CreatedDate tag
az policy definition create \
  --name "add-createddate-tag" \
  --display-name "Add CreatedDate tag to resource groups" \
  --description "Adds CreatedDate tag with current UTC time to resource groups if missing" \
  --rules '{
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Resources/subscriptions/resourceGroups"
        },
        {
          "field": "tags[CreatedDate]",
          "exists": "false"
        }
      ]
    },
    "then": {
      "effect": "modify",
      "details": {
        "roleDefinitionIds": [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        ],
        "operations": [
          {
            "operation": "add",
            "field": "tags[CreatedDate]",
            "value": "[utcNow()]"
          }
        ]
      }
    }
  }' \
  --mode All
```

#### Step 2.2: Assign Policy
```bash
# Assign policy to subscription
az policy assignment create \
  --name "add-createddate-tag-assignment" \
  --policy "add-createddate-tag" \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID" \
  --mi-system-assigned \
  --location "eastus"

# Grant policy managed identity permissions
POLICY_PRINCIPAL_ID=$(az policy assignment show \
  --name "add-createddate-tag-assignment" \
  --query "identity.principalId" -o tsv)

az role assignment create \
  --assignee $POLICY_PRINCIPAL_ID \
  --role "Tag Contributor" \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID"
```

### Phase 3: Deploy Azure Function

#### Step 3.1: Create Function App
```bash
FUNCTION_APP_NAME="func-resource-tagging"
STORAGE_ACCOUNT="stresourcetag$(openssl rand -hex 4)"

# Create storage account
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS

# Create function app
az functionapp create \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --storage-account $STORAGE_ACCOUNT \
  --consumption-plan-location $LOCATION \
  --runtime python \
  --runtime-version 3.9 \
  --functions-version 4 \
  --assign-identity
```

#### Step 3.2: Deploy Function Code
```bash
# Navigate to function directory
cd azure-function

# Deploy function
func azure functionapp publish $FUNCTION_APP_NAME
```

#### Step 3.3: Grant Function Permissions
```bash
FUNCTION_PRINCIPAL_ID=$(az functionapp identity show \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "principalId" -o tsv)

# Grant Tag Contributor on each subscription
az role assignment create \
  --assignee $FUNCTION_PRINCIPAL_ID \
  --role "Tag Contributor" \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID"
```

#### Step 3.4: Create Event Grid Subscription
```bash
FUNCTION_ENDPOINT=$(az functionapp function show \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --function-name "tag_resource" \
  --query "invokeUrlTemplate" -o tsv)

az eventgrid event-subscription create \
  --name "rg-creation-tagging" \
  --source-resource-id "/subscriptions/YOUR_SUBSCRIPTION_ID" \
  --endpoint $FUNCTION_ENDPOINT \
  --endpoint-type webhook \
  --included-event-types "Microsoft.Resources.ResourceWriteSuccess" \
  --advanced-filter data.operationName StringContains "Microsoft.Resources/subscriptions/resourceGroups/write"
```

### Phase 4: Deploy Logic App

#### Step 4.1: Create Logic App
```bash
LOGIC_APP_NAME="auto-resource-cleanup"

# Create Logic App with managed identity
az logic workflow create \
  --name $LOGIC_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --mi-system-assigned \
  --definition @logic-app/cleanup-workflow.json
```

#### Step 4.2: Create Office 365 Connection
```bash
# This must be done in Azure Portal:
# 1. Go to Logic App Designer
# 2. Add "Send an email (V2)" action
# 3. Sign in with account that has Send As permission on shared mailbox
# 4. Save the connection
```

#### Step 4.3: Grant Logic App Permissions
```bash
LOGIC_APP_PRINCIPAL_ID=$(az logic workflow show \
  --name $LOGIC_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "identity.principalId" -o tsv)

# For each subscription, assign roles:
az role assignment create \
  --assignee $LOGIC_APP_PRINCIPAL_ID \
  --role "Resource Group Cleanup" \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID"

az role assignment create \
  --assignee $LOGIC_APP_PRINCIPAL_ID \
  --role "Cost Management Reader" \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID"
```

### Phase 5: Deploy Workbook

#### Step 5.1: Import Workbook
```bash
# In Azure Portal:
# 1. Go to Azure Monitor > Workbooks
# 2. Click "+ New"
# 3. Click "</>" (Advanced Editor)
# 4. Paste contents of workbook/cleanup-dashboard.json
# 5. Click "Apply"
# 6. Save workbook
```

### Phase 6: Backfill Existing Resources

#### Step 6.1: Run Backfill Script
```powershell
# Test mode (no changes)
./scripts/backfill-tags.ps1 -WhatIf

# Apply changes
./scripts/backfill-tags.ps1
```

---

## Configuration

### Logic App Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `adminFallbackEmail` | Admin email(s) for reports | Required |
| `excludedSubscriptions` | Subscription IDs to skip | None |
| `warningDays` | Days before warning (10-14) | 10 |
| `deletionDays` | Days before deletion | 15 |

### Customizing Email Templates

Edit the Logic App workflow to customize:
- Email subject lines
- HTML body templates
- Footer text
- Importance levels

### Excluding Subscriptions

In the Logic App workflow, modify the Resource Graph query:
```kusto
| where subscriptionId !in ('SUBSCRIPTION_ID_TO_EXCLUDE')
```

### Changing Schedule

Default: Every Friday at 11:59 PM GMT

To change, modify the recurrence trigger:
```json
"recurrence": {
  "frequency": "Week",
  "interval": 1,
  "schedule": {
    "weekDays": ["Friday"],
    "hours": [23],
    "minutes": [59]
  },
  "timeZone": "GMT Standard Time"
}
```

---

## Monitoring

### Logic App Run History
```bash
# List recent runs
az logic workflow run list \
  --resource-group $RESOURCE_GROUP \
  --workflow-name $LOGIC_APP_NAME \
  --query "[].{Name:name,Status:status,StartTime:startTime}" \
  -o table
```

### Manual Trigger
```bash
# Trigger Logic App manually
az rest --method post \
  --uri "https://management.azure.com/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME/triggers/Recurrence/run?api-version=2016-06-01"
```

### View Workbook
Navigate to: Azure Portal > Monitor > Workbooks > Sandbox Cleanup Dashboard

---

## Troubleshooting

### Common Issues

#### 1. Emails not sending
- Verify Office 365 connection is authenticated
- Check shared mailbox permissions (Send As)
- Verify email addresses are valid

#### 2. Resource groups not being deleted
- Check for resource locks
- Verify Logic App managed identity has delete permissions
- Check if subscription is excluded

#### 3. Tags not being applied
- Verify Azure Function is running
- Check Event Grid subscription is active
- Verify function has Tag Contributor role

#### 4. Cost data showing $0
- Verify Cost Management Reader role is assigned
- Cost data may have 24-48 hour delay
- Check if subscription has cost management enabled

### Logs and Diagnostics

```bash
# Check Logic App run details
az logic workflow run action list \
  --resource-group $RESOURCE_GROUP \
  --workflow-name $LOGIC_APP_NAME \
  --run-name "RUN_NAME"

# Check Function App logs
az functionapp log tail \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP
```

---

## Cost Considerations

| Component | Estimated Monthly Cost |
|-----------|----------------------|
| Logic App | ~$5-10 (based on runs) |
| Azure Function | ~$0-5 (consumption plan) |
| Event Grid | ~$0.60 per million events |
| Storage Account | ~$1-2 |
| **Total** | **~$7-18/month** |

---

## Security Best Practices

1. **Least Privilege**: Use custom roles with minimal permissions
2. **Managed Identity**: Avoid storing credentials in code
3. **Audit Logging**: Enable diagnostic settings on all components
4. **Resource Locks**: Use locks on critical resources to prevent accidental deletion
5. **Excluded Subscriptions**: Always exclude production subscriptions

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## License

MIT License - See LICENSE file for details

---

## Support

For issues and questions:
- Open a GitHub issue
- Contact: admin@example.com
