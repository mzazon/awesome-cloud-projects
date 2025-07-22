#!/bin/bash

# Destroy script for Orchestrating Quantum-Enhanced Machine Learning Workflows
# This script removes all Azure resources created by the deploy.sh script
# including Azure Quantum workspace, Azure ML workspace, Batch account, and supporting infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
CONFIG_FILE="${SCRIPT_DIR}/deployment.conf"

# Logging functions
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$TIMESTAMP] ✅ $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo "[$TIMESTAMP] ⚠️  WARNING: $1" | tee -a "$LOG_FILE"
}

# Error handling for non-critical operations
continue_on_error() {
    log_warning "Operation failed but continuing cleanup: $1"
}

# Start cleanup
log "============================================"
log "Starting Azure Quantum-ML Workflow Cleanup"
log "============================================"

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Cannot proceed with cleanup."
    exit 1
fi

# Check if logged into Azure
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

log_success "Prerequisites check completed"

# Load configuration from deployment
if [[ -f "$CONFIG_FILE" ]]; then
    log "Loading configuration from $CONFIG_FILE..."
    source "$CONFIG_FILE"
    log_success "Configuration loaded"
else
    log_warning "Configuration file not found. Using environment variables or prompting for input."
    
    # Try to get from environment or prompt user
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        echo -n "Enter Resource Group name: "
        read -r RESOURCE_GROUP
    fi
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource Group name is required for cleanup"
        exit 1
    fi
    
    log "Using Resource Group: $RESOURCE_GROUP"
fi

# Verify resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_error "Resource group '$RESOURCE_GROUP' not found. It may have already been deleted."
    exit 1
fi

# Display what will be deleted
log "Resources to be deleted:"
log "  Resource Group: ${RESOURCE_GROUP:-Unknown}"
log "  Quantum Workspace: ${QUANTUM_WORKSPACE:-Will be deleted with RG}"
log "  ML Workspace: ${ML_WORKSPACE:-Will be deleted with RG}"
log "  Storage Account: ${STORAGE_ACCOUNT:-Will be deleted with RG}"
log "  Batch Account: ${BATCH_ACCOUNT:-Will be deleted with RG}"
log "  Key Vault: ${KEY_VAULT:-Will be deleted with RG}"
log ""

# Confirmation prompt
echo "⚠️  WARNING: This will permanently delete all resources in the resource group!"
echo "This action cannot be undone."
echo ""
echo -n "Are you sure you want to continue? (yes/no): "
read -r CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

log "User confirmed deletion. Proceeding with cleanup..."

# Step 1: Delete ML endpoints and deployments first (if any exist)
if [[ -n "${ML_WORKSPACE:-}" ]]; then
    log "Checking for ML endpoints to delete..."
    
    # List and delete any online endpoints
    ENDPOINTS=$(az ml online-endpoint list \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$ML_WORKSPACE" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$ENDPOINTS" ]]; then
        for endpoint in $ENDPOINTS; do
            log "Deleting ML endpoint: $endpoint..."
            az ml online-endpoint delete \
                --name "$endpoint" \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$ML_WORKSPACE" \
                --yes \
                --no-wait || continue_on_error "Failed to delete endpoint $endpoint"
        done
        
        log "Waiting for endpoint deletions to complete..."
        sleep 60
    else
        log "No ML endpoints found to delete"
    fi
fi

# Step 2: Delete ML compute resources
if [[ -n "${ML_WORKSPACE:-}" ]]; then
    log "Deleting ML compute resources..."
    
    # Delete compute cluster
    az ml compute delete \
        --name quantum-ml-cluster \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$ML_WORKSPACE" \
        --yes \
        --no-wait 2>/dev/null || continue_on_error "Failed to delete ML compute cluster"
    
    # Delete compute instance
    az ml compute delete \
        --name quantum-ml-compute \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$ML_WORKSPACE" \
        --yes \
        --no-wait 2>/dev/null || continue_on_error "Failed to delete ML compute instance"
    
    log_success "ML compute resource deletion initiated"
fi

# Step 3: Clean up quantum jobs (if any are running)
if [[ -n "${QUANTUM_WORKSPACE:-}" ]]; then
    log "Checking for running quantum jobs..."
    
    # List running jobs and cancel them
    RUNNING_JOBS=$(az quantum job list \
        --workspace-name "$QUANTUM_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?status=='Running'].id" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$RUNNING_JOBS" ]]; then
        for job_id in $RUNNING_JOBS; do
            log "Cancelling quantum job: $job_id..."
            az quantum job cancel \
                --job-id "$job_id" \
                --workspace-name "$QUANTUM_WORKSPACE" \
                --resource-group "$RESOURCE_GROUP" 2>/dev/null || continue_on_error "Failed to cancel job $job_id"
        done
        log_success "Quantum jobs cancelled"
    else
        log "No running quantum jobs found"
    fi
fi

# Step 4: Delete Batch pools and jobs
if [[ -n "${BATCH_ACCOUNT:-}" ]]; then
    log "Cleaning up Batch account resources..."
    
    # Set batch account context
    az batch account set \
        --name "$BATCH_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" 2>/dev/null || continue_on_error "Failed to set Batch account context"
    
    # Delete any batch pools
    POOLS=$(az batch pool list --query "[].id" -o tsv 2>/dev/null || echo "")
    if [[ -n "$POOLS" ]]; then
        for pool in $POOLS; do
            log "Deleting batch pool: $pool..."
            az batch pool delete --pool-id "$pool" --yes 2>/dev/null || continue_on_error "Failed to delete pool $pool"
        done
    fi
    
    # Delete any batch jobs
    JOBS=$(az batch job list --query "[].id" -o tsv 2>/dev/null || echo "")
    if [[ -n "$JOBS" ]]; then
        for job in $JOBS; do
            log "Deleting batch job: $job..."
            az batch job delete --job-id "$job" --yes 2>/dev/null || continue_on_error "Failed to delete job $job"
        done
    fi
    
    log_success "Batch resources cleaned up"
fi

# Step 5: Clear Key Vault secrets (soft delete protection)
if [[ -n "${KEY_VAULT:-}" ]]; then
    log "Clearing Key Vault secrets..."
    
    # List and delete secrets
    SECRETS=$(az keyvault secret list \
        --vault-name "$KEY_VAULT" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$SECRETS" ]]; then
        for secret in $SECRETS; do
            log "Deleting secret: $secret..."
            az keyvault secret delete \
                --vault-name "$KEY_VAULT" \
                --name "$secret" 2>/dev/null || continue_on_error "Failed to delete secret $secret"
        done
        
        # Purge deleted secrets (if soft-delete is enabled)
        log "Purging deleted secrets..."
        for secret in $SECRETS; do
            az keyvault secret purge \
                --vault-name "$KEY_VAULT" \
                --name "$secret" 2>/dev/null || continue_on_error "Failed to purge secret $secret"
        done
    fi
    
    log_success "Key Vault secrets cleared"
fi

# Step 6: Wait for compute resources to finish deleting
log "Waiting for compute resources to finish deletion..."
sleep 120

# Step 7: Delete the entire resource group
log "Deleting resource group and all remaining resources..."
log "This may take several minutes..."

az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait

log_success "Resource group deletion initiated: $RESOURCE_GROUP"

# Step 8: Clean up local files
log "Cleaning up local files..."

# Remove deployment configuration
if [[ -f "$CONFIG_FILE" ]]; then
    rm "$CONFIG_FILE"
    log_success "Removed deployment configuration file"
fi

# Remove quantum development directory structure
QUANTUM_DIR="${SCRIPT_DIR}/../quantum-ml-pipeline"
if [[ -d "$QUANTUM_DIR" ]]; then
    rm -rf "$QUANTUM_DIR"
    log_success "Removed quantum development directory structure"
fi

# Step 9: Verification (async check)
log "Setting up verification check..."
cat > "${SCRIPT_DIR}/verify_cleanup.sh" << EOF
#!/bin/bash
# Verification script to check if cleanup completed

echo "Checking if resource group $RESOURCE_GROUP still exists..."
if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    echo "⚠️  Resource group still exists. Deletion may still be in progress."
    echo "Check Azure Portal for current status."
else
    echo "✅ Resource group successfully deleted."
    rm -f "\$0"  # Remove this verification script
fi
EOF

chmod +x "${SCRIPT_DIR}/verify_cleanup.sh"

# Final summary
log "============================================"
log "CLEANUP COMPLETED"
log "============================================"
log ""
log "Actions taken:"
log "  ✅ ML endpoints and deployments deleted"
log "  ✅ ML compute resources deletion initiated"
log "  ✅ Quantum jobs cancelled"
log "  ✅ Batch resources cleaned up"
log "  ✅ Key Vault secrets purged"
log "  ✅ Resource group deletion initiated"
log "  ✅ Local configuration files removed"
log ""
log "Resource group: $RESOURCE_GROUP"
log "Status: Deletion in progress (async operation)"
log ""
log "Note: Complete resource deletion may take 5-15 minutes."
log "Run ./verify_cleanup.sh to check deletion status."
log ""
log "If any resources remain after 30 minutes, check Azure Portal"
log "and manually delete any remaining resources."

# Make the script executable (if not already)
chmod +x "$0"

log_success "Cleanup script completed at $TIMESTAMP"

echo ""
echo "🎯 Cleanup initiated successfully!"
echo "   Resource group '$RESOURCE_GROUP' is being deleted."
echo "   Run ./verify_cleanup.sh in a few minutes to verify completion."