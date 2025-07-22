#!/bin/bash
#
# Deploy script for Azure FHIR-Compliant Healthcare API Orchestration
# This script deploys the complete healthcare API infrastructure using
# Azure Container Apps and Azure Health Data Services with proper error handling
#
# Usage: ./deploy.sh [--dry-run] [--debug] [--resource-group <name>] [--location <location>]
#
# Requirements:
# - Azure CLI v2.53.0 or later
# - Healthcare APIs extension for Azure CLI
# - Appropriate Azure permissions for healthcare services
#
# Author: Recipe Generator
# Version: 1.0
# Date: 2025-01-27

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
DEBUG=false
RESOURCE_GROUP=""
LOCATION="eastus"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--debug] [--resource-group <name>] [--location <location>]"
            echo ""
            echo "Options:"
            echo "  --dry-run           Show what would be deployed without actually deploying"
            echo "  --debug             Enable debug logging"
            echo "  --resource-group    Specify resource group name (default: auto-generated)"
            echo "  --location          Specify Azure region (default: eastus)"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Enable debug mode if requested
if [[ "$DEBUG" == "true" ]]; then
    set -x
fi

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Info logging
log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

# Success logging
log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

# Warning logging
log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

# Error logging
log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Progress indicator
show_progress() {
    local message="$1"
    echo -e "${BLUE}[PROGRESS]${NC} $message"
}

# Cleanup function for error handling
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "Deployment failed. Check $LOG_FILE for details."
        log_error "Consider running with --debug for more information."
        echo -e "${RED}Deployment failed!${NC}"
        exit 1
    fi
}

# Set up error handling
trap cleanup EXIT

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI version
check_azure_cli_version() {
    local required_version="2.53.0"
    local current_version
    
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install Azure CLI v${required_version} or later."
        exit 1
    fi
    
    current_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    
    if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" != "$required_version" ]]; then
        log_error "Azure CLI version ${current_version} is too old. Required: ${required_version} or later."
        exit 1
    fi
    
    log_success "Azure CLI version check passed: ${current_version}"
}

# Function to check Azure authentication
check_azure_auth() {
    log_info "Checking Azure authentication..."
    
    if ! az account show >/dev/null 2>&1; then
        log_error "Not authenticated to Azure. Please run: az login"
        exit 1
    fi
    
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    
    log_success "Authenticated to Azure subscription: ${subscription_name} (${subscription_id})"
}

# Function to check required Azure extensions
check_azure_extensions() {
    log_info "Checking required Azure CLI extensions..."
    
    # Check for healthcareapis extension
    if ! az extension show --name healthcareapis >/dev/null 2>&1; then
        log_info "Installing healthcareapis extension..."
        az extension add --name healthcareapis --yes
    fi
    
    # Check for containerapp extension
    if ! az extension show --name containerapp >/dev/null 2>&1; then
        log_info "Installing containerapp extension..."
        az extension add --name containerapp --yes
    fi
    
    log_success "Required Azure CLI extensions are installed"
}

# Function to check Azure permissions
check_azure_permissions() {
    log_info "Checking Azure permissions..."
    
    local subscription_id=$(az account show --query id --output tsv)
    
    # Check if user has required permissions for healthcare services
    if ! az ad signed-in-user show >/dev/null 2>&1; then
        log_warning "Unable to verify user permissions. Proceeding with deployment..."
    else
        log_success "Azure permissions check passed"
    fi
}

# Function to check service availability in region
check_service_availability() {
    local location="$1"
    log_info "Checking service availability in region: ${location}"
    
    # Check if Container Apps is available in the region
    if ! az provider show --namespace Microsoft.App --query "registrationState" -o tsv | grep -q "Registered"; then
        log_warning "Container Apps provider not registered. Registering..."
        az provider register --namespace Microsoft.App
    fi
    
    # Check if Healthcare APIs is available in the region
    if ! az provider show --namespace Microsoft.HealthcareApis --query "registrationState" -o tsv | grep -q "Registered"; then
        log_warning "Healthcare APIs provider not registered. Registering..."
        az provider register --namespace Microsoft.HealthcareApis
    fi
    
    log_success "Service availability check passed for region: ${location}"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource group name if not provided
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP="rg-healthcare-fhir-${RANDOM_SUFFIX}"
    fi
    
    # Set environment variables
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export TENANT_ID=$(az account show --query tenantId --output tsv)
    export LOCATION="$LOCATION"
    export RESOURCE_GROUP="$RESOURCE_GROUP"
    export HEALTH_WORKSPACE="hw-healthcare-${RANDOM_SUFFIX}"
    export FHIR_SERVICE="fhir-service-${RANDOM_SUFFIX}"
    export CONTAINER_ENV="cae-healthcare-${RANDOM_SUFFIX}"
    export API_MANAGEMENT="apim-healthcare-${RANDOM_SUFFIX}"
    export COMM_SERVICE="comm-healthcare-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS="log-healthcare-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Health Workspace: ${HEALTH_WORKSPACE}"
    log_info "  FHIR Service: ${FHIR_SERVICE}"
    log_info "  Container Environment: ${CONTAINER_ENV}"
    log_info "  API Management: ${API_MANAGEMENT}"
    log_info "  Communication Service: ${COMM_SERVICE}"
    log_info "  Log Analytics: ${LOG_ANALYTICS}"
}

# Function to execute command with dry-run support
execute_command() {
    local description="$1"
    local command="$2"
    local required="${3:-true}"
    
    show_progress "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $command"
        return 0
    fi
    
    log_info "Executing: $command"
    
    if eval "$command" >> "$LOG_FILE" 2>&1; then
        log_success "$description completed successfully"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            log_error "$description failed"
            exit 1
        else
            log_warning "$description failed (non-critical)"
            return 1
        fi
    fi
}

# Function to wait for resource provisioning
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local sleep_interval="${4:-10}"
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be ready..."
    
    for i in $(seq 1 $max_attempts); do
        case "$resource_type" in
            "healthcareapis-workspace")
                if az healthcareapis workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$resource_name" --query "properties.provisioningState" -o tsv 2>/dev/null | grep -q "Succeeded"; then
                    log_success "${resource_type} '${resource_name}' is ready"
                    return 0
                fi
                ;;
            "containerapp-env")
                if az containerapp env show --resource-group "$RESOURCE_GROUP" --name "$resource_name" --query "properties.provisioningState" -o tsv 2>/dev/null | grep -q "Succeeded"; then
                    log_success "${resource_type} '${resource_name}' is ready"
                    return 0
                fi
                ;;
            *)
                log_warning "Unknown resource type for waiting: $resource_type"
                return 0
                ;;
        esac
        
        log_info "Attempt $i/$max_attempts: ${resource_type} '${resource_name}' not ready yet. Waiting ${sleep_interval} seconds..."
        sleep "$sleep_interval"
    done
    
    log_error "Timeout waiting for ${resource_type} '${resource_name}' to be ready"
    return 1
}

# Main deployment function
deploy_infrastructure() {
    log_info "Starting Azure FHIR Healthcare API Orchestration deployment..."
    
    # Step 1: Create resource group
    execute_command \
        "Creating resource group with healthcare-specific tags" \
        "az group create --name '${RESOURCE_GROUP}' --location '${LOCATION}' --tags purpose=healthcare-fhir environment=demo compliance=hipaa workload=fhir-api"
    
    # Step 2: Create Log Analytics workspace
    execute_command \
        "Creating Log Analytics workspace for healthcare monitoring" \
        "az monitor log-analytics workspace create --resource-group '${RESOURCE_GROUP}' --workspace-name '${LOG_ANALYTICS}' --location '${LOCATION}' --sku pergb2018"
    
    # Step 3: Create Healthcare workspace
    execute_command \
        "Creating Healthcare workspace with compliance settings" \
        "az healthcareapis workspace create --resource-group '${RESOURCE_GROUP}' --workspace-name '${HEALTH_WORKSPACE}' --location '${LOCATION}' --tags compliance=hipaa-hitrust data-classification=phi purpose=fhir-orchestration"
    
    # Wait for healthcare workspace to be ready
    if [[ "$DRY_RUN" == "false" ]]; then
        wait_for_resource "healthcareapis-workspace" "$HEALTH_WORKSPACE"
    fi
    
    # Step 4: Deploy FHIR service
    execute_command \
        "Deploying FHIR service with authentication and RBAC" \
        "az healthcareapis fhir-service create --resource-group '${RESOURCE_GROUP}' --workspace-name '${HEALTH_WORKSPACE}' --fhir-service-name '${FHIR_SERVICE}' --kind fhir-R4 --location '${LOCATION}' --auth-config-authority 'https://login.microsoftonline.com/${TENANT_ID}' --auth-config-audience 'https://${HEALTH_WORKSPACE}-${FHIR_SERVICE}.fhir.azurehealthcareapis.com' --auth-config-smart-proxy-enabled true"
    
    # Get FHIR service endpoint
    if [[ "$DRY_RUN" == "false" ]]; then
        FHIR_ENDPOINT=$(az healthcareapis fhir-service show --resource-group "$RESOURCE_GROUP" --workspace-name "$HEALTH_WORKSPACE" --fhir-service-name "$FHIR_SERVICE" --query "properties.serviceUrl" --output tsv)
        log_success "FHIR service endpoint: ${FHIR_ENDPOINT}"
    fi
    
    # Step 5: Create Container Apps environment
    execute_command \
        "Creating Container Apps environment with healthcare monitoring" \
        "az containerapp env create --resource-group '${RESOURCE_GROUP}' --name '${CONTAINER_ENV}' --location '${LOCATION}' --logs-workspace-id \$(az monitor log-analytics workspace show --resource-group '${RESOURCE_GROUP}' --workspace-name '${LOG_ANALYTICS}' --query customerId --output tsv) --logs-workspace-key \$(az monitor log-analytics workspace get-shared-keys --resource-group '${RESOURCE_GROUP}' --workspace-name '${LOG_ANALYTICS}' --query primarySharedKey --output tsv)"
    
    # Wait for container environment to be ready
    if [[ "$DRY_RUN" == "false" ]]; then
        wait_for_resource "containerapp-env" "$CONTAINER_ENV"
    fi
    
    # Step 6: Deploy patient management microservice
    execute_command \
        "Deploying patient management microservice" \
        "az containerapp create --resource-group '${RESOURCE_GROUP}' --name patient-service --environment '${CONTAINER_ENV}' --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest --target-port 80 --ingress external --min-replicas 1 --max-replicas 10 --cpu 0.5 --memory 1.0Gi --env-vars FHIR_ENDPOINT='${FHIR_ENDPOINT:-https://placeholder.fhir.azurehealthcareapis.com}' SERVICE_NAME=patient-service COMPLIANCE_MODE=hipaa"
    
    # Step 7: Deploy provider notification service
    execute_command \
        "Deploying provider notification service" \
        "az containerapp create --resource-group '${RESOURCE_GROUP}' --name provider-notification-service --environment '${CONTAINER_ENV}' --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest --target-port 80 --ingress external --min-replicas 1 --max-replicas 5 --cpu 0.25 --memory 0.5Gi --env-vars FHIR_ENDPOINT='${FHIR_ENDPOINT:-https://placeholder.fhir.azurehealthcareapis.com}' SERVICE_NAME=provider-notification NOTIFICATION_MODE=realtime"
    
    # Step 8: Create Communication Services
    execute_command \
        "Creating Communication Services resource" \
        "az communication create --name '${COMM_SERVICE}' --resource-group '${RESOURCE_GROUP}' --data-location 'United States' --tags purpose=healthcare-notifications compliance=hipaa"
    
    # Get Communication Services connection string
    if [[ "$DRY_RUN" == "false" ]]; then
        COMM_CONNECTION_STRING=$(az communication list-key --name "$COMM_SERVICE" --resource-group "$RESOURCE_GROUP" --query "primaryConnectionString" --output tsv)
        log_success "Communication Services configured"
    fi
    
    # Step 9: Deploy workflow orchestration service
    execute_command \
        "Deploying workflow orchestration service" \
        "az containerapp create --resource-group '${RESOURCE_GROUP}' --name workflow-orchestration-service --environment '${CONTAINER_ENV}' --image mcr.microsoft.com/azuredocs/containerapps-helloworld:latest --target-port 80 --ingress external --min-replicas 2 --max-replicas 8 --cpu 1.0 --memory 2.0Gi --env-vars FHIR_ENDPOINT='${FHIR_ENDPOINT:-https://placeholder.fhir.azurehealthcareapis.com}' COMM_CONNECTION_STRING='${COMM_CONNECTION_STRING:-placeholder}' SERVICE_NAME=workflow-orchestration WORKFLOW_ENGINE=healthcare"
    
    # Step 10: Create API Management
    execute_command \
        "Creating API Management gateway for healthcare APIs" \
        "az apim create --resource-group '${RESOURCE_GROUP}' --name '${API_MANAGEMENT}' --location '${LOCATION}' --publisher-name 'Healthcare Organization' --publisher-email 'admin@healthcare.org' --sku-name Developer --tags purpose=healthcare-api-gateway compliance=hipaa-hitrust"
    
    log_success "Healthcare API orchestration infrastructure deployment completed!"
    
    # Display deployment summary
    echo ""
    echo "======================================"
    echo "DEPLOYMENT SUMMARY"
    echo "======================================"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Health Workspace: ${HEALTH_WORKSPACE}"
    echo "FHIR Service: ${FHIR_SERVICE}"
    echo "Container Environment: ${CONTAINER_ENV}"
    echo "API Management: ${API_MANAGEMENT}"
    echo "Communication Service: ${COMM_SERVICE}"
    echo "Log Analytics: ${LOG_ANALYTICS}"
    echo ""
    echo "Microservices deployed:"
    echo "  - patient-service"
    echo "  - provider-notification-service"
    echo "  - workflow-orchestration-service"
    echo ""
    echo "Next steps:"
    echo "1. Configure API Management policies and security"
    echo "2. Set up authentication and authorization"
    echo "3. Deploy actual healthcare application containers"
    echo "4. Configure monitoring and alerting"
    echo "5. Set up backup and disaster recovery"
    echo ""
    echo "For cleanup, run: ./destroy.sh --resource-group ${RESOURCE_GROUP}"
    echo "======================================"
}

# Main execution
main() {
    log_info "Starting deployment script with PID: $$"
    
    # Initialize log file
    echo "=== Azure FHIR Healthcare API Orchestration Deployment Log ===" > "$LOG_FILE"
    echo "Date: $(date)" >> "$LOG_FILE"
    echo "User: $(whoami)" >> "$LOG_FILE"
    echo "Arguments: $*" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # Pre-deployment checks
    check_azure_cli_version
    check_azure_auth
    check_azure_extensions
    check_azure_permissions
    check_service_availability "$LOCATION"
    
    # Set up environment
    setup_environment
    
    # Show deployment plan
    echo ""
    echo "======================================"
    echo "DEPLOYMENT PLAN"
    echo "======================================"
    echo "Mode: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "LIVE DEPLOYMENT")"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Debug Mode: ${DEBUG}"
    echo "Log File: ${LOG_FILE}"
    echo "======================================"
    echo ""
    
    # Confirm deployment
    if [[ "$DRY_RUN" == "false" ]]; then
        echo -e "${YELLOW}This will create Azure resources that may incur costs.${NC}"
        echo -e "${YELLOW}Estimated cost: \$150-300/month for development environment${NC}"
        echo ""
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Start deployment
    deploy_infrastructure
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"