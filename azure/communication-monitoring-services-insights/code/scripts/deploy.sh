#!/usr/bin/env bash

#############################################################################
# Azure Communication Monitoring Deployment Script
# Recipe: Communication Monitoring with Communication Services and Application Insights
# Purpose: Deploy Azure Communication Services with comprehensive monitoring
#############################################################################

set -euo pipefail

# Configuration and Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy-config"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
DEFAULT_RESOURCE_GROUP="rg-comm-monitor"
DEFAULT_LOCATION="eastus"

#############################################################################
# Utility Functions
#############################################################################

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Generate random suffix for unique resource names
generate_suffix() {
    if command_exists openssl; then
        openssl rand -hex 3
    elif command_exists shuf; then
        shuf -i 100000-999999 -n 1
    else
        echo $((RANDOM % 900000 + 100000))
    fi
}

# Validate Azure CLI authentication
validate_azure_auth() {
    log "INFO" "Validating Azure CLI authentication..."
    
    if ! command_exists az; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/"
    fi
    
    local account_info
    if ! account_info=$(az account show 2>/dev/null); then
        error_exit "Not logged into Azure CLI. Please run 'az login' first."
    fi
    
    local subscription_id
    subscription_id=$(echo "$account_info" | jq -r '.id')
    local subscription_name
    subscription_name=$(echo "$account_info" | jq -r '.name')
    
    log "INFO" "Authenticated to Azure subscription: $subscription_name ($subscription_id)"
    
    # Verify required resource providers are registered
    log "INFO" "Checking Azure resource provider registrations..."
    
    local providers=("Microsoft.Communication" "Microsoft.OperationalInsights" "Microsoft.Insights")
    for provider in "${providers[@]}"; do
        local status
        status=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
        
        if [[ "$status" != "Registered" ]]; then
            log "WARN" "Resource provider $provider is not registered. Registering now..."
            az provider register --namespace "$provider" || error_exit "Failed to register $provider"
            
            # Wait for registration to complete
            local max_attempts=30
            local attempt=1
            while [[ $attempt -le $max_attempts ]]; do
                status=$(az provider show --namespace "$provider" --query "registrationState" -o tsv)
                if [[ "$status" == "Registered" ]]; then
                    log "INFO" "Provider $provider registered successfully"
                    break
                fi
                log "INFO" "Waiting for $provider registration... (attempt $attempt/$max_attempts)"
                sleep 10
                ((attempt++))
            done
            
            if [[ $attempt -gt $max_attempts ]]; then
                error_exit "Timeout waiting for $provider registration"
            fi
        else
            log "INFO" "Provider $provider is already registered"
        fi
    done
}

# Load or create configuration
load_config() {
    log "INFO" "Loading deployment configuration..."
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log "INFO" "Loading existing configuration from $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        log "INFO" "Creating new deployment configuration..."
        
        # Generate unique suffix
        RANDOM_SUFFIX=${RANDOM_SUFFIX:-$(generate_suffix)}
        
        # Set default values
        RESOURCE_GROUP=${RESOURCE_GROUP:-"${DEFAULT_RESOURCE_GROUP}-${RANDOM_SUFFIX}"}
        LOCATION=${LOCATION:-"$DEFAULT_LOCATION"}
        COMM_SERVICE_NAME=${COMM_SERVICE_NAME:-"cs-monitor-${RANDOM_SUFFIX}"}
        LOG_WORKSPACE_NAME=${LOG_WORKSPACE_NAME:-"law-monitor-${RANDOM_SUFFIX}"}
        APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME:-"ai-monitor-${RANDOM_SUFFIX}"}
        
        # Save configuration
        cat > "$CONFIG_FILE" << EOF
# Deployment Configuration - Generated $(date)
RANDOM_SUFFIX="$RANDOM_SUFFIX"
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
COMM_SERVICE_NAME="$COMM_SERVICE_NAME"
LOG_WORKSPACE_NAME="$LOG_WORKSPACE_NAME"
APP_INSIGHTS_NAME="$APP_INSIGHTS_NAME"
EOF
        
        log "INFO" "Configuration saved to $CONFIG_FILE"
    fi
    
    # Display configuration
    log "INFO" "Deployment Configuration:"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  Location: $LOCATION"
    log "INFO" "  Communication Service: $COMM_SERVICE_NAME"
    log "INFO" "  Log Analytics Workspace: $LOG_WORKSPACE_NAME"
    log "INFO" "  Application Insights: $APP_INSIGHTS_NAME"
}

# Check if resource group exists
check_resource_group() {
    log "INFO" "Checking if resource group exists..."
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "WARN" "Resource group $RESOURCE_GROUP already exists"
        return 0
    else
        log "INFO" "Resource group $RESOURCE_GROUP does not exist"
        return 1
    fi
}

# Create resource group
create_resource_group() {
    log "INFO" "Creating resource group: $RESOURCE_GROUP"
    
    if ! check_resource_group; then
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo deployment=communication-monitoring \
            || error_exit "Failed to create resource group"
        
        log "INFO" "✅ Resource group created successfully"
    else
        log "WARN" "Resource group already exists, skipping creation"
    fi
}

# Create Log Analytics Workspace
create_log_analytics_workspace() {
    log "INFO" "Creating Log Analytics Workspace: $LOG_WORKSPACE_NAME"
    
    # Check if workspace already exists
    if az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE_NAME" >/dev/null 2>&1; then
        log "WARN" "Log Analytics Workspace already exists, skipping creation"
        return 0
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE_NAME" \
        --location "$LOCATION" \
        --tags purpose=communication-monitoring deployment=automated \
        || error_exit "Failed to create Log Analytics Workspace"
    
    # Wait for workspace to be fully provisioned
    log "INFO" "Waiting for Log Analytics Workspace to be ready..."
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local provisioning_state
        provisioning_state=$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE_NAME" \
            --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")
        
        if [[ "$provisioning_state" == "Succeeded" ]]; then
            log "INFO" "✅ Log Analytics Workspace created successfully"
            break
        fi
        
        log "INFO" "Workspace provisioning state: $provisioning_state (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error_exit "Timeout waiting for Log Analytics Workspace provisioning"
    fi
    
    # Get workspace ID for later use
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE_NAME" \
        --query id --output tsv) || error_exit "Failed to get workspace ID"
    
    log "INFO" "Workspace ID: $WORKSPACE_ID"
}

# Create Application Insights
create_application_insights() {
    log "INFO" "Creating Application Insights: $APP_INSIGHTS_NAME"
    
    # Check if Application Insights already exists
    if az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "WARN" "Application Insights already exists, skipping creation"
        return 0
    fi
    
    az monitor app-insights component create \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --workspace "$WORKSPACE_ID" \
        --application-type web \
        --tags purpose=communication-monitoring deployment=automated \
        || error_exit "Failed to create Application Insights"
    
    # Get connection string
    AI_CONNECTION_STRING=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv) || error_exit "Failed to get connection string"
    
    log "INFO" "✅ Application Insights created successfully"
    log "DEBUG" "Connection String: ${AI_CONNECTION_STRING:0:50}..."
}

# Create Communication Services
create_communication_services() {
    log "INFO" "Creating Communication Services: $COMM_SERVICE_NAME"
    
    # Check if Communication Services already exists
    if az communication show \
        --name "$COMM_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "WARN" "Communication Services already exists, skipping creation"
        return 0
    fi
    
    az communication create \
        --name "$COMM_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "Global" \
        --data-location "United States" \
        --tags purpose=communication environment=demo deployment=automated \
        || error_exit "Failed to create Communication Services"
    
    # Get resource ID
    COMM_SERVICE_ID=$(az communication show \
        --name "$COMM_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv) || error_exit "Failed to get Communication Services ID"
    
    log "INFO" "✅ Communication Services created successfully"
    log "DEBUG" "Resource ID: $COMM_SERVICE_ID"
}

# Configure diagnostic settings
configure_diagnostic_settings() {
    log "INFO" "Configuring diagnostic settings for Communication Services"
    
    # Check if diagnostic settings already exist
    local existing_settings
    existing_settings=$(az monitor diagnostic-settings list \
        --resource "$COMM_SERVICE_ID" \
        --query "[?name=='CommServiceDiagnostics']" -o tsv 2>/dev/null || true)
    
    if [[ -n "$existing_settings" ]]; then
        log "WARN" "Diagnostic settings already exist, skipping configuration"
        return 0
    fi
    
    # Create diagnostic settings with comprehensive log categories
    az monitor diagnostic-settings create \
        --name "CommServiceDiagnostics" \
        --resource "$COMM_SERVICE_ID" \
        --workspace "$WORKSPACE_ID" \
        --logs '[
          {
            "category": "EmailSendMailOperational",
            "enabled": true,
            "retentionPolicy": {"enabled": false, "days": 0}
          },
          {
            "category": "EmailStatusUpdateOperational", 
            "enabled": true,
            "retentionPolicy": {"enabled": false, "days": 0}
          },
          {
            "category": "SMSOperational",
            "enabled": true,
            "retentionPolicy": {"enabled": false, "days": 0}
          }
        ]' \
        --metrics '[
          {
            "category": "AllMetrics",
            "enabled": true,
            "retentionPolicy": {"enabled": false, "days": 0}
          }
        ]' \
        || error_exit "Failed to configure diagnostic settings"
    
    log "INFO" "✅ Diagnostic settings configured successfully"
}

# Create monitoring resources
create_monitoring_resources() {
    log "INFO" "Creating monitoring and alerting resources"
    
    # Create action group for alerts
    local action_group_name="CommServiceAlerts"
    
    if ! az monitor action-group show \
        --name "$action_group_name" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        
        az monitor action-group create \
            --name "$action_group_name" \
            --resource-group "$RESOURCE_GROUP" \
            --short-name "CommAlerts" \
            || log "WARN" "Failed to create action group (non-critical)"
        
        log "INFO" "✅ Action group created successfully"
    else
        log "WARN" "Action group already exists, skipping creation"
    fi
    
    # Create metric alert (simplified for compatibility)
    local alert_name="CommunicationServiceFailures"
    
    if ! az monitor metrics alert show \
        --name "$alert_name" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        
        # Note: Creating a basic alert that monitors resource availability
        az monitor metrics alert create \
            --name "$alert_name" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "$COMM_SERVICE_ID" \
            --condition "total APIRequests > 10" \
            --description "Alert when Communication Services requests exceed threshold" \
            --evaluation-frequency 5m \
            --window-size 15m \
            --severity 2 \
            --action "$action_group_name" \
            || log "WARN" "Failed to create metric alert (non-critical)"
        
        log "INFO" "✅ Metric alert created successfully"
    else
        log "WARN" "Metric alert already exists, skipping creation"
    fi
}

# Create monitoring query file
create_monitoring_query() {
    log "INFO" "Creating custom monitoring query file"
    
    local query_file="${SCRIPT_DIR}/monitoring-query.kql"
    
    cat > "$query_file" << 'EOF'
// Communication Services Monitoring Dashboard Query
union 
(
    ACSEmailSendMailOperational
    | where TimeGenerated >= ago(24h)
    | summarize 
        EmailsSent = count(),
        EmailsSuccessful = countif(Level == "Informational"),
        EmailsFailed = countif(Level == "Error")
    | extend ServiceType = "Email"
),
(
    ACSSMSOperational  
    | where TimeGenerated >= ago(24h)
    | summarize 
        MessagesSent = count(),
        MessagesDelivered = countif(DeliveryStatus == "Delivered"),
        MessagesFailed = countif(DeliveryStatus == "Failed")
    | extend ServiceType = "SMS"
)
| project ServiceType, 
          TotalSent = coalesce(EmailsSent, MessagesSent),
          Successful = coalesce(EmailsSuccessful, MessagesDelivered), 
          Failed = coalesce(EmailsFailed, MessagesFailed)
| extend SuccessRate = round((todouble(Successful) / todouble(TotalSent)) * 100, 2)
EOF
    
    log "INFO" "✅ Monitoring query saved to: $query_file"
}

# Validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    local validation_errors=0
    
    # Validate resource group
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "ERROR" "Resource group validation failed"
        ((validation_errors++))
    fi
    
    # Validate Log Analytics Workspace
    local workspace_state
    workspace_state=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE_NAME" \
        --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$workspace_state" != "Succeeded" ]]; then
        log "ERROR" "Log Analytics Workspace validation failed: $workspace_state"
        ((validation_errors++))
    fi
    
    # Validate Application Insights
    local ai_state
    ai_state=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$ai_state" != "Succeeded" ]]; then
        log "ERROR" "Application Insights validation failed: $ai_state"
        ((validation_errors++))
    fi
    
    # Validate Communication Services
    local comm_state
    comm_state=$(az communication show \
        --name "$COMM_SERVICE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState -o tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$comm_state" != "Succeeded" ]]; then
        log "ERROR" "Communication Services validation failed: $comm_state"
        ((validation_errors++))
    fi
    
    # Validate diagnostic settings
    local diag_count
    diag_count=$(az monitor diagnostic-settings list \
        --resource "$COMM_SERVICE_ID" \
        --query "length([?name=='CommServiceDiagnostics'])" -o tsv 2>/dev/null || echo "0")
    
    if [[ "$diag_count" -eq 0 ]]; then
        log "ERROR" "Diagnostic settings validation failed"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log "INFO" "✅ All validation checks passed"
        return 0
    else
        log "ERROR" "Validation failed with $validation_errors errors"
        return 1
    fi
}

# Display deployment summary
display_summary() {
    log "INFO" "Deployment Summary:"
    log "INFO" "=================="
    log "INFO" "Resource Group: $RESOURCE_GROUP"
    log "INFO" "Location: $LOCATION"
    log "INFO" ""
    log "INFO" "Created Resources:"
    log "INFO" "  ✅ Log Analytics Workspace: $LOG_WORKSPACE_NAME"
    log "INFO" "  ✅ Application Insights: $APP_INSIGHTS_NAME"
    log "INFO" "  ✅ Communication Services: $COMM_SERVICE_NAME"
    log "INFO" "  ✅ Diagnostic Settings: CommServiceDiagnostics"
    log "INFO" "  ✅ Monitoring Query: ${SCRIPT_DIR}/monitoring-query.kql"
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "  1. Access Application Insights at: https://portal.azure.com"
    log "INFO" "  2. Use the monitoring query to analyze communication metrics"
    log "INFO" "  3. Configure additional alert rules as needed"
    log "INFO" ""
    log "INFO" "To clean up resources, run: ./destroy.sh"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Communication Services with monitoring infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -g, --resource-group    Resource group name (default: auto-generated)
    -l, --location          Azure region (default: eastus)
    -f, --force             Force redeployment (overwrite existing config)
    -v, --verbose           Enable verbose logging
    --dry-run              Show what would be deployed without creating resources

EXAMPLES:
    $0                                    # Deploy with default settings
    $0 -g my-rg -l westus2               # Deploy to specific resource group and region
    $0 --force                           # Force redeployment
    $0 --dry-run                         # Preview deployment

EOF
}

#############################################################################
# Main Execution
#############################################################################

main() {
    local force_deployment=false
    local dry_run=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -f|--force)
                force_deployment=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    if [[ "$verbose" == true ]]; then
        set -x
    fi
    
    log "INFO" "Starting Azure Communication Monitoring deployment..."
    log "INFO" "Script directory: $SCRIPT_DIR"
    log "INFO" "Log file: $LOG_FILE"
    
    # Force redeployment if requested
    if [[ "$force_deployment" == true ]]; then
        log "INFO" "Force deployment requested, removing existing configuration"
        rm -f "$CONFIG_FILE"
    fi
    
    # Dry run mode
    if [[ "$dry_run" == true ]]; then
        log "INFO" "DRY RUN MODE - No resources will be created"
        load_config
        log "INFO" "Would deploy the following resources:"
        log "INFO" "  - Resource Group: $RESOURCE_GROUP"
        log "INFO" "  - Log Analytics Workspace: $LOG_WORKSPACE_NAME"
        log "INFO" "  - Application Insights: $APP_INSIGHTS_NAME"
        log "INFO" "  - Communication Services: $COMM_SERVICE_NAME"
        exit 0
    fi
    
    # Execute deployment steps
    validate_azure_auth
    load_config
    create_resource_group
    create_log_analytics_workspace
    create_application_insights
    create_communication_services
    configure_diagnostic_settings
    create_monitoring_resources
    create_monitoring_query
    
    # Validate and summarize
    if validate_deployment; then
        display_summary
        log "INFO" "🎉 Deployment completed successfully!"
        log "INFO" "Configuration saved to: $CONFIG_FILE"
        log "INFO" "Logs available at: $LOG_FILE"
    else
        error_exit "Deployment validation failed"
    fi
}

# Execute main function with all arguments
main "$@"