#!/bin/bash

# Azure Service Discovery with Service Connector and Tables - Cleanup Script
# This script removes all resources created by the deployment script
# It follows the reverse order of creation for safe cleanup

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

# Check prerequisites
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
    
    log_success "Prerequisites check passed"
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Try to load from .env file first
    if [ -f .env ]; then
        log_info "Loading variables from .env file..."
        source .env
    else
        log_warning ".env file not found. Using manual input or environment variables."
        
        # Prompt for required variables if not set
        if [ -z "${RESOURCE_GROUP:-}" ]; then
            echo -n "Enter Resource Group name: "
            read RESOURCE_GROUP
        fi
        
        if [ -z "${RESOURCE_GROUP:-}" ]; then
            log_error "Resource Group is required for cleanup"
            exit 1
        fi
    fi
    
    log_success "Environment variables loaded"
    log_info "Resource Group: ${RESOURCE_GROUP}"
}

# Confirm cleanup operation
confirm_cleanup() {
    log_warning "This operation will PERMANENTLY DELETE the following resources:"
    echo "=================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "- Storage Account: ${STORAGE_ACCOUNT:-unknown}"
    echo "- Function App: ${FUNCTION_APP:-unknown}"
    echo "- Web App: ${WEB_APP:-unknown}"
    echo "- SQL Server: ${SQL_SERVER:-unknown}"
    echo "- Redis Cache: ${REDIS_CACHE:-unknown}"
    echo "- All Service Connector connections"
    echo "- All contained data and configurations"
    echo "=================================="
    echo ""
    
    log_warning "This action cannot be undone!"
    echo -n "Are you sure you want to continue? (yes/no): "
    read confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed. Proceeding with resource deletion..."
}

# Check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists..."
    
    if ! az group exists --name "${RESOURCE_GROUP}" --output tsv | grep -q "true"; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist"
        log_info "Nothing to clean up"
        exit 0
    fi
    
    log_success "Resource group found: ${RESOURCE_GROUP}"
}

# Remove Service Connector connections
remove_service_connector_connections() {
    log_info "Removing Service Connector connections..."
    
    # Function to safely remove connections
    remove_connections() {
        local resource_type=$1
        local resource_name=$2
        
        if [ -n "${resource_name:-}" ]; then
            log_info "Removing connections for ${resource_type}: ${resource_name}"
            
            # List and delete connections
            local connections=$(az ${resource_type} connection list \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${resource_name}" \
                --query "[].id" --output tsv 2>/dev/null || echo "")
            
            if [ -n "$connections" ]; then
                echo "$connections" | while read -r connection_id; do
                    if [ -n "$connection_id" ]; then
                        log_info "Removing connection: $connection_id"
                        az resource delete --ids "$connection_id" --output none 2>/dev/null || true
                    fi
                done
                log_success "Connections removed for ${resource_name}"
            else
                log_info "No connections found for ${resource_name}"
            fi
        fi
    }
    
    # Remove webapp connections
    remove_connections "webapp" "${WEB_APP:-}"
    
    # Remove function app connections
    remove_connections "functionapp" "${FUNCTION_APP:-}"
    
    log_success "Service Connector connections cleanup completed"
}

# Remove individual resources (fallback method)
remove_individual_resources() {
    log_info "Attempting to remove individual resources..."
    
    # Function to safely delete resource
    delete_resource() {
        local resource_type=$1
        local resource_name=$2
        local additional_params=${3:-}
        
        if [ -n "${resource_name:-}" ]; then
            log_info "Deleting ${resource_type}: ${resource_name}"
            
            case $resource_type in
                "webapp")
                    az webapp delete \
                        --name "${resource_name}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --output none 2>/dev/null || log_warning "Failed to delete webapp: ${resource_name}"
                    ;;
                "functionapp")
                    az functionapp delete \
                        --name "${resource_name}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --output none 2>/dev/null || log_warning "Failed to delete function app: ${resource_name}"
                    ;;
                "sql-server")
                    az sql server delete \
                        --name "${resource_name}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --yes \
                        --output none 2>/dev/null || log_warning "Failed to delete SQL server: ${resource_name}"
                    ;;
                "redis")
                    az redis delete \
                        --name "${resource_name}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --yes \
                        --output none 2>/dev/null || log_warning "Failed to delete Redis cache: ${resource_name}"
                    ;;
                "storage-account")
                    az storage account delete \
                        --name "${resource_name}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --yes \
                        --output none 2>/dev/null || log_warning "Failed to delete storage account: ${resource_name}"
                    ;;
                "appservice-plan")
                    az appservice plan delete \
                        --name "${resource_name}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --yes \
                        --output none 2>/dev/null || log_warning "Failed to delete app service plan: ${resource_name}"
                    ;;
            esac
            
            log_success "Deleted ${resource_type}: ${resource_name}"
        fi
    }
    
    # Remove resources in reverse order of creation
    delete_resource "webapp" "${WEB_APP:-}"
    delete_resource "functionapp" "${FUNCTION_APP:-}"
    delete_resource "sql-server" "${SQL_SERVER:-}"
    delete_resource "redis" "${REDIS_CACHE:-}"
    delete_resource "storage-account" "${STORAGE_ACCOUNT:-}"
    delete_resource "appservice-plan" "${APP_SERVICE_PLAN:-}"
    
    log_success "Individual resources cleanup completed"
}

# Remove resource group and all resources
remove_resource_group() {
    log_info "Removing resource group and all contained resources..."
    
    # Delete resource group and all contained resources
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    log_info "This may take several minutes..."
    
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Deletion may take several minutes to complete"
    
    # Optional: Wait for deletion to complete
    echo -n "Wait for deletion to complete? (yes/no): "
    read wait_confirmation
    
    if [ "$wait_confirmation" = "yes" ]; then
        log_info "Waiting for resource group deletion to complete..."
        
        # Check deletion status
        local timeout=1800  # 30 minutes timeout
        local elapsed=0
        local check_interval=30
        
        while [ $elapsed -lt $timeout ]; do
            if ! az group exists --name "${RESOURCE_GROUP}" --output tsv | grep -q "true"; then
                log_success "Resource group successfully deleted: ${RESOURCE_GROUP}"
                break
            fi
            
            elapsed=$((elapsed + check_interval))
            local remaining=$((timeout - elapsed))
            log_info "Still deleting... (${remaining}s remaining)"
            sleep $check_interval
        done
        
        if [ $elapsed -ge $timeout ]; then
            log_warning "Timeout waiting for deletion. Check Azure portal for status."
        fi
    else
        log_info "Deletion is running in the background"
        log_info "You can check status in Azure portal or with: az group show --name ${RESOURCE_GROUP}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    if [ -f .env ]; then
        rm -f .env
        log_success "Removed .env file"
    fi
    
    # Remove any temporary function directories that might exist
    rm -rf /tmp/health-monitor-* /tmp/service-registrar-* /tmp/service-discovery-* 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Display cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "=================================="
    echo "Resource Group: ${RESOURCE_GROUP} (deletion initiated)"
    echo "Service Connector connections: Removed"
    echo "Local files: Cleaned up"
    echo "=================================="
    echo ""
    
    log_info "Cleanup operations completed"
    log_info "Monitor deletion progress in Azure portal if needed"
}

# Main cleanup function
main() {
    log_info "Starting Azure Service Discovery cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_cleanup
    check_resource_group
    
    # Try Service Connector cleanup first (more thorough)
    remove_service_connector_connections
    
    # Remove the entire resource group (recommended approach)
    remove_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Show summary
    show_cleanup_summary
    
    log_success "Cleanup completed successfully!"
    log_info "Total cleanup time: $SECONDS seconds"
}

# Handle script interruption
trap 'log_warning "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"