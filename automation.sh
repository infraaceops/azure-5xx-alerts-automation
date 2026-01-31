#!/usr/bin/env bash

################################
# CONFIG (EDIT THESE)
################################
RESOURCE_GROUP="rg-alert-test"
LOCATION="eastus"
APP_INSIGHTS_NAME="appi-alert-test"
ACTION_GROUP_NAME="ag-alert-test"
ALERT_EMAIL="shadab@infraaceops.com"

ENVIRONMENT="TEST"

################################
# SET CONTEXT
################################

################################
# CREATE ACTION GROUP
################################
az monitor action-group create \
  --name "$ACTION_GROUP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --short-name "PPAY" \
  --action email OnCallEmail "$ALERT_EMAIL"

ACTION_GROUP_ID=$(az monitor action-group show \
  --name "$ACTION_GROUP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv)

################################
# GET APP INSIGHTS ID
################################
APP_INSIGHTS_ID=$(az monitor app-insights component show \
  --app "$APP_INSIGHTS_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id -o tsv)

################################
# KQL WITH ROOT-CAUSE SIGNALS
################################

# -------- 5XX ROOT-CAUSE SIGNALS --------
KQL_5XX="
requests
| where timestamp > ago(5m)
| where resultCode startswith \"5\"
| summarize
    Total5xx = count(),
    AffectedEndpoints = make_set(name, 5),
    AffectedInstances = make_set(cloud_RoleInstance, 5),
    ResultCodes = make_set(resultCode)
"

# -------- 401 ROOT-CAUSE SIGNALS --------
KQL_401="
requests
| where timestamp > ago(5m)
| where resultCode == \"401\"
| summarize
    Total401 = count(),
    AffectedEndpoints = make_set(name, 5),
    ClientTypes = make_set(client_Type),
    AuthResults = make_set(resultCode)
"

################################
# CREATE 5XX ALERT
################################
az monitor scheduled-query create \
  --name "alert-5xx-spike-${ENVIRONMENT}" \
  --resource-group "$RESOURCE_GROUP" \
  --scopes "$APP_INSIGHTS_ID" \
  --condition "Total5xx > 200" \
  --condition-query "$KQL_5XX" \
  --description "5xx spike detected in ${ENVIRONMENT}.
Probable causes:
- Backend/service crash
- Dependency outage
- Bad deployment or config change

Alert context includes affected endpoints and instances." \
  --severity 2 \
  --evaluation-frequency 5m \
  --window-size 5m \
  --action-groups "$ACTION_GROUP_ID" \
  --enabled true

################################
# CREATE 401 ALERT
################################
az monitor scheduled-query create \
  --name "alert-401-spike-${ENVIRONMENT}" \
  --resource-group "$RESOURCE_GROUP" \
  --scopes "$APP_INSIGHTS_ID" \
  --condition "Total401 > 200" \
  --condition-query "$KQL_401" \
  --description "401 spike detected in ${ENVIRONMENT}.
Probable causes:
- Token expired / invalid
- Auth service outage
- Issuer / audience misconfiguration

Alert context includes affected endpoints and client types." \
  --severity 2 \
  --evaluation-frequency 5m \
  --window-size 5m \
  --action-groups "$ACTION_GROUP_ID" \
  --enabled true

################################
# VERIFY
################################
az monitor scheduled-query list \
  --resource-group "$RESOURCE_GROUP" \
  --output table

################################
# TESTING INFO
################################
cat <<EOF

========================================
WHAT YOU WILL SEE IN EMAIL
========================================
✔ Total error count
✔ Affected endpoints (top 5)
✔ Affected instances / clients
✔ Status code patterns

========================================
TEST 401 ALERT
========================================
for i in {1..250}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://api.example.com/payment
done

Wait ~5 minutes for email.

========================================
DONE
========================================
EOF
