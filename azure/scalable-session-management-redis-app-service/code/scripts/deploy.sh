#!/bin/bash

# =============================================================================
# Azure Distributed Session Management Deployment Script
# =============================================================================
# 
# This script deploys Azure Managed Redis and Azure App Service for 
# distributed session management with proper monitoring and security.
#
# Prerequisites:
# - Azure CLI installed and authenticated
# - Contributor access to Azure subscription
# - Bash shell environment
#
# Estimated deployment time: 15-20 minutes
# Estimated cost: ~$75-100/month
#
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-session-demo}"
LOCATION="${LOCATION:-eastus}"
REDIS_SKU="${REDIS_SKU:-M10}"
APP_SERVICE_SKU="${APP_SERVICE_SKU:-S1}"
WORKER_COUNT="${WORKER_COUNT:-2}"
DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# Utility Functions
# =============================================================================

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
    
    echo "[$timestamp][$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log "ERROR" "$1"
    save_deployment_state "FAILED"
    exit 1
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check subscription access
    local subscription_id
    subscription_id=$(az account show --query id --output tsv 2>/dev/null) || \
        error_exit "Unable to get subscription ID. Please check your Azure access."
    
    log "INFO" "Using Azure subscription: $subscription_id"
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for generating random suffixes."
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

generate_resource_names() {
    log "INFO" "Generating unique resource names..."
    
    # Generate random suffix for unique naming
    local random_suffix
    random_suffix=$(openssl rand -hex 3 2>/dev/null) || \
        error_exit "Failed to generate random suffix"
    
    # Export resource names for use in deployment
    export REDIS_NAME="redis-session-${random_suffix}"
    export APP_SERVICE_PLAN="plan-session-${random_suffix}"
    export WEB_APP_NAME="app-session-${random_suffix}"
    export VNET_NAME="vnet-session-${random_suffix}"
    export SUBNET_NAME="subnet-redis"
    export WORKSPACE_NAME="law-session-${random_suffix}"
    export ACTION_GROUP_NAME="SessionAlerts"
    
    log "INFO" "Resource names generated with suffix: $random_suffix"
    log "DEBUG" "Redis name: $REDIS_NAME"
    log "DEBUG" "App Service Plan: $APP_SERVICE_PLAN"
    log "DEBUG" "Web App name: $WEB_APP_NAME"
}

save_deployment_state() {
    local status="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$STATE_FILE" << EOF
DEPLOYMENT_STATUS=$status
DEPLOYMENT_TIMESTAMP=$timestamp
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
REDIS_NAME=${REDIS_NAME:-}
APP_SERVICE_PLAN=${APP_SERVICE_PLAN:-}
WEB_APP_NAME=${WEB_APP_NAME:-}
VNET_NAME=${VNET_NAME:-}
WORKSPACE_NAME=${WORKSPACE_NAME:-}
ACTION_GROUP_NAME=${ACTION_GROUP_NAME:-}
EOF
    
    log "INFO" "Deployment state saved: $status"
}

wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_wait="${3:-300}"  # Default 5 minutes
    local interval=30
    local waited=0
    
    log "INFO" "Waiting for $resource_type '$resource_name' to be ready..."
    
    while [ $waited -lt $max_wait ]; do
        local status
        case "$resource_type" in
            "redis")
                status=$(az redis show --name "$resource_name" --resource-group "$RESOURCE_GROUP" \
                    --query provisioningState --output tsv 2>/dev/null || echo "NotFound")
                ;;
            "webapp")
                status=$(az webapp show --name "$resource_name" --resource-group "$RESOURCE_GROUP" \
                    --query state --output tsv 2>/dev/null || echo "NotFound")
                ;;
            *)
                log "WARN" "Unknown resource type: $resource_type"
                return 1
                ;;
        esac
        
        if [[ "$status" == "Succeeded" ]] || [[ "$status" == "Running" ]]; then
            log "INFO" "$resource_type '$resource_name' is ready"
            return 0
        fi
        
        log "DEBUG" "$resource_type status: $status (waited ${waited}s)"
        sleep $interval
        waited=$((waited + interval))
    done
    
    error_exit "$resource_type '$resource_name' did not become ready within ${max_wait}s"
}

# =============================================================================
# Deployment Functions
# =============================================================================

create_resource_group() {
    log "INFO" "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create resource group $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log "INFO" "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=session-demo environment=demo \
        --output table || error_exit "Failed to create resource group"
    
    log "INFO" "Resource group created successfully"
}

create_virtual_network() {
    log "INFO" "Creating virtual network and subnet..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create VNet $VNET_NAME with subnet $SUBNET_NAME"
        return 0
    fi
    
    # Create virtual network
    az network vnet create \
        --name "$VNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --address-prefix 10.0.0.0/16 \
        --output table || error_exit "Failed to create virtual network"
    
    # Create subnet for Redis
    az network vnet subnet create \
        --name "$SUBNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --address-prefix 10.0.1.0/24 \
        --output table || error_exit "Failed to create subnet"
    
    log "INFO" "Virtual network and subnet created successfully"
}

deploy_redis_instance() {
    log "INFO" "Deploying Azure Managed Redis instance..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create Redis instance $REDIS_NAME with SKU $REDIS_SKU"
        return 0
    fi
    
    # Create Redis instance
    az redis create \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku-family M \
        --sku-capacity 10 \
        --sku-name "$REDIS_SKU" \
        --enable-non-ssl-port false \
        --minimum-tls-version 1.2 \
        --output table || error_exit "Failed to create Redis instance"
    
    # Wait for Redis to be ready
    wait_for_resource "redis" "$REDIS_NAME" 900  # 15 minutes max
    
    # Configure Redis optimization settings
    log "INFO" "Configuring Redis optimization settings..."
    
    az redis update \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --set redisConfiguration.maxmemory-policy=allkeys-lru \
        --set redisConfiguration.maxmemory-reserved=50 \
        --set redisConfiguration.maxfragmentationmemory-reserved=50 \
        --output table || log "WARN" "Failed to configure Redis optimization settings"
    
    # Set up maintenance schedule
    az redis patch-schedule create \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --schedule-entries '[{
            "dayOfWeek": "Sunday",
            "startHourUtc": 2,
            "maintenanceWindow": "PT5H"
        }]' \
        --output table || log "WARN" "Failed to create Redis patch schedule"
    
    log "INFO" "Redis instance deployed and configured successfully"
}

create_app_service() {
    log "INFO" "Creating App Service Plan and Web App..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create App Service Plan $APP_SERVICE_PLAN with $WORKER_COUNT workers"
        log "INFO" "[DRY RUN] Would create Web App $WEB_APP_NAME"
        return 0
    fi
    
    # Create App Service Plan
    az appservice plan create \
        --name "$APP_SERVICE_PLAN" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "$APP_SERVICE_SKU" \
        --number-of-workers "$WORKER_COUNT" \
        --output table || error_exit "Failed to create App Service Plan"
    
    # Create Web App
    az webapp create \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --plan "$APP_SERVICE_PLAN" \
        --runtime "DOTNET:8" \
        --output table || error_exit "Failed to create Web App"
    
    # Wait for Web App to be ready
    wait_for_resource "webapp" "$WEB_APP_NAME" 300  # 5 minutes max
    
    log "INFO" "App Service created successfully"
}

configure_app_service() {
    log "INFO" "Configuring App Service with Redis connection..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would configure Web App settings and Redis connection"
        return 0
    fi
    
    # Get Redis connection details
    local redis_host redis_key redis_connection
    redis_host=$(az redis show \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query hostName --output tsv) || error_exit "Failed to get Redis hostname"
    
    redis_key=$(az redis list-keys \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryKey --output tsv) || error_exit "Failed to get Redis key"
    
    redis_connection="${redis_host}:6380,password=${redis_key},ssl=True,abortConnect=False"
    
    # Configure Web App settings
    az webapp config appsettings set \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "RedisConnection=${redis_connection}" \
        "WEBSITE_NODE_DEFAULT_VERSION=~18" \
        "APPINSIGHTS_INSTRUMENTATIONKEY=placeholder" \
        --output table || error_exit "Failed to configure Web App settings"
    
    # Configure Web App for optimal performance
    az webapp config set \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --always-on true \
        --http20-enabled true \
        --output table || log "WARN" "Failed to configure Web App advanced settings"
    
    log "INFO" "App Service configured with Redis connection successfully"
}

setup_monitoring() {
    log "INFO" "Setting up Azure Monitor and alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create Log Analytics workspace and monitoring alerts"
        return 0
    fi
    
    # Get subscription ID
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --name "$WORKSPACE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output table || error_exit "Failed to create Log Analytics workspace"
    
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --name "$WORKSPACE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv) || error_exit "Failed to get workspace ID"
    
    # Create action group for alerts
    az monitor action-group create \
        --name "$ACTION_GROUP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --short-name "SessAlert" \
        --output table || error_exit "Failed to create action group"
    
    # Enable diagnostic settings for Redis
    az monitor diagnostic-settings create \
        --name "RedisSessionDiagnostics" \
        --resource "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cache/Redis/${REDIS_NAME}" \
        --workspace "$workspace_id" \
        --logs '[{"category": "ConnectedClientList", "enabled": true},
                 {"category": "AllMetrics", "enabled": true}]' \
        --output table || log "WARN" "Failed to configure Redis diagnostic settings"
    
    # Create metric alert for cache misses
    az monitor metrics alert create \
        --name "HighCacheMissRate" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cache/Redis/${REDIS_NAME}" \
        --condition "avg cachemisses > 100" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action "$ACTION_GROUP_NAME" \
        --description "Alert when cache miss rate is high" \
        --output table || log "WARN" "Failed to create cache miss alert"
    
    # Create alert for Redis connection errors
    az monitor metrics alert create \
        --name "RedisConnectionErrors" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cache/Redis/${REDIS_NAME}" \
        --condition "total errors > 10" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action "$ACTION_GROUP_NAME" \
        --description "Alert on Redis connection errors" \
        --output table || log "WARN" "Failed to create connection error alert"
    
    log "INFO" "Monitoring and alerting configured successfully"
}

validate_deployment() {
    log "INFO" "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would validate Redis status, App Service status, and monitoring configuration"
        return 0
    fi
    
    # Check Redis status
    local redis_status
    redis_status=$(az redis show \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$redis_status" != "Succeeded" ]]; then
        error_exit "Redis instance validation failed. Status: $redis_status"
    fi
    log "INFO" "✅ Redis instance validation passed"
    
    # Check App Service status
    local webapp_status
    webapp_status=$(az webapp show \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query state --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$webapp_status" != "Running" ]]; then
        error_exit "Web App validation failed. Status: $webapp_status"
    fi
    log "INFO" "✅ Web App validation passed"
    
    # Check metric alerts
    local alert_count
    alert_count=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query "length(@)" --output tsv 2>/dev/null || echo "0")
    
    if [[ "$alert_count" -lt 2 ]]; then
        log "WARN" "Expected 2 metric alerts, found $alert_count"
    else
        log "INFO" "✅ Monitoring alerts validation passed"
    fi
    
    log "INFO" "Deployment validation completed successfully"
}

display_deployment_info() {
    log "INFO" "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "This was a dry run. No resources were actually created."
        return 0
    fi
    
    echo ""
    echo "=========================================="
    echo "Deployment Summary"
    echo "=========================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Redis Instance: $REDIS_NAME"
    echo "App Service Plan: $APP_SERVICE_PLAN"
    echo "Web App: $WEB_APP_NAME"
    echo "Web App URL: https://${WEB_APP_NAME}.azurewebsites.net"
    echo ""
    echo "Monitoring:"
    echo "- Log Analytics Workspace: $WORKSPACE_NAME"
    echo "- Action Group: $ACTION_GROUP_NAME"
    echo "- Metric Alerts: 2 alerts configured"
    echo ""
    echo "Next Steps:"
    echo "1. Visit the Web App URL to test the application"
    echo "2. Monitor Redis performance in Azure Portal"
    echo "3. Review metric alerts in Azure Monitor"
    echo "4. Scale App Service instances to test session persistence"
    echo ""
    echo "Estimated Monthly Cost: ~$75-100 USD"
    echo "=========================================="
}

cleanup_on_error() {
    log "WARN" "Deployment failed. Cleaning up partially created resources..."
    
    # This will be handled by the destroy script if needed
    log "INFO" "Run ./destroy.sh to clean up any created resources"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    local start_time
    start_time=$(date +%s)
    
    echo "=========================================="
    echo "Azure Distributed Session Management"
    echo "Deployment Script"
    echo "=========================================="
    echo ""
    
    # Initialize logging
    : > "$LOG_FILE"  # Clear log file
    log "INFO" "Starting deployment process..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                log "INFO" "Dry run mode enabled"
                ;;
            --resource-group)
                RESOURCE_GROUP="$2"
                shift
                ;;
            --location)
                LOCATION="$2"
                shift
                ;;
            --redis-sku)
                REDIS_SKU="$2"
                shift
                ;;
            --app-service-sku)
                APP_SERVICE_SKU="$2"
                shift
                ;;
            --worker-count)
                WORKER_COUNT="$2"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run              Run in dry-run mode (no resources created)"
                echo "  --resource-group NAME  Resource group name (default: rg-session-demo)"
                echo "  --location LOCATION    Azure region (default: eastus)"
                echo "  --redis-sku SKU        Redis SKU (default: M10)"
                echo "  --app-service-sku SKU  App Service SKU (default: S1)"
                echo "  --worker-count COUNT   Number of App Service workers (default: 2)"
                echo "  --help, -h             Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log "WARN" "Unknown option: $1"
                shift
                ;;
        esac
        shift
    done
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    check_prerequisites
    generate_resource_names
    save_deployment_state "IN_PROGRESS"
    
    create_resource_group
    create_virtual_network
    deploy_redis_instance
    create_app_service
    configure_app_service
    setup_monitoring
    validate_deployment
    
    save_deployment_state "COMPLETED"
    display_deployment_info
    
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log "INFO" "Deployment completed in ${duration} seconds"
    
    return 0
}

# Execute main function with all arguments
main "$@"