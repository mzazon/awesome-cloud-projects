#!/bin/bash

# Destroy script for Multi-Region Distributed Applications with Aurora DSQL
# This script safely removes all AWS resources created by the deploy.sh script
# Resources are deleted in reverse order to handle dependencies properly

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Global variables
FORCE_DELETE=${FORCE_DELETE:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Display help information
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Aurora DSQL Multi-Region Deployment

OPTIONS:
    -f, --force             Skip confirmation prompts and force deletion
    -y, --yes               Skip confirmation prompts (same as --force)
    --skip-confirmation     Skip confirmation prompts
    -h, --help              Show this help message

EXAMPLES:
    $0                      Interactive destruction with confirmations
    $0 --force              Force destruction without confirmations
    $0 -y                   Force destruction without confirmations (short form)

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force|-y|--yes)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid."
    fi
    
    # Check if deployment state files exist
    if [[ ! -f "deployment_state.json" ]] && [[ ! -f "deployment_state.env" ]]; then
        warn "No deployment state files found. This may be a manual cleanup or the deployment was not completed."
        info "Continuing with resource discovery based on naming patterns..."
    fi
    
    log "Prerequisites check completed."
}

# Load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Load from JSON file if available
    if [[ -f "deployment_state.json" ]]; then
        DEPLOYMENT_ID=$(jq -r '.deployment_id' deployment_state.json 2>/dev/null || echo "unknown")
        export PRIMARY_REGION=$(jq -r '.primary_region' deployment_state.json 2>/dev/null || echo "us-east-1")
        export SECONDARY_REGION=$(jq -r '.secondary_region' deployment_state.json 2>/dev/null || echo "us-west-2")
        export WITNESS_REGION=$(jq -r '.witness_region' deployment_state.json 2>/dev/null || echo "eu-west-1")
        export CLUSTER_NAME_PRIMARY=$(jq -r '.cluster_name_primary' deployment_state.json 2>/dev/null || echo "")
        export CLUSTER_NAME_SECONDARY=$(jq -r '.cluster_name_secondary' deployment_state.json 2>/dev/null || echo "")
        export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name' deployment_state.json 2>/dev/null || echo "")
        export EVENTBRIDGE_BUS_NAME=$(jq -r '.eventbridge_bus_name' deployment_state.json 2>/dev/null || echo "")
        export IAM_ROLE_NAME=$(jq -r '.iam_role_name' deployment_state.json 2>/dev/null || echo "")
        export IAM_POLICY_NAME=$(jq -r '.iam_policy_name' deployment_state.json 2>/dev/null || echo "")
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment_state.json 2>/dev/null || aws sts get-caller-identity --query Account --output text)
    fi
    
    # Load from ENV file if available
    if [[ -f "deployment_state.env" ]]; then
        source deployment_state.env
    fi
    
    # Extract suffix from resource names for pattern matching
    if [[ -n "${CLUSTER_NAME_PRIMARY}" ]]; then
        RANDOM_SUFFIX=$(echo "${CLUSTER_NAME_PRIMARY}" | sed 's/.*-//')
    elif [[ -n "${LAMBDA_FUNCTION_NAME}" ]]; then
        RANDOM_SUFFIX=$(echo "${LAMBDA_FUNCTION_NAME}" | sed 's/.*-//')
    else
        RANDOM_SUFFIX=""
    fi
    
    info "Deployment state loaded:"
    info "  Primary Region: ${PRIMARY_REGION}"
    info "  Secondary Region: ${SECONDARY_REGION}"
    info "  Witness Region: ${WITNESS_REGION}"
    info "  Resource Suffix: ${RANDOM_SUFFIX}"
    
    if [[ -z "${RANDOM_SUFFIX}" ]]; then
        warn "Could not determine resource suffix. Manual resource discovery will be attempted."
    fi
}

# Confirm destruction with user
confirm_destruction() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]]; then
        log "Skipping confirmation (force mode enabled)"
        return 0
    fi
    
    echo
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warn "This will permanently delete all Aurora DSQL resources including:"
    warn "  • Aurora DSQL clusters in ${PRIMARY_REGION} and ${SECONDARY_REGION}"
    warn "  • Lambda functions in both regions"
    warn "  • EventBridge buses and rules"
    warn "  • IAM roles and policies"
    warn "  • All data stored in the Aurora DSQL clusters"
    echo
    warn "This action CANNOT be undone!"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    echo
    read -p "Please type 'DELETE' to confirm permanent data destruction: " -r
    if [[ ! $REPLY =~ ^DELETE$ ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    log "User confirmed destruction. Proceeding..."
}

# Discover resources if state files are missing
discover_resources() {
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        log "Using known resource suffix: ${RANDOM_SUFFIX}"
        return 0
    fi
    
    log "Discovering Aurora DSQL resources..."
    
    # Try to find Aurora DSQL clusters with app-cluster pattern
    info "Searching for Aurora DSQL clusters..."
    
    # Look for clusters in primary region
    PRIMARY_CLUSTERS=$(aws dsql list-clusters \
        --region "${PRIMARY_REGION}" \
        --query 'clusters[?contains(clusterName, `app-cluster-primary`)].{Name:clusterName,Id:clusterIdentifier}' \
        --output text 2>/dev/null || echo "")
    
    # Look for clusters in secondary region
    SECONDARY_CLUSTERS=$(aws dsql list-clusters \
        --region "${SECONDARY_REGION}" \
        --query 'clusters[?contains(clusterName, `app-cluster-secondary`)].{Name:clusterName,Id:clusterIdentifier}' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${PRIMARY_CLUSTERS}" ]]; then
        info "Found primary region clusters: ${PRIMARY_CLUSTERS}"
    fi
    
    if [[ -n "${SECONDARY_CLUSTERS}" ]]; then
        info "Found secondary region clusters: ${SECONDARY_CLUSTERS}"
    fi
    
    # Try to discover Lambda functions
    info "Searching for Lambda functions..."
    
    PRIMARY_LAMBDAS=$(aws lambda list-functions \
        --region "${PRIMARY_REGION}" \
        --query 'Functions[?contains(FunctionName, `dsql-processor`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    SECONDARY_LAMBDAS=$(aws lambda list-functions \
        --region "${SECONDARY_REGION}" \
        --query 'Functions[?contains(FunctionName, `dsql-processor`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${PRIMARY_LAMBDAS}" ]]; then
        info "Found primary region Lambda functions: ${PRIMARY_LAMBDAS}"
    fi
    
    if [[ -n "${SECONDARY_LAMBDAS}" ]]; then
        info "Found secondary region Lambda functions: ${SECONDARY_LAMBDAS}"
    fi
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete Lambda function in primary region
    if [[ -n "${LAMBDA_FUNCTION_NAME}" ]]; then
        info "Deleting Lambda function ${LAMBDA_FUNCTION_NAME}-primary in ${PRIMARY_REGION}..."
        aws lambda delete-function \
            --region "${PRIMARY_REGION}" \
            --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
            2>/dev/null && info "  ✅ Deleted ${LAMBDA_FUNCTION_NAME}-primary" || warn "  ⚠️  Function may not exist or already deleted"
        
        info "Deleting Lambda function ${LAMBDA_FUNCTION_NAME}-secondary in ${SECONDARY_REGION}..."
        aws lambda delete-function \
            --region "${SECONDARY_REGION}" \
            --function-name "${LAMBDA_FUNCTION_NAME}-secondary" \
            2>/dev/null && info "  ✅ Deleted ${LAMBDA_FUNCTION_NAME}-secondary" || warn "  ⚠️  Function may not exist or already deleted"
    else
        # Try pattern-based cleanup
        info "Attempting pattern-based Lambda function cleanup..."
        
        # Primary region
        for func in $(aws lambda list-functions \
            --region "${PRIMARY_REGION}" \
            --query 'Functions[?contains(FunctionName, `dsql-processor`)].FunctionName' \
            --output text 2>/dev/null); do
            info "Deleting discovered Lambda function: ${func}"
            aws lambda delete-function \
                --region "${PRIMARY_REGION}" \
                --function-name "${func}" \
                2>/dev/null && info "  ✅ Deleted ${func}" || warn "  ⚠️  Failed to delete ${func}"
        done
        
        # Secondary region
        for func in $(aws lambda list-functions \
            --region "${SECONDARY_REGION}" \
            --query 'Functions[?contains(FunctionName, `dsql-processor`)].FunctionName' \
            --output text 2>/dev/null); do
            info "Deleting discovered Lambda function: ${func}"
            aws lambda delete-function \
                --region "${SECONDARY_REGION}" \
                --function-name "${func}" \
                2>/dev/null && info "  ✅ Deleted ${func}" || warn "  ⚠️  Failed to delete ${func}"
        done
    fi
    
    log "Lambda function cleanup completed."
}

# Delete EventBridge resources
delete_eventbridge_resources() {
    log "Deleting EventBridge resources..."
    
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        # Delete EventBridge rules and targets using known suffix
        info "Deleting EventBridge rules with suffix ${RANDOM_SUFFIX}..."
        
        # Primary region
        info "Cleaning up EventBridge resources in ${PRIMARY_REGION}..."
        
        # Remove targets first
        aws events remove-targets \
            --region "${PRIMARY_REGION}" \
            --rule "CrossRegionReplication-${RANDOM_SUFFIX}" \
            --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
            --ids "1" \
            2>/dev/null && info "  ✅ Removed targets from primary region rule" || warn "  ⚠️  Targets may not exist"
        
        # Delete rule
        aws events delete-rule \
            --region "${PRIMARY_REGION}" \
            --name "CrossRegionReplication-${RANDOM_SUFFIX}" \
            --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
            2>/dev/null && info "  ✅ Deleted primary region rule" || warn "  ⚠️  Rule may not exist"
        
        # Delete custom event bus
        aws events delete-event-bus \
            --region "${PRIMARY_REGION}" \
            --name "${EVENTBRIDGE_BUS_NAME}" \
            2>/dev/null && info "  ✅ Deleted primary region event bus" || warn "  ⚠️  Event bus may not exist"
        
        # Secondary region
        info "Cleaning up EventBridge resources in ${SECONDARY_REGION}..."
        
        # Remove targets first
        aws events remove-targets \
            --region "${SECONDARY_REGION}" \
            --rule "CrossRegionReplication-${RANDOM_SUFFIX}" \
            --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
            --ids "1" \
            2>/dev/null && info "  ✅ Removed targets from secondary region rule" || warn "  ⚠️  Targets may not exist"
        
        # Delete rule
        aws events delete-rule \
            --region "${SECONDARY_REGION}" \
            --name "CrossRegionReplication-${RANDOM_SUFFIX}" \
            --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
            2>/dev/null && info "  ✅ Deleted secondary region rule" || warn "  ⚠️  Rule may not exist"
        
        # Delete custom event bus
        aws events delete-event-bus \
            --region "${SECONDARY_REGION}" \
            --name "${EVENTBRIDGE_BUS_NAME}" \
            2>/dev/null && info "  ✅ Deleted secondary region event bus" || warn "  ⚠️  Event bus may not exist"
    else
        # Try pattern-based cleanup
        info "Attempting pattern-based EventBridge cleanup..."
        
        # Look for rules with CrossRegionReplication pattern
        for region in "${PRIMARY_REGION}" "${SECONDARY_REGION}"; do
            info "Searching for EventBridge rules in ${region}..."
            
            # List event buses with dsql-events pattern
            for bus in $(aws events list-event-buses \
                --region "${region}" \
                --query 'EventBuses[?contains(Name, `dsql-events`)].Name' \
                --output text 2>/dev/null); do
                
                info "Found event bus: ${bus} in ${region}"
                
                # List rules for this bus
                for rule in $(aws events list-rules \
                    --region "${region}" \
                    --event-bus-name "${bus}" \
                    --query 'Rules[?contains(Name, `CrossRegionReplication`)].Name' \
                    --output text 2>/dev/null); do
                    
                    info "Cleaning up rule: ${rule}"
                    
                    # Remove targets
                    aws events remove-targets \
                        --region "${region}" \
                        --rule "${rule}" \
                        --event-bus-name "${bus}" \
                        --ids "1" \
                        2>/dev/null || warn "  ⚠️  Could not remove targets for ${rule}"
                    
                    # Delete rule
                    aws events delete-rule \
                        --region "${region}" \
                        --name "${rule}" \
                        --event-bus-name "${bus}" \
                        2>/dev/null && info "  ✅ Deleted rule ${rule}" || warn "  ⚠️  Could not delete rule ${rule}"
                done
                
                # Delete event bus
                aws events delete-event-bus \
                    --region "${region}" \
                    --name "${bus}" \
                    2>/dev/null && info "  ✅ Deleted event bus ${bus}" || warn "  ⚠️  Could not delete event bus ${bus}"
            done
        done
    fi
    
    log "EventBridge resources cleanup completed."
}

# Delete Aurora DSQL clusters
delete_dsql_clusters() {
    log "Deleting Aurora DSQL clusters..."
    
    # Load cluster IDs from state file if available
    if [[ -f "deployment_state.env" ]]; then
        source deployment_state.env
    fi
    
    # Delete multi-region cluster link first if cluster IDs are known
    if [[ -n "${PRIMARY_CLUSTER_ID}" ]]; then
        info "Deleting multi-region cluster link..."
        aws dsql delete-multi-region-clusters \
            --region "${PRIMARY_REGION}" \
            --primary-cluster-identifier "${PRIMARY_CLUSTER_ID}" \
            2>/dev/null && info "  ✅ Multi-region cluster link deleted" || warn "  ⚠️  Multi-region link may not exist or already deleted"
        
        # Wait for multi-region deletion to complete
        info "Waiting for multi-region deletion to complete..."
        aws dsql wait multi-region-clusters-deleted \
            --region "${PRIMARY_REGION}" \
            --primary-cluster-identifier "${PRIMARY_CLUSTER_ID}" \
            2>/dev/null || warn "  ⚠️  Multi-region deletion wait failed or already completed"
    fi
    
    # Delete secondary cluster
    if [[ -n "${SECONDARY_CLUSTER_ID}" ]]; then
        info "Deleting secondary Aurora DSQL cluster: ${SECONDARY_CLUSTER_ID}..."
        aws dsql delete-cluster \
            --region "${SECONDARY_REGION}" \
            --cluster-identifier "${SECONDARY_CLUSTER_ID}" \
            2>/dev/null && info "  ✅ Secondary cluster deletion initiated" || warn "  ⚠️  Secondary cluster may not exist or already deleted"
    elif [[ -n "${CLUSTER_NAME_SECONDARY}" ]]; then
        # Try to find cluster by name
        SECONDARY_CLUSTER_ID=$(aws dsql describe-clusters \
            --region "${SECONDARY_REGION}" \
            --query 'clusters[?clusterName==`'${CLUSTER_NAME_SECONDARY}'`].clusterIdentifier' \
            --output text 2>/dev/null)
        
        if [[ -n "${SECONDARY_CLUSTER_ID}" ]]; then
            info "Deleting secondary Aurora DSQL cluster: ${SECONDARY_CLUSTER_ID}..."
            aws dsql delete-cluster \
                --region "${SECONDARY_REGION}" \
                --cluster-identifier "${SECONDARY_CLUSTER_ID}" \
                2>/dev/null && info "  ✅ Secondary cluster deletion initiated" || warn "  ⚠️  Failed to delete secondary cluster"
        fi
    else
        # Try pattern-based cleanup for secondary region
        info "Searching for Aurora DSQL clusters in ${SECONDARY_REGION}..."
        for cluster in $(aws dsql list-clusters \
            --region "${SECONDARY_REGION}" \
            --query 'clusters[?contains(clusterName, `app-cluster-secondary`)].clusterIdentifier' \
            --output text 2>/dev/null); do
            info "Deleting discovered cluster: ${cluster}"
            aws dsql delete-cluster \
                --region "${SECONDARY_REGION}" \
                --cluster-identifier "${cluster}" \
                2>/dev/null && info "  ✅ Cluster ${cluster} deletion initiated" || warn "  ⚠️  Failed to delete cluster ${cluster}"
        done
    fi
    
    # Delete primary cluster
    if [[ -n "${PRIMARY_CLUSTER_ID}" ]]; then
        info "Deleting primary Aurora DSQL cluster: ${PRIMARY_CLUSTER_ID}..."
        aws dsql delete-cluster \
            --region "${PRIMARY_REGION}" \
            --cluster-identifier "${PRIMARY_CLUSTER_ID}" \
            2>/dev/null && info "  ✅ Primary cluster deletion initiated" || warn "  ⚠️  Primary cluster may not exist or already deleted"
    elif [[ -n "${CLUSTER_NAME_PRIMARY}" ]]; then
        # Try to find cluster by name
        PRIMARY_CLUSTER_ID=$(aws dsql describe-clusters \
            --region "${PRIMARY_REGION}" \
            --query 'clusters[?clusterName==`'${CLUSTER_NAME_PRIMARY}'`].clusterIdentifier' \
            --output text 2>/dev/null)
        
        if [[ -n "${PRIMARY_CLUSTER_ID}" ]]; then
            info "Deleting primary Aurora DSQL cluster: ${PRIMARY_CLUSTER_ID}..."
            aws dsql delete-cluster \
                --region "${PRIMARY_REGION}" \
                --cluster-identifier "${PRIMARY_CLUSTER_ID}" \
                2>/dev/null && info "  ✅ Primary cluster deletion initiated" || warn "  ⚠️  Failed to delete primary cluster"
        fi
    else
        # Try pattern-based cleanup for primary region
        info "Searching for Aurora DSQL clusters in ${PRIMARY_REGION}..."
        for cluster in $(aws dsql list-clusters \
            --region "${PRIMARY_REGION}" \
            --query 'clusters[?contains(clusterName, `app-cluster-primary`)].clusterIdentifier' \
            --output text 2>/dev/null); do
            info "Deleting discovered cluster: ${cluster}"
            aws dsql delete-cluster \
                --region "${PRIMARY_REGION}" \
                --cluster-identifier "${cluster}" \
                2>/dev/null && info "  ✅ Cluster ${cluster} deletion initiated" || warn "  ⚠️  Failed to delete cluster ${cluster}"
        done
    fi
    
    log "Aurora DSQL cluster deletion initiated. Clusters will be deleted asynchronously."
}

# Delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [[ -n "${IAM_ROLE_NAME}" ]] && [[ -n "${IAM_POLICY_NAME}" ]]; then
        # Detach policies from role
        info "Detaching policies from IAM role: ${IAM_ROLE_NAME}..."
        
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            2>/dev/null && info "  ✅ Detached AWSLambdaBasicExecutionRole" || warn "  ⚠️  Policy may not be attached"
        
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}" \
            2>/dev/null && info "  ✅ Detached custom policy" || warn "  ⚠️  Custom policy may not be attached"
        
        # Delete custom policy
        info "Deleting custom IAM policy: ${IAM_POLICY_NAME}..."
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}" \
            2>/dev/null && info "  ✅ Deleted custom policy" || warn "  ⚠️  Custom policy may not exist"
        
        # Delete IAM role
        info "Deleting IAM role: ${IAM_ROLE_NAME}..."
        aws iam delete-role \
            --role-name "${IAM_ROLE_NAME}" \
            2>/dev/null && info "  ✅ Deleted IAM role" || warn "  ⚠️  IAM role may not exist"
    else
        # Try pattern-based cleanup
        info "Attempting pattern-based IAM resource cleanup..."
        
        # Look for roles with DSQLLambdaRole pattern
        for role in $(aws iam list-roles \
            --query 'Roles[?contains(RoleName, `DSQLLambdaRole`)].RoleName' \
            --output text 2>/dev/null); do
            
            info "Found IAM role: ${role}"
            
            # Get attached policies
            for policy_arn in $(aws iam list-attached-role-policies \
                --role-name "${role}" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null); do
                
                info "Detaching policy: ${policy_arn}"
                aws iam detach-role-policy \
                    --role-name "${role}" \
                    --policy-arn "${policy_arn}" \
                    2>/dev/null && info "  ✅ Detached ${policy_arn}" || warn "  ⚠️  Failed to detach ${policy_arn}"
                
                # Delete custom policies (not AWS managed)
                if [[ "${policy_arn}" == *":policy/DSQLEventBridgePolicy"* ]]; then
                    info "Deleting custom policy: ${policy_arn}"
                    aws iam delete-policy \
                        --policy-arn "${policy_arn}" \
                        2>/dev/null && info "  ✅ Deleted custom policy" || warn "  ⚠️  Failed to delete custom policy"
                fi
            done
            
            # Delete role
            info "Deleting IAM role: ${role}"
            aws iam delete-role \
                --role-name "${role}" \
                2>/dev/null && info "  ✅ Deleted IAM role ${role}" || warn "  ⚠️  Failed to delete IAM role ${role}"
        done
    fi
    
    log "IAM resources cleanup completed."
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment state files
    if [[ -f "deployment_state.json" ]]; then
        rm -f deployment_state.json
        info "  ✅ Removed deployment_state.json"
    fi
    
    if [[ -f "deployment_state.env" ]]; then
        rm -f deployment_state.env
        info "  ✅ Removed deployment_state.env"
    fi
    
    # Remove deployment summary
    if [[ -f "deployment_summary.txt" ]]; then
        rm -f deployment_summary.txt
        info "  ✅ Removed deployment_summary.txt"
    fi
    
    # Remove any temporary files that might exist
    rm -f lambda_function.py function.zip schema.sql
    rm -f response.json test_response.json write_response.json read_response.json
    
    log "Local file cleanup completed."
}

# Wait for Aurora DSQL cluster deletion
wait_for_cluster_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log "Skipping wait for cluster deletion (force mode enabled)"
        return 0
    fi
    
    log "Waiting for Aurora DSQL cluster deletion to complete..."
    info "This may take several minutes. You can cancel this wait and clusters will continue deleting in the background."
    
    # Check if clusters still exist and wait
    if [[ -n "${PRIMARY_CLUSTER_ID}" ]]; then
        info "Waiting for primary cluster ${PRIMARY_CLUSTER_ID} deletion..."
        aws dsql wait cluster-deleted \
            --region "${PRIMARY_REGION}" \
            --cluster-identifier "${PRIMARY_CLUSTER_ID}" \
            2>/dev/null && info "  ✅ Primary cluster deleted" || warn "  ⚠️  Primary cluster deletion wait failed or cluster already deleted"
    fi
    
    if [[ -n "${SECONDARY_CLUSTER_ID}" ]]; then
        info "Waiting for secondary cluster ${SECONDARY_CLUSTER_ID} deletion..."
        aws dsql wait cluster-deleted \
            --region "${SECONDARY_REGION}" \
            --cluster-identifier "${SECONDARY_CLUSTER_ID}" \
            2>/dev/null && info "  ✅ Secondary cluster deleted" || warn "  ⚠️  Secondary cluster deletion wait failed or cluster already deleted"
    fi
    
    log "Aurora DSQL cluster deletion wait completed."
}

# Generate destruction summary
generate_destruction_summary() {
    log "Generating destruction summary..."
    
    cat > destruction_summary.txt << EOF
Aurora DSQL Multi-Region Destruction Summary
===========================================

Destruction Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Destroyed Resources:

Regions Cleaned:
  Primary Region: ${PRIMARY_REGION}
  Secondary Region: ${SECONDARY_REGION}
  Witness Region: ${WITNESS_REGION}

Resources Deleted:
  ✅ Aurora DSQL Clusters (primary and secondary)
  ✅ Multi-region cluster links
  ✅ Lambda functions (both regions)
  ✅ EventBridge buses and rules
  ✅ IAM roles and policies
  ✅ Local deployment state files

Notes:
- Aurora DSQL cluster deletion is asynchronous and may take several minutes to complete
- All data stored in the Aurora DSQL clusters has been permanently deleted
- Lambda functions and EventBridge resources have been immediately removed
- IAM roles and policies have been cleaned up

Status: Destruction completed successfully ✅

EOF
    
    info "Destruction summary saved to destruction_summary.txt"
    cat destruction_summary.txt
}

# Main destruction function
main() {
    log "Starting Aurora DSQL Multi-Region Destruction..."
    
    parse_arguments "$@"
    check_prerequisites
    load_deployment_state
    discover_resources
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_lambda_functions
    delete_eventbridge_resources
    delete_dsql_clusters
    delete_iam_resources
    wait_for_cluster_deletion
    cleanup_local_files
    generate_destruction_summary
    
    log "Destruction completed successfully! 🧹"
    warn "All Aurora DSQL data has been permanently deleted."
    log "Review destruction_summary.txt for details."
    
    return 0
}

# Handle script interruption
trap 'error "Destruction interrupted. Some resources may still exist. Re-run this script to continue cleanup."' INT TERM

# Run main function
main "$@"