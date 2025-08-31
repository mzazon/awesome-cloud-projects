#!/bin/bash

#####################################################################
# Azure Basic File Storage with Blob Storage and Portal - Deploy Script
# Recipe: Basic File Storage with Blob Storage and Portal
# Version: 1.1
# Description: Deploy Azure Storage Account with Blob containers
#####################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Configuration with defaults
DEFAULT_LOCATION="eastus"
DEFAULT_SKU="Standard_LRS"
DEFAULT_ACCESS_TIER="Hot"

# Script usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Storage Account with Blob containers for file storage.

OPTIONS:
    -r, --resource-group    Resource group name (will be created if not exists)
    -s, --storage-account   Storage account name (must be globally unique)
    -l, --location          Azure region (default: ${DEFAULT_LOCATION})
    -k, --sku              Storage SKU (default: ${DEFAULT_SKU})
    -t, --access-tier      Access tier (default: ${DEFAULT_ACCESS_TIER})
    -d, --dry-run          Show what would be deployed without making changes
    -h, --help             Show this help message

EXAMPLES:
    $0 -r rg-storage-demo -s mystorageaccount123
    $0 --resource-group my-rg --storage-account sa123456 --location westus2
    $0 --dry-run -r test-rg -s teststorage456

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -s|--storage-account)
                STORAGE_ACCOUNT="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -k|--sku)
                SKU="$2"
                shift 2
                ;;
            -t|--access-tier)
                ACCESS_TIER="$2"
                shift 2
                ;;
            -d|--dry-run)
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
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        log_info "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription
    local subscription_name
    local subscription_id
    subscription_name=$(az account show --query name -o tsv)
    subscription_id=$(az account show --query id -o tsv)
    log_info "Using subscription: ${subscription_name} (${subscription_id})"
    
    # Validate required parameters
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "Resource group name is required. Use -r or --resource-group option."
        exit 1
    fi
    
    if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
        log_error "Storage account name is required. Use -s or --storage-account option."
        exit 1
    fi
    
    # Validate storage account name
    if [[ ! "${STORAGE_ACCOUNT}" =~ ^[a-z0-9]{3,24}$ ]]; then
        log_error "Storage account name must be 3-24 characters, lowercase letters and numbers only."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set default values for optional parameters
set_defaults() {
    LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    SKU="${SKU:-$DEFAULT_SKU}"
    ACCESS_TIER="${ACCESS_TIER:-$DEFAULT_ACCESS_TIER}"
    DRY_RUN="${DRY_RUN:-false}"
}

# Check if storage account name is available
check_storage_account_availability() {
    log_info "Checking storage account name availability..."
    
    local availability_result
    availability_result=$(az storage account check-name --name "${STORAGE_ACCOUNT}" --query nameAvailable -o tsv)
    
    if [[ "${availability_result}" != "true" ]]; then
        local reason
        reason=$(az storage account check-name --name "${STORAGE_ACCOUNT}" --query reason -o tsv)
        log_error "Storage account name '${STORAGE_ACCOUNT}' is not available. Reason: ${reason}"
        exit 1
    fi
    
    log_success "Storage account name '${STORAGE_ACCOUNT}' is available"
}

# Create or verify resource group
create_resource_group() {
    log_info "Creating/verifying resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group '${RESOURCE_GROUP}' in '${LOCATION}'"
        return
    fi
    
    # Check if resource group exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' already exists"
        local existing_location
        existing_location=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)
        if [[ "${existing_location}" != "${LOCATION}" ]]; then
            log_warning "Existing resource group is in '${existing_location}', but deployment targets '${LOCATION}'"
        fi
    else
        log_info "Creating resource group '${RESOURCE_GROUP}' in '${LOCATION}'"
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=demo environment=learning recipe=basic-file-storage-blob-portal \
            --output none
        
        log_success "Resource group '${RESOURCE_GROUP}' created successfully"
    fi
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create storage account '${STORAGE_ACCOUNT}' with SKU '${SKU}' and access tier '${ACCESS_TIER}'"
        return
    fi
    
    # Check if storage account already exists
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account '${STORAGE_ACCOUNT}' already exists"
        return
    fi
    
    log_info "Creating storage account with security best practices..."
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku "${SKU}" \
        --kind StorageV2 \
        --access-tier "${ACCESS_TIER}" \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --https-only true \
        --tags purpose=demo environment=learning recipe=basic-file-storage-blob-portal \
        --output none
    
    log_success "Storage account '${STORAGE_ACCOUNT}' created with security hardening"
}

# Configure RBAC permissions
configure_rbac() {
    log_info "Configuring RBAC permissions..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would assign Storage Blob Data Contributor role to current user"
        return
    fi
    
    # Get current user ID
    local current_user_id
    current_user_id=$(az ad signed-in-user show --query id -o tsv)
    
    # Get subscription ID
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    
    local scope="/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
    
    # Check if role assignment already exists
    local existing_assignment
    existing_assignment=$(az role assignment list \
        --assignee "${current_user_id}" \
        --role "Storage Blob Data Contributor" \
        --scope "${scope}" \
        --query length(@) -o tsv)
    
    if [[ "${existing_assignment}" -gt 0 ]]; then
        log_warning "RBAC role assignment already exists for current user"
    else
        log_info "Assigning Storage Blob Data Contributor role to current user..."
        az role assignment create \
            --role "Storage Blob Data Contributor" \
            --assignee "${current_user_id}" \
            --scope "${scope}" \
            --output none
        
        log_success "RBAC permissions configured successfully"
        log_warning "Role assignment may take 1-2 minutes to propagate"
    fi
}

# Create blob containers
create_containers() {
    log_info "Creating blob containers..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create containers: documents, images, backups"
        return
    fi
    
    # Wait for RBAC propagation
    log_info "Waiting 30 seconds for RBAC permissions to propagate..."
    sleep 30
    
    local containers=("documents" "images" "backups")
    
    for container in "${containers[@]}"; do
        log_info "Creating container: ${container}"
        
        # Check if container already exists
        if az storage container exists \
            --name "${container}" \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            --query exists -o tsv &> /dev/null; then
            
            local exists
            exists=$(az storage container exists \
                --name "${container}" \
                --account-name "${STORAGE_ACCOUNT}" \
                --auth-mode login \
                --query exists -o tsv)
            
            if [[ "${exists}" == "true" ]]; then
                log_warning "Container '${container}' already exists"
                continue
            fi
        fi
        
        # Create container with retry logic
        local max_retries=3
        local retry_count=0
        
        while [[ ${retry_count} -lt ${max_retries} ]]; do
            if az storage container create \
                --name "${container}" \
                --account-name "${STORAGE_ACCOUNT}" \
                --auth-mode login \
                --output none 2>/dev/null; then
                log_success "Container '${container}' created successfully"
                break
            else
                retry_count=$((retry_count + 1))
                if [[ ${retry_count} -lt ${max_retries} ]]; then
                    log_warning "Failed to create container '${container}', retrying in 10 seconds... (${retry_count}/${max_retries})"
                    sleep 10
                else
                    log_error "Failed to create container '${container}' after ${max_retries} attempts"
                    exit 1
                fi
            fi
        done
    done
    
    log_success "All containers created successfully"
}

# Upload sample files
upload_sample_files() {
    log_info "Creating and uploading sample files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create and upload sample files to documents container"
        return
    fi
    
    # Create temporary directory for sample files
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create sample files
    echo "This is a sample document for testing Azure Blob Storage capabilities." > "${temp_dir}/sample-document.txt"
    echo '{"app": "demo", "environment": "test", "version": "1.0", "created": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' > "${temp_dir}/config.json"
    
    # Upload files to documents container
    log_info "Uploading sample-document.txt..."
    az storage blob upload \
        --file "${temp_dir}/sample-document.txt" \
        --name "sample-document.txt" \
        --container-name "documents" \
        --account-name "${STORAGE_ACCOUNT}" \
        --auth-mode login \
        --output none
    
    log_info "Uploading config.json with hierarchical naming..."
    az storage blob upload \
        --file "${temp_dir}/config.json" \
        --name "settings/config.json" \
        --container-name "documents" \
        --account-name "${STORAGE_ACCOUNT}" \
        --auth-mode login \
        --output none
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
    
    log_success "Sample files uploaded successfully"
}

# Display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary:"
    echo "========================"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Location: ${LOCATION}"
    echo "SKU: ${SKU}"
    echo "Access Tier: ${ACCESS_TIER}"
    echo "Containers: documents, images, backups"
    echo "========================"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        # Get subscription ID for portal URL
        local subscription_id
        subscription_id=$(az account show --query id -o tsv)
        
        echo ""
        log_success "Deployment completed successfully!"
        echo ""
        echo "🌐 Access your storage account in the Azure Portal:"
        echo "https://portal.azure.com/#@/resource/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}/overview"
        echo ""
        echo "📁 Portal navigation instructions:"
        echo "1. Navigate to Storage accounts > ${STORAGE_ACCOUNT}"
        echo "2. Select 'Storage browser' from the left menu"
        echo "3. Choose 'Blob containers' to view:"
        echo "   - documents (contains uploaded sample files)"
        echo "   - images (ready for image uploads)"
        echo "   - backups (ready for backup files)"
        echo ""
        echo "💡 Next steps:"
        echo "- Upload files through the Azure Portal or Azure CLI"
        echo "- Test download functionality"
        echo "- Explore Azure Storage features like lifecycle management"
        echo ""
        echo "🗑️  To clean up resources, run: ./destroy.sh -r ${RESOURCE_GROUP}"
    else
        log_info "Dry run completed - no resources were created"
    fi
}

# Main execution function
main() {
    log_info "Starting Azure Basic File Storage deployment..."
    
    # Parse command line arguments
    parse_args "$@"
    
    # Set default values
    set_defaults
    
    # Check prerequisites
    check_prerequisites
    
    # Check storage account availability (skip in dry-run mode)
    if [[ "${DRY_RUN}" != "true" ]]; then
        check_storage_account_availability
    fi
    
    # Execute deployment steps
    create_resource_group
    create_storage_account
    configure_rbac
    create_containers
    upload_sample_files
    
    # Show deployment summary
    show_deployment_summary
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Execute main function with all arguments
main "$@"