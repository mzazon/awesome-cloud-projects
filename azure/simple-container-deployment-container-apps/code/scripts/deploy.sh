#!/bin/bash

# Azure Container Apps Deployment Script
# This script deploys a simple container application using Azure Container Apps
# Based on the recipe: Simple Container App Deployment with Container Apps

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handler
error_handler() {
    local line_number="$1"
    log_error "Script failed at line ${line_number}. Check ${LOG_FILE} for details."
    log_error "You may need to run destroy.sh to clean up partial deployments."
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Usage function
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Deploy Azure Container Apps infrastructure and application.

OPTIONS:
    -r, --resource-group    Resource group name (optional, will generate if not provided)
    -l, --location         Azure location (default: eastus)
    -a, --app-name         Container app name (optional, will generate if not provided)
    -e, --environment      Container Apps environment name (optional, will generate)
    -h, --help             Show this help message
    -v, --verbose          Enable verbose logging
    --dry-run              Show what would be deployed without executing

EXAMPLES:
    ${SCRIPT_NAME}                                    # Deploy with default settings
    ${SCRIPT_NAME} -l westus2                        # Deploy in West US 2 region
    ${SCRIPT_NAME} --resource-group my-rg            # Use specific resource group
    ${SCRIPT_NAME} --dry-run                         # Preview deployment

EOF
}

# Default values
LOCATION="eastus"
VERBOSE=false
DRY_RUN=false
RESOURCE_GROUP=""
CONTAINER_APP_NAME=""
CONTAINERAPPS_ENVIRONMENT=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -a|--app-name)
            CONTAINER_APP_NAME="$2"
            shift 2
            ;;
        -e|--environment)
            CONTAINERAPPS_ENVIRONMENT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Installation guide: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.28.0)
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local min_version="2.28.0"
    
    if ! printf '%s\n%s\n' "$min_version" "$az_version" | sort -V -C; then
        log_error "Azure CLI version $az_version is below minimum required version $min_version"
        log_info "Please update Azure CLI: az upgrade"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required but not installed. Please install openssl."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Generate unique suffix for resource names
generate_suffix() {
    openssl rand -hex 3
}

# Setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix if not provided
    local random_suffix
    random_suffix=$(generate_suffix)
    
    # Set default resource names if not provided
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP="rg-containerapp-demo-${random_suffix}"
    fi
    
    if [[ -z "$CONTAINER_APP_NAME" ]]; then
        CONTAINER_APP_NAME="hello-app-${random_suffix}"
    fi
    
    if [[ -z "$CONTAINERAPPS_ENVIRONMENT" ]]; then
        CONTAINERAPPS_ENVIRONMENT="env-demo-${random_suffix}"
    fi
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Export variables for potential use by other processes
    export RESOURCE_GROUP
    export LOCATION
    export SUBSCRIPTION_ID
    export CONTAINERAPPS_ENVIRONMENT
    export CONTAINER_APP_NAME
    
    log_info "Environment configured:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Subscription ID: ${SUBSCRIPTION_ID}"
    log_info "  Container Apps Environment: ${CONTAINERAPPS_ENVIRONMENT}"
    log_info "  Container App Name: ${CONTAINER_APP_NAME}"
    
    # Store configuration for cleanup script
    cat > "${SCRIPT_DIR}/.deploy_config" << EOF
RESOURCE_GROUP="${RESOURCE_GROUP}"
LOCATION="${LOCATION}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
CONTAINERAPPS_ENVIRONMENT="${CONTAINERAPPS_ENVIRONMENT}"
CONTAINER_APP_NAME="${CONTAINER_APP_NAME}"
DEPLOYMENT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Environment setup completed"
}

# Check if resource group exists
check_resource_group() {
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group '$RESOURCE_GROUP' already exists"
        return 0
    else
        return 1
    fi
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    if ! check_resource_group; then
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo created-by=deploy-script
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Register Azure resource providers
register_providers() {
    log_info "Registering Azure resource providers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would register Microsoft.App and Microsoft.OperationalInsights providers"
        return 0
    fi
    
    # Register Container Apps provider
    log_info "Registering Microsoft.App provider..."
    az provider register --namespace Microsoft.App
    
    # Register Log Analytics provider for monitoring
    log_info "Registering Microsoft.OperationalInsights provider..."
    az provider register --namespace Microsoft.OperationalInsights
    
    # Wait for registration to complete
    log_info "Waiting for provider registration to complete..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local registration_state
        registration_state=$(az provider show --namespace Microsoft.App --query "registrationState" -o tsv)
        
        if [[ "$registration_state" == "Registered" ]]; then
            log_success "Microsoft.App provider registered successfully"
            break
        fi
        
        log_info "Waiting for registration... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_warning "Provider registration taking longer than expected, continuing with deployment"
    fi
    
    log_success "Resource providers registered"
}

# Install Container Apps CLI extension
install_containerapp_extension() {
    log_info "Installing Container Apps CLI extension..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install containerapp CLI extension"
        return 0
    fi
    
    # Install or upgrade the Container Apps extension
    az extension add --name containerapp --upgrade --yes
    
    # Verify installation
    if az containerapp --help &> /dev/null; then
        log_success "Container Apps CLI extension installed successfully"
    else
        log_error "Failed to install Container Apps CLI extension"
        exit 1
    fi
}

# Create Container Apps environment
create_environment() {
    log_info "Creating Container Apps environment: $CONTAINERAPPS_ENVIRONMENT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Container Apps environment: $CONTAINERAPPS_ENVIRONMENT"
        return 0
    fi
    
    # Check if environment already exists
    if az containerapp env show --name "$CONTAINERAPPS_ENVIRONMENT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Container Apps environment '$CONTAINERAPPS_ENVIRONMENT' already exists"
        return 0
    fi
    
    az containerapp env create \
        --name "$CONTAINERAPPS_ENVIRONMENT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=demo environment=learning created-by=deploy-script
    
    # Verify environment creation
    local provisioning_state
    provisioning_state=$(az containerapp env show \
        --name "$CONTAINERAPPS_ENVIRONMENT" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.provisioningState" -o tsv)
    
    if [[ "$provisioning_state" == "Succeeded" ]]; then
        log_success "Container Apps environment created: $CONTAINERAPPS_ENVIRONMENT"
    else
        log_error "Container Apps environment creation failed. State: $provisioning_state"
        exit 1
    fi
}

# Deploy container application
deploy_container_app() {
    log_info "Deploying container application: $CONTAINER_APP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy container app: $CONTAINER_APP_NAME"
        log_info "[DRY RUN] Image: mcr.microsoft.com/k8se/quickstart:latest"
        return 0
    fi
    
    # Check if container app already exists
    if az containerapp show --name "$CONTAINER_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Container app '$CONTAINER_APP_NAME' already exists"
        return 0
    fi
    
    # Deploy the container application
    az containerapp create \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINERAPPS_ENVIRONMENT" \
        --image mcr.microsoft.com/k8se/quickstart:latest \
        --target-port 80 \
        --ingress external \
        --min-replicas 0 \
        --max-replicas 5 \
        --cpu 0.25 \
        --memory 0.5Gi \
        --tags purpose=demo app=quickstart created-by=deploy-script
    
    # Get application URL
    local app_url
    app_url=$(az containerapp show \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.configuration.ingress.fqdn" -o tsv)
    
    log_success "Container app deployed successfully"
    log_success "Application URL: https://${app_url}"
    
    # Store URL for reference
    echo "APP_URL=https://${app_url}" >> "${SCRIPT_DIR}/.deploy_config"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Check container app status
    local provisioning_state
    provisioning_state=$(az containerapp show \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.provisioningState" -o tsv)
    
    if [[ "$provisioning_state" != "Succeeded" ]]; then
        log_error "Container app deployment failed. State: $provisioning_state"
        exit 1
    fi
    
    # Test application endpoint
    local app_url
    app_url=$(az containerapp show \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.configuration.ingress.fqdn" -o tsv)
    
    if [[ -n "$app_url" ]]; then
        log_info "Testing application endpoint: https://${app_url}"
        
        # Wait a moment for the application to be ready
        sleep 30
        
        # Test with curl (with timeout and retries)
        local max_retries=5
        local retry=1
        
        while [[ $retry -le $max_retries ]]; do
            if curl -f -s -I "https://${app_url}" --max-time 30 &> /dev/null; then
                log_success "Application is accessible at: https://${app_url}"
                break
            else
                log_info "Application not ready yet, retrying... (attempt $retry/$max_retries)"
                sleep 15
                ((retry++))
            fi
        done
        
        if [[ $retry -gt $max_retries ]]; then
            log_warning "Application may not be fully ready yet. Manual verification recommended."
            log_info "Test URL manually: https://${app_url}"
        fi
    fi
    
    log_success "Deployment validation completed"
}

# Display deployment summary
show_summary() {
    log_info "Deployment Summary"
    log_info "=================="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Container Apps Environment: $CONTAINERAPPS_ENVIRONMENT"
    log_info "Container App: $CONTAINER_APP_NAME"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        local app_url
        app_url=$(az containerapp show \
            --name "$CONTAINER_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || echo "Not available")
        
        log_info "Application URL: https://${app_url}"
        log_info ""
        log_info "Next Steps:"
        log_info "1. Test your application: https://${app_url}"
        log_info "2. Monitor with: az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow"
        log_info "3. Scale with: az containerapp update --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --min-replicas 0 --max-replicas 10"
        log_info "4. Clean up with: ./destroy.sh"
    else
        log_info "[DRY RUN] No resources were actually created"
    fi
    
    log_info ""
    log_info "Configuration saved to: ${SCRIPT_DIR}/.deploy_config"
    log_info "Deployment log: ${LOG_FILE}"
}

# Main execution
main() {
    log_info "Starting Azure Container Apps deployment"
    log_info "Script: $SCRIPT_NAME"
    log_info "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
    fi
    
    check_prerequisites
    setup_environment
    create_resource_group
    register_providers
    install_containerapp_extension
    create_environment
    deploy_container_app
    validate_deployment
    show_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function
main "$@"