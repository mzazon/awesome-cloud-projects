#!/bin/bash

# Deploy Multi-Platform Push Notifications with Azure Notification Hubs and Azure Spring Apps
# This script deploys the complete infrastructure for the push notification system

set -e
set -u
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "${RED}❌ ERROR: $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    log "${YELLOW}🔍 Running in DRY-RUN mode - no resources will be created${NC}"
    AZ_CMD="echo [DRY-RUN] az"
else
    AZ_CMD="az"
fi

# Print banner
log "${BLUE}============================================${NC}"
log "${BLUE}  Azure Push Notification System Deploy${NC}"
log "${BLUE}============================================${NC}"
log ""

# Check prerequisites
log "${BLUE}🔍 Checking prerequisites...${NC}"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error_exit "Not logged in to Azure. Please run 'az login' first"
fi

# Check if openssl is available for random string generation
if ! command -v openssl &> /dev/null; then
    error_exit "openssl is not installed. Please install it for random string generation"
fi

# Check if Java is installed for Spring Boot development
if ! command -v java &> /dev/null; then
    log "${YELLOW}⚠️  Java is not installed. This is needed for Spring Boot development${NC}"
fi

log "${GREEN}✅ Prerequisites check passed${NC}"

# Default values
RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-pushnotif-demo"}
LOCATION=${LOCATION:-"eastus"}
NOTIFICATION_HUB_NAMESPACE=${NOTIFICATION_HUB_NAMESPACE:-"nhns-$(openssl rand -hex 4)"}
NOTIFICATION_HUB_NAME=${NOTIFICATION_HUB_NAME:-"nh-multiplatform"}
SPRING_APPS_NAME=${SPRING_APPS_NAME:-"asa-pushnotif-$(openssl rand -hex 4)"}
KEY_VAULT_NAME=${KEY_VAULT_NAME:-"kv-push$(openssl rand -hex 4)"}
APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME:-"ai-pushnotif"}
SPRING_APP_NAME=${SPRING_APP_NAME:-"notification-api"}

# Display configuration
log "${BLUE}📋 Configuration:${NC}"
log "Resource Group: $RESOURCE_GROUP"
log "Location: $LOCATION"
log "Notification Hub Namespace: $NOTIFICATION_HUB_NAMESPACE"
log "Notification Hub Name: $NOTIFICATION_HUB_NAME"
log "Spring Apps Name: $SPRING_APPS_NAME"
log "Key Vault Name: $KEY_VAULT_NAME"
log "Application Insights Name: $APP_INSIGHTS_NAME"
log "Spring App Name: $SPRING_APP_NAME"
log ""

# Confirmation prompt
if [[ "$DRY_RUN" != "true" ]]; then
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "${YELLOW}Deployment cancelled${NC}"
        exit 0
    fi
fi

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    
    case $resource_type in
        "group")
            $AZ_CMD group show --name "$resource_name" &> /dev/null
            ;;
        "keyvault")
            $AZ_CMD keyvault show --name "$resource_name" &> /dev/null
            ;;
        "notification-hub-namespace")
            $AZ_CMD notification-hub namespace show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "notification-hub")
            $AZ_CMD notification-hub show --name "$resource_name" --namespace-name "$NOTIFICATION_HUB_NAMESPACE" --resource-group "$resource_group" &> /dev/null
            ;;
        "spring")
            $AZ_CMD spring show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "app-insights")
            $AZ_CMD monitor app-insights component show --app "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Step 1: Create Resource Group
log "${BLUE}🏗️  Step 1: Creating Resource Group...${NC}"
if resource_exists "group" "$RESOURCE_GROUP" ""; then
    log "${YELLOW}⚠️  Resource group '$RESOURCE_GROUP' already exists${NC}"
else
    log "Creating resource group: $RESOURCE_GROUP"
    $AZ_CMD group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=demo environment=dev created-by=script deployment-timestamp="$TIMESTAMP"
    log "${GREEN}✅ Resource group created successfully${NC}"
fi

# Step 2: Create Application Insights
log "${BLUE}🏗️  Step 2: Creating Application Insights...${NC}"
if resource_exists "app-insights" "$APP_INSIGHTS_NAME" "$RESOURCE_GROUP"; then
    log "${YELLOW}⚠️  Application Insights '$APP_INSIGHTS_NAME' already exists${NC}"
else
    log "Creating Application Insights: $APP_INSIGHTS_NAME"
    $AZ_CMD monitor app-insights component create \
        --app "$APP_INSIGHTS_NAME" \
        --location "$LOCATION" \
        --resource-group "$RESOURCE_GROUP" \
        --application-type web \
        --tags purpose=monitoring environment=dev
    log "${GREEN}✅ Application Insights created successfully${NC}"
fi

# Get Application Insights connection string
log "Getting Application Insights connection string..."
if [[ "$DRY_RUN" != "true" ]]; then
    APP_INSIGHTS_CONNECTION=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString -o tsv)
    log "Application Insights connection string obtained"
else
    APP_INSIGHTS_CONNECTION="[DRY-RUN] mock-connection-string"
fi

# Step 3: Create Notification Hub Namespace
log "${BLUE}🏗️  Step 3: Creating Notification Hub Namespace...${NC}"
if resource_exists "notification-hub-namespace" "$NOTIFICATION_HUB_NAMESPACE" "$RESOURCE_GROUP"; then
    log "${YELLOW}⚠️  Notification Hub namespace '$NOTIFICATION_HUB_NAMESPACE' already exists${NC}"
else
    log "Creating Notification Hub namespace: $NOTIFICATION_HUB_NAMESPACE"
    $AZ_CMD notification-hub namespace create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NOTIFICATION_HUB_NAMESPACE" \
        --location "$LOCATION" \
        --sku Standard \
        --tags purpose=notifications environment=dev
    log "${GREEN}✅ Notification Hub namespace created successfully${NC}"
fi

# Step 4: Create Notification Hub
log "${BLUE}🏗️  Step 4: Creating Notification Hub...${NC}"
if resource_exists "notification-hub" "$NOTIFICATION_HUB_NAME" "$RESOURCE_GROUP"; then
    log "${YELLOW}⚠️  Notification Hub '$NOTIFICATION_HUB_NAME' already exists${NC}"
else
    log "Creating Notification Hub: $NOTIFICATION_HUB_NAME"
    $AZ_CMD notification-hub create \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$NOTIFICATION_HUB_NAMESPACE" \
        --name "$NOTIFICATION_HUB_NAME" \
        --location "$LOCATION"
    log "${GREEN}✅ Notification Hub created successfully${NC}"
fi

# Step 5: Create Azure Key Vault
log "${BLUE}🏗️  Step 5: Creating Azure Key Vault...${NC}"
if resource_exists "keyvault" "$KEY_VAULT_NAME" "$RESOURCE_GROUP"; then
    log "${YELLOW}⚠️  Key Vault '$KEY_VAULT_NAME' already exists${NC}"
else
    log "Creating Key Vault: $KEY_VAULT_NAME"
    $AZ_CMD keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --enable-rbac-authorization false \
        --tags purpose=secrets environment=dev
    log "${GREEN}✅ Key Vault created successfully${NC}"
fi

# Step 6: Store secrets in Key Vault
log "${BLUE}🏗️  Step 6: Storing secrets in Key Vault...${NC}"
log "Storing placeholder secrets (replace with actual values in production)"

# Store FCM server key
$AZ_CMD keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "fcm-server-key" \
    --value "your-fcm-server-key-replace-with-actual-key" \
    --description "Firebase Cloud Messaging server key for Android notifications"

# Store APNS key ID
$AZ_CMD keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "apns-key-id" \
    --value "your-apns-key-id-replace-with-actual-key" \
    --description "Apple Push Notification Service key ID for iOS notifications"

# Store VAPID public key
$AZ_CMD keyvault secret set \
    --vault-name "$KEY_VAULT_NAME" \
    --name "vapid-public-key" \
    --value "your-vapid-public-key-replace-with-actual-key" \
    --description "VAPID public key for web push notifications"

# Get and store Notification Hub connection string
log "Getting Notification Hub connection string..."
if [[ "$DRY_RUN" != "true" ]]; then
    NH_CONNECTION_STRING=$(az notification-hub namespace authorization-rule keys list \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$NOTIFICATION_HUB_NAMESPACE" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString -o tsv)
    
    $AZ_CMD keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "notification-hub-connection" \
        --value "$NH_CONNECTION_STRING" \
        --description "Azure Notification Hub connection string"
else
    NH_CONNECTION_STRING="[DRY-RUN] mock-connection-string"
fi

log "${GREEN}✅ Secrets stored in Key Vault successfully${NC}"

# Step 7: Create Azure Spring Apps
log "${BLUE}🏗️  Step 7: Creating Azure Spring Apps...${NC}"
if resource_exists "spring" "$SPRING_APPS_NAME" "$RESOURCE_GROUP"; then
    log "${YELLOW}⚠️  Azure Spring Apps '$SPRING_APPS_NAME' already exists${NC}"
else
    log "Creating Azure Spring Apps: $SPRING_APPS_NAME"
    $AZ_CMD spring create \
        --name "$SPRING_APPS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --tags purpose=microservices environment=dev
    log "${GREEN}✅ Azure Spring Apps created successfully${NC}"
fi

# Step 8: Create Spring App
log "${BLUE}🏗️  Step 8: Creating Spring App...${NC}"
log "Creating Spring app: $SPRING_APP_NAME"
$AZ_CMD spring app create \
    --name "$SPRING_APP_NAME" \
    --service "$SPRING_APPS_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --assign-endpoint true \
    --cpu 1 \
    --memory 2Gi \
    --instance-count 1

log "${GREEN}✅ Spring app created successfully${NC}"

# Step 9: Enable system-assigned managed identity
log "${BLUE}🏗️  Step 9: Enabling managed identity...${NC}"
log "Enabling system-assigned managed identity for Spring app"
$AZ_CMD spring app identity assign \
    --name "$SPRING_APP_NAME" \
    --service "$SPRING_APPS_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --system-assigned

# Get the identity principal ID
if [[ "$DRY_RUN" != "true" ]]; then
    IDENTITY_PRINCIPAL_ID=$(az spring app identity show \
        --name "$SPRING_APP_NAME" \
        --service "$SPRING_APPS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv)
    log "Managed identity principal ID: $IDENTITY_PRINCIPAL_ID"
else
    IDENTITY_PRINCIPAL_ID="[DRY-RUN] mock-principal-id"
fi

log "${GREEN}✅ Managed identity enabled successfully${NC}"

# Step 10: Grant Key Vault access to managed identity
log "${BLUE}🏗️  Step 10: Granting Key Vault access...${NC}"
log "Granting Key Vault access to managed identity"
$AZ_CMD keyvault set-policy \
    --name "$KEY_VAULT_NAME" \
    --object-id "$IDENTITY_PRINCIPAL_ID" \
    --secret-permissions get list \
    --certificate-permissions get list

log "${GREEN}✅ Key Vault access granted successfully${NC}"

# Step 11: Configure environment variables
log "${BLUE}🏗️  Step 11: Configuring environment variables...${NC}"
log "Setting environment variables for Spring app"
$AZ_CMD spring app update \
    --name "$SPRING_APP_NAME" \
    --service "$SPRING_APPS_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --env AZURE_KEYVAULT_URI="https://${KEY_VAULT_NAME}.vault.azure.net/" \
          NOTIFICATION_HUB_NAMESPACE="$NOTIFICATION_HUB_NAMESPACE" \
          NOTIFICATION_HUB_NAME="$NOTIFICATION_HUB_NAME" \
          APPLICATIONINSIGHTS_CONNECTION_STRING="$APP_INSIGHTS_CONNECTION" \
          SPRING_PROFILES_ACTIVE="azure"

log "${GREEN}✅ Environment variables configured successfully${NC}"

# Step 12: Configure diagnostic settings
log "${BLUE}🏗️  Step 12: Configuring monitoring...${NC}"
log "Creating Log Analytics workspace for diagnostic settings"

# Create Log Analytics workspace
LAW_NAME="law-notifications-${TIMESTAMP}"
$AZ_CMD monitor log-analytics workspace create \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LAW_NAME" \
    --location "$LOCATION" \
    --tags purpose=monitoring environment=dev

# Get workspace ID
if [[ "$DRY_RUN" != "true" ]]; then
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LAW_NAME" \
        --query id -o tsv)
    
    NH_RESOURCE_ID=$(az notification-hub namespace show \
        --name "$NOTIFICATION_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query id -o tsv)
    
    # Configure diagnostic settings
    $AZ_CMD monitor diagnostic-settings create \
        --name "notification-diagnostics" \
        --resource "$NH_RESOURCE_ID" \
        --workspace "$WORKSPACE_ID" \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --logs '[{"category": "OperationalLogs", "enabled": true}]'
else
    WORKSPACE_ID="[DRY-RUN] mock-workspace-id"
fi

log "${GREEN}✅ Monitoring configured successfully${NC}"

# Step 13: Display important information
log "${BLUE}📋 Deployment Summary:${NC}"
log "=================================="
log "Resource Group: $RESOURCE_GROUP"
log "Location: $LOCATION"
log "Notification Hub Namespace: $NOTIFICATION_HUB_NAMESPACE"
log "Notification Hub Name: $NOTIFICATION_HUB_NAME"
log "Spring Apps Service: $SPRING_APPS_NAME"
log "Spring App: $SPRING_APP_NAME"
log "Key Vault: $KEY_VAULT_NAME"
log "Application Insights: $APP_INSIGHTS_NAME"
log "Log Analytics Workspace: $LAW_NAME"
log ""

# Get Spring app URL
if [[ "$DRY_RUN" != "true" ]]; then
    APP_URL=$(az spring app show \
        --name "$SPRING_APP_NAME" \
        --service "$SPRING_APPS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.url -o tsv)
    log "Spring App URL: $APP_URL"
else
    APP_URL="[DRY-RUN] mock-app-url"
fi

log ""
log "${GREEN}🎉 Deployment completed successfully!${NC}"
log ""
log "${YELLOW}⚠️  Next Steps:${NC}"
log "1. Configure platform-specific credentials in Azure Portal:"
log "   - Navigate to Notification Hub > Google (GCM/FCM)"
log "   - Enter your FCM Server Key from Firebase Console"
log "   - Configure APNS settings with your Apple certificates"
log "   - Set up Web Push with your VAPID keys"
log ""
log "2. Update Key Vault secrets with actual values:"
log "   - fcm-server-key: Replace with your actual FCM server key"
log "   - apns-key-id: Replace with your actual APNS key ID"
log "   - vapid-public-key: Replace with your actual VAPID public key"
log ""
log "3. Deploy your Spring Boot application:"
log "   - Build your notification service application"
log "   - Deploy using: az spring app deploy --name $SPRING_APP_NAME --service $SPRING_APPS_NAME --resource-group $RESOURCE_GROUP --artifact-path <your-jar-file>"
log ""
log "4. Test the deployment:"
log "   - Health check: curl $APP_URL/actuator/health"
log "   - Test notification: curl -X POST $APP_URL/api/notifications"
log ""
log "${GREEN}✅ Deployment log saved to: $LOG_FILE${NC}"