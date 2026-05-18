#!/bin/bash
set -euo pipefail

usage() {
  echo "Usage: $0 <workload> <environment>"
  echo "  workload:    3-char workload abbreviation (e.g. ccv)"
  echo "  environment: prd / stg / dev"
  exit 1
}

[ $# -lt 2 ] && usage

WORKLOAD="$1"
ENVIRONMENT="$2"
LOCATION="japaneast"
RG_NAME="rg-${WORKLOAD}-${ENVIRONMENT}-001"
KV_NAME="kv-${WORKLOAD}-${ENVIRONMENT}-001"
SSH_KEY_PATH_DEV="${HOME}/.ssh/azure-${WORKLOAD}-${ENVIRONMENT}-dev"
SSH_KEY_PATH_PRX="${HOME}/.ssh/azure-${WORKLOAD}-${ENVIRONMENT}-prx"

echo "=== Azure Claude Code VM Prerequisites ==="
echo "Workload    : ${WORKLOAD}"
echo "Environment : ${ENVIRONMENT}"
echo "Resource Group : ${RG_NAME}"
echo "Key Vault   : ${KV_NAME}"
echo ""

# Check login
az account show > /dev/null 2>&1 || { echo "[ERROR] Please run 'az login' first"; exit 1; }
CURRENT_USER=$(az account show --query user.name -o tsv)
echo "Logged in as: ${CURRENT_USER}"
echo ""

# 1. Create resource group
echo "[1/4] Creating resource group..."
az group create \
  --name "${RG_NAME}" \
  --location "${LOCATION}" \
  --tags \
    "Environment=${ENVIRONMENT}" \
    "Owner=${CURRENT_USER}" \
    "Project=${WORKLOAD}: Claude Code VM" \
  --output none
echo "      ${RG_NAME} created"

# 2. Create Key Vault
echo "[2/4] Creating Key Vault..."
az keyvault create \
  --name "${KV_NAME}" \
  --resource-group "${RG_NAME}" \
  --location "${LOCATION}" \
  --enable-rbac-authorization true \
  --enabled-for-template-deployment true \
  --output none
echo "      ${KV_NAME} created"

# Assign RBAC role for Key Vault
MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
KV_ID=$(az keyvault show --name "${KV_NAME}" --resource-group "${RG_NAME}" --query id -o tsv)
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee "${MY_OBJECT_ID}" \
  --scope "${KV_ID}" \
  --output none
echo "      Key Vault Secrets Officer role assigned"

# Wait for RBAC propagation (secret operations return 403 before it propagates)
echo "      Waiting for RBAC role to propagate..."
for i in $(seq 1 10); do
  az keyvault secret list --vault-name "${KV_NAME}" --output none 2>/dev/null && break
  echo "      ... ${i}/10 (retrying in 30s)"
  sleep 30
done

# 3. Generate SSH key pairs (one per VM role: dev / prx)
echo "[3/4] Generating SSH key pairs..."
for ROLE in dev prx; do
  KEY_PATH_VAR="SSH_KEY_PATH_$(echo ${ROLE} | tr '[:lower:]' '[:upper:]')"
  KEY_PATH="${!KEY_PATH_VAR}"
  if [ -f "${KEY_PATH}" ]; then
    echo "      Using existing SSH key (${ROLE}): ${KEY_PATH}"
  else
    ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "azure-${WORKLOAD}-${ENVIRONMENT}-${ROLE}" -N ""
    echo "      SSH key generated (${ROLE}): ${KEY_PATH}"
  fi
done

# 4. Store SSH keys in Key Vault (one per VM role: dev / prx)
echo "[4/4] Storing SSH keys in Key Vault..."
for ROLE in dev prx; do
  KEY_PATH_VAR="SSH_KEY_PATH_$(echo ${ROLE} | tr '[:lower:]' '[:upper:]')"
  KEY_PATH="${!KEY_PATH_VAR}"
  az keyvault secret set \
    --vault-name "${KV_NAME}" \
    --name "ssh-public-key-${ROLE}" \
    --value "$(cat "${KEY_PATH}.pub")" \
    --output none
  az keyvault secret set \
    --vault-name "${KV_NAME}" \
    --name "ssh-private-key-${ROLE}" \
    --file "${KEY_PATH}" \
    --output none
  rm -f "${KEY_PATH}"
  echo "      ssh-public-key-${ROLE} / ssh-private-key-${ROLE} stored; local private key removed"
done

echo ""
echo "=== Prerequisites complete ==="
echo ""
echo "Run the following command to deploy:"
echo ""
echo "  az deployment group create \\"
echo "    --resource-group ${RG_NAME} \\"
echo "    --template-file bicep/main.bicep \\"
echo "    --parameters bicep/main.parameters.json \\"
echo "    --parameters keyVaultName=${KV_NAME} \\"
echo "    --parameters allowedSshSourceIp=\$(curl -sf https://ifconfig.me)/32"
echo ""
