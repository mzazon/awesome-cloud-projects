#!/bin/bash

# Azure Container Security Scanning Deployment Script
# This script deploys Azure Container Registry with Microsoft Defender integration
# for comprehensive container security scanning and compliance enforcement

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCE_PREFIX="container-security"
LOCATION="eastus"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Warning function
warn() {
    log "${YELLOW}WARNING: ${1}${NC}"
}

# Success function
success() {
    log "${GREEN}SUCCESS: ${1}${NC}"
}

# Info function
info() {
    log "${BLUE}INFO: ${1}${NC}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: ${AZ_VERSION}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Please log in to Azure using 'az login'"
    fi
    
    # Check if Docker is installed (for image building)
    if ! command -v docker &> /dev/null; then
        warn "Docker is not installed. Image building will be skipped."
        SKIP_DOCKER=true
    else
        SKIP_DOCKER=false
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install it first."
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. Please install it first."
    fi
    
    success "Prerequisites check completed"
}

# Generate unique suffix
generate_suffix() {
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    info "Generated unique suffix: ${RANDOM_SUFFIX}"
}

# Set environment variables
set_environment() {
    info "Setting environment variables..."
    
    export RESOURCE_GROUP="rg-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export LOCATION="${LOCATION}"
    export ACR_NAME="acr${RESOURCE_PREFIX//[^a-zA-Z0-9]/}${RANDOM_SUFFIX}"
    export AKS_NAME="aks-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export WORKSPACE_NAME="law-${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    
    # Save variables to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" <<EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
ACR_NAME=${ACR_NAME}
AKS_NAME=${AKS_NAME}
WORKSPACE_NAME=${WORKSPACE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    info "Environment variables set and saved to .env file"
}

# Create resource group
create_resource_group() {
    info "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=security environment=demo deployment=automated \
        --output table
    
    success "Resource group created successfully"
}

# Create Log Analytics workspace
create_log_analytics_workspace() {
    info "Creating Log Analytics workspace: ${WORKSPACE_NAME}"
    
    WORKSPACE_ID=$(az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${WORKSPACE_NAME}" \
        --location "${LOCATION}" \
        --query id --output tsv)
    
    if [ -z "${WORKSPACE_ID}" ]; then
        error_exit "Failed to create Log Analytics workspace"
    fi
    
    # Save workspace ID for later use
    echo "WORKSPACE_ID=${WORKSPACE_ID}" >> "${SCRIPT_DIR}/.env"
    
    success "Log Analytics workspace created successfully"
}

# Create Azure Container Registry
create_acr() {
    info "Creating Azure Container Registry: ${ACR_NAME}"
    
    az acr create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${ACR_NAME}" \
        --sku Standard \
        --location "${LOCATION}" \
        --admin-enabled false \
        --output table
    
    # Enable content trust
    info "Enabling content trust for ACR..."
    az acr config content-trust update \
        --registry "${ACR_NAME}" \
        --status enabled
    
    # Get ACR resource ID
    ACR_ID=$(az acr show \
        --name "${ACR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    if [ -z "${ACR_ID}" ]; then
        error_exit "Failed to get ACR resource ID"
    fi
    
    # Save ACR ID for later use
    echo "ACR_ID=${ACR_ID}" >> "${SCRIPT_DIR}/.env"
    
    success "Azure Container Registry created with security features enabled"
}

# Enable Microsoft Defender for Containers
enable_defender() {
    info "Enabling Microsoft Defender for Containers..."
    
    # Enable Defender for Containers
    az security pricing create \
        --name Containers \
        --tier Standard \
        --output table
    
    # Enable Defender for Container Registry
    az security pricing create \
        --name ContainerRegistry \
        --tier Standard \
        --output table
    
    # Configure Defender settings
    az security setting create \
        --name MCAS \
        --enabled true \
        --output table
    
    success "Microsoft Defender for Containers enabled"
}

# Configure vulnerability assessment integration
configure_vulnerability_assessment() {
    info "Configuring vulnerability assessment integration..."
    
    # Allow trusted Microsoft services
    az acr update \
        --name "${ACR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --allow-trusted-services true \
        --output table
    
    # Create diagnostic settings
    az monitor diagnostic-settings create \
        --name acr-security-logs \
        --resource "${ACR_ID}" \
        --workspace "${WORKSPACE_ID}" \
        --logs '[{"category": "ContainerRegistryRepositoryEvents", "enabled": true},
                {"category": "ContainerRegistryLoginEvents", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --output table
    
    success "Vulnerability assessment integration configured"
}

# Create and assign Azure policies
create_policies() {
    info "Creating and assigning Azure policies..."
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    
    # Assign vulnerability resolution policy
    az policy assignment create \
        --name "require-vuln-resolution" \
        --display-name "Container images must have vulnerabilities resolved" \
        --policy "/providers/Microsoft.Authorization/policyDefinitions/090c7b07-b4ed-4561-ad20-e9075f3ccaff" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --params '{"effect": {"value": "AuditIfNotExists"}}' \
        --output table
    
    # Assign anonymous pull policy
    az policy assignment create \
        --name "disable-anonymous-pull" \
        --display-name "Disable anonymous pull on container registries" \
        --policy "/providers/Microsoft.Authorization/policyDefinitions/9f2dea28-e834-476c-99c5-3507b4728395" \
        --scope "${ACR_ID}" \
        --params '{"effect": {"value": "Deny"}}' \
        --output table
    
    success "Compliance policies configured and assigned"
}

# Build and push sample image
build_sample_image() {
    if [ "${SKIP_DOCKER}" = true ]; then
        warn "Skipping Docker image build (Docker not available)"
        return
    fi
    
    info "Building and pushing sample container image..."
    
    # Create temporary directory for build
    BUILD_DIR=$(mktemp -d)
    cd "${BUILD_DIR}"
    
    # Create sample Dockerfile
    cat > Dockerfile <<EOF
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y nginx
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF
    
    # Build and push image
    az acr build \
        --registry "${ACR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --image sample-app:v1 \
        --file Dockerfile . \
        --output table
    
    # Cleanup build directory
    cd - > /dev/null
    rm -rf "${BUILD_DIR}"
    
    success "Sample image pushed to ACR for scanning"
}

# Create service principal for DevOps
create_service_principal() {
    info "Creating service principal for Azure DevOps integration..."
    
    SP_NAME="sp-acr-devops-${RANDOM_SUFFIX}"
    SP_INFO=$(az ad sp create-for-rbac \
        --name "${SP_NAME}" \
        --role acrpush \
        --scopes "${ACR_ID}" \
        --output json)
    
    if [ -z "${SP_INFO}" ]; then
        error_exit "Failed to create service principal"
    fi
    
    # Extract and save credentials
    SP_APP_ID=$(echo "${SP_INFO}" | jq -r .appId)
    SP_PASSWORD=$(echo "${SP_INFO}" | jq -r .password)
    
    # Save service principal info
    cat >> "${SCRIPT_DIR}/.env" <<EOF
SP_NAME=${SP_NAME}
SP_APP_ID=${SP_APP_ID}
SP_PASSWORD=${SP_PASSWORD}
EOF
    
    # Create sample Azure Pipeline YAML
    cat > "${SCRIPT_DIR}/../azure-pipelines.yml" <<EOF
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

variables:
  acrName: '${ACR_NAME}'
  imageName: 'secure-app'

stages:
- stage: Build
  jobs:
  - job: BuildAndScan
    steps:
    - task: Docker@2
      inputs:
        containerRegistry: 'ACR-Connection'
        repository: '\$(imageName)'
        command: 'buildAndPush'
        Dockerfile: '**/Dockerfile'
        tags: '\$(Build.BuildId)'
    
    - task: AzureCLI@2
      displayName: 'Wait for vulnerability scan'
      inputs:
        azureSubscription: 'Azure-Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          echo "Waiting for vulnerability scan to complete..."
          sleep 60
EOF
    
    info "Service Principal App ID: ${SP_APP_ID}"
    success "DevOps integration configured"
}

# Set up security monitoring
setup_monitoring() {
    info "Setting up security monitoring dashboard..."
    
    # Create query pack for container security
    QUERY_PACK_NAME="container-security-queries-${RANDOM_SUFFIX}"
    
    # Create Log Analytics query for vulnerability tracking
    QUERY='ContainerRegistryRepositoryEvents | where OperationName == "PushImage" | join kind=leftouter (SecurityRecommendation | where RecommendationDisplayName contains "vulnerabilities") on $left.CorrelationId == $right.AssessedResourceId | project TimeGenerated, Repository, Tag, VulnerabilityCount, Severity | order by TimeGenerated desc'
    
    # Create alert for critical vulnerabilities
    az monitor metrics alert create \
        --name "critical-vulnerability-alert" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "${ACR_ID}" \
        --condition "total HighSeverityVulnerabilities > 0" \
        --description "Critical vulnerabilities detected in container images" \
        --severity 1 \
        --output table
    
    success "Security monitoring dashboard configured"
}

# Validation function
validate_deployment() {
    info "Validating deployment..."
    
    # Check Defender for Containers status
    DEFENDER_STATUS=$(az security pricing show \
        --name Containers \
        --query pricingTier -o tsv)
    
    if [ "${DEFENDER_STATUS}" != "Standard" ]; then
        error_exit "Defender for Containers is not in Standard tier"
    fi
    
    # Check ACR exists and is accessible
    ACR_STATUS=$(az acr show \
        --name "${ACR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query provisioningState -o tsv)
    
    if [ "${ACR_STATUS}" != "Succeeded" ]; then
        error_exit "ACR is not in succeeded state"
    fi
    
    # Check policy assignments
    POLICY_COUNT=$(az policy assignment list \
        --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}" \
        --query length(@))
    
    if [ "${POLICY_COUNT}" -eq 0 ]; then
        warn "No policy assignments found"
    fi
    
    success "Deployment validation completed"
}

# Main deployment function
main() {
    log "Starting Azure Container Security Scanning deployment..."
    log "Deployment started at: $(date)"
    
    check_prerequisites
    generate_suffix
    set_environment
    create_resource_group
    create_log_analytics_workspace
    create_acr
    enable_defender
    configure_vulnerability_assessment
    create_policies
    build_sample_image
    create_service_principal
    setup_monitoring
    validate_deployment
    
    success "Deployment completed successfully!"
    
    # Display summary
    log ""
    log "=== DEPLOYMENT SUMMARY ==="
    log "Resource Group: ${RESOURCE_GROUP}"
    log "ACR Name: ${ACR_NAME}"
    log "Location: ${LOCATION}"
    log "Service Principal App ID: ${SP_APP_ID}"
    log "Environment file: ${SCRIPT_DIR}/.env"
    log "Log file: ${LOG_FILE}"
    log ""
    log "Next steps:"
    log "1. Configure your Azure DevOps service connection with the service principal"
    log "2. Push container images to test vulnerability scanning"
    log "3. Review security recommendations in Azure Security Center"
    log "4. Monitor compliance status in Azure Policy"
    log ""
    log "To clean up resources, run: ./destroy.sh"
}

# Handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error_exit "Deployment failed. Check ${LOG_FILE} for details."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"