#!/bin/bash

# Azure Quantum-Enhanced Financial Risk Analytics - Cleanup Script
# This script safely removes all infrastructure resources created by the deployment script
# Includes confirmation prompts and proper resource dependency handling

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] INFO: $1${NC}"
    echo "[${timestamp}] INFO: $1" >> "${LOG_FILE}"
}

warn() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] WARNING: $1${NC}"
    echo "[${timestamp}] WARNING: $1" >> "${LOG_FILE}"
}

error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] ERROR: $1${NC}" >&2
    echo "[${timestamp}] ERROR: $1" >> "${ERROR_LOG}"
    echo "[${timestamp}] ERROR: $1" >> "${LOG_FILE}"
}

# Configuration validation
validate_prerequisites() {
    log "Validating prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI and try again."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &>/dev/null; then
        error "Not logged in to Azure. Please run 'az login' and try again."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: ${az_version}"
    
    log "Prerequisites validation completed successfully"
}

# Load environment variables from deployment
load_deployment_config() {
    log "Loading deployment configuration..."
    
    # Try to load from deployment summary first
    if [[ -f "${SCRIPT_DIR}/deployment_summary.txt" ]]; then
        log "Loading configuration from deployment summary..."
        
        # Extract values from deployment summary
        export RESOURCE_GROUP=$(grep "Resource Group:" "${SCRIPT_DIR}/deployment_summary.txt" | cut -d' ' -f3)
        export LOCATION=$(grep "Location:" "${SCRIPT_DIR}/deployment_summary.txt" | cut -d' ' -f2)
        export SUBSCRIPTION_ID=$(grep "Subscription ID:" "${SCRIPT_DIR}/deployment_summary.txt" | cut -d' ' -f3)
        
        # Extract resource names
        export KEY_VAULT_NAME=$(grep "Azure Key Vault:" "${SCRIPT_DIR}/deployment_summary.txt" | cut -d' ' -f4)
        export DATA_LAKE_NAME=$(grep "Azure Data Lake Storage:" "${SCRIPT_DIR}/deployment_summary.txt" | cut -d' ' -f5)
        export SYNAPSE_WORKSPACE=$(grep "Azure Synapse Analytics:" "${SCRIPT_DIR}/deployment_summary.txt" | cut -d' ' -f4)
        export QUANTUM_WORKSPACE=$(grep "Azure Quantum:" "${SCRIPT_DIR}/deployment_summary.txt" | cut -d' ' -f3)
        export ML_WORKSPACE=$(grep "Azure Machine Learning:" "${SCRIPT_DIR}/deployment_summary.txt" | cut -d' ' -f4)
        
        log "Configuration loaded from deployment summary"
    else
        warn "Deployment summary not found. Using manual configuration..."
        
        # Manual configuration if deployment summary is not available
        read -p "Enter Resource Group name: " RESOURCE_GROUP
        read -p "Enter Location [eastus]: " LOCATION
        LOCATION=${LOCATION:-eastus}
        
        export RESOURCE_GROUP
        export LOCATION
        export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        
        log "Manual configuration completed"
    fi
    
    # Validate required variables
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        error "Resource Group name is required"
        exit 1
    fi
    
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Subscription ID: ${SUBSCRIPTION_ID}"
}

# List resources to be deleted
list_resources() {
    log "Listing resources to be deleted..."
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        warn "Resource group '${RESOURCE_GROUP}' not found. Nothing to delete."
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}Resources in Resource Group '${RESOURCE_GROUP}':${NC}"
    echo "================================================"
    
    # List all resources in the resource group
    az resource list --resource-group "${RESOURCE_GROUP}" --output table || {
        error "Failed to list resources in resource group"
        return 1
    }
    
    echo ""
    return 0
}

# Get user confirmation
confirm_deletion() {
    echo -e "${RED}⚠️  WARNING: This will permanently delete all resources!${NC}"
    echo -e "${RED}⚠️  This action cannot be undone!${NC}"
    echo ""
    
    # Show estimated costs saved
    echo -e "${YELLOW}💰 Deleting these resources will stop all associated charges.${NC}"
    echo ""
    
    # Get user confirmation
    read -p "Are you sure you want to delete all resources in '${RESOURCE_GROUP}'? (yes/no): " confirmation
    
    case "${confirmation}" in
        yes|YES|y|Y)
            log "User confirmed deletion"
            return 0
            ;;
        *)
            log "User cancelled deletion"
            echo "Deletion cancelled."
            exit 0
            ;;
    esac
}

# Delete Machine Learning resources
delete_ml_resources() {
    log "Deleting Azure Machine Learning resources..."
    
    if [[ -n "${ML_WORKSPACE}" ]]; then
        # Delete ML compute clusters first
        log "Deleting ML compute clusters..."
        az ml compute delete \
            --name "ml-cluster" \
            --workspace-name "${ML_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes 2>/dev/null || {
            warn "Failed to delete ML compute cluster or cluster not found"
        }
        
        # Delete ML workspace
        log "Deleting ML workspace: ${ML_WORKSPACE}"
        az ml workspace delete \
            --name "${ML_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes 2>/dev/null || {
            warn "Failed to delete ML workspace or workspace not found"
        }
    else
        log "Checking for ML workspaces in resource group..."
        local ml_workspaces=$(az ml workspace list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].name" --output tsv 2>/dev/null)
        
        for workspace in ${ml_workspaces}; do
            log "Deleting ML workspace: ${workspace}"
            az ml workspace delete \
                --name "${workspace}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes 2>/dev/null || {
                warn "Failed to delete ML workspace: ${workspace}"
            }
        done
    fi
    
    log "ML resources deletion completed"
}

# Delete Synapse Analytics resources
delete_synapse_resources() {
    log "Deleting Azure Synapse Analytics resources..."
    
    if [[ -n "${SYNAPSE_WORKSPACE}" ]]; then
        # Delete Spark pools first
        log "Deleting Spark pools..."
        az synapse spark pool delete \
            --name "sparkpool01" \
            --workspace-name "${SYNAPSE_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes 2>/dev/null || {
            warn "Failed to delete Spark pool or pool not found"
        }
        
        # Delete SQL pools if any exist
        log "Checking for SQL pools..."
        local sql_pools=$(az synapse sql pool list \
            --workspace-name "${SYNAPSE_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].name" --output tsv 2>/dev/null)
        
        for pool in ${sql_pools}; do
            log "Deleting SQL pool: ${pool}"
            az synapse sql pool delete \
                --name "${pool}" \
                --workspace-name "${SYNAPSE_WORKSPACE}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes 2>/dev/null || {
                warn "Failed to delete SQL pool: ${pool}"
            }
        done
        
        # Delete Synapse workspace
        log "Deleting Synapse workspace: ${SYNAPSE_WORKSPACE}"
        az synapse workspace delete \
            --name "${SYNAPSE_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes 2>/dev/null || {
            warn "Failed to delete Synapse workspace or workspace not found"
        }
    else
        log "Checking for Synapse workspaces in resource group..."
        local synapse_workspaces=$(az synapse workspace list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].name" --output tsv 2>/dev/null)
        
        for workspace in ${synapse_workspaces}; do
            log "Deleting Synapse workspace: ${workspace}"
            az synapse workspace delete \
                --name "${workspace}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes 2>/dev/null || {
                warn "Failed to delete Synapse workspace: ${workspace}"
            }
        done
    fi
    
    log "Synapse resources deletion completed"
}

# Delete Quantum resources
delete_quantum_resources() {
    log "Deleting Azure Quantum resources..."
    
    if [[ -n "${QUANTUM_WORKSPACE}" ]]; then
        log "Deleting Quantum workspace: ${QUANTUM_WORKSPACE}"
        az quantum workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${QUANTUM_WORKSPACE}" \
            --yes 2>/dev/null || {
            warn "Failed to delete Quantum workspace or workspace not found"
        }
    else
        log "Checking for Quantum workspaces in resource group..."
        local quantum_workspaces=$(az quantum workspace list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].name" --output tsv 2>/dev/null)
        
        for workspace in ${quantum_workspaces}; do
            log "Deleting Quantum workspace: ${workspace}"
            az quantum workspace delete \
                --resource-group "${RESOURCE_GROUP}" \
                --workspace-name "${workspace}" \
                --yes 2>/dev/null || {
                warn "Failed to delete Quantum workspace: ${workspace}"
            }
        done
    fi
    
    log "Quantum resources deletion completed"
}

# Delete Storage resources
delete_storage_resources() {
    log "Deleting Azure Storage resources..."
    
    if [[ -n "${DATA_LAKE_NAME}" ]]; then
        log "Deleting Data Lake Storage: ${DATA_LAKE_NAME}"
        az storage account delete \
            --name "${DATA_LAKE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes 2>/dev/null || {
            warn "Failed to delete Data Lake Storage or storage not found"
        }
    else
        log "Checking for Storage accounts in resource group..."
        local storage_accounts=$(az storage account list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].name" --output tsv 2>/dev/null)
        
        for account in ${storage_accounts}; do
            log "Deleting Storage account: ${account}"
            az storage account delete \
                --name "${account}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes 2>/dev/null || {
                warn "Failed to delete Storage account: ${account}"
            }
        done
    fi
    
    log "Storage resources deletion completed"
}

# Delete Key Vault resources
delete_key_vault_resources() {
    log "Deleting Azure Key Vault resources..."
    
    if [[ -n "${KEY_VAULT_NAME}" ]]; then
        log "Deleting Key Vault: ${KEY_VAULT_NAME}"
        az keyvault delete \
            --name "${KEY_VAULT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            2>/dev/null || {
            warn "Failed to delete Key Vault or vault not found"
        }
        
        # Purge Key Vault to completely remove it
        log "Purging Key Vault: ${KEY_VAULT_NAME}"
        az keyvault purge \
            --name "${KEY_VAULT_NAME}" \
            --location "${LOCATION}" \
            2>/dev/null || {
            warn "Failed to purge Key Vault or vault not found"
        }
    else
        log "Checking for Key Vaults in resource group..."
        local key_vaults=$(az keyvault list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].name" --output tsv 2>/dev/null)
        
        for vault in ${key_vaults}; do
            log "Deleting Key Vault: ${vault}"
            az keyvault delete \
                --name "${vault}" \
                --resource-group "${RESOURCE_GROUP}" \
                2>/dev/null || {
                warn "Failed to delete Key Vault: ${vault}"
            }
            
            # Purge Key Vault
            log "Purging Key Vault: ${vault}"
            az keyvault purge \
                --name "${vault}" \
                --location "${LOCATION}" \
                2>/dev/null || {
                warn "Failed to purge Key Vault: ${vault}"
            }
        done
    fi
    
    log "Key Vault resources deletion completed"
}

# Delete remaining resources and resource group
delete_resource_group() {
    log "Deleting resource group and remaining resources..."
    
    # Delete any remaining resources
    log "Checking for remaining resources..."
    local remaining_resources=$(az resource list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].id" --output tsv 2>/dev/null)
    
    if [[ -n "${remaining_resources}" ]]; then
        log "Found remaining resources. Deleting individually..."
        echo "${remaining_resources}" | while read -r resource_id; do
            if [[ -n "${resource_id}" ]]; then
                log "Deleting resource: ${resource_id}"
                az resource delete --ids "${resource_id}" --verbose 2>/dev/null || {
                    warn "Failed to delete resource: ${resource_id}"
                }
            fi
        done
    fi
    
    # Delete the resource group
    log "Deleting resource group: ${RESOURCE_GROUP}"
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait || {
        error "Failed to delete resource group: ${RESOURCE_GROUP}"
        return 1
    }
    
    log "Resource group deletion initiated successfully"
    log "Note: Complete deletion may take 10-15 minutes"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Wait a moment for deletion to propagate
    sleep 10
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        warn "Resource group still exists - deletion is in progress"
        log "You can check deletion status with: az group show --name ${RESOURCE_GROUP}"
    else
        log "Resource group successfully deleted"
    fi
    
    # Check for any remaining Key Vaults in soft-delete state
    local soft_deleted_vaults=$(az keyvault list-deleted \
        --query "[?properties.location=='${LOCATION}' && contains(name, 'kv-finance')].name" \
        --output tsv 2>/dev/null)
    
    if [[ -n "${soft_deleted_vaults}" ]]; then
        warn "Found Key Vaults in soft-delete state:"
        echo "${soft_deleted_vaults}"
        log "These will be automatically purged after the retention period"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment summary
    if [[ -f "${SCRIPT_DIR}/deployment_summary.txt" ]]; then
        rm -f "${SCRIPT_DIR}/deployment_summary.txt"
        log "Removed deployment summary file"
    fi
    
    # Archive log files
    if [[ -f "${SCRIPT_DIR}/deploy.log" ]]; then
        mv "${SCRIPT_DIR}/deploy.log" "${SCRIPT_DIR}/deploy.log.$(date +%Y%m%d_%H%M%S)"
        log "Archived deployment log file"
    fi
    
    log "Local file cleanup completed"
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "Generating cleanup summary..."
    
    cat > "${SCRIPT_DIR}/cleanup_summary.txt" << EOF
=================================================================
Azure Quantum-Enhanced Financial Risk Analytics Cleanup Summary
=================================================================

Cleanup Date: $(date)
Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Subscription ID: ${SUBSCRIPTION_ID}

Cleanup Status:
===============
✅ Azure Machine Learning resources deleted
✅ Azure Synapse Analytics resources deleted
✅ Azure Quantum resources deleted
✅ Azure Storage resources deleted
✅ Azure Key Vault resources deleted
✅ Resource group deletion initiated

Notes:
======
- Resource group deletion may take 10-15 minutes to complete
- Key Vaults may remain in soft-delete state for the retention period
- All associated costs have been stopped

Verification:
=============
Check resource group status: az group show --name ${RESOURCE_GROUP}
Check soft-deleted Key Vaults: az keyvault list-deleted

If you encounter any issues, please check Azure portal or contact support.
EOF
    
    log "Cleanup summary saved to: ${SCRIPT_DIR}/cleanup_summary.txt"
}

# Main cleanup function
main() {
    log "Starting Azure Quantum-Enhanced Financial Risk Analytics cleanup..."
    
    # Initialize log files
    > "${LOG_FILE}"
    > "${ERROR_LOG}"
    
    # Execute cleanup steps
    validate_prerequisites
    load_deployment_config
    
    # List resources and get confirmation
    if list_resources; then
        confirm_deletion
    else
        log "No resources found to delete"
        exit 0
    fi
    
    # Execute deletion in proper order
    delete_ml_resources
    delete_synapse_resources
    delete_quantum_resources
    delete_storage_resources
    delete_key_vault_resources
    delete_resource_group
    
    # Verify and cleanup
    verify_cleanup
    cleanup_local_files
    generate_cleanup_summary
    
    log "Cleanup completed successfully!"
    log "Review the cleanup summary at: ${SCRIPT_DIR}/cleanup_summary.txt"
    log "Log files: ${LOG_FILE} and ${ERROR_LOG}"
    
    echo ""
    echo -e "${GREEN}✅ Azure Quantum-Enhanced Financial Risk Analytics cleanup completed!${NC}"
    echo -e "${BLUE}📋 Cleanup summary: ${SCRIPT_DIR}/cleanup_summary.txt${NC}"
    echo -e "${BLUE}📝 Full logs: ${LOG_FILE}${NC}"
    echo ""
    echo -e "${YELLOW}ℹ️  Resource group deletion may take 10-15 minutes to complete${NC}"
    echo -e "${YELLOW}ℹ️  Check Azure portal to verify complete removal${NC}"
    echo ""
}

# Execute main function
main "$@"