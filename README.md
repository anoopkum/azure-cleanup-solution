# Azure Cleanup Solution

Automated Azure Logic App for cleaning up sandbox resource groups with cost tracking and email notifications.

## Features

- **Auto Cleanup**: Deletes RGs older than 15 days
- **Warning Emails**: Notifies creators 5 days before deletion (10-14 days old)
- **Cost Tracking**: Shows month-to-date costs per RG
- **Resource Locks**: Skips locked RGs
- **Auto Tagging**: Azure Function tags new RGs with Creator/CreatedDate

## Quick Start

```bash
# 1. Update variables in scripts/deploy.sh
# 2. Run deployment
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Structure

```
├── logic-app/cleanup-workflow.json    # Main Logic App
├── azure-function/                    # Auto-tagging function
├── workbook/cleanup-dashboard.json    # Azure Workbook
└── scripts/
    ├── deploy.sh                      # Full deployment script
    ├── setup-roles.sh                 # Role assignments
    └── backfill-tags.ps1              # Tag existing RGs
```

## Configuration

Update these in `scripts/deploy.sh`:
- `SUBSCRIPTION_ID` - Your Azure subscription
- `RESOURCE_GROUP` - RG for the solution
- `ADMIN_EMAILS` - Admin notification emails
- `SHARED_MAILBOX` - Sender email address

## License

MIT
