#!/bin/bash

# deploy.sh - Deploy Azure IoT Edge Predictive Maintenance Infrastructure
# This script deploys the complete infrastructure for edge-based predictive maintenance
# using Azure IoT Edge and Azure Monitor

set -euo pipefail

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
FORCE=false

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP="rg-predictive-maintenance"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure IoT Edge Predictive Maintenance Infrastructure

OPTIONS:
    -g, --resource-group NAME    Resource group name (default: ${DEFAULT_RESOURCE_GROUP})
    -l, --location LOCATION      Azure location (default: ${DEFAULT_LOCATION})
    -d, --dry-run               Show what would be deployed without actually deploying
    -f, --force                 Force deployment even if resources exist
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose logging

EXAMPLES:
    $0                                                    # Deploy with defaults
    $0 -g my-rg -l westus2                              # Deploy to specific resource group and location
    $0 --dry-run                                         # Show what would be deployed
    $0 --force                                           # Force deployment

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if IoT extension is installed
    if ! az extension show --name azure-iot &> /dev/null; then
        log "INFO" "Installing Azure IoT CLI extension..."
        az extension add --name azure-iot
    fi
    
    # Check if Stream Analytics extension is installed
    if ! az extension show --name stream-analytics &> /dev/null; then
        log "INFO" "Installing Stream Analytics CLI extension..."
        az extension add --name stream-analytics
    fi
    
    # Verify account information
    local account_info=$(az account show --query '{subscriptionId:id,tenantId:tenantId,name:name}' -o json)
    local subscription_id=$(echo "$account_info" | jq -r '.subscriptionId')
    local tenant_id=$(echo "$account_info" | jq -r '.tenantId')
    local subscription_name=$(echo "$account_info" | jq -r '.name')
    
    log "INFO" "Using subscription: $subscription_name ($subscription_id)"
    log "INFO" "Tenant ID: $tenant_id"
    
    # Check if jq is available (optional but helpful)
    if ! command -v jq &> /dev/null; then
        log "WARN" "jq is not installed. Some output formatting may be limited."
    fi
}

# Generate unique resource names
generate_resource_names() {
    local random_suffix=$(openssl rand -hex 4 2>/dev/null || echo "$(date +%s | tail -c 4)")
    
    export IOT_HUB_NAME="hub-pm-${random_suffix}"
    export STORAGE_ACCOUNT="stpm${random_suffix}"
    export DEVICE_ID="edge-device-01"
    export SA_JOB_NAME="sa-edge-anomaly-${random_suffix}"
    export LOG_ANALYTICS_WORKSPACE="law-pm-${random_suffix}"
    export ACTION_GROUP_NAME="ag-maintenance-team-${random_suffix}"
    export ALERT_RULE_NAME="alert-high-temperature-${random_suffix}"
    
    log "INFO" "Generated resource names:"
    log "INFO" "  IoT Hub: $IOT_HUB_NAME"
    log "INFO" "  Storage Account: $STORAGE_ACCOUNT"
    log "INFO" "  Stream Analytics Job: $SA_JOB_NAME"
    log "INFO" "  Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
}

# Check if resource group exists
check_resource_group() {
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Resource group '$RESOURCE_GROUP' already exists"
        if [[ "$FORCE" == "false" ]]; then
            read -p "Resource group already exists. Continue? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "INFO" "Deployment cancelled by user"
                exit 0
            fi
        fi
    else
        log "INFO" "Resource group '$RESOURCE_GROUP' will be created"
    fi
}

# Create resource group
create_resource_group() {
    log "INFO" "Creating resource group '$RESOURCE_GROUP' in location '$LOCATION'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create resource group: $RESOURCE_GROUP"
        return
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=predictive-maintenance environment=demo \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "✅ Resource group created successfully"
    else
        error_exit "Failed to create resource group"
    fi
}

# Create IoT Hub
create_iot_hub() {
    log "INFO" "Creating IoT Hub '$IOT_HUB_NAME'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create IoT Hub: $IOT_HUB_NAME"
        return
    fi
    
    az iot hub create \
        --name "$IOT_HUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku S1 \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "✅ IoT Hub created successfully"
    else
        error_exit "Failed to create IoT Hub"
    fi
}

# Create Storage Account
create_storage_account() {
    log "INFO" "Creating Storage Account '$STORAGE_ACCOUNT'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create Storage Account: $STORAGE_ACCOUNT"
        return
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "✅ Storage Account created successfully"
        
        # Create container for Stream Analytics
        az storage container create \
            --name streamanalytics \
            --account-name "$STORAGE_ACCOUNT" \
            --auth-mode login \
            --output none
        
        # Create container for telemetry archive
        az storage container create \
            --name telemetry-archive \
            --account-name "$STORAGE_ACCOUNT" \
            --auth-mode login \
            --output none
            
        log "INFO" "✅ Storage containers created successfully"
    else
        error_exit "Failed to create Storage Account"
    fi
}

# Create Log Analytics Workspace
create_log_analytics_workspace() {
    log "INFO" "Creating Log Analytics Workspace '$LOG_ANALYTICS_WORKSPACE'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
        return
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "✅ Log Analytics Workspace created successfully"
    else
        error_exit "Failed to create Log Analytics Workspace"
    fi
}

# Register IoT Edge Device
register_edge_device() {
    log "INFO" "Registering IoT Edge Device '$DEVICE_ID'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would register IoT Edge Device: $DEVICE_ID"
        return
    fi
    
    az iot hub device-identity create \
        --device-id "$DEVICE_ID" \
        --edge-enabled \
        --hub-name "$IOT_HUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "✅ IoT Edge Device registered successfully"
        
        # Get connection string
        local connection_string=$(az iot hub device-identity connection-string show \
            --device-id "$DEVICE_ID" \
            --hub-name "$IOT_HUB_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query connectionString \
            --output tsv)
        
        log "INFO" "📝 Device connection string (save this for edge device configuration):"
        log "INFO" "$connection_string"
    else
        error_exit "Failed to register IoT Edge Device"
    fi
}

# Create Stream Analytics Job
create_stream_analytics_job() {
    log "INFO" "Creating Stream Analytics Job '$SA_JOB_NAME'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create Stream Analytics Job: $SA_JOB_NAME"
        return
    fi
    
    # Note: Stream Analytics job creation for IoT Edge is complex and may require additional configuration
    # This is a simplified version for demonstration
    log "WARN" "Stream Analytics job creation for IoT Edge requires additional manual configuration"
    log "INFO" "Please refer to Azure documentation for complete Stream Analytics Edge deployment"
}

# Create Action Group for Alerts
create_action_group() {
    log "INFO" "Creating Action Group '$ACTION_GROUP_NAME'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create Action Group: $ACTION_GROUP_NAME"
        return
    fi
    
    az monitor action-group create \
        --name "$ACTION_GROUP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --short-name MaintTeam \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "✅ Action Group created successfully"
        log "WARN" "⚠️  Please configure email/SMS receivers manually in the Azure portal"
    else
        error_exit "Failed to create Action Group"
    fi
}

# Create Alert Rule
create_alert_rule() {
    log "INFO" "Creating Alert Rule '$ALERT_RULE_NAME'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create Alert Rule: $ALERT_RULE_NAME"
        return
    fi
    
    local subscription_id=$(az account show --query id --output tsv)
    local scope="/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Devices/IotHubs/${IOT_HUB_NAME}"
    
    az monitor metrics alert create \
        --name "$ALERT_RULE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "$scope" \
        --condition "avg messages.telemetry.allProtocol > 100" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action "$ACTION_GROUP_NAME" \
        --description "Alert when high message volume indicates anomalies" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "✅ Alert Rule created successfully"
    else
        error_exit "Failed to create Alert Rule"
    fi
}

# Configure IoT Hub Message Routing
configure_message_routing() {
    log "INFO" "Configuring IoT Hub message routing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would configure message routing"
        return
    fi
    
    # Get storage connection string
    local storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    # Create routing endpoint
    az iot hub routing-endpoint create \
        --hub-name "$IOT_HUB_NAME" \
        --endpoint-name telemetry-storage \
        --endpoint-type azurestoragecontainer \
        --endpoint-resource-group "$RESOURCE_GROUP" \
        --endpoint-subscription-id "$(az account show --query id --output tsv)" \
        --connection-string "$storage_connection" \
        --container-name telemetry-archive \
        --encoding json \
        --output none
    
    # Create route
    az iot hub route create \
        --hub-name "$IOT_HUB_NAME" \
        --route-name telemetry-to-storage \
        --source DeviceMessages \
        --endpoint-name telemetry-storage \
        --condition true \
        --enabled true \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "INFO" "✅ Message routing configured successfully"
    else
        log "WARN" "Failed to configure message routing (this may require manual setup)"
    fi
}

# Validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would validate deployment"
        return
    fi
    
    local validation_failed=false
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "ERROR" "Resource group validation failed"
        validation_failed=true
    fi
    
    # Check IoT Hub
    if ! az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "ERROR" "IoT Hub validation failed"
        validation_failed=true
    fi
    
    # Check Storage Account
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "ERROR" "Storage Account validation failed"
        validation_failed=true
    fi
    
    # Check Log Analytics Workspace
    if ! az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
        log "ERROR" "Log Analytics Workspace validation failed"
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        error_exit "Deployment validation failed"
    else
        log "INFO" "✅ Deployment validation passed"
    fi
}

# Print deployment summary
print_summary() {
    log "INFO" "📋 Deployment Summary:"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  Location: $LOCATION"
    log "INFO" "  IoT Hub: $IOT_HUB_NAME"
    log "INFO" "  Storage Account: $STORAGE_ACCOUNT"
    log "INFO" "  Log Analytics: $LOG_ANALYTICS_WORKSPACE"
    log "INFO" "  Edge Device: $DEVICE_ID"
    log "INFO" ""
    log "INFO" "📝 Next Steps:"
    log "INFO" "1. Configure your IoT Edge device with the connection string provided above"
    log "INFO" "2. Deploy the Stream Analytics job to the edge device"
    log "INFO" "3. Configure alert notification recipients in the Azure portal"
    log "INFO" "4. Monitor the deployment using Azure Monitor"
    log "INFO" ""
    log "INFO" "📊 Estimated monthly cost: ~$50 (IoT Hub S1 + Storage + minimal Stream Analytics)"
    log "INFO" "🚨 Remember to clean up resources when done to avoid unnecessary charges"
}

# Main deployment function
main() {
    log "INFO" "Starting Azure IoT Edge Predictive Maintenance deployment..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Set defaults
    RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
    LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Generate resource names
    generate_resource_names
    
    # Check if resource group exists
    check_resource_group
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "🔍 DRY RUN MODE - No resources will be created"
        log "INFO" "Would deploy to resource group: $RESOURCE_GROUP"
        log "INFO" "Would deploy to location: $LOCATION"
        print_summary
        return
    fi
    
    # Create resources
    create_resource_group
    create_iot_hub
    create_storage_account
    create_log_analytics_workspace
    register_edge_device
    create_stream_analytics_job
    create_action_group
    create_alert_rule
    configure_message_routing
    
    # Validate deployment
    validate_deployment
    
    # Print summary
    print_summary
    
    log "INFO" "🎉 Deployment completed successfully!"
    log "INFO" "📄 Check the log file for detailed information: $LOG_FILE"
}

# Handle script interruption
cleanup_on_exit() {
    log "WARN" "Script interrupted. Cleaning up..."
    exit 130
}

# Set up signal handlers
trap cleanup_on_exit SIGINT SIGTERM

# Run main function
main "$@"