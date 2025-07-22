#!/bin/bash

# Destroy script for Creating Accessible AI-Powered Customer Service Bots
# with Azure Immersive Reader and Bot Framework
# Version: 1.0
# Provider: Azure

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Default configuration
DRY_RUN=false
SKIP_CONFIRMATION=false
FORCE_DELETE=false
DELETE_RESOURCE_GROUP=false

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Azure Immersive Reader and Bot Framework resources for accessible customer service.

OPTIONS:
    -h, --help                Show this help message
    -r, --resource-group RG   Resource group name (required)
    -d, --dry-run            Show what would be deleted without actually deleting
    -y, --yes                Skip confirmation prompts
    -f, --force              Force delete without safety checks
    -g, --delete-group       Delete the entire resource group
    -v, --verbose            Enable verbose logging

EXAMPLES:
    $0 -r rg-accessible-bot-abc123           # Delete individual resources
    $0 -r rg-accessible-bot-abc123 -g        # Delete entire resource group
    $0 -r rg-accessible-bot-abc123 --dry-run # Preview what would be deleted
    $0 -r rg-accessible-bot-abc123 --yes     # Delete without confirmation

SAFETY FEATURES:
    - Requires explicit resource group specification
    - Confirmation prompts for destructive actions
    - Dry-run mode to preview actions
    - Individual resource deletion by default
    - Resource group deletion only with --delete-group flag

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -g|--delete-group)
            DELETE_RESOURCE_GROUP=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
    error "Resource group name is required. Use -r or --resource-group to specify."
    show_help
    exit 1
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is required but not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo "unknown")
    info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription information
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist or is not accessible."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Discover resources in the resource group
discover_resources() {
    log "Discovering resources in resource group: $RESOURCE_GROUP"
    
    # Get all resources in the resource group
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name,type:type,location:location}" --output json 2>/dev/null || echo "[]")
    
    if [[ "$resources" == "[]" ]]; then
        warn "No resources found in resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Parse and categorize resources
    BOT_RESOURCES=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.BotService/botServices") | .name' 2>/dev/null || echo "")
    COGNITIVE_RESOURCES=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.CognitiveServices/accounts") | .name' 2>/dev/null || echo "")
    KEYVAULT_RESOURCES=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.KeyVault/vaults") | .name' 2>/dev/null || echo "")
    STORAGE_RESOURCES=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Storage/storageAccounts") | .name' 2>/dev/null || echo "")
    WEBAPP_RESOURCES=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Web/sites") | .name' 2>/dev/null || echo "")
    APP_PLAN_RESOURCES=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Web/serverfarms") | .name' 2>/dev/null || echo "")
    INSIGHTS_RESOURCES=$(echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Insights/components") | .name' 2>/dev/null || echo "")
    
    # Display discovered resources
    info "Discovered resources:"
    echo "$resources" | jq -r '.[] | "  - \(.name) (\(.type))"' 2>/dev/null || echo "  - Unable to parse resource list"
    
    return 0
}

# Display destruction plan
show_destruction_plan() {
    cat << EOF

${RED}=== DESTRUCTION PLAN ===${NC}

Resource Group: $RESOURCE_GROUP
Destruction Mode: $([ "$DELETE_RESOURCE_GROUP" == "true" ] && echo "Full Resource Group Deletion" || echo "Individual Resource Deletion")

EOF

    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        cat << EOF
${RED}⚠️  COMPLETE RESOURCE GROUP DELETION ⚠️${NC}

This will permanently delete:
- The entire resource group: $RESOURCE_GROUP
- ALL resources within the resource group
- ALL data, configurations, and settings
- This action CANNOT be undone

EOF
    else
        cat << EOF
Individual Resources to be deleted:
EOF
        [[ -n "$BOT_RESOURCES" ]] && echo "├── Bot Services: $BOT_RESOURCES"
        [[ -n "$COGNITIVE_RESOURCES" ]] && echo "├── Cognitive Services: $COGNITIVE_RESOURCES"
        [[ -n "$WEBAPP_RESOURCES" ]] && echo "├── Web Apps: $WEBAPP_RESOURCES"
        [[ -n "$APP_PLAN_RESOURCES" ]] && echo "├── App Service Plans: $APP_PLAN_RESOURCES"
        [[ -n "$KEYVAULT_RESOURCES" ]] && echo "├── Key Vaults: $KEYVAULT_RESOURCES"
        [[ -n "$STORAGE_RESOURCES" ]] && echo "├── Storage Accounts: $STORAGE_RESOURCES"
        [[ -n "$INSIGHTS_RESOURCES" ]] && echo "└── Application Insights: $INSIGHTS_RESOURCES"
        
        cat << EOF

The resource group '$RESOURCE_GROUP' will be preserved.

EOF
    fi
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        cat << EOF
${RED}⚠️  FINAL WARNING ⚠️${NC}

You are about to PERMANENTLY DELETE the entire resource group and ALL its contents.
This action is IRREVERSIBLE and will result in complete data loss.

Type 'DELETE' to confirm resource group deletion: 
EOF
        read -r response
        if [[ "$response" != "DELETE" ]]; then
            info "Resource group deletion cancelled by user"
            exit 0
        fi
    else
        echo -n "Do you want to proceed with resource deletion? (y/N): "
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS])
                return 0
                ;;
            *)
                info "Resource deletion cancelled by user"
                exit 0
                ;;
        esac
    fi
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] $description"
        info "[DRY RUN] Command: $cmd"
        return 0
    fi
    
    info "$description"
    if eval "$cmd"; then
        log "✅ $description - Success"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            warn "⚠️  $description - Failed (ignored)"
            return 0
        else
            error "❌ $description - Failed"
            return 1
        fi
    fi
}

# Delete Bot Framework resources
delete_bot_resources() {
    if [[ -z "$BOT_RESOURCES" ]]; then
        info "No Bot Framework resources found to delete"
        return 0
    fi
    
    log "Deleting Bot Framework resources..."
    
    for bot_name in $BOT_RESOURCES; do
        local cmd="az bot delete --name '$bot_name' --resource-group '$RESOURCE_GROUP' --yes"
        execute_cmd "$cmd" "Deleting Bot Framework registration: $bot_name" "true"
    done
}

# Delete Cognitive Services resources
delete_cognitive_resources() {
    if [[ -z "$COGNITIVE_RESOURCES" ]]; then
        info "No Cognitive Services resources found to delete"
        return 0
    fi
    
    log "Deleting Cognitive Services resources..."
    
    for cog_name in $COGNITIVE_RESOURCES; do
        local cmd="az cognitiveservices account delete --name '$cog_name' --resource-group '$RESOURCE_GROUP' --yes"
        execute_cmd "$cmd" "Deleting Cognitive Services account: $cog_name" "true"
    done
}

# Delete Web App resources
delete_webapp_resources() {
    if [[ -z "$WEBAPP_RESOURCES" ]]; then
        info "No Web App resources found to delete"
        return 0
    fi
    
    log "Deleting Web App resources..."
    
    for webapp_name in $WEBAPP_RESOURCES; do
        local cmd="az webapp delete --name '$webapp_name' --resource-group '$RESOURCE_GROUP'"
        execute_cmd "$cmd" "Deleting Web App: $webapp_name" "true"
    done
}

# Delete App Service Plans
delete_app_service_plans() {
    if [[ -z "$APP_PLAN_RESOURCES" ]]; then
        info "No App Service Plans found to delete"
        return 0
    fi
    
    log "Deleting App Service Plans..."
    
    for plan_name in $APP_PLAN_RESOURCES; do
        local cmd="az appservice plan delete --name '$plan_name' --resource-group '$RESOURCE_GROUP' --yes"
        execute_cmd "$cmd" "Deleting App Service Plan: $plan_name" "true"
    done
}

# Delete Key Vault resources (with purge protection handling)
delete_keyvault_resources() {
    if [[ -z "$KEYVAULT_RESOURCES" ]]; then
        info "No Key Vault resources found to delete"
        return 0
    fi
    
    log "Deleting Key Vault resources..."
    
    for kv_name in $KEYVAULT_RESOURCES; do
        # Check if Key Vault has purge protection enabled
        local purge_protection=$(az keyvault show --name "$kv_name" --query "properties.enablePurgeProtection" --output tsv 2>/dev/null || echo "false")
        
        local cmd="az keyvault delete --name '$kv_name' --resource-group '$RESOURCE_GROUP'"
        execute_cmd "$cmd" "Deleting Key Vault: $kv_name" "true"
        
        # If purge protection is not enabled, purge the vault
        if [[ "$purge_protection" != "true" && "$DRY_RUN" == "false" ]]; then
            info "Purging Key Vault: $kv_name"
            az keyvault purge --name "$kv_name" --no-wait 2>/dev/null || warn "Failed to purge Key Vault: $kv_name"
        elif [[ "$purge_protection" == "true" ]]; then
            warn "Key Vault '$kv_name' has purge protection enabled. It will be soft-deleted but not purged."
        fi
    done
}

# Delete Storage Account resources
delete_storage_resources() {
    if [[ -z "$STORAGE_RESOURCES" ]]; then
        info "No Storage Account resources found to delete"
        return 0
    fi
    
    log "Deleting Storage Account resources..."
    
    for storage_name in $STORAGE_RESOURCES; do
        local cmd="az storage account delete --name '$storage_name' --resource-group '$RESOURCE_GROUP' --yes"
        execute_cmd "$cmd" "Deleting Storage Account: $storage_name" "true"
    done
}

# Delete Application Insights resources
delete_insights_resources() {
    if [[ -z "$INSIGHTS_RESOURCES" ]]; then
        info "No Application Insights resources found to delete"
        return 0
    fi
    
    log "Deleting Application Insights resources..."
    
    for insights_name in $INSIGHTS_RESOURCES; do
        local cmd="az monitor app-insights component delete --app '$insights_name' --resource-group '$RESOURCE_GROUP'"
        execute_cmd "$cmd" "Deleting Application Insights: $insights_name" "true"
    done
}

# Delete entire resource group
delete_resource_group() {
    if [[ "$DELETE_RESOURCE_GROUP" != "true" ]]; then
        return 0
    fi
    
    log "Deleting entire resource group..."
    
    local cmd="az group delete --name '$RESOURCE_GROUP' --yes --no-wait"
    execute_cmd "$cmd" "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Resource group deletion initiated. This may take several minutes to complete."
        info "You can check the status with: az group show --name '$RESOURCE_GROUP'"
    fi
}

# Delete individual resources
delete_individual_resources() {
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        return 0
    fi
    
    log "Deleting individual resources..."
    
    # Delete resources in reverse dependency order
    delete_bot_resources
    delete_webapp_resources
    delete_app_service_plans
    delete_cognitive_resources
    delete_insights_resources
    delete_storage_resources
    delete_keyvault_resources  # Delete Key Vault last due to purge protection
}

# Validate destruction
validate_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Skipping destruction validation"
        return 0
    fi
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        # Check if resource group deletion is in progress
        local group_exists=$(az group exists --name "$RESOURCE_GROUP" 2>/dev/null || echo "false")
        if [[ "$group_exists" == "false" ]]; then
            log "✅ Resource group successfully deleted"
        else
            info "Resource group deletion is in progress"
        fi
        return 0
    fi
    
    log "Validating resource destruction..."
    
    # Check that resources have been deleted
    local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
    
    if [[ "$remaining_resources" -eq 0 ]]; then
        log "✅ All resources successfully deleted"
        info "The empty resource group '$RESOURCE_GROUP' has been preserved"
    else
        warn "Some resources may still exist in the resource group"
        info "Remaining resources: $remaining_resources"
        
        # List remaining resources
        az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name,type:type}" --output table 2>/dev/null || true
    fi
}

# Display destruction summary
show_destruction_summary() {
    cat << EOF

${GREEN}=== DESTRUCTION SUMMARY ===${NC}

Resource Group: $RESOURCE_GROUP
Destruction Mode: $([ "$DELETE_RESOURCE_GROUP" == "true" ] && echo "Full Resource Group Deletion" || echo "Individual Resource Deletion")

EOF

    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        cat << EOF
${GREEN}✅ Resource group deletion initiated${NC}

The resource group '$RESOURCE_GROUP' and all its contents are being deleted.
This process may take several minutes to complete.

To verify completion, run:
  az group exists --name '$RESOURCE_GROUP'

EOF
    else
        cat << EOF
${GREEN}✅ Individual resource deletion completed${NC}

The following resource types have been processed:
- Bot Framework registrations
- Cognitive Services accounts  
- Web Apps and App Service Plans
- Key Vault resources
- Storage Accounts
- Application Insights components

The resource group '$RESOURCE_GROUP' has been preserved.

To delete the empty resource group, run:
  az group delete --name '$RESOURCE_GROUP' --yes

EOF
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Azure Immersive Reader Bot Framework resources..."
    
    # Check prerequisites
    check_prerequisites
    
    # Discover resources
    discover_resources
    
    # Show destruction plan
    show_destruction_plan
    
    # Confirm destruction
    confirm_destruction
    
    # Execute destruction
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        delete_resource_group
    else
        delete_individual_resources
    fi
    
    # Validate destruction
    validate_destruction
    
    # Show summary
    show_destruction_summary
    
    log "Destruction process completed!"
}

# Error handling
trap 'error "Destruction process failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"