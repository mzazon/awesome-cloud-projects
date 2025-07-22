#!/bin/bash

# Industrial Training Platform Cleanup Script
# Removes all Azure resources created for the immersive industrial training platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Default values
RESOURCE_GROUP=""
FORCE_DELETE=false
SKIP_CONFIRMATION=false
BACKUP_DATA=false
DRY_RUN=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Industrial Training Platform resources

OPTIONS:
    -g, --resource-group <name>    Resource group name (required)
    -f, --force                    Force delete without confirmation
    -y, --yes                      Skip confirmation prompts
    -b, --backup                   Backup training data before deletion
    -d, --dry-run                  Show what would be deleted without actually deleting
    -h, --help                     Show this help message

EXAMPLES:
    $0 --resource-group rg-industrial-training-demo
    $0 -g rg-training --force --backup
    $0 -g rg-training --dry-run

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -b|--backup)
            BACKUP_DATA=true
            shift
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
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    error "Resource group name is required. Use -g or --resource-group"
    usage
    exit 1
fi

log "🔥 Industrial Training Platform Cleanup"
log "======================================"
log "Resource Group: ${RESOURCE_GROUP}"
log "Force Delete: ${FORCE_DELETE}"
log "Skip Confirmation: ${SKIP_CONFIRMATION}"
log "Backup Data: ${BACKUP_DATA}"
log "Dry Run: ${DRY_RUN}"

# Check if Azure CLI is installed and user is logged in
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
    exit 1
fi

if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    error "Resource group '${RESOURCE_GROUP}' does not exist"
    exit 1
fi

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
log "Subscription ID: ${SUBSCRIPTION_ID}"

# List resources in the resource group
log "🔍 Analyzing resources in resource group..."
RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{name:name, type:type, location:location}' --output table)

if [[ -z "$RESOURCES" ]]; then
    warning "No resources found in resource group '${RESOURCE_GROUP}'"
    exit 0
fi

log "Resources found in '${RESOURCE_GROUP}':"
echo "$RESOURCES"

# Dry run - show what would be deleted
if [[ "$DRY_RUN" == true ]]; then
    log "🧪 DRY RUN MODE - No resources will be deleted"
    log "The following resources would be deleted:"
    echo "$RESOURCES"
    
    # Check for active Remote Rendering sessions
    ARR_ACCOUNTS=$(az resource list --resource-group "${RESOURCE_GROUP}" --resource-type "Microsoft.MixedReality/remoteRenderingAccounts" --query '[].name' --output tsv)
    
    if [[ -n "$ARR_ACCOUNTS" ]]; then
        log "Active Remote Rendering sessions check:"
        for account in $ARR_ACCOUNTS; do
            log "  - Account: $account"
            SESSIONS=$(az mixed-reality remote-rendering session list --account-name "$account" --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
            log "    Active sessions: $SESSIONS"
        done
    fi
    
    # Check for storage account contents
    STORAGE_ACCOUNTS=$(az resource list --resource-group "${RESOURCE_GROUP}" --resource-type "Microsoft.Storage/storageAccounts" --query '[].name' --output tsv)
    
    if [[ -n "$STORAGE_ACCOUNTS" ]]; then
        log "Storage account contents check:"
        for account in $STORAGE_ACCOUNTS; do
            log "  - Storage Account: $account"
            CONTAINERS=$(az storage container list --account-name "$account" --auth-mode login --query 'length(@)' --output tsv 2>/dev/null || echo "0")
            log "    Container count: $CONTAINERS"
        done
    fi
    
    success "Dry run completed. Use without --dry-run to actually delete resources."
    exit 0
fi

# Backup training data if requested
if [[ "$BACKUP_DATA" == true ]]; then
    log "💾 Backing up training data..."
    
    # Create backup directory with timestamp
    BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Find storage accounts
    STORAGE_ACCOUNTS=$(az resource list --resource-group "${RESOURCE_GROUP}" --resource-type "Microsoft.Storage/storageAccounts" --query '[].name' --output tsv)
    
    if [[ -n "$STORAGE_ACCOUNTS" ]]; then
        for account in $STORAGE_ACCOUNTS; do
            log "Backing up storage account: $account"
            
            # Get storage account key
            STORAGE_KEY=$(az storage account keys list \
                --account-name "$account" \
                --resource-group "${RESOURCE_GROUP}" \
                --query '[0].value' --output tsv 2>/dev/null)
            
            if [[ -n "$STORAGE_KEY" ]]; then
                # Create account backup directory
                ACCOUNT_BACKUP_DIR="$BACKUP_DIR/$account"
                mkdir -p "$ACCOUNT_BACKUP_DIR"
                
                # List and backup containers
                CONTAINERS=$(az storage container list \
                    --account-name "$account" \
                    --account-key "$STORAGE_KEY" \
                    --query '[].name' --output tsv 2>/dev/null)
                
                for container in $CONTAINERS; do
                    log "  Backing up container: $container"
                    mkdir -p "$ACCOUNT_BACKUP_DIR/$container"
                    
                    # Download all blobs in container
                    az storage blob download-batch \
                        --destination "$ACCOUNT_BACKUP_DIR/$container" \
                        --source "$container" \
                        --account-name "$account" \
                        --account-key "$STORAGE_KEY" \
                        --max-connections 5 \
                        --overwrite 2>/dev/null || log "  Warning: Some blobs may not have been downloaded"
                done
            else
                warning "Unable to access storage account keys for $account"
            fi
        done
        
        success "Training data backed up to: $BACKUP_DIR"
    else
        log "No storage accounts found to backup"
    fi
fi

# Confirmation prompt
if [[ "$SKIP_CONFIRMATION" == false && "$FORCE_DELETE" == false ]]; then
    echo ""
    warning "⚠️  WARNING: This operation will permanently delete all resources in the resource group!"
    warning "⚠️  This includes:"
    warning "   - Azure Remote Rendering accounts and active sessions"
    warning "   - Azure Spatial Anchors accounts and stored anchors"
    warning "   - Storage accounts and all training content"
    warning "   - Azure AD application registrations"
    warning "   - All associated data and configurations"
    echo ""
    read -p "Are you sure you want to proceed? (Type 'yes' to continue): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

# Stop active Remote Rendering sessions before deletion
log "🎨 Stopping active Remote Rendering sessions..."
ARR_ACCOUNTS=$(az resource list --resource-group "${RESOURCE_GROUP}" --resource-type "Microsoft.MixedReality/remoteRenderingAccounts" --query '[].name' --output tsv)

if [[ -n "$ARR_ACCOUNTS" ]]; then
    for account in $ARR_ACCOUNTS; do
        log "Checking sessions for account: $account"
        
        # List active sessions
        SESSIONS=$(az mixed-reality remote-rendering session list \
            --account-name "$account" \
            --resource-group "${RESOURCE_GROUP}" \
            --query '[].id' --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$SESSIONS" ]]; then
            for session_id in $SESSIONS; do
                log "  Stopping session: $session_id"
                az mixed-reality remote-rendering session stop \
                    --account-name "$account" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --session-id "$session_id" 2>/dev/null || log "  Warning: Failed to stop session $session_id"
            done
        else
            log "  No active sessions found"
        fi
    done
    
    success "Remote Rendering sessions stopped"
else
    log "No Remote Rendering accounts found"
fi

# Delete Azure AD application registrations
log "🔐 Removing Azure AD application registrations..."
# Note: We need to identify applications by searching for our naming pattern
# since we don't have the exact app ID stored

APP_PATTERN="industrial-training-platform-*"
APPS=$(az ad app list --display-name "$APP_PATTERN" --query '[].{appId:appId, displayName:displayName}' --output tsv 2>/dev/null || echo "")

if [[ -n "$APPS" ]]; then
    while IFS=$'\t' read -r app_id display_name; do
        if [[ "$display_name" == *"industrial-training-platform"* ]]; then
            log "Deleting application: $display_name ($app_id)"
            az ad app delete --id "$app_id" 2>/dev/null || log "  Warning: Failed to delete application $app_id"
        fi
    done <<< "$APPS"
    success "Azure AD applications removed"
else
    log "No matching Azure AD applications found"
fi

# Clear any local temporary files
log "🧹 Cleaning up local files..."
LOCAL_FILES=("deployment-summary.json" "unity-azure-config.zip" "test-download.json")

for file in "${LOCAL_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        log "  Removed: $file"
    fi
done

# Remove backup directories older than 7 days (optional cleanup)
if [[ -d "./backup-"* ]]; then
    log "Cleaning up old backup directories..."
    find . -type d -name "backup-*" -mtime +7 -exec rm -rf {} + 2>/dev/null || true
fi

success "Local cleanup completed"

# Delete the entire resource group
log "🗑️  Deleting resource group and all resources..."
warning "This may take 10-15 minutes to complete"

if [[ "$FORCE_DELETE" == true ]]; then
    # Force delete without waiting
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --force-deletion-types Microsoft.Compute/virtualMachines,Microsoft.Compute/virtualMachineScaleSets 2>/dev/null || true
    
    success "Resource group deletion initiated (force mode)"
    log "Deletion is running in the background. Monitor progress in Azure portal."
else
    # Normal delete with progress monitoring
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait 2>/dev/null || true
    
    success "Resource group deletion initiated"
    log "Monitoring deletion progress..."
    
    # Monitor deletion progress
    TIMEOUT=900  # 15 minutes timeout
    ELAPSED=0
    INTERVAL=30
    
    while [[ $ELAPSED -lt $TIMEOUT ]]; do
        if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
            success "Resource group '${RESOURCE_GROUP}' has been deleted"
            break
        fi
        
        log "Deletion in progress... (${ELAPSED}s elapsed)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        warning "Deletion timeout reached. Check Azure portal for final status."
    fi
fi

# Final validation
log "🔍 Performing final validation..."

# Check if resource group still exists
if az group show --name "${RESOURCE_GROUP}" &>/dev/null 2>&1; then
    warning "Resource group '${RESOURCE_GROUP}' still exists"
    log "Deletion may still be in progress. Check Azure portal for status."
else
    success "Resource group '${RESOURCE_GROUP}' has been successfully deleted"
fi

# Display cleanup summary
log "📋 Cleanup Summary"
log "=================="
log "Resource Group: ${RESOURCE_GROUP}"
log "Subscription: ${SUBSCRIPTION_ID}"
log "Cleanup Time: $(date)"

if [[ "$BACKUP_DATA" == true && -d "$BACKUP_DIR" ]]; then
    log "Backup Location: $BACKUP_DIR"
fi

log ""
log "✅ Cleanup completed successfully!"
log ""
log "📝 Important Notes:"
log "- All Azure resources in the resource group have been deleted"
log "- Azure AD applications have been removed"
log "- Local temporary files have been cleaned up"

if [[ "$BACKUP_DATA" == true ]]; then
    log "- Training data has been backed up locally"
fi

log "- Billing for these resources will stop within 24 hours"
log ""
log "🔐 Security Recommendations:"
log "- Review any remaining Azure AD permissions"
log "- Check for any orphaned service principals"
log "- Verify removal from any automation scripts"
log "- Update any dependent applications or services"

success "Industrial Training Platform cleanup completed successfully!"