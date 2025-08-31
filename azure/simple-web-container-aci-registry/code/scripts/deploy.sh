#!/bin/bash

# ==============================================================================
# Azure Container Instances Deployment Script
# Recipe: Simple Web Container with Azure Container Instances
# 
# This script deploys:
# - Azure Container Registry (ACR)
# - Custom nginx web container
# - Azure Container Instance (ACI) with public IP
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ==============================================================================
# CONFIGURATION AND VARIABLES
# ==============================================================================

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Default values (can be overridden by environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
LOCATION="${LOCATION:-eastus}"
CONTAINER_REGISTRY_NAME="${CONTAINER_REGISTRY_NAME:-}"
CONTAINER_INSTANCE_NAME="${CONTAINER_INSTANCE_NAME:-}"
IMAGE_NAME="${IMAGE_NAME:-simple-nginx}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
DRY_RUN="${DRY_RUN:-false}"

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Logging function
log() {
    echo "[${TIMESTAMP}] $*" | tee -a "${LOG_FILE}"
}

# Error logging function
log_error() {
    echo "[${TIMESTAMP}] ERROR: $*" | tee -a "${LOG_FILE}" >&2
}

# Success logging function
log_success() {
    echo "[${TIMESTAMP}] ✅ $*" | tee -a "${LOG_FILE}"
}

# Warning logging function
log_warning() {
    echo "[${TIMESTAMP}] ⚠️  $*" | tee -a "${LOG_FILE}"
}

# Progress indicator
show_progress() {
    local message="$1"
    echo -n "[${TIMESTAMP}] ${message}... " | tee -a "${LOG_FILE}"
}

complete_progress() {
    echo "Done" | tee -a "${LOG_FILE}"
}

# ==============================================================================
# PREREQUISITE FUNCTIONS
# ==============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        return 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it from: https://docs.docker.com/get-docker/"
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        return 1
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        return 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install openssl for unique name generation."
        return 1
    fi
    
    log_success "All prerequisites satisfied"
    return 0
}

# ==============================================================================
# CONFIGURATION FUNCTIONS
# ==============================================================================

generate_unique_names() {
    log "Generating unique resource names..."
    
    # Generate unique suffix using openssl
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    
    # Set default values if not provided
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        RESOURCE_GROUP="rg-simple-web-container-${random_suffix}"
    fi
    
    if [[ -z "${CONTAINER_REGISTRY_NAME}" ]]; then
        CONTAINER_REGISTRY_NAME="acrsimpleweb${random_suffix}"
    fi
    
    if [[ -z "${CONTAINER_INSTANCE_NAME}" ]]; then
        CONTAINER_INSTANCE_NAME="aci-nginx-${random_suffix}"
    fi
    
    log "Resource names generated:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Container Registry: ${CONTAINER_REGISTRY_NAME}"
    log "  Container Instance: ${CONTAINER_INSTANCE_NAME}"
    log "  Location: ${LOCATION}"
}

validate_configuration() {
    log "Validating configuration..."
    
    # Validate Azure location
    if ! az account list-locations --query "[?name=='${LOCATION}']" --output tsv | grep -q "${LOCATION}"; then
        log_error "Invalid Azure location: ${LOCATION}"
        log "Available locations: $(az account list-locations --query '[].name' --output tsv | tr '\n' ' ')"
        return 1
    fi
    
    # Validate container registry name (ACR naming requirements)
    if [[ ! "${CONTAINER_REGISTRY_NAME}" =~ ^[a-zA-Z0-9]{5,50}$ ]]; then
        log_error "Container registry name must be 5-50 alphanumeric characters: ${CONTAINER_REGISTRY_NAME}"
        return 1
    fi
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists. Will use existing group."
    fi
    
    log_success "Configuration validated"
    return 0
}

# ==============================================================================
# DEPLOYMENT FUNCTIONS
# ==============================================================================

create_resource_group() {
    show_progress "Creating resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create resource group: ${RESOURCE_GROUP}"
        complete_progress
        return 0
    fi
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
        complete_progress
        return 0
    fi
    
    if az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo created-by=deploy-script >> "${LOG_FILE}" 2>&1; then
        complete_progress
        log_success "Resource group created successfully"
    else
        log_error "Failed to create resource group"
        return 1
    fi
}

create_container_registry() {
    show_progress "Creating Azure Container Registry: ${CONTAINER_REGISTRY_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create container registry: ${CONTAINER_REGISTRY_NAME}"
        complete_progress
        return 0
    fi
    
    # Check if registry already exists
    if az acr show --name "${CONTAINER_REGISTRY_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Container registry ${CONTAINER_REGISTRY_NAME} already exists"
        complete_progress
        return 0
    fi
    
    if az acr create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --sku Basic \
        --admin-enabled true \
        --location "${LOCATION}" >> "${LOG_FILE}" 2>&1; then
        complete_progress
        log_success "Container registry created successfully"
    else
        log_error "Failed to create container registry"
        return 1
    fi
}

build_and_push_container() {
    show_progress "Building and pushing container image"
    
    local temp_dir="${SCRIPT_DIR}/temp_nginx_app"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would build and push container image"
        complete_progress
        return 0
    fi
    
    # Create temporary directory for container files
    mkdir -p "${temp_dir}"
    
    # Create HTML file
    cat > "${temp_dir}/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Azure Container Instances Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f0f8ff; }
        .container { max-width: 800px; margin: 0 auto; padding: 20px; }
        .header { background-color: #0078d4; color: white; padding: 20px; border-radius: 5px; }
        .content { background-color: white; padding: 20px; margin-top: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Azure Container Instances Demo</h1>
            <p>Simple web application running on serverless containers</p>
        </div>
        <div class="content">
            <h2>Deployment Information</h2>
            <p><strong>Service:</strong> Azure Container Instances</p>
            <p><strong>Registry:</strong> Azure Container Registry</p>
            <p><strong>Status:</strong> Running successfully!</p>
            <p>This containerized web application demonstrates serverless container deployment with automatic scaling and pay-per-second billing.</p>
        </div>
    </div>
</body>
</html>
EOF
    
    # Create Dockerfile
    cat > "${temp_dir}/Dockerfile" << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF
    
    # Get registry login server
    local registry_login_server
    registry_login_server=$(az acr show \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query loginServer \
        --output tsv)
    
    # Login to ACR
    if ! az acr login --name "${CONTAINER_REGISTRY_NAME}" >> "${LOG_FILE}" 2>&1; then
        log_error "Failed to login to container registry"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    # Build container image
    local full_image_name="${registry_login_server}/${IMAGE_NAME}:${IMAGE_TAG}"
    if ! docker build -t "${full_image_name}" "${temp_dir}" >> "${LOG_FILE}" 2>&1; then
        log_error "Failed to build container image"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    # Push container image
    if ! docker push "${full_image_name}" >> "${LOG_FILE}" 2>&1; then
        log_error "Failed to push container image"
        rm -rf "${temp_dir}"
        return 1
    fi
    
    # Clean up temporary directory
    rm -rf "${temp_dir}"
    
    complete_progress
    log_success "Container image built and pushed: ${full_image_name}"
}

deploy_container_instance() {
    show_progress "Deploying container instance: ${CONTAINER_INSTANCE_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would deploy container instance: ${CONTAINER_INSTANCE_NAME}"
        complete_progress
        return 0
    fi
    
    # Get registry credentials
    local registry_login_server registry_username registry_password
    registry_login_server=$(az acr show \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query loginServer \
        --output tsv)
    
    registry_username=$(az acr credential show \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --query username \
        --output tsv)
    
    registry_password=$(az acr credential show \
        --name "${CONTAINER_REGISTRY_NAME}" \
        --query passwords[0].value \
        --output tsv)
    
    # Deploy container instance
    local full_image_name="${registry_login_server}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    if az container create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CONTAINER_INSTANCE_NAME}" \
        --image "${full_image_name}" \
        --registry-login-server "${registry_login_server}" \
        --registry-username "${registry_username}" \
        --registry-password "${registry_password}" \
        --cpu 1 \
        --memory 1 \
        --ports 80 \
        --ip-address Public \
        --location "${LOCATION}" >> "${LOG_FILE}" 2>&1; then
        complete_progress
        log_success "Container instance deployed successfully"
    else
        log_error "Failed to deploy container instance"
        return 1
    fi
}

get_application_info() {
    show_progress "Retrieving application information"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would retrieve application information"
        complete_progress
        return 0
    fi
    
    # Wait for container to be ready
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local container_state
        container_state=$(az container show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${CONTAINER_INSTANCE_NAME}" \
            --query containers[0].instanceView.currentState.state \
            --output tsv 2>/dev/null || echo "Unknown")
        
        if [[ "${container_state}" == "Running" ]]; then
            break
        fi
        
        log "Waiting for container to start (attempt ${attempt}/${max_attempts})..."
        sleep 10
        ((attempt++))
    done
    
    # Get container information
    local container_ip container_state
    container_ip=$(az container show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CONTAINER_INSTANCE_NAME}" \
        --query ipAddress.ip \
        --output tsv)
    
    container_state=$(az container show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${CONTAINER_INSTANCE_NAME}" \
        --query containers[0].instanceView.currentState.state \
        --output tsv)
    
    complete_progress
    
    # Display deployment information
    echo ""
    echo "=================================================================="
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "=================================================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Container Registry: ${CONTAINER_REGISTRY_NAME}"
    echo "Container Instance: ${CONTAINER_INSTANCE_NAME}"
    echo "Container State: ${container_state}"
    echo ""
    echo "🌐 Web Application URL: http://${container_ip}"
    echo ""
    echo "📊 View container logs:"
    echo "  az container logs --resource-group ${RESOURCE_GROUP} --name ${CONTAINER_INSTANCE_NAME}"
    echo ""
    echo "📈 Monitor container status:"
    echo "  az container show --resource-group ${RESOURCE_GROUP} --name ${CONTAINER_INSTANCE_NAME}"
    echo ""
    echo "🧹 To clean up resources, run:"
    echo "  ./destroy.sh"
    echo "=================================================================="
    
    # Test connectivity
    if [[ -n "${container_ip}" ]]; then
        show_progress "Testing web application connectivity"
        if curl -s --max-time 10 "http://${container_ip}" > /dev/null; then
            complete_progress
            log_success "Web application is responding correctly"
        else
            log_warning "Web application may not be fully ready yet. Please wait a few moments and try accessing the URL manually."
        fi
    fi
}

# ==============================================================================
# CLEANUP FUNCTION
# ==============================================================================

cleanup_on_error() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Deployment failed with exit code: ${exit_code}"
        log "Check ${LOG_FILE} for detailed error information"
        log "To clean up any partially created resources, run: ./destroy.sh"
    fi
}

# ==============================================================================
# HELP FUNCTION
# ==============================================================================

show_help() {
    cat << EOF
Azure Container Instances Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without actually deploying
    -g, --resource-group   Specify resource group name (default: auto-generated)
    -l, --location         Specify Azure location (default: eastus)
    -r, --registry         Specify container registry name (default: auto-generated)
    -i, --instance         Specify container instance name (default: auto-generated)
    --image-name           Specify container image name (default: simple-nginx)
    --image-tag            Specify container image tag (default: v1)

ENVIRONMENT VARIABLES:
    RESOURCE_GROUP              Override resource group name
    LOCATION                    Override Azure location
    CONTAINER_REGISTRY_NAME     Override container registry name
    CONTAINER_INSTANCE_NAME     Override container instance name
    IMAGE_NAME                  Override container image name
    IMAGE_TAG                   Override container image tag
    DRY_RUN                     Set to 'true' for dry run mode

EXAMPLES:
    # Deploy with default settings
    $0

    # Deploy to specific resource group and location
    $0 --resource-group my-rg --location westus2

    # Dry run to see what would be deployed
    $0 --dry-run

    # Deploy with custom names
    $0 --registry myregistry123 --instance mycontainer

EOF
}

# ==============================================================================
# COMMAND LINE ARGUMENT PARSING
# ==============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -r|--registry)
                CONTAINER_REGISTRY_NAME="$2"
                shift 2
                ;;
            -i|--instance)
                CONTAINER_INSTANCE_NAME="$2"
                shift 2
                ;;
            --image-name)
                IMAGE_NAME="$2"
                shift 2
                ;;
            --image-tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                log "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    # Initialize log file
    echo "===== Azure Container Instances Deployment Log - ${TIMESTAMP} =====" > "${LOG_FILE}"
    
    # Set up error handling
    trap cleanup_on_error EXIT
    
    log "Starting Azure Container Instances deployment..."
    log "Script directory: ${SCRIPT_DIR}"
    log "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Display configuration
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "🔍 DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites || exit 1
    generate_unique_names
    validate_configuration || exit 1
    create_resource_group || exit 1
    create_container_registry || exit 1
    build_and_push_container || exit 1
    deploy_container_instance || exit 1
    get_application_info || exit 1
    
    # Clear error trap on successful completion
    trap - EXIT
    
    log_success "Deployment completed successfully!"
    log "Total deployment time: $(($(date +%s) - $(date -d "${TIMESTAMP}" +%s 2>/dev/null || echo 0))) seconds"
}

# Execute main function with all arguments
main "$@"