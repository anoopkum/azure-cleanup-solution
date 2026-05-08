#!/bin/bash
# Azure Cleanup Solution - Deployment Script

# === UPDATE THESE VARIABLES ===
SUBSCRIPTION_ID="YOUR_SUBSCRIPTION_ID"
RESOURCE_GROUP="rg-cleanup-solution"
LOCATION="uksouth"
LOGIC_APP_NAME="auto-resource-cleanup"
ADMIN_EMAILS="admin@example.com"
SHARED_MAILBOX="cleanup@example.com"

# === DEPLOYMENT ===
echo "Deploying Azure Cleanup Solution..."

az account set --subscription $SUBSCRIPTION_ID
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy Logic App
sed -e "s/YOUR_SUBSCRIPTION_ID/$SUBSCRIPTION_ID/g" \
    -e "s/YOUR_RESOURCE_GROUP/$RESOURCE_GROUP/g" \
    -e "s/YOUR_LOCATION/$LOCATION/g" \
    ../logic-app/cleanup-workflow.json > /tmp/workflow.json

az logic workflow create \
    --resource-group $RESOURCE_GROUP \
    --name $LOGIC_APP_NAME \
    --definition /tmp/workflow.json

# Assign roles
PRINCIPAL_ID=$(az logic workflow show --name $LOGIC_APP_NAME --resource-group $RESOURCE_GROUP --query "identity.principalId" -o tsv)
az role assignment create --assignee $PRINCIPAL_ID --role "Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --assignee $PRINCIPAL_ID --role "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID"
az role assignment create --assignee $PRINCIPAL_ID --role "Cost Management Reader" --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "Done! Authorize Office 365 connection in Azure Portal."
