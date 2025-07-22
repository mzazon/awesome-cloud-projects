#!/bin/bash

# =============================================================================
# Azure Front Door Premium + NetApp Files Cleanup Script
# Safely removes all resources created by the deployment script
# =============================================================================

set -e # Exit on any error
set -u # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install it first."
    exit 1
fi

success "Prerequisites check passed"

# =============================================================================
# RESOURCE GROUP DETECTION
# =============================================================================

log "Detecting resource groups to clean up..."

# Function to find resource groups matching the pattern
find_resource_groups() {
    az group list --query "[?starts_with(name, 'rg-content-delivery-')].name" --output tsv
}

# Get all matching resource groups
RESOURCE_GROUPS=$(find_resource_groups)

if [[ -z "${RESOURCE_GROUPS}" ]]; then
    warning "No resource groups found matching pattern 'rg-content-delivery-*'"
    echo "This script looks for resource groups created by the deployment script."
    echo "If you used a different resource group name, please specify it:"
    echo ""
    read -p "Enter resource group name (or press Enter to exit): " MANUAL_RG
    
    if [[ -z "${MANUAL_RG}" ]]; then
        log "Exiting cleanup script"
        exit 0
    fi
    
    # Check if the manually entered resource group exists
    if ! az group show --name "${MANUAL_RG}" &> /dev/null; then
        error "Resource group '${MANUAL_RG}' does not exist"
        exit 1
    fi
    
    RESOURCE_GROUPS="${MANUAL_RG}"
fi

# =============================================================================
# CONFIRMATION PROMPT
# =============================================================================

echo ""
echo "==============================================================================" 
echo "RESOURCES TO BE DELETED"
echo "=============================================================================="
echo ""

for RG in ${RESOURCE_GROUPS}; do
    echo "Resource Group: ${RG}"
    echo "Location: $(az group show --name "${RG}" --query location --output tsv 2>/dev/null || echo "Unknown")"
    echo ""
    
    # List key resources in each group
    log "Key resources in ${RG}:"
    
    # Front Door profiles
    FRONT_DOOR_PROFILES=$(az afd profile list --resource-group "${RG}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "${FRONT_DOOR_PROFILES}" ]]; then
        echo "  Front Door Profiles: ${FRONT_DOOR_PROFILES}"
    fi
    
    # NetApp Files accounts
    ANF_ACCOUNTS=$(az netappfiles account list --resource-group "${RG}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "${ANF_ACCOUNTS}" ]]; then
        echo "  NetApp Files Accounts: ${ANF_ACCOUNTS}"
    fi
    
    # Virtual networks
    VNETS=$(az network vnet list --resource-group "${RG}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "${VNETS}" ]]; then
        echo "  Virtual Networks: ${VNETS}"
    fi
    
    # WAF policies
    WAF_POLICIES=$(az network front-door waf-policy list --resource-group "${RG}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "${WAF_POLICIES}" ]]; then
        echo "  WAF Policies: ${WAF_POLICIES}"
    fi
    
    # Log Analytics workspaces
    LOG_WORKSPACES=$(az monitor log-analytics workspace list --resource-group "${RG}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "${LOG_WORKSPACES}" ]]; then
        echo "  Log Analytics Workspaces: ${LOG_WORKSPACES}"
    fi
    
    echo ""
done

echo "=============================================================================="
echo "WARNING: This operation is irreversible!"
echo "All resources in the above resource groups will be permanently deleted."
echo "=============================================================================="
echo ""

read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " CONFIRMATION

if [[ "${CONFIRMATION}" != "DELETE" ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

# =============================================================================
# CLEANUP PROCESS
# =============================================================================

log "Starting cleanup process..."

# Function to safely delete resources with retry logic
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local max_retries=3
    local retry_count=0
    
    while [[ ${retry_count} -lt ${max_retries} ]]; do
        if eval "${delete_command}"; then
            success "Deleted ${resource_type}"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ ${retry_count} -lt ${max_retries} ]]; then
                warning "Failed to delete ${resource_type}, retrying (${retry_count}/${max_retries})..."
                sleep 10
            else
                error "Failed to delete ${resource_type} after ${max_retries} attempts"
                return 1
            fi
        fi
    done
}

# Process each resource group
for RESOURCE_GROUP in ${RESOURCE_GROUPS}; do
    log "Processing resource group: ${RESOURCE_GROUP}"
    
    # =============================================================================
    # STEP 1: REMOVE FRONT DOOR RESOURCES
    # =============================================================================
    
    log "Removing Front Door resources..."
    
    # Get Front Door profiles
    FRONT_DOOR_PROFILES=$(az afd profile list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for PROFILE in ${FRONT_DOOR_PROFILES}; do
        if [[ -n "${PROFILE}" ]]; then
            safe_delete "Front Door profile ${PROFILE}" \
                "az afd profile delete --resource-group '${RESOURCE_GROUP}' --profile-name '${PROFILE}' --yes"
        fi
    done
    
    # =============================================================================
    # STEP 2: REMOVE WAF POLICIES
    # =============================================================================
    
    log "Removing WAF policies..."
    
    WAF_POLICIES=$(az network front-door waf-policy list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for WAF_POLICY in ${WAF_POLICIES}; do
        if [[ -n "${WAF_POLICY}" ]]; then
            safe_delete "WAF policy ${WAF_POLICY}" \
                "az network front-door waf-policy delete --resource-group '${RESOURCE_GROUP}' --name '${WAF_POLICY}' --yes"
        fi
    done
    
    # =============================================================================
    # STEP 3: REMOVE NETAPP FILES RESOURCES
    # =============================================================================
    
    log "Removing NetApp Files resources..."
    
    # Get NetApp Files accounts
    ANF_ACCOUNTS=$(az netappfiles account list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for ANF_ACCOUNT in ${ANF_ACCOUNTS}; do
        if [[ -n "${ANF_ACCOUNT}" ]]; then
            log "Processing NetApp Files account: ${ANF_ACCOUNT}"
            
            # Get capacity pools
            CAPACITY_POOLS=$(az netappfiles pool list --resource-group "${RESOURCE_GROUP}" --account-name "${ANF_ACCOUNT}" --query "[].name" --output tsv 2>/dev/null || echo "")
            
            for POOL in ${CAPACITY_POOLS}; do
                if [[ -n "${POOL}" ]]; then
                    # Get volumes in the pool
                    VOLUMES=$(az netappfiles volume list --resource-group "${RESOURCE_GROUP}" --account-name "${ANF_ACCOUNT}" --pool-name "${POOL}" --query "[].name" --output tsv 2>/dev/null || echo "")
                    
                    for VOLUME in ${VOLUMES}; do
                        if [[ -n "${VOLUME}" ]]; then
                            safe_delete "NetApp Files volume ${VOLUME}" \
                                "az netappfiles volume delete --resource-group '${RESOURCE_GROUP}' --account-name '${ANF_ACCOUNT}' --pool-name '${POOL}' --volume-name '${VOLUME}' --yes"
                        fi
                    done
                    
                    # Delete the capacity pool
                    safe_delete "NetApp Files capacity pool ${POOL}" \
                        "az netappfiles pool delete --resource-group '${RESOURCE_GROUP}' --account-name '${ANF_ACCOUNT}' --pool-name '${POOL}' --yes"
                fi
            done
            
            # Delete the NetApp Files account
            safe_delete "NetApp Files account ${ANF_ACCOUNT}" \
                "az netappfiles account delete --resource-group '${RESOURCE_GROUP}' --account-name '${ANF_ACCOUNT}' --yes"
        fi
    done
    
    # =============================================================================
    # STEP 4: REMOVE NETWORKING RESOURCES
    # =============================================================================
    
    log "Removing networking resources..."
    
    # Remove load balancers
    LOAD_BALANCERS=$(az network lb list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for LB in ${LOAD_BALANCERS}; do
        if [[ -n "${LB}" ]]; then
            safe_delete "Load balancer ${LB}" \
                "az network lb delete --resource-group '${RESOURCE_GROUP}' --name '${LB}'"
        fi
    done
    
    # Remove virtual networks (this will also remove subnets)
    VNETS=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for VNET in ${VNETS}; do
        if [[ -n "${VNET}" ]]; then
            safe_delete "Virtual network ${VNET}" \
                "az network vnet delete --resource-group '${RESOURCE_GROUP}' --name '${VNET}'"
        fi
    done
    
    # =============================================================================
    # STEP 5: REMOVE MONITORING RESOURCES
    # =============================================================================
    
    log "Removing monitoring resources..."
    
    # Remove Log Analytics workspaces
    LOG_WORKSPACES=$(az monitor log-analytics workspace list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for WORKSPACE in ${LOG_WORKSPACES}; do
        if [[ -n "${WORKSPACE}" ]]; then
            safe_delete "Log Analytics workspace ${WORKSPACE}" \
                "az monitor log-analytics workspace delete --resource-group '${RESOURCE_GROUP}' --workspace-name '${WORKSPACE}' --yes"
        fi
    done
    
    # =============================================================================
    # STEP 6: REMOVE RESOURCE GROUP
    # =============================================================================
    
    log "Removing resource group: ${RESOURCE_GROUP}"
    
    # Final resource group deletion
    safe_delete "Resource group ${RESOURCE_GROUP}" \
        "az group delete --name '${RESOURCE_GROUP}' --yes --no-wait"
    
    success "Cleanup completed for resource group: ${RESOURCE_GROUP}"
done

# =============================================================================
# CLEANUP VERIFICATION
# =============================================================================

log "Verifying cleanup..."

# Wait a moment for deletions to propagate
sleep 5

# Check if any of the resource groups still exist
REMAINING_GROUPS=""
for RG in ${RESOURCE_GROUPS}; do
    if az group show --name "${RG}" &> /dev/null; then
        REMAINING_GROUPS="${REMAINING_GROUPS} ${RG}"
    fi
done

if [[ -n "${REMAINING_GROUPS}" ]]; then
    warning "Some resource groups are still being deleted: ${REMAINING_GROUPS}"
    echo "This is normal for large deployments. Deletion will continue in the background."
    echo "You can monitor the progress using:"
    echo "  az group list --query \"[?starts_with(name, 'rg-content-delivery-')].{Name:name,State:properties.provisioningState}\""
else
    success "All resource groups have been successfully deleted"
fi

# =============================================================================
# CLEANUP SUMMARY
# =============================================================================

echo ""
echo "==============================================================================" 
echo "CLEANUP SUMMARY"
echo "=============================================================================="
echo ""
echo "Processed resource groups:"
for RG in ${RESOURCE_GROUPS}; do
    echo "  - ${RG}"
done
echo ""
echo "Resources removed:"
echo "  - Azure Front Door Premium profiles and endpoints"
echo "  - Web Application Firewall policies"
echo "  - Azure NetApp Files accounts, capacity pools, and volumes"
echo "  - Virtual networks and subnets"
echo "  - Load balancers and networking components"
echo "  - Log Analytics workspaces"
echo "  - Resource groups"
echo ""
echo "=============================================================================="
echo "CLEANUP COMPLETED"
echo "=============================================================================="
echo ""

if [[ -n "${REMAINING_GROUPS}" ]]; then
    echo "Note: Some resources may still be deleting in the background."
    echo "This is normal for complex deployments with dependencies."
    echo ""
    echo "To verify complete cleanup, run:"
    echo "  az group list --query \"[?starts_with(name, 'rg-content-delivery-')].name\""
    echo ""
else
    echo "All resources have been successfully removed."
    echo "No further action is required."
    echo ""
fi

success "Cleanup script completed!"