#!/bin/bash

# AWS Multi-Account Governance Cleanup Script
# Safely removes Organizations, Service Control Policies, and associated resources

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DRY_RUN=false
FORCE=false
CONFIRM=true

# Logging function
log() {
    echo -e "${2:-}$(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    log "ERROR: $1" "$RED"
}

log_success() {
    log "SUCCESS: $1" "$GREEN"
}

log_info() {
    log "INFO: $1" "$BLUE"
}

log_warning() {
    log "WARNING: $1" "$YELLOW"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check logs at: $LOG_FILE"
    exit 1
}

# Help function
show_help() {
    cat << EOF
AWS Multi-Account Governance Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deleted without making changes
    -f, --force         Delete resources without additional confirmations
    -y, --yes           Skip initial confirmation prompt
    -r, --region        AWS region (default: from AWS CLI config)
    -v, --verbose       Enable verbose logging

EXAMPLES:
    $0                  Interactive cleanup with confirmations
    $0 --dry-run        Show cleanup plan
    $0 --force --yes    Delete all resources without prompts
    $0 --region us-west-2 --verbose

WARNING:
    This script will permanently delete AWS Organizations resources.
    Make sure you understand the implications before proceeding.

WHAT GETS DELETED:
    - Service Control Policies and their attachments
    - Organization-wide CloudTrail
    - CloudWatch dashboards
    - S3 buckets (CloudTrail and Config)
    - AWS Budgets
    - Organizational Units (if empty)
    - Organization (if requested and safe)
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -y|--yes)
                CONFIRM=false
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check Organizations access
    if ! aws organizations describe-organization &> /dev/null 2>&1; then
        log_warning "No organization found or insufficient permissions."
        log_info "Some cleanup operations may not be available."
    fi
    
    log_success "Prerequisites check completed"
}

# Load state from deployment
load_deployment_state() {
    log_info "Loading deployment state..."
    
    local state_file="${SCRIPT_DIR}/.deployment_state"
    
    if [[ -f "$state_file" ]]; then
        log_info "Found deployment state file: $state_file"
        
        # Source the state file to load environment variables
        # shellcheck source=/dev/null
        source "$state_file"
        
        log_info "Loaded state variables from previous deployment"
    else
        log_warning "No deployment state file found. Will attempt to discover resources."
        
        # Try to discover existing resources
        discover_existing_resources
    fi
}

# Discover existing resources
discover_existing_resources() {
    log_info "Discovering existing organization resources..."
    
    # Try to get organization info
    if aws organizations describe-organization &> /dev/null; then
        export ORG_ID=$(aws organizations describe-organization --query Organization.Id --output text 2>/dev/null || echo "")
        export ORG_MGMT_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Discover OUs
        if [[ -n "$ORG_ID" ]]; then
            export PROD_OU_ID=$(aws organizations list-organizational-units \
                --parent-id "$ORG_ID" \
                --query "OrganizationalUnits[?Name=='Production'].Id" \
                --output text 2>/dev/null || echo "")
            export DEV_OU_ID=$(aws organizations list-organizational-units \
                --parent-id "$ORG_ID" \
                --query "OrganizationalUnits[?Name=='Development'].Id" \
                --output text 2>/dev/null || echo "")
            export SANDBOX_OU_ID=$(aws organizations list-organizational-units \
                --parent-id "$ORG_ID" \
                --query "OrganizationalUnits[?Name=='Sandbox'].Id" \
                --output text 2>/dev/null || echo "")
            export SECURITY_OU_ID=$(aws organizations list-organizational-units \
                --parent-id "$ORG_ID" \
                --query "OrganizationalUnits[?Name=='Security'].Id" \
                --output text 2>/dev/null || echo "")
        fi
        
        # Discover SCPs
        export COST_SCP_ID=$(aws organizations list-policies \
            --filter SERVICE_CONTROL_POLICY \
            --query "Policies[?Name=='CostControlPolicy'].Id" \
            --output text 2>/dev/null || echo "")
        export SECURITY_SCP_ID=$(aws organizations list-policies \
            --filter SERVICE_CONTROL_POLICY \
            --query "Policies[?Name=='SecurityBaselinePolicy'].Id" \
            --output text 2>/dev/null || echo "")
        export REGION_SCP_ID=$(aws organizations list-policies \
            --filter SERVICE_CONTROL_POLICY \
            --query "Policies[?Name=='RegionRestrictionPolicy'].Id" \
            --output text 2>/dev/null || echo "")
        
        # Discover CloudTrail
        export CLOUDTRAIL_ARN=$(aws cloudtrail describe-trails \
            --query "trailList[?Name=='OrganizationTrail'].TrailARN" \
            --output text 2>/dev/null || echo "")
    fi
    
    log_info "Resource discovery completed"
}

# Confirm cleanup operation
confirm_cleanup() {
    if [[ "$CONFIRM" == "false" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This script will permanently delete AWS Organization resources."
    log_warning "This includes:"
    log_warning "  - Service Control Policies"
    log_warning "  - Organization-wide CloudTrail"
    log_warning "  - S3 buckets and their contents"
    log_warning "  - CloudWatch dashboards"
    log_warning "  - AWS Budgets"
    log_warning "  - Organizational Units"
    echo
    
    if [[ -n "${ORG_ID:-}" ]]; then
        log_info "Organization ID: $ORG_ID"
    fi
    if [[ -n "${ORG_MGMT_ACCOUNT_ID:-}" ]]; then
        log_info "Management Account: $ORG_MGMT_ACCOUNT_ID"
    fi
    
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    if [[ "$FORCE" == "false" ]]; then
        echo
        read -p "Final confirmation - this will PERMANENTLY DELETE resources. Type 'DELETE' to proceed: " -r
        if [[ ! $REPLY =~ ^DELETE$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Detach and delete Service Control Policies
cleanup_service_control_policies() {
    log_info "Cleaning up Service Control Policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would detach and delete Service Control Policies"
        return 0
    fi
    
    # Define policy-OU attachments to remove
    local attachments=()
    [[ -n "${COST_SCP_ID:-}" && -n "${PROD_OU_ID:-}" ]] && attachments+=("$COST_SCP_ID:$PROD_OU_ID:cost control from Production")
    [[ -n "${COST_SCP_ID:-}" && -n "${DEV_OU_ID:-}" ]] && attachments+=("$COST_SCP_ID:$DEV_OU_ID:cost control from Development")
    [[ -n "${SECURITY_SCP_ID:-}" && -n "${PROD_OU_ID:-}" ]] && attachments+=("$SECURITY_SCP_ID:$PROD_OU_ID:security baseline from Production")
    [[ -n "${REGION_SCP_ID:-}" && -n "${SANDBOX_OU_ID:-}" ]] && attachments+=("$REGION_SCP_ID:$SANDBOX_OU_ID:region restriction from Sandbox")
    
    # Detach policies from OUs
    for attachment in "${attachments[@]}"; do
        if [[ -z "$attachment" ]]; then continue; fi
        
        IFS=':' read -r policy_id target_id description <<< "$attachment"
        
        # Check if policy is attached
        local attached_targets
        attached_targets=$(aws organizations list-targets-for-policy \
            --policy-id "$policy_id" \
            --query "Targets[?TargetId=='$target_id'].TargetId" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached_targets" ]]; then
            aws organizations detach-policy \
                --policy-id "$policy_id" \
                --target-id "$target_id" 2>/dev/null || \
                log_warning "Failed to detach $description"
            log_success "Detached $description"
        else
            log_info "Policy not attached: $description"
        fi
    done
    
    # Delete SCPs
    local policies=("$COST_SCP_ID:CostControlPolicy" "$SECURITY_SCP_ID:SecurityBaselinePolicy" "$REGION_SCP_ID:RegionRestrictionPolicy")
    
    for policy in "${policies[@]}"; do
        if [[ -z "$policy" ]]; then continue; fi
        
        IFS=':' read -r policy_id policy_name <<< "$policy"
        
        if [[ -n "$policy_id" ]]; then
            # Check if policy exists
            if aws organizations describe-policy --policy-id "$policy_id" &> /dev/null; then
                aws organizations delete-policy --policy-id "$policy_id" 2>/dev/null || \
                    log_warning "Failed to delete policy $policy_name"
                log_success "Deleted policy $policy_name"
            else
                log_info "Policy $policy_name not found or already deleted"
            fi
        fi
    done
}

# Delete CloudTrail and monitoring resources
cleanup_cloudtrail_and_monitoring() {
    log_info "Cleaning up CloudTrail and monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete CloudTrail, CloudWatch dashboard, and S3 buckets"
        return 0
    fi
    
    # Stop and delete CloudTrail
    if [[ -n "${CLOUDTRAIL_ARN:-}" ]]; then
        if aws cloudtrail describe-trails --query "trailList[?TrailARN=='$CLOUDTRAIL_ARN']" --output text | grep -q .; then
            aws cloudtrail stop-logging --name "OrganizationTrail" 2>/dev/null || \
                log_warning "Failed to stop CloudTrail logging"
            
            aws cloudtrail delete-trail --name "OrganizationTrail" 2>/dev/null || \
                log_warning "Failed to delete CloudTrail"
            
            log_success "Deleted CloudTrail: OrganizationTrail"
        else
            log_info "CloudTrail OrganizationTrail not found"
        fi
    fi
    
    # Delete CloudWatch dashboard
    if aws cloudwatch list-dashboards --query "DashboardEntries[?DashboardName=='OrganizationGovernance']" --output text | grep -q .; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "OrganizationGovernance" 2>/dev/null || \
            log_warning "Failed to delete CloudWatch dashboard"
        log_success "Deleted CloudWatch dashboard: OrganizationGovernance"
    else
        log_info "CloudWatch dashboard OrganizationGovernance not found"
    fi
    
    # Delete S3 buckets
    local buckets=("${CLOUDTRAIL_BUCKET:-}" "${CONFIG_BUCKET:-}")
    
    for bucket in "${buckets[@]}"; do
        if [[ -n "$bucket" ]]; then
            if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
                # Empty bucket first
                aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
                
                # Delete bucket
                aws s3 rb "s3://$bucket" 2>/dev/null || \
                    log_warning "Failed to delete S3 bucket: $bucket"
                
                log_success "Deleted S3 bucket: $bucket"
            else
                log_info "S3 bucket $bucket not found"
            fi
        fi
    done
}

# Delete budgets
cleanup_budgets() {
    log_info "Cleaning up AWS Budgets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete organization budget"
        return 0
    fi
    
    # Delete organization budget
    if [[ -n "${ORG_MGMT_ACCOUNT_ID:-}" ]]; then
        local existing_budget
        existing_budget=$(aws budgets describe-budgets \
            --account-id "$ORG_MGMT_ACCOUNT_ID" \
            --query "Budgets[?BudgetName=='OrganizationMasterBudget'].BudgetName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$existing_budget" ]]; then
            aws budgets delete-budget \
                --account-id "$ORG_MGMT_ACCOUNT_ID" \
                --budget-name "OrganizationMasterBudget" 2>/dev/null || \
                log_warning "Failed to delete budget OrganizationMasterBudget"
            log_success "Deleted budget: OrganizationMasterBudget"
        else
            log_info "Budget OrganizationMasterBudget not found"
        fi
    fi
}

# Delete Organizational Units
cleanup_organizational_units() {
    log_info "Cleaning up Organizational Units..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete empty Organizational Units"
        return 0
    fi
    
    local ou_ids=("${PROD_OU_ID:-}" "${DEV_OU_ID:-}" "${SANDBOX_OU_ID:-}" "${SECURITY_OU_ID:-}")
    local ou_names=("Production" "Development" "Sandbox" "Security")
    
    for i in "${!ou_ids[@]}"; do
        local ou_id="${ou_ids[$i]}"
        local ou_name="${ou_names[$i]}"
        
        if [[ -n "$ou_id" ]]; then
            # Check if OU has any accounts
            local accounts
            accounts=$(aws organizations list-accounts-for-parent \
                --parent-id "$ou_id" \
                --query 'Accounts[*].Id' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$accounts" ]]; then
                log_warning "OU $ou_name has member accounts. Cannot delete. Accounts: $accounts"
                log_info "To delete this OU, first move all accounts to another OU or close them"
            else
                # Check if OU has any child OUs
                local child_ous
                child_ous=$(aws organizations list-organizational-units \
                    --parent-id "$ou_id" \
                    --query 'OrganizationalUnits[*].Id' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$child_ous" ]]; then
                    log_warning "OU $ou_name has child OUs. Cannot delete."
                else
                    # OU is empty, safe to delete
                    aws organizations delete-organizational-unit \
                        --organizational-unit-id "$ou_id" 2>/dev/null || \
                        log_warning "Failed to delete OU $ou_name"
                    log_success "Deleted OU: $ou_name"
                fi
            fi
        else
            log_info "OU $ou_name not found"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete local policy files and state"
        return 0
    fi
    
    local policy_dir="${SCRIPT_DIR}/../policies"
    local files=(
        "$policy_dir/cost-control-scp.json"
        "$policy_dir/security-baseline-scp.json"
        "$policy_dir/region-restriction-scp.json"
        "$policy_dir/cloudtrail-bucket-policy.json"
        "$policy_dir/organization-budget.json"
        "$policy_dir/governance-dashboard.json"
        "${SCRIPT_DIR}/.deployment_state"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" 2>/dev/null || log_warning "Failed to delete file: $file"
            log_success "Deleted file: $(basename "$file")"
        fi
    done
    
    # Remove policy directory if empty
    if [[ -d "$policy_dir" ]] && [[ -z "$(ls -A "$policy_dir" 2>/dev/null)" ]]; then
        rmdir "$policy_dir" 2>/dev/null || log_warning "Failed to remove empty policy directory"
        log_success "Removed empty policy directory"
    fi
}

# Warn about organization deletion
warn_about_organization() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Organization deletion would require manual action"
        return 0
    fi
    
    if [[ -n "${ORG_ID:-}" ]]; then
        echo
        log_warning "=== ORGANIZATION DELETION ==="
        log_warning "The AWS Organization ($ORG_ID) was not automatically deleted."
        log_warning "To delete the organization:"
        log_warning "1. Ensure all member accounts are removed"
        log_warning "2. Use: aws organizations delete-organization"
        log_warning "3. Or delete through the AWS Console"
        echo
        log_info "Note: Organizations with member accounts cannot be deleted."
        log_info "You must first close or move all member accounts."
    fi
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate that resources were deleted"
        return 0
    fi
    
    local issues=0
    
    # Check if SCPs still exist
    local remaining_scps
    remaining_scps=$(aws organizations list-policies \
        --filter SERVICE_CONTROL_POLICY \
        --query "Policies[?Name=='CostControlPolicy' || Name=='SecurityBaselinePolicy' || Name=='RegionRestrictionPolicy'].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_scps" ]]; then
        log_warning "Some SCPs still exist: $remaining_scps"
        ((issues++))
    fi
    
    # Check CloudTrail
    if aws cloudtrail describe-trails --query "trailList[?Name=='OrganizationTrail']" --output text 2>/dev/null | grep -q .; then
        log_warning "CloudTrail OrganizationTrail still exists"
        ((issues++))
    fi
    
    # Check CloudWatch dashboard
    if aws cloudwatch list-dashboards --query "DashboardEntries[?DashboardName=='OrganizationGovernance']" --output text 2>/dev/null | grep -q .; then
        log_warning "CloudWatch dashboard OrganizationGovernance still exists"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "Cleanup validation completed - no issues found"
    else
        log_warning "Cleanup validation found $issues issues"
    fi
}

# Main cleanup function
main() {
    log_info "Starting AWS Multi-Account Governance cleanup..."
    log_info "Log file: $LOG_FILE"
    
    parse_args "$@"
    check_prerequisites
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS region not set. Use --region option or configure AWS CLI."
    fi
    
    load_deployment_state
    confirm_cleanup
    
    # Core cleanup steps
    cleanup_service_control_policies
    cleanup_cloudtrail_and_monitoring
    cleanup_budgets
    cleanup_organizational_units
    cleanup_local_files
    warn_about_organization
    
    # Validation
    validate_cleanup
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed. No resources were deleted."
        log_info "Run without --dry-run to perform the actual cleanup."
    else
        log_success "Multi-Account Governance cleanup completed!"
        log_warning "Remember to manually delete the organization if no longer needed."
    fi
}

# Run main function with all arguments
main "$@"