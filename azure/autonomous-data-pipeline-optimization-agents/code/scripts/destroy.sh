#!/bin/bash

# Azure Intelligent Data Pipeline Automation - Cleanup Script
# This script safely removes all resources created for the intelligent pipeline automation solution

set -e
set -o pipefail

# Script configuration
SCRIPT_NAME="Azure Intelligent Pipeline Automation Cleanup"
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
CLEANUP_ERRORS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
    echo -e "${YELLOW}⚠️  Non-critical error in function: ${FUNCNAME[1]}, line: $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}Exit code: $exit_code${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}Continuing with cleanup...${NC}" | tee -a "$LOG_FILE"
}

trap 'handle_error $LINENO' ERR

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local percent=$((current * 100 / total))
    echo -e "${BLUE}[${current}/${total}] (${percent}%) ${message}${NC}"
}

# Confirmation function
confirm_cleanup() {
    echo -e "${RED}⚠️  WARNING: This will permanently delete all resources created for the intelligent pipeline automation solution!${NC}"
    echo ""
    echo "This includes:"
    echo "• Resource group and all contained resources"
    echo "• AI Foundry Hub and all agents"
    echo "• Data Factory and all pipelines"
    echo "• Storage accounts and data"
    echo "• Monitoring and logging data"
    echo "• Event Grid topics and subscriptions"
    echo ""
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${GREEN}Cleanup cancelled by user.${NC}"
        exit 0
    fi
    
    echo ""
    read -p "Please type 'DELETE' to confirm permanent resource deletion: " -r
    if [[ $REPLY != "DELETE" ]]; then
        echo -e "${GREEN}Cleanup cancelled - confirmation text did not match.${NC}"
        exit 0
    fi
    
    echo ""
    echo -e "${RED}Proceeding with resource deletion...${NC}"
    log "User confirmed cleanup operation"
}

# Validation functions
check_prerequisites() {
    log "🔍 Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        echo -e "${RED}❌ Azure CLI is not installed.${NC}"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        echo -e "${RED}❌ Not logged into Azure. Please run 'az login' first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check completed${NC}"
}

# Resource discovery functions
discover_resources() {
    log "🔍 Discovering resources to cleanup..."
    
    echo -e "${BLUE}Searching for resource groups with 'intelligent-pipeline' pattern...${NC}"
    
    # Find resource groups that match our pattern
    local resource_groups=$(az group list --query "[?contains(name, 'intelligent-pipeline')].name" --output tsv)
    
    if [ -z "$resource_groups" ]; then
        echo -e "${YELLOW}⚠️  No resource groups found matching 'intelligent-pipeline' pattern.${NC}"
        echo "This could mean:"
        echo "• Resources have already been deleted"
        echo "• Resources were created with different naming convention"
        echo "• You might need to specify the resource group manually"
        echo ""
        
        read -p "Do you want to specify a resource group manually? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Enter the resource group name: " -r RESOURCE_GROUP
            if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                echo -e "${RED}❌ Resource group '$RESOURCE_GROUP' not found.${NC}"
                exit 1
            fi
        else
            echo -e "${GREEN}No cleanup needed - exiting.${NC}"
            exit 0
        fi
    else
        echo -e "${GREEN}Found resource groups:${NC}"
        echo "$resource_groups"
        echo ""
        
        # If multiple resource groups found, let user choose
        local group_count=$(echo "$resource_groups" | wc -l)
        if [ "$group_count" -gt 1 ]; then
            echo -e "${YELLOW}Multiple resource groups found. Please select one:${NC}"
            select RESOURCE_GROUP in $resource_groups "All of them" "Cancel"; do
                case $RESOURCE_GROUP in
                    "All of them")
                        RESOURCE_GROUP="$resource_groups"
                        break
                        ;;
                    "Cancel")
                        echo -e "${GREEN}Cleanup cancelled by user.${NC}"
                        exit 0
                        ;;
                    *)
                        if [ -n "$RESOURCE_GROUP" ]; then
                            break
                        else
                            echo "Invalid selection. Please try again."
                        fi
                        ;;
                esac
            done
        else
            RESOURCE_GROUP="$resource_groups"
        fi
    fi
    
    log "Target resource group(s): $RESOURCE_GROUP"
}

# Get subscription ID
get_subscription_info() {
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    
    echo -e "${GREEN}Using Azure subscription: $subscription_name ($SUBSCRIPTION_ID)${NC}"
    log "Using subscription: $subscription_name ($SUBSCRIPTION_ID)"
}

# Individual cleanup functions
stop_ai_agents() {
    show_progress 1 8 "Stopping AI agents..."
    
    for rg in $RESOURCE_GROUP; do
        log "Stopping AI agents in resource group: $rg"
        
        # Find AI Foundry projects in the resource group
        local projects=$(az ml project list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        
        if [ -n "$projects" ]; then
            for project in $projects; do
                echo "  Stopping agents in project: $project"
                
                # List and stop all agents in the project
                local agents=$(az ml agent list --resource-group "$rg" --project "$project" --query "[].name" --output tsv 2>/dev/null || true)
                
                if [ -n "$agents" ]; then
                    for agent in $agents; do
                        echo "    Stopping agent: $agent"
                        az ml agent stop \
                            --name "$agent" \
                            --resource-group "$rg" \
                            --project "$project" \
                            >> "$LOG_FILE" 2>&1 || true
                    done
                fi
            done
        fi
    done
    
    log "✅ AI agents stopped"
}

remove_event_grid_subscriptions() {
    show_progress 2 8 "Removing Event Grid subscriptions..."
    
    for rg in $RESOURCE_GROUP; do
        log "Removing Event Grid subscriptions in resource group: $rg"
        
        # Find Data Factory instances
        local data_factories=$(az datafactory list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        
        if [ -n "$data_factories" ]; then
            for df in $data_factories; do
                echo "  Removing Event Grid subscriptions for Data Factory: $df"
                
                # Remove event subscriptions
                local source_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${rg}/providers/Microsoft.DataFactory/factories/${df}"
                
                # Find and delete event subscriptions
                local subscriptions=$(az eventgrid event-subscription list \
                    --source-resource-id "$source_resource_id" \
                    --query "[].name" --output tsv 2>/dev/null || true)
                
                if [ -n "$subscriptions" ]; then
                    for sub in $subscriptions; do
                        echo "    Deleting subscription: $sub"
                        az eventgrid event-subscription delete \
                            --name "$sub" \
                            --source-resource-id "$source_resource_id" \
                            >> "$LOG_FILE" 2>&1 || true
                    done
                fi
            done
        fi
        
        # Remove Event Grid topics
        local topics=$(az eventgrid topic list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        if [ -n "$topics" ]; then
            for topic in $topics; do
                echo "  Deleting Event Grid topic: $topic"
                az eventgrid topic delete \
                    --resource-group "$rg" \
                    --name "$topic" \
                    >> "$LOG_FILE" 2>&1 || true
            done
        fi
    done
    
    log "✅ Event Grid subscriptions and topics removed"
}

remove_monitoring_resources() {
    show_progress 3 8 "Removing monitoring resources..."
    
    for rg in $RESOURCE_GROUP; do
        log "Removing monitoring resources in resource group: $rg"
        
        # Remove monitoring dashboards
        local dashboards=$(az monitor dashboard list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        if [ -n "$dashboards" ]; then
            for dashboard in $dashboards; do
                echo "  Deleting dashboard: $dashboard"
                az monitor dashboard delete \
                    --resource-group "$rg" \
                    --name "$dashboard" \
                    >> "$LOG_FILE" 2>&1 || true
            done
        fi
        
        # Remove alert rules
        local alerts=$(az monitor metrics alert list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        if [ -n "$alerts" ]; then
            for alert in $alerts; do
                echo "  Deleting alert rule: $alert"
                az monitor metrics alert delete \
                    --name "$alert" \
                    --resource-group "$rg" \
                    >> "$LOG_FILE" 2>&1 || true
            done
        fi
        
        # Remove diagnostic settings
        local data_factories=$(az datafactory list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        if [ -n "$data_factories" ]; then
            for df in $data_factories; do
                echo "  Removing diagnostic settings for: $df"
                az monitor diagnostic-settings delete \
                    --resource "$df" \
                    --resource-group "$rg" \
                    --resource-type Microsoft.DataFactory/factories \
                    --name "DataFactoryDiagnostics" \
                    >> "$LOG_FILE" 2>&1 || true
            done
        fi
    done
    
    log "✅ Monitoring resources removed"
}

remove_ai_foundry_resources() {
    show_progress 4 8 "Removing AI Foundry resources..."
    
    for rg in $RESOURCE_GROUP; do
        log "Removing AI Foundry resources in resource group: $rg"
        
        # Remove AI Foundry projects first
        local projects=$(az ml project list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        if [ -n "$projects" ]; then
            for project in $projects; do
                echo "  Deleting AI Foundry project: $project"
                az ml project delete \
                    --name "$project" \
                    --resource-group "$rg" \
                    --yes \
                    >> "$LOG_FILE" 2>&1 || true
            done
        fi
        
        # Wait for projects to be deleted
        echo "  Waiting for projects to be fully deleted..."
        sleep 30
        
        # Remove AI Foundry hubs
        local hubs=$(az ml hub list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        if [ -n "$hubs" ]; then
            for hub in $hubs; do
                echo "  Deleting AI Foundry hub: $hub"
                az ml hub delete \
                    --name "$hub" \
                    --resource-group "$rg" \
                    --yes \
                    >> "$LOG_FILE" 2>&1 || true
            done
        fi
    done
    
    log "✅ AI Foundry resources removed"
}

remove_data_factory() {
    show_progress 5 8 "Removing Data Factory resources..."
    
    for rg in $RESOURCE_GROUP; do
        log "Removing Data Factory resources in resource group: $rg"
        
        local data_factories=$(az datafactory list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        if [ -n "$data_factories" ]; then
            for df in $data_factories; do
                echo "  Deleting Data Factory: $df"
                az datafactory delete \
                    --resource-group "$rg" \
                    --factory-name "$df" \
                    --yes \
                    >> "$LOG_FILE" 2>&1 || true
            done
        fi
    done
    
    log "✅ Data Factory resources removed"
}

remove_storage_accounts() {
    show_progress 6 8 "Removing storage accounts..."
    
    for rg in $RESOURCE_GROUP; do
        log "Removing storage accounts in resource group: $rg"
        
        local storage_accounts=$(az storage account list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        if [ -n "$storage_accounts" ]; then
            for sa in $storage_accounts; do
                echo "  Deleting storage account: $sa"
                az storage account delete \
                    --name "$sa" \
                    --resource-group "$rg" \
                    --yes \
                    >> "$LOG_FILE" 2>&1 || true
            done
        fi
    done
    
    log "✅ Storage accounts removed"
}

remove_key_vaults() {
    show_progress 7 8 "Removing Key Vaults..."
    
    for rg in $RESOURCE_GROUP; do
        log "Removing Key Vaults in resource group: $rg"
        
        local key_vaults=$(az keyvault list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        if [ -n "$key_vaults" ]; then
            for kv in $key_vaults; do
                echo "  Deleting Key Vault: $kv"
                az keyvault delete \
                    --name "$kv" \
                    --resource-group "$rg" \
                    >> "$LOG_FILE" 2>&1 || true
                
                echo "  Purging Key Vault: $kv"
                az keyvault purge \
                    --name "$kv" \
                    --no-wait \
                    >> "$LOG_FILE" 2>&1 || true
            done
        fi
    done
    
    log "✅ Key Vaults removed"
}

remove_resource_groups() {
    show_progress 8 8 "Removing resource groups..."
    
    for rg in $RESOURCE_GROUP; do
        log "Removing resource group: $rg"
        echo "  Deleting resource group: $rg"
        
        az group delete \
            --name "$rg" \
            --yes \
            --no-wait \
            >> "$LOG_FILE" 2>&1 || true
    done
    
    log "✅ Resource group deletion initiated"
}

# Verification functions
verify_cleanup() {
    echo -e "${BLUE}🔍 Verifying cleanup completion...${NC}"
    
    local remaining_resources=0
    
    for rg in $RESOURCE_GROUP; do
        if az group show --name "$rg" &> /dev/null; then
            echo -e "${YELLOW}⚠️  Resource group still exists: $rg${NC}"
            echo "  (Deletion may still be in progress)"
            remaining_resources=$((remaining_resources + 1))
        else
            echo -e "${GREEN}✅ Resource group successfully deleted: $rg${NC}"
        fi
    done
    
    if [ $remaining_resources -eq 0 ]; then
        echo -e "${GREEN}🎉 All resources successfully cleaned up!${NC}"
    else
        echo -e "${YELLOW}⚠️  Some resources may still be deleting in the background.${NC}"
        echo "  Check the Azure portal in a few minutes to confirm complete deletion."
    fi
}

cleanup_temp_files() {
    log "🧹 Cleaning up temporary files..."
    
    # Remove any temporary config files that might exist
    rm -f pipeline-config.json
    rm -f monitoring-agent-config.json
    rm -f quality-agent-config.json
    rm -f optimization-agent-config.json
    rm -f healing-agent-config.json
    rm -f dashboard-config.json
    
    echo -e "${GREEN}✅ Temporary files cleaned up${NC}"
}

display_cleanup_summary() {
    echo ""
    echo -e "${GREEN}🎉 Cleanup process completed!${NC}"
    echo ""
    echo -e "${BLUE}📋 Cleanup Summary:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${YELLOW}Resource Groups Processed:${NC}"
    for rg in $RESOURCE_GROUP; do
        echo "  • $rg"
    done
    echo ""
    echo -e "${BLUE}📊 Resources Removed:${NC}"
    echo "• AI Foundry agents, projects, and hubs"
    echo "• Azure Data Factory and pipelines"
    echo "• Event Grid topics and subscriptions"
    echo "• Monitoring dashboards and alerts"
    echo "• Storage accounts and data"
    echo "• Key Vaults (including purge)"
    echo "• Log Analytics workspaces"
    echo "• Resource groups and all contained resources"
    echo ""
    
    if [ $CLEANUP_ERRORS -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Non-critical errors encountered: $CLEANUP_ERRORS${NC}"
        echo "  These are typically due to resources being already deleted or dependencies."
        echo "  Check the log file for details: $LOG_FILE"
        echo ""
    fi
    
    echo -e "${BLUE}📝 Important Notes:${NC}"
    echo "• Resource deletion may take a few minutes to complete in the background"
    echo "• Some resources (like Key Vaults) have been purged to prevent name conflicts"
    echo "• Billing will stop once all resources are fully deleted"
    echo "• Check the Azure portal to confirm complete deletion if needed"
    echo ""
    echo -e "${GREEN}📋 Log file saved as: $LOG_FILE${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution
main() {
    echo -e "${BLUE}🚀 Starting ${SCRIPT_NAME}${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    log "Starting cleanup of Azure Intelligent Data Pipeline Automation resources"
    
    # Pre-cleanup checks
    check_prerequisites
    get_subscription_info
    discover_resources
    confirm_cleanup
    
    echo ""
    echo -e "${RED}🗑️  Beginning resource cleanup...${NC}"
    echo ""
    
    # Main cleanup process (in reverse order of creation)
    stop_ai_agents
    remove_event_grid_subscriptions
    remove_monitoring_resources
    remove_ai_foundry_resources
    remove_data_factory
    remove_storage_accounts
    remove_key_vaults
    remove_resource_groups
    
    # Post-cleanup
    cleanup_temp_files
    verify_cleanup
    display_cleanup_summary
    
    log "Cleanup process completed"
    
    if [ $CLEANUP_ERRORS -eq 0 ]; then
        echo -e "${GREEN}✨ All resources have been successfully cleaned up!${NC}"
    else
        echo -e "${YELLOW}⚠️  Cleanup completed with $CLEANUP_ERRORS non-critical errors.${NC}"
        echo -e "${YELLOW}Check the log file for details: $LOG_FILE${NC}"
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi