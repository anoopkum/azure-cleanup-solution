#!/bin/bash
# Setup Custom Role and Assign to Logic App Managed Identity
# Run: chmod +x setup-roles.sh && ./setup-roles.sh

# Variables - UPDATE THESE
LOGIC_APP_NAME="YOUR_LOGIC_APP_NAME"
LOGIC_APP_RG="YOUR_RESOURCE_GROUP"
TENANT_ID="YOUR_TENANT_ID"

# All subscription IDs in tenant - UPDATE THESE
SUBSCRIPTIONS=(
  "00000000-0000-0000-0000-000000000001"  # Subscription-1
  "00000000-0000-0000-0000-000000000002"  # Subscription-2
  "00000000-0000-0000-0000-000000000003"  # Subscription-3
)

# Login to Azure
echo "Logging in to Azure..."
az login --tenant $TENANT_ID

# Get Logic App Managed Identity Principal ID
echo "Getting Logic App Managed Identity..."
PRINCIPAL_ID=$(az logic workflow show --name $LOGIC_APP_NAME --resource-group $LOGIC_APP_RG --query "identity.principalId" -o tsv)
echo "Principal ID: $PRINCIPAL_ID"

# Build AssignableScopes dynamically
SCOPES=""
for SUB_ID in "${SUBSCRIPTIONS[@]}"; do
  SCOPES="$SCOPES\"/subscriptions/$SUB_ID\","
done
SCOPES="${SCOPES%,}"  # Remove trailing comma

# Create custom role definition JSON
cat > custom-role.json << EOF
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
  "AssignableScopes": [$SCOPES]
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
echo "Assigning Cost Management Reader role..."
for SUB_ID in "${SUBSCRIPTIONS[@]}"; do
  echo "  Assigning to subscription: $SUB_ID"
  az role assignment create \
    --assignee $PRINCIPAL_ID \
    --role "Cost Management Reader" \
    --scope "/subscriptions/$SUB_ID" \
    2>/dev/null && echo "    [OK]" || echo "    [Already exists or failed]"
done

# Cleanup
rm -f custom-role.json

echo ""
echo "Setup complete!"
