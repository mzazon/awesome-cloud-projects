#!/bin/bash

# Cost-Aware Resource Lifecycle Cleanup Script
# Safely removes MemoryDB cluster, Lambda function, EventBridge Scheduler, and associated resources
# Version: 1.0

set -euo pipefail

# Enable debug mode if requested
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -x
fi

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMP_DIR="/tmp/memorydb-cleanup-$$"
readonly LOG_FILE="/tmp/memorydb-cleanup-$(date +%Y%m%d-%H%M%S).log"

# Default values
DRY_RUN=${DRY_RUN:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
FORCE_DELETE=${FORCE_DELETE:-false}

# Cleanup function
cleanup() {
    local exit_code=$?
    log_info "Cleaning up temporary resources..."
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Cleanup completed successfully. Log file: ${LOG_FILE}"
    else
        log_error "Cleanup failed with exit code $exit_code. Check log file: ${LOG_FILE}"
    fi
    
    exit $exit_code
}

trap cleanup EXIT

# Initialize logging
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to discover resources
discover_resources() {
    log_info "Discovering cost optimization resources..."
    
    # Set AWS environment
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable."
        exit 1
    fi
    
    # Create temporary directory for resource discovery
    mkdir -p "$TEMP_DIR"
    
    # Discover MemoryDB clusters with cost-aware naming pattern
    log_info "Discovering MemoryDB clusters..."
    aws memorydb describe-clusters \
        --query 'Clusters[?contains(ClusterName, `cost-aware-memorydb`)].{Name:ClusterName,Status:Status,NodeType:NodeType}' \
        --output table > "$TEMP_DIR/memorydb_clusters.txt" 2>/dev/null || echo "No MemoryDB clusters found" > "$TEMP_DIR/memorydb_clusters.txt"
    
    # Discover Lambda functions with cost optimization pattern
    log_info "Discovering Lambda functions..."
    aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `memorydb-cost-optimizer`)].{Name:FunctionName,Runtime:Runtime,LastModified:LastModified}' \
        --output table > "$TEMP_DIR/lambda_functions.txt" 2>/dev/null || echo "No Lambda functions found" > "$TEMP_DIR/lambda_functions.txt"
    
    # Discover EventBridge Scheduler groups
    log_info "Discovering EventBridge Scheduler groups..."
    aws scheduler list-schedule-groups \
        --query 'ScheduleGroups[?contains(Name, `cost-optimization-schedules`)].{Name:Name,State:State,CreationDate:CreationDate}' \
        --output table > "$TEMP_DIR/scheduler_groups.txt" 2>/dev/null || echo "No scheduler groups found" > "$TEMP_DIR/scheduler_groups.txt"
    
    # Discover IAM roles
    log_info "Discovering IAM roles..."
    aws iam list-roles \
        --query 'Roles[?contains(RoleName, `memorydb-cost-optimizer`) || contains(RoleName, `eventbridge-scheduler-role`)].{Name:RoleName,CreateDate:CreateDate}' \
        --output table > "$TEMP_DIR/iam_roles.txt" 2>/dev/null || echo "No IAM roles found" > "$TEMP_DIR/iam_roles.txt"
    
    # Discover CloudWatch dashboards
    log_info "Discovering CloudWatch dashboards..."
    aws cloudwatch list-dashboards \
        --query 'DashboardEntries[?contains(DashboardName, `MemoryDB-Cost-Optimization`)].{Name:DashboardName,LastModified:LastModified}' \
        --output table > "$TEMP_DIR/dashboards.txt" 2>/dev/null || echo "No dashboards found" > "$TEMP_DIR/dashboards.txt"
    
    # Discover CloudWatch alarms
    log_info "Discovering CloudWatch alarms..."
    aws cloudwatch describe-alarms \
        --query 'MetricAlarms[?contains(AlarmName, `MemoryDB-`) || contains(AlarmName, `memorydb-`)].{Name:AlarmName,State:StateValue}' \
        --output table > "$TEMP_DIR/alarms.txt" 2>/dev/null || echo "No alarms found" > "$TEMP_DIR/alarms.txt"
    
    # Discover budgets
    log_info "Discovering budgets..."
    aws budgets describe-budgets --account-id "$AWS_ACCOUNT_ID" \
        --query 'Budgets[?contains(BudgetName, `MemoryDB-Cost-Budget`)].{Name:BudgetName,BudgetLimit:BudgetLimit}' \
        --output table > "$TEMP_DIR/budgets.txt" 2>/dev/null || echo "No budgets found" > "$TEMP_DIR/budgets.txt"
    
    log_success "Resource discovery completed"
}

# Function to display discovered resources
display_resources() {
    log_info "Discovered Resources Summary:"
    echo "=================================="
    
    echo "MemoryDB Clusters:"
    cat "$TEMP_DIR/memorydb_clusters.txt"
    echo ""
    
    echo "Lambda Functions:"
    cat "$TEMP_DIR/lambda_functions.txt"
    echo ""
    
    echo "EventBridge Scheduler Groups:"
    cat "$TEMP_DIR/scheduler_groups.txt"
    echo ""
    
    echo "IAM Roles:"
    cat "$TEMP_DIR/iam_roles.txt"
    echo ""
    
    echo "CloudWatch Dashboards:"
    cat "$TEMP_DIR/dashboards.txt"
    echo ""
    
    echo "CloudWatch Alarms:"
    cat "$TEMP_DIR/alarms.txt"
    echo ""
    
    echo "Budgets:"
    cat "$TEMP_DIR/budgets.txt"
    echo ""
    
    echo "=================================="
}

# Function to get user confirmation for specific resources
get_cleanup_confirmation() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo "The following resources will be deleted:"
    display_resources
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force delete mode enabled - proceeding without confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to delete ALL these resources? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Last chance - type 'YES' to proceed with deletion: " final_confirmation
    
    if [[ "$final_confirmation" != "YES" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete EventBridge Scheduler resources
delete_scheduler_resources() {
    log_info "Removing EventBridge Scheduler resources..."
    
    # Get list of scheduler groups with cost optimization pattern
    local scheduler_groups=$(aws scheduler list-schedule-groups \
        --query 'ScheduleGroups[?contains(Name, `cost-optimization-schedules`)].Name' \
        --output text 2>/dev/null || echo "")
    
    for group in $scheduler_groups; do
        if [[ -z "$group" ]]; then
            continue
        fi
        
        log_info "Processing scheduler group: $group"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete schedules in group: $group"
            continue
        fi
        
        # Delete all schedules in the group
        local schedules=$(aws scheduler list-schedules --group-name "$group" \
            --query 'Schedules[].Name' --output text 2>/dev/null || echo "")
        
        for schedule in $schedules; do
            if [[ -n "$schedule" ]]; then
                log_info "Deleting schedule: $schedule"
                aws scheduler delete-schedule \
                    --name "$schedule" \
                    --group-name "$group" \
                    2>/dev/null || log_warning "Failed to delete schedule: $schedule"
            fi
        done
        
        # Delete the scheduler group
        log_info "Deleting scheduler group: $group"
        aws scheduler delete-schedule-group \
            --name "$group" \
            2>/dev/null || log_warning "Failed to delete scheduler group: $group"
        
        log_success "Deleted scheduler group: $group"
    done
    
    if [[ -z "$scheduler_groups" ]]; then
        log_info "No EventBridge Scheduler groups found to delete"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Removing monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete monitoring resources"
        return 0
    fi
    
    # Delete CloudWatch dashboards
    local dashboards=$(aws cloudwatch list-dashboards \
        --query 'DashboardEntries[?contains(DashboardName, `MemoryDB-Cost-Optimization`)].DashboardName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        for dashboard in $dashboards; do
            log_info "Deleting dashboard: $dashboard"
            aws cloudwatch delete-dashboards \
                --dashboard-names "$dashboard" \
                2>/dev/null || log_warning "Failed to delete dashboard: $dashboard"
        done
        log_success "Deleted CloudWatch dashboards"
    fi
    
    # Delete CloudWatch alarms
    local alarms=$(aws cloudwatch describe-alarms \
        --query 'MetricAlarms[?contains(AlarmName, `MemoryDB-`) || contains(AlarmName, `memorydb-`)].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$alarms" ]]; then
        log_info "Deleting CloudWatch alarms..."
        aws cloudwatch delete-alarms --alarm-names $alarms \
            2>/dev/null || log_warning "Failed to delete some alarms"
        log_success "Deleted CloudWatch alarms"
    fi
    
    # Delete budgets
    local budgets=$(aws budgets describe-budgets --account-id "$AWS_ACCOUNT_ID" \
        --query 'Budgets[?contains(BudgetName, `MemoryDB-Cost-Budget`)].BudgetName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$budgets" ]]; then
        for budget in $budgets; do
            log_info "Deleting budget: $budget"
            aws budgets delete-budget \
                --account-id "$AWS_ACCOUNT_ID" \
                --budget-name "$budget" \
                2>/dev/null || log_warning "Failed to delete budget: $budget"
        done
        log_success "Deleted budgets"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log_info "Removing Lambda functions..."
    
    # Get Lambda functions with cost optimizer pattern
    local lambda_functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `memorydb-cost-optimizer`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$lambda_functions" ]]; then
        log_info "No Lambda functions found to delete"
        return 0
    fi
    
    for function_name in $lambda_functions; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Lambda function: $function_name"
            continue
        fi
        
        log_info "Deleting Lambda function: $function_name"
        aws lambda delete-function \
            --function-name "$function_name" \
            2>/dev/null || log_warning "Failed to delete Lambda function: $function_name"
        
        log_success "Deleted Lambda function: $function_name"
    done
}

# Function to delete IAM resources
delete_iam_resources() {
    log_info "Removing IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete IAM resources"
        return 0
    fi
    
    # Get IAM roles related to cost optimization
    local iam_roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `memorydb-cost-optimizer`) || contains(RoleName, `eventbridge-scheduler-role`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    for role_name in $iam_roles; do
        if [[ -z "$role_name" ]]; then
            continue
        fi
        
        log_info "Processing IAM role: $role_name"
        
        # Detach managed policies
        local attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $attached_policies; do
            if [[ -n "$policy_arn" ]]; then
                log_info "Detaching policy: $policy_arn"
                aws iam detach-role-policy \
                    --role-name "$role_name" \
                    --policy-arn "$policy_arn" \
                    2>/dev/null || log_warning "Failed to detach policy: $policy_arn"
            fi
        done
        
        # Delete inline policies
        local inline_policies=$(aws iam list-role-policies \
            --role-name "$role_name" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $inline_policies; do
            if [[ -n "$policy_name" ]]; then
                log_info "Deleting inline policy: $policy_name"
                aws iam delete-role-policy \
                    --role-name "$role_name" \
                    --policy-name "$policy_name" \
                    2>/dev/null || log_warning "Failed to delete inline policy: $policy_name"
            fi
        done
        
        # Delete the role
        log_info "Deleting IAM role: $role_name"
        aws iam delete-role \
            --role-name "$role_name" \
            2>/dev/null || log_warning "Failed to delete IAM role: $role_name"
        
        log_success "Deleted IAM role: $role_name"
    done
    
    # Delete custom policies
    local custom_policies=$(aws iam list-policies \
        --scope Local \
        --query 'Policies[?contains(PolicyName, `memorydb-cost-optimizer`) || contains(PolicyName, `scheduler-lambda-invoke`)].{Name:PolicyName,Arn:Arn}' \
        --output json 2>/dev/null || echo '[]')
    
    if [[ "$custom_policies" != "[]" ]]; then
        echo "$custom_policies" | jq -r '.[] | @base64' | while IFS= read -r policy_data; do
            local policy_json=$(echo "$policy_data" | base64 -d)
            local policy_name=$(echo "$policy_json" | jq -r '.Name')
            local policy_arn=$(echo "$policy_json" | jq -r '.Arn')
            
            log_info "Deleting custom policy: $policy_name"
            aws iam delete-policy \
                --policy-arn "$policy_arn" \
                2>/dev/null || log_warning "Failed to delete policy: $policy_name"
        done
        
        log_success "Deleted custom IAM policies"
    fi
}

# Function to delete MemoryDB resources
delete_memorydb_resources() {
    log_info "Removing MemoryDB resources..."
    
    # Get MemoryDB clusters with cost-aware pattern
    local memorydb_clusters=$(aws memorydb describe-clusters \
        --query 'Clusters[?contains(ClusterName, `cost-aware-memorydb`)].ClusterName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$memorydb_clusters" ]]; then
        log_info "No MemoryDB clusters found to delete"
    else
        for cluster_name in $memorydb_clusters; do
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete MemoryDB cluster: $cluster_name"
                continue
            fi
            
            log_info "Deleting MemoryDB cluster: $cluster_name (this may take several minutes)"
            
            # Check cluster status before deletion
            local cluster_status=$(aws memorydb describe-clusters \
                --cluster-name "$cluster_name" \
                --query 'Clusters[0].Status' \
                --output text 2>/dev/null || echo "unknown")
            
            if [[ "$cluster_status" == "available" || "$cluster_status" == "modifying" ]]; then
                aws memorydb delete-cluster \
                    --cluster-name "$cluster_name" \
                    --no-final-snapshot \
                    2>/dev/null || log_warning "Failed to initiate cluster deletion: $cluster_name"
                
                log_success "Initiated deletion of MemoryDB cluster: $cluster_name"
                
                # Wait for cluster deletion with timeout
                local timeout=900  # 15 minutes
                local elapsed=0
                local interval=30
                
                log_info "Waiting for cluster deletion to complete..."
                while [[ $elapsed -lt $timeout ]]; do
                    if ! aws memorydb describe-clusters --cluster-name "$cluster_name" &> /dev/null; then
                        log_success "MemoryDB cluster deleted: $cluster_name"
                        break
                    fi
                    
                    local current_status=$(aws memorydb describe-clusters \
                        --cluster-name "$cluster_name" \
                        --query 'Clusters[0].Status' \
                        --output text 2>/dev/null || echo "deleted")
                    
                    if [[ "$current_status" == "deleted" ]]; then
                        log_success "MemoryDB cluster deleted: $cluster_name"
                        break
                    fi
                    
                    log_info "Cluster status: $current_status (waiting ${interval}s...)"
                    sleep $interval
                    elapsed=$((elapsed + interval))
                done
                
                if [[ $elapsed -ge $timeout ]]; then
                    log_warning "Timeout waiting for cluster deletion. Check AWS Console for status."
                fi
            else
                log_warning "Cluster $cluster_name is in $cluster_status state, cannot delete"
            fi
        done
    fi
    
    # Delete subnet groups
    log_info "Cleaning up MemoryDB subnet groups..."
    local subnet_groups=$(aws memorydb describe-subnet-groups \
        --query 'SubnetGroups[?contains(SubnetGroupName, `cost-aware-memorydb`)].SubnetGroupName' \
        --output text 2>/dev/null || echo "")
    
    for subnet_group in $subnet_groups; do
        if [[ -n "$subnet_group" && "$DRY_RUN" == "false" ]]; then
            log_info "Deleting subnet group: $subnet_group"
            aws memorydb delete-subnet-group \
                --subnet-group-name "$subnet_group" \
                2>/dev/null || log_warning "Failed to delete subnet group: $subnet_group"
        elif [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete subnet group: $subnet_group"
        fi
    done
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up temporary files"
        return 0
    fi
    
    # Remove any lambda packages or temporary files that might exist
    rm -f /tmp/lambda-response.json 2>/dev/null || true
    rm -f /tmp/scale-test.json 2>/dev/null || true
    rm -f /tmp/lambda-test-response.json 2>/dev/null || true
    rm -rf /tmp/lambda-package* 2>/dev/null || true
    rm -f /tmp/lambda-function.zip 2>/dev/null || true
    
    log_success "Cleaned up temporary files"
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating resource cleanup..."
    
    local validation_errors=0
    
    # Check if MemoryDB clusters still exist
    local remaining_clusters=$(aws memorydb describe-clusters \
        --query 'Clusters[?contains(ClusterName, `cost-aware-memorydb`)].ClusterName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_clusters" ]]; then
        log_warning "Some MemoryDB clusters may still exist: $remaining_clusters"
        validation_errors=$((validation_errors + 1))
    else
        log_success "No MemoryDB clusters remain"
    fi
    
    # Check Lambda functions
    local remaining_functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `memorydb-cost-optimizer`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_functions" ]]; then
        log_warning "Some Lambda functions may still exist: $remaining_functions"
        validation_errors=$((validation_errors + 1))
    else
        log_success "No Lambda functions remain"
    fi
    
    # Check EventBridge Scheduler groups
    local remaining_groups=$(aws scheduler list-schedule-groups \
        --query 'ScheduleGroups[?contains(Name, `cost-optimization-schedules`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_groups" ]]; then
        log_warning "Some scheduler groups may still exist: $remaining_groups"
        validation_errors=$((validation_errors + 1))
    else
        log_success "No scheduler groups remain"
    fi
    
    # Check IAM roles
    local remaining_roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `memorydb-cost-optimizer`) || contains(RoleName, `eventbridge-scheduler-role`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_roles" ]]; then
        log_warning "Some IAM roles may still exist: $remaining_roles"
        validation_errors=$((validation_errors + 1))
    else
        log_success "No IAM roles remain"
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "Cleanup validation completed successfully"
    else
        log_warning "Cleanup validation found $validation_errors potential issues"
    fi
    
    return $validation_errors
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "=================================="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN MODE - No resources were actually deleted"
    else
        echo "Deleted Resources:"
        echo "  ✓ MemoryDB clusters and subnet groups"
        echo "  ✓ Lambda functions"
        echo "  ✓ EventBridge Scheduler groups and schedules"
        echo "  ✓ IAM roles and policies"
        echo "  ✓ CloudWatch dashboards and alarms"
        echo "  ✓ Budget alerts"
        echo "  ✓ Temporary files"
    fi
    echo ""
    echo "Log File: $LOG_FILE"
    echo "=================================="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "All cost optimization resources have been removed"
        log_info "Check your AWS bill to confirm charges have stopped"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Cost-Aware Resource Lifecycle Cleanup"
    log_info "==============================================="
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --dry-run              Show what would be deleted without making changes"
                echo "  --skip-confirmation    Skip confirmation prompts"
                echo "  --force                Force deletion without confirmation (dangerous!)"
                echo "  --help                 Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Show cleanup configuration
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "FORCE DELETE MODE - Resources will be deleted without confirmation"
    fi
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Execute cleanup steps
    check_prerequisites
    discover_resources
    get_cleanup_confirmation
    
    # Delete resources in reverse order of creation
    delete_scheduler_resources
    delete_monitoring_resources
    delete_lambda_functions
    delete_iam_resources
    delete_memorydb_resources
    cleanup_temp_files
    
    if [[ "$DRY_RUN" == "false" ]]; then
        validate_cleanup
    fi
    
    display_cleanup_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Cleanup completed successfully!"
        log_info "All cost optimization resources have been removed from your AWS account."
    else
        log_info "Dry run completed. Use --skip-confirmation to proceed with actual deletion."
    fi
}

# Run main function with all arguments
main "$@"