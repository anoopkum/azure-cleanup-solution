# Azure Sandbox Resource Cleanup Solution

Automatically delete Azure resource groups older than 15 days. Save 40-60% on sandbox cloud costs.

![Sample Report](sample-report.html)

---

## The Problem

- Developers create resources in sandbox environments
- They forget to delete them after testing
- Company pays for idle resources indefinitely

## The Solution

Automated lifecycle management:
1. **Tag** resources when created (who + when)
2. **Warn** owners at day 10
3. **Delete** automatically at day 15
4. **Report** to admins with cost savings

---

## How It Works

```
Day 0: Resource Created
       ↓
       Event Grid → Azure Function
       ↓
       Tags added: CreatedDate + Creator
       
Day 10: Logic App runs
        ↓
        Warning email sent to Creator
        "Your resources will be deleted in 5 days"

Day 15: Logic App runs
        ↓
        Resource Group deleted
        ↓
        Notification sent to Creator
        Admin report generated
```

---

## Components

| Component | Purpose | Cost |
|-----------|---------|------|
| **Azure Function** | Tags resources with CreatedDate & Creator | ~$0-5/mo |
| **Event Grid** | Triggers Function on resource creation | ~$0.60/million events |
| **Logic App** | Runs cleanup workflow weekly | ~$5-10/mo |
| **Office 365 Connection** | Sends email notifications | Included |
| **Workbook** | Real-time dashboard | Free |

**Total: ~$10-20/month**

---

## Quick Start

### Prerequisites
- Azure CLI installed
- PowerShell with Az module
- Office 365 account (for emails)

### Step 1: Clone Repository
```bash
git clone https://github.com/anoopkum/azure-cleanup-solution.git
cd azure-cleanup-solution
```

### Step 2: Update Configuration
Edit `scripts/deploy.sh` and set your values:
```bash
SUBSCRIPTION_ID="your-subscription-id"
RESOURCE_GROUP="rg-resource-cleanup"
LOCATION="eastus"
ADMIN_EMAILS="admin1@company.com;admin2@company.com"
```

### Step 3: Run Deployment
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

### Step 4: Configure Email Connection
1. Go to Azure Portal → Logic App → Designer
2. Click on email action → Sign in
3. Authorize with account that has Send As permission on shared mailbox

### Step 5: Backfill Existing Resources (Optional)
```powershell
./scripts/backfill-tags.ps1 -WhatIf  # Preview
./scripts/backfill-tags.ps1          # Apply
```

---

## File Structure

```
├── logic-app/
│   └── cleanup-workflow.json    # Main Logic App workflow
├── azure-function/
│   ├── function_app.py          # Tagging function
│   └── requirements.txt         # Python dependencies
├── scripts/
│   ├── deploy.sh                # One-click deployment
│   ├── setup-roles.sh           # Create custom roles
│   └── backfill-tags.ps1        # Tag existing resources
├── workbook/
│   └── cleanup-dashboard.json   # Azure Workbook
└── sample-report.html           # Sample cleanup report
```

---

## Workflow Details

### Tagging (Azure Function)

When a resource group is created:
```
Event Grid detects creation
    ↓
Triggers Azure Function
    ↓
Function reads event data:
  - Caller (user email or service principal)
  - Timestamp
    ↓
Adds tags to resource group:
  - CreatedDate: "2026-04-18T10:00:00Z"
  - Creator: "user@company.com"
```

### Cleanup (Logic App)

Runs every Friday at 11:59 PM:
```
1. Query all subscriptions
2. Find resource groups with CreatedDate tag
3. For each resource group:
   
   Age 10-14 days → Send WARNING email
   Age 15+ days  → Check for locks
                   ├── Locked: Skip, add to report
                   └── Not locked: DELETE
                       └── Send deletion notification

4. Send admin report with:
   - Total deleted
   - Cost saved
   - Warnings sent
   - Failed deletions
   - Locked (exceptions)
```

---

## Email Notifications

### Warning Email (Day 10-14)
```
Subject: Azure Resource Cleanup Warning – Sandbox Environment

Your resource group will be deleted in X days.

Resource Group: rg-my-test
Creator: user@company.com
Age: 12 days

Resources in this group:
- my-vm (Microsoft.Compute/virtualMachines)
- my-storage (Microsoft.Storage/storageAccounts)

Please review and take action.
```

### Deletion Email (Day 15+)
```
Subject: Azure Resource Cleanup Deletion – Sandbox

Your resource group has been deleted.

Resource Group: rg-my-test
Age at deletion: 15 days
Cost saved: $45.23

Resources that were deleted:
- my-vm (Microsoft.Compute/virtualMachines)
- my-storage (Microsoft.Storage/storageAccounts)
```

### Admin Report (Weekly)
Summary of all cleanup activity with cost savings.

---

## Configuration Options

### Change Lifecycle Days
In `logic-app/cleanup-workflow.json`, modify the queries:
```
Age >= 10 days → Warning
Age >= 15 days → Deletion
```

### Exclude Subscriptions
Add subscription IDs to exclude:
```kusto
| where subscriptionId !in ('subscription-id-to-exclude')
```

### Change Schedule
Modify the recurrence trigger:
```json
"recurrence": {
  "frequency": "Week",
  "interval": 1,
  "schedule": {
    "weekDays": ["Friday"],
    "hours": [23],
    "minutes": [59]
  }
}
```

### Protect Resources (Exceptions)
Add a resource lock to prevent deletion:
```bash
az lock create --name "DoNotDelete" \
  --resource-group "rg-important" \
  --lock-type CanNotDelete
```

---

## Permissions Required

### Logic App Managed Identity
| Role | Scope | Purpose |
|------|-------|---------|
| Reader | All subscriptions | List resource groups |
| Resource Group Cleanup (custom) | All subscriptions | Delete resource groups |
| Cost Management Reader | All subscriptions | Get cost data |

### Azure Function Managed Identity
| Role | Scope | Purpose |
|------|-------|---------|
| Tag Contributor | All subscriptions | Add tags to resources |

### Custom Role Definition
```json
{
  "Name": "Resource Group Cleanup",
  "Actions": [
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/delete",
    "Microsoft.ResourceGraph/resources/read"
  ]
}
```

---

## Troubleshooting

### Emails not sending
- Check Office 365 connection is authorized
- Verify shared mailbox Send As permissions
- Check Logic App run history for errors

### Resources not being deleted
- Check for resource locks
- Verify Logic App has delete permissions
- Check if subscription is excluded

### Tags not being applied
- Verify Event Grid subscription is active
- Check Azure Function logs
- Verify Function has Tag Contributor role

### View Logs
```bash
# Logic App runs
az logic workflow run list \
  --resource-group rg-resource-cleanup \
  --workflow-name auto-resource-cleanup \
  -o table

# Function logs
az functionapp log tail \
  --name func-resource-tagging \
  --resource-group rg-resource-cleanup
```

---

## Manual Trigger

Run cleanup immediately (without waiting for schedule):
```bash
az rest --method post --uri \
  "https://management.azure.com/subscriptions/{subscription-id}/resourceGroups/rg-resource-cleanup/providers/Microsoft.Logic/workflows/auto-resource-cleanup/triggers/Recurrence/run?api-version=2016-06-01"
```

---

## Results

After implementing this solution:
- **40-60% cost reduction** on sandbox environments
- **Zero complaints** - owners get fair warning
- **Full visibility** - dashboard shows all resources
- **Exceptions handled** - resource locks for approved cases

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

---

## License

MIT License

---

## Questions?

Open an issue or reach out on LinkedIn.
