#!/usr/bin/env bash

####################################
# CONFIG
####################################
LOCATION="eastus"
RG_NAME="rg-alert-test"
LAW_NAME="law-alert-test"
ENV_NAME="aca-env-alert-test"
APP_NAME="aca-test-api"

####################################
# SET CONTEXT
####################################

####################################
# CREATE RESOURCE GROUP
####################################
echo "Creating Resource Group..."
az group create \
  --name "$RG_NAME" \
  --location "$LOCATION"

####################################
# CREATE LOG ANALYTICS
####################################
echo "Creating Log Analytics Workspace..."
az monitor log-analytics workspace create \
  --resource-group "$RG_NAME" \
  --workspace-name "$LAW_NAME" \
  --location "$LOCATION"

LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RG_NAME" \
  --workspace-name "$LAW_NAME" \
  --query customerId -o tsv)

LAW_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group "$RG_NAME" \
  --workspace-name "$LAW_NAME" \
  --query primarySharedKey -o tsv)

####################################
# CREATE CONTAINER APPS ENV
####################################
echo "Creating Container Apps Environment..."
az containerapp env create \
  --name "$ENV_NAME" \
  --resource-group "$RG_NAME" \
  --location "$LOCATION" \
  --logs-workspace-id "$LAW_ID" \
  --logs-workspace-key "$LAW_KEY"

####################################
# DEPLOY TEST CONTAINER APP
####################################
echo "Deploying test container app..."

az containerapp create \
  --name "$APP_NAME" \
  --resource-group "$RG_NAME" \
  --environment "$ENV_NAME" \
  --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest \
  --target-port 80 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 1

APP_URL=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RG_NAME" \
  --query properties.configuration.ingress.fqdn -o tsv)

echo "App URL: https://$APP_URL"

####################################
# WAIT FOR APP
####################################
echo "Waiting for app to be ready..."
sleep 30

####################################
# TEST 401 (NO AUTH ENDPOINT)
####################################
echo "Generating 401 errors..."
for i in {1..50}; do
  curl -s -o /dev/null -w "%{http_code}\n" "https://$APP_URL/secure"
done

####################################
# TEST 5XX (INVALID PATH)
####################################
echo "Generating 5xx errors..."
for i in {1..50}; do
  curl -s -o /dev/null -w "%{http_code}\n" "https://$APP_URL/does-not-exist"
done

echo "Traffic generated. Wait 5-10 minutes for alerts."

# ####################################
# # OPTIONAL WAIT BEFORE DESTROY
# ####################################
# read -p "Press ENTER to destroy infra..."

# ####################################
# # DESTROY EVERYTHING
# ####################################
# echo "Deleting Resource Group..."
# az group delete \
#   --name "$RG_NAME" \
#   --yes \
#   --no-wait

# echo "DONE. Infra cleanup started."
