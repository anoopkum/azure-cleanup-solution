#!/bin/bash
# Setup Custom Role and Assign to Logic App Managed Identity
# Run: chmod +x setup-mi-role.sh && ./setup-mi-role.sh

# Variables - UPDATE THESE
LOGIC_APP_NAME="YOUR_LOGIC_APP_NAME"
LOGIC_APP_RG="YOUR_RESOURCE_GROUP"
TENANT_ID="e2e605ca-a105-4b19-bcb9-5b1ca2d5ce71"

# All subscription IDs in tenant
SUBSCRIPTIONS=(
  "ebf0db91-bfb3-4b64-a25a-c3342eb9cbc8"  # Advisory-Team
  "f43b1ca7-0345-4069-8be5-ad3b3edaab85"  # Data-Innovation
  "8395734e-4998-4955-8336-56d2f18a8732"  # Gov-Innovation
  "YOUR_SUBSCRIPTION_ID"  # Innovation-Control
  "3c31025e-bee4-4e89-9b66-5b0413992606"  # POC-Innovation
  "1c31a1ec-7511-4413-b012-7a9cdc68228f"  # Productivity-Innovation
  "44511bd8-e2f9-48d0-bfe0-ee653035e34d"  # PVC-Innovation
  "33ae5b48-3339-4aa3-bb5a-22695a65db5f"  # SArchitect-Innovation
  "5ed9830b-9ef4-4764-bfeb-f5aaa29bdd97"  # Security-Innovation
)

# Login to Azure
echo "Logging in to Azure..."
az login --tenant $TENANT_ID

# Get Logic App Managed Identity Principal ID
echo "Getting Logic App Managed Identity..."
PRINCIPAL_ID=$(az logic workflow show --name $LOGIC_APP_NAME --resource-group $LOGIC_APP_RG --query "identity.principalId" -o tsv)
echo "Principal ID: $PRINCIPAL_ID"

# Create custom role definition JSON
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
    "/subscriptions/ebf0db91-bfb3-4b64-a25a-c3342eb9cbc8",
    "/subscriptions/f43b1ca7-0345-4069-8be5-ad3b3edaab85",
    "/subscriptions/8395734e-4998-4955-8336-56d2f18a8732",
    "/subscriptions/YOUR_SUBSCRIPTION_ID",
    "/subscriptions/3c31025e-bee4-4e89-9b66-5b0413992606",
    "/subscriptions/1c31a1ec-7511-4413-b012-7a9cdc68228f",
    "/subscriptions/44511bd8-e2f9-48d0-bfe0-ee653035e34d",
    "/subscriptions/33ae5b48-3339-4aa3-bb5a-22695a65db5f",
    "/subscriptions/5ed9830b-9ef4-4764-bfeb-f5aaa29bdd97"
  ]
}
EOF

# Create or update custom role
echo "Creating custom role..."
az role definition create --role-definition custom-role.json 2>/dev/null || \
az role definition update --role-definition custom-role.json

# Wait for propagation
echo "Waiting 30 seconds for role to propagate..."
sleep 30

# Assign role to each subscription
echo "Assigning Resource Group Cleanup role to Managed Identity..."
for SUB_ID in "${SUBSCRIPTIONS[@]}"; do
  echo "  Assigning to subscription: $SUB_ID"
  az role assignment create \
    --assignee $PRINCIPAL_ID \
    --role "Resource Group Cleanup" \
    --scope "/subscriptions/$SUB_ID" \
    2>/dev/null && echo "    [OK]" || echo "    [Already exists or failed]"
done

# Assign Cost Management Reader role for cost tracking
echo ""
echo "Assigning Cost Management Reader role for cost tracking..."
for SUB_ID in "${SUBSCRIPTIONS[@]}"; do
  echo "  Assigning Cost Management Reader to subscription: $SUB_ID"
  az role assignment create \
    --assignee $PRINCIPAL_ID \
    --role "Cost Management Reader" \
    --scope "/subscriptions/$SUB_ID" \
    2>/dev/null && echo "    [OK]" || echo "    [Already exists or failed]"
done

# Verify
echo ""
echo "Verifying role assignments..."
az role assignment list --assignee $PRINCIPAL_ID --query "[?roleDefinitionName=='Resource Group Cleanup'].{Role:roleDefinitionName,Scope:scope}" -o table
echo ""
az role assignment list --assignee $PRINCIPAL_ID --query "[?roleDefinitionName=='Cost Management Reader'].{Role:roleDefinitionName,Scope:scope}" -o table

# Cleanup
rm -f custom-role.json

echo ""
echo "Setup complete!"
