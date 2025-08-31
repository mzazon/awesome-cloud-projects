#!/bin/bash

#===============================================================================
# Azure Basic Push Notifications with Notification Hubs - Deployment Script
#===============================================================================
# This script deploys the complete infrastructure for Azure Notification Hubs
# following the recipe "Basic Push Notifications with Notification Hubs"
#
# Prerequisites:
# - Azure CLI installed and authenticated
# - Contributor permissions on target subscription
# - notification-hub extension for Azure CLI
#===============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check the logs above for details."
    log_info "You may need to manually clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

#===============================================================================
# Configuration and Variables
#===============================================================================

# Default configuration (can be overridden by environment variables)
RESOURCE_GROUP_PREFIX="${RESOURCE_GROUP_PREFIX:-rg-notifications}"
LOCATION="${LOCATION:-eastus}"
NH_NAMESPACE_PREFIX="${NH_NAMESPACE_PREFIX:-nh-namespace}"
NH_NAME_PREFIX="${NH_NAME_PREFIX:-notification-hub}"
ENVIRONMENT="${ENVIRONMENT:-demo}"
DRY_RUN="${DRY_RUN:-false}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set derived variables
RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
NH_NAMESPACE="${NH_NAMESPACE_PREFIX}-${RANDOM_SUFFIX}"
NH_NAME="${NH_NAME_PREFIX}-${RANDOM_SUFFIX}"

#===============================================================================
# Prerequisites Check
#===============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    log_info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    
    # Check if notification-hub extension is available
    if ! az extension show --name notification-hub &> /dev/null; then
        log_info "Installing notification-hub extension for Azure CLI..."
        az extension add --name notification-hub --yes
        log_success "Notification Hub extension installed successfully"
    else
        log_info "Notification Hub extension is already installed"
    fi
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" --output tsv | grep -q "${LOCATION}"; then
        log_error "Invalid location: ${LOCATION}"
        log_info "Available locations: $(az account list-locations --query '[].name' --output tsv | tr '\n' ' ')"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

#===============================================================================
# Display Configuration
#===============================================================================

display_configuration() {
    log_info "Deployment Configuration:"
    echo "  Resource Group:     ${RESOURCE_GROUP}"
    echo "  Location:           ${LOCATION}"
    echo "  NH Namespace:       ${NH_NAMESPACE}"
    echo "  Notification Hub:   ${NH_NAME}"
    echo "  Environment:        ${ENVIRONMENT}"
    echo "  Random Suffix:      ${RANDOM_SUFFIX}"
    echo "  Subscription ID:    ${SUBSCRIPTION_ID}"
    echo ""
}

#===============================================================================
# Deployment Functions
#===============================================================================

deploy_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment="${ENVIRONMENT}" created-by=deploy-script \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

deploy_notification_hub_namespace() {
    log_info "Creating Notification Hub namespace: ${NH_NAMESPACE}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create NH namespace: ${NH_NAMESPACE}"
        return 0
    fi
    
    az notification-hub namespace create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${NH_NAMESPACE}" \
        --location "${LOCATION}" \
        --sku Free \
        --output none
    
    # Wait for namespace to be ready
    log_info "Waiting for namespace to be ready..."
    timeout=300  # 5 minutes
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        status=$(az notification-hub namespace show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${NH_NAMESPACE}" \
            --query provisioningState \
            --output tsv 2>/dev/null || echo "NotFound")
        
        if [[ "${status}" == "Succeeded" ]]; then
            break
        elif [[ "${status}" == "Failed" ]]; then
            log_error "Notification Hub namespace deployment failed"
            exit 1
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Waiting for namespace... (${elapsed}s/${timeout}s)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log_error "Timeout waiting for namespace to be ready"
        exit 1
    fi
    
    log_success "Notification Hub namespace created: ${NH_NAMESPACE}"
}

deploy_notification_hub() {
    log_info "Creating notification hub: ${NH_NAME}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create notification hub: ${NH_NAME}"
        return 0
    fi
    
    az notification-hub create \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${NH_NAMESPACE}" \
        --name "${NH_NAME}" \
        --location "${LOCATION}" \
        --output none
    
    # Wait for hub to be ready
    log_info "Waiting for notification hub to be ready..."
    timeout=180  # 3 minutes
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if az notification-hub show \
            --resource-group "${RESOURCE_GROUP}" \
            --namespace-name "${NH_NAMESPACE}" \
            --name "${NH_NAME}" \
            --output none &>/dev/null; then
            break
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        log_info "Waiting for notification hub... (${elapsed}s/${timeout}s)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log_error "Timeout waiting for notification hub to be ready"
        exit 1
    fi
    
    log_success "Notification hub created: ${NH_NAME}"
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would verify deployment"
        return 0
    fi
    
    # Verify resource group
    if ! az group show --name "${RESOURCE_GROUP}" --output none &>/dev/null; then
        log_error "Resource group verification failed"
        return 1
    fi
    
    # Verify namespace
    namespace_status=$(az notification-hub namespace show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${NH_NAMESPACE}" \
        --query provisioningState \
        --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "${namespace_status}" != "Succeeded" ]]; then
        log_error "Namespace verification failed. Status: ${namespace_status}"
        return 1
    fi
    
    # Verify notification hub
    if ! az notification-hub show \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${NH_NAMESPACE}" \
        --name "${NH_NAME}" \
        --output none &>/dev/null; then
        log_error "Notification hub verification failed"
        return 1
    fi
    
    # Get connection strings for output
    log_info "Retrieving connection strings..."
    
    LISTEN_CONNECTION=$(az notification-hub authorization-rule list-keys \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${NH_NAMESPACE}" \
        --notification-hub-name "${NH_NAME}" \
        --name DefaultListenSharedAccessSignature \
        --query primaryConnectionString \
        --output tsv 2>/dev/null || echo "")
    
    FULL_CONNECTION=$(az notification-hub authorization-rule list-keys \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${NH_NAMESPACE}" \
        --notification-hub-name "${NH_NAME}" \
        --name DefaultFullSharedAccessSignature \
        --query primaryConnectionString \
        --output tsv 2>/dev/null || echo "")
    
    # Send test notification
    log_info "Sending test notification..."
    if az notification-hub test-send \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${NH_NAMESPACE}" \
        --notification-hub-name "${NH_NAME}" \
        --notification-format template \
        --message "Hello from Azure Notification Hubs!" \
        --output none &>/dev/null; then
        log_success "Test notification sent successfully"
    else
        log_warning "Test notification failed, but infrastructure is deployed"
    fi
    
    log_success "Deployment verification completed"
}

display_outputs() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would display connection strings and outputs"
        return 0
    fi
    
    log_info "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT OUTPUTS ==="
    echo "Resource Group:           ${RESOURCE_GROUP}"
    echo "Location:                 ${LOCATION}"
    echo "Notification Hub Namespace: ${NH_NAMESPACE}"
    echo "Notification Hub:         ${NH_NAME}"
    echo ""
    echo "=== CONNECTION STRINGS ==="
    if [[ -n "${LISTEN_CONNECTION:-}" ]]; then
        echo "Listen Connection String: ${LISTEN_CONNECTION}"
    else
        echo "Listen Connection String: [Failed to retrieve]"
    fi
    echo ""
    if [[ -n "${FULL_CONNECTION:-}" ]]; then
        echo "Full Access Connection String: ${FULL_CONNECTION}"
    else
        echo "Full Access Connection String: [Failed to retrieve]"
    fi
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Configure platform-specific credentials (APNS, FCM, WNS)"
    echo "2. Integrate the listen connection string into your mobile applications"
    echo "3. Use the full access connection string in your back-end services"
    echo "4. Test notifications with real devices"
    echo ""
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    log_info "Starting Azure Notification Hubs deployment..."
    
    # Check if help is requested
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        echo "Azure Notification Hubs Deployment Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Environment Variables:"
        echo "  RESOURCE_GROUP_PREFIX  Prefix for resource group name (default: rg-notifications)"
        echo "  LOCATION               Azure region (default: eastus)"
        echo "  NH_NAMESPACE_PREFIX    Prefix for namespace name (default: nh-namespace)"
        echo "  NH_NAME_PREFIX         Prefix for hub name (default: notification-hub)"
        echo "  ENVIRONMENT            Environment tag (default: demo)"
        echo "  DRY_RUN                Set to 'true' for dry run (default: false)"
        echo ""
        echo "Examples:"
        echo "  $0                                    # Deploy with defaults"
        echo "  LOCATION=westus2 $0                  # Deploy to West US 2"
        echo "  DRY_RUN=true $0                      # Dry run mode"
        echo "  ENVIRONMENT=prod $0                  # Deploy for production"
        echo ""
        exit 0
    fi
    
    # Confirm deployment unless in non-interactive mode
    if [[ "${CI:-false}" != "true" ]] && [[ "${DRY_RUN}" != "true" ]]; then
        display_configuration
        read -p "Do you want to proceed with this deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    display_configuration
    deploy_resource_group
    deploy_notification_hub_namespace
    deploy_notification_hub
    verify_deployment
    display_outputs
    
    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"