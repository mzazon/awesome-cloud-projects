#!/bin/bash

# ============================================================================
# Azure Basic Web Monitoring Deployment Script
# ============================================================================
# This script deploys a complete web application monitoring setup using
# Azure App Service and Azure Monitor following the recipe implementation.
#
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   -r, --resource-group NAME    Custom resource group name
#   -l, --location LOCATION      Azure region (default: eastus)
#   -n, --app-name NAME         Custom app name
#   -e, --email EMAIL           Email for alert notifications
#   -d, --dry-run               Show what would be deployed without executing
#   -v, --verbose               Enable verbose logging
#   -h, --help                  Show this help message
#
# Example:
#   ./deploy.sh --email admin@company.com --location westus2
# ============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Default configuration
DEFAULT_LOCATION="eastus"
DEFAULT_EMAIL="admin@example.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
VERBOSE=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Utility Functions
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") 
            if [[ "$VERBOSE" == true ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

show_help() {
    cat << EOF
Azure Basic Web Monitoring Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -r, --resource-group NAME    Custom resource group name
    -l, --location LOCATION      Azure region (default: eastus)
    -n, --app-name NAME         Custom app name
    -e, --email EMAIL           Email for alert notifications
    -d, --dry-run               Show what would be deployed without executing
    -v, --verbose               Enable verbose logging
    -h, --help                  Show this help message

EXAMPLES:
    $0 --email admin@company.com --location westus2
    $0 --dry-run --verbose
    $0 --resource-group my-monitoring-rg --app-name my-webapp

PREREQUISITES:
    - Azure CLI installed and configured
    - Valid Azure subscription with Contributor access
    - Internet connectivity for container image deployment

EOF
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "DEBUG" "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription info
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    log "INFO" "Using Azure subscription: $subscription_name ($subscription_id)"
    
    # Check location validity
    if ! az account list-locations --query "[?name=='$LOCATION']" -o tsv | grep -q "$LOCATION"; then
        log "ERROR" "Invalid Azure location: $LOCATION"
        log "INFO" "Available locations: $(az account list-locations --query '[].name' -o tsv | tr '\n' ' ')"
        exit 1
    fi
    
    log "INFO" "✅ Prerequisites check passed"
}

generate_unique_suffix() {
    # Generate a 6-character random hex string for unique resource names
    openssl rand -hex 3 2>/dev/null || date +%s | tail -c 7
}

execute_command() {
    local cmd="$1"
    local description="$2"
    
    log "INFO" "$description"
    log "DEBUG" "Executing: $cmd"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        log "INFO" "✅ $description completed successfully"
        return 0
    else
        log "ERROR" "❌ Failed: $description"
        return 1
    fi
}

wait_for_resource() {
    local resource_name="$1"
    local resource_type="$2"
    local max_attempts=30
    local attempt=1
    
    log "INFO" "Waiting for $resource_type '$resource_name' to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        case "$resource_type" in
            "webapp")
                if az webapp show --name "$resource_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    local state=$(az webapp show --name "$resource_name" --resource-group "$RESOURCE_GROUP" --query state -o tsv)
                    if [[ "$state" == "Running" ]]; then
                        log "INFO" "✅ Web app is running"
                        return 0
                    fi
                fi
                ;;
            "workspace")
                if az monitor log-analytics workspace show --workspace-name "$resource_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    log "INFO" "✅ Log Analytics workspace is ready"
                    return 0
                fi
                ;;
        esac
        
        log "DEBUG" "Attempt $attempt/$max_attempts - Resource not ready yet, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    log "WARN" "Resource may not be fully ready, continuing anyway..."
    return 0
}

# ============================================================================
# Deployment Functions  
# ============================================================================

create_resource_group() {
    log "INFO" "Creating resource group: $RESOURCE_GROUP"
    
    local cmd="az group create \
        --name '$RESOURCE_GROUP' \
        --location '$LOCATION' \
        --tags purpose=recipe environment=demo created-by=deploy-script"
    
    execute_command "$cmd" "Resource group creation"
}

create_app_service_plan() {
    log "INFO" "Creating App Service plan: $APP_SERVICE_PLAN"
    
    local cmd="az appservice plan create \
        --name '$APP_SERVICE_PLAN' \
        --resource-group '$RESOURCE_GROUP' \
        --location '$LOCATION' \
        --sku F1 \
        --is-linux"
    
    execute_command "$cmd" "App Service plan creation"
}

create_web_application() {
    log "INFO" "Creating web application: $APP_NAME"
    
    local cmd="az webapp create \
        --name '$APP_NAME' \
        --resource-group '$RESOURCE_GROUP' \
        --plan '$APP_SERVICE_PLAN' \
        --container-image-name mcr.microsoft.com/appsvc/node:18-lts"
    
    execute_command "$cmd" "Web application creation"
    
    # Configure app settings
    local config_cmd="az webapp config appsettings set \
        --name '$APP_NAME' \
        --resource-group '$RESOURCE_GROUP' \
        --settings 'WEBSITES_ENABLE_APP_SERVICE_STORAGE=false'"
    
    execute_command "$config_cmd" "Web application configuration"
    
    # Wait for web app to be ready
    wait_for_resource "$APP_NAME" "webapp"
    
    # Get and display web app URL
    if [[ "$DRY_RUN" == false ]]; then
        APP_URL=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query "defaultHostName" -o tsv)
        log "INFO" "Web application URL: https://$APP_URL"
    fi
}

create_log_analytics_workspace() {
    log "INFO" "Creating Log Analytics workspace: $LOG_WORKSPACE"
    
    local cmd="az monitor log-analytics workspace create \
        --workspace-name '$LOG_WORKSPACE' \
        --resource-group '$RESOURCE_GROUP' \
        --location '$LOCATION' \
        --sku PerGB2018"
    
    execute_command "$cmd" "Log Analytics workspace creation"
    
    # Wait for workspace to be ready
    wait_for_resource "$LOG_WORKSPACE" "workspace"
    
    # Get workspace ID for later use
    if [[ "$DRY_RUN" == false ]]; then
        WORKSPACE_ID=$(az monitor log-analytics workspace show \
            --workspace-name "$LOG_WORKSPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --query "id" -o tsv)
        log "DEBUG" "Workspace ID: $WORKSPACE_ID"
    fi
}

configure_application_logging() {
    log "INFO" "Configuring application logging for: $APP_NAME"
    
    # Enable application logging
    local app_logging_cmd="az webapp log config \
        --name '$APP_NAME' \
        --resource-group '$RESOURCE_GROUP' \
        --application-logging filesystem \
        --level information \
        --retention-in-days 3"
    
    execute_command "$app_logging_cmd" "Application logging configuration"
    
    # Enable web server logging
    local web_logging_cmd="az webapp log config \
        --name '$APP_NAME' \
        --resource-group '$RESOURCE_GROUP' \
        --web-server-logging filesystem \
        --retention-in-days 3"
    
    execute_command "$web_logging_cmd" "Web server logging configuration"
}

configure_diagnostic_settings() {
    log "INFO" "Configuring diagnostic settings for centralized logging"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Get App Service resource ID
        APP_ID=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query "id" -o tsv)
        log "DEBUG" "App Service ID: $APP_ID"
        
        # Create diagnostic setting
        local diag_cmd="az monitor diagnostic-settings create \
            --name 'AppServiceDiagnostics' \
            --resource '$APP_ID' \
            --workspace '$WORKSPACE_ID' \
            --logs '[
                {\"category\":\"AppServiceHTTPLogs\",\"enabled\":true},
                {\"category\":\"AppServiceConsoleLogs\",\"enabled\":true},
                {\"category\":\"AppServiceAppLogs\",\"enabled\":true}
            ]' \
            --metrics '[{\"category\":\"AllMetrics\",\"enabled\":true}]'"
        
        execute_command "$diag_cmd" "Diagnostic settings configuration"
    else
        log "INFO" "[DRY-RUN] Would configure diagnostic settings for App Service"
    fi
}

create_alert_rules() {
    log "INFO" "Creating performance and error alert rules"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Create response time alert
        local response_alert_cmd="az monitor metrics alert create \
            --name 'HighResponseTime-$APP_NAME' \
            --resource-group '$RESOURCE_GROUP' \
            --scopes '$APP_ID' \
            --condition 'avg AverageResponseTime > 5' \
            --description 'Alert when average response time exceeds 5 seconds' \
            --evaluation-frequency 1m \
            --window-size 5m \
            --severity 2"
        
        execute_command "$response_alert_cmd" "Response time alert rule creation"
        
        # Create HTTP error alert
        local error_alert_cmd="az monitor metrics alert create \
            --name 'HTTP5xxErrors-$APP_NAME' \
            --resource-group '$RESOURCE_GROUP' \
            --scopes '$APP_ID' \
            --condition 'total Http5xx > 10' \
            --description 'Alert when HTTP 5xx errors exceed 10 in 5 minutes' \
            --evaluation-frequency 1m \
            --window-size 5m \
            --severity 1"
        
        execute_command "$error_alert_cmd" "HTTP error alert rule creation"
    else
        log "INFO" "[DRY-RUN] Would create response time and HTTP error alert rules"
    fi
}

configure_email_notifications() {
    log "INFO" "Configuring email notifications for alerts"
    
    # Create action group
    local action_group_cmd="az monitor action-group create \
        --name 'WebAppAlerts-$RANDOM_SUFFIX' \
        --resource-group '$RESOURCE_GROUP' \
        --short-name 'WebAlert' \
        --email-receivers name='Admin' email='$EMAIL'"
    
    execute_command "$action_group_cmd" "Email notification action group creation"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Get action group ID
        ACTION_GROUP_ID=$(az monitor action-group show \
            --name "WebAppAlerts-$RANDOM_SUFFIX" \
            --resource-group "$RESOURCE_GROUP" \
            --query "id" -o tsv)
        
        # Update alert rules to use action group
        local update_response_alert_cmd="az monitor metrics alert update \
            --name 'HighResponseTime-$APP_NAME' \
            --resource-group '$RESOURCE_GROUP' \
            --add-action '$ACTION_GROUP_ID'"
        
        execute_command "$update_response_alert_cmd" "Response time alert notification setup"
        
        local update_error_alert_cmd="az monitor metrics alert update \
            --name 'HTTP5xxErrors-$APP_NAME' \
            --resource-group '$RESOURCE_GROUP' \
            --add-action '$ACTION_GROUP_ID'"
        
        execute_command "$update_error_alert_cmd" "HTTP error alert notification setup"
    else
        log "INFO" "[DRY-RUN] Would configure email notifications for alert rules"
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_deployment() {
    log "INFO" "Validating deployment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY-RUN] Skipping validation"
        return 0
    fi
    
    # Check web application status
    local app_state=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query state -o tsv)
    if [[ "$app_state" == "Running" ]]; then
        log "INFO" "✅ Web application is running"
    else
        log "WARN" "⚠️ Web application state: $app_state"
    fi
    
    # Test web application response
    if command -v curl &> /dev/null && [[ -n "${APP_URL:-}" ]]; then
        log "INFO" "Testing web application response..."
        if curl -s -o /dev/null -w "%{http_code}" "https://$APP_URL" | grep -q "200"; then
            log "INFO" "✅ Web application responds with HTTP 200"
        else
            log "WARN" "⚠️ Web application may not be fully ready yet"
        fi
    fi
    
    # Check alert rule status
    local alert_count=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv)
    log "INFO" "✅ Created $alert_count alert rules"
    
    # Display Log Analytics workspace info
    log "INFO" "✅ Log Analytics workspace ready for log queries"
    
    log "INFO" "🎉 Deployment validation completed successfully!"
}

# ============================================================================
# Cleanup on Exit
# ============================================================================

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Deployment failed with exit code $exit_code"
        log "INFO" "Check the log file for details: $LOG_FILE"
        log "INFO" "To clean up partially created resources, run: ./destroy.sh --resource-group '$RESOURCE_GROUP'"
    fi
}

trap cleanup_on_exit EXIT

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--resource-group)
                CUSTOM_RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -n|--app-name)
                CUSTOM_APP_NAME="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set defaults and generate unique names
    LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    EMAIL="${EMAIL:-$DEFAULT_EMAIL}"
    RANDOM_SUFFIX=$(generate_unique_suffix)
    
    # Set resource names
    RESOURCE_GROUP="${CUSTOM_RESOURCE_GROUP:-rg-recipe-${RANDOM_SUFFIX}}"
    APP_NAME="${CUSTOM_APP_NAME:-webapp-${RANDOM_SUFFIX}}"
    APP_SERVICE_PLAN="plan-${RANDOM_SUFFIX}"
    LOG_WORKSPACE="logs-${RANDOM_SUFFIX}"
    
    # Display configuration
    log "INFO" "=== Azure Basic Web Monitoring Deployment ==="
    log "INFO" "Resource Group: $RESOURCE_GROUP"
    log "INFO" "Location: $LOCATION"
    log "INFO" "App Name: $APP_NAME"
    log "INFO" "Email: $EMAIL"
    log "INFO" "Dry Run: $DRY_RUN"
    log "INFO" "Verbose: $VERBOSE"
    log "INFO" "================================================"
    
    # Validate email format
    if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log "WARN" "Email format may be invalid: $EMAIL"
        log "INFO" "Please ensure you use a valid email address for alert notifications"
    fi
    
    # Execute deployment steps
    check_prerequisites
    create_resource_group
    create_app_service_plan
    create_web_application
    create_log_analytics_workspace
    configure_application_logging
    configure_diagnostic_settings
    create_alert_rules
    configure_email_notifications
    validate_deployment
    
    # Summary
    log "INFO" "=== Deployment Summary ==="
    log "INFO" "✅ Resource Group: $RESOURCE_GROUP"
    log "INFO" "✅ Web Application: $APP_NAME"
    if [[ -n "${APP_URL:-}" ]]; then
        log "INFO" "✅ Application URL: https://$APP_URL"
    fi
    log "INFO" "✅ Log Analytics Workspace: $LOG_WORKSPACE"
    log "INFO" "✅ Alert Rules: 2 configured"
    log "INFO" "✅ Email Notifications: $EMAIL"
    log "INFO" ""
    log "INFO" "🎉 Deployment completed successfully!"
    log "INFO" "Visit your web application and check Azure Monitor for metrics and logs."
    log "INFO" ""
    log "INFO" "To clean up resources, run: ./destroy.sh --resource-group '$RESOURCE_GROUP'"
    log "INFO" "Log file available at: $LOG_FILE"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi