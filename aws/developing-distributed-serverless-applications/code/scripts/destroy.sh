#!/bin/bash

# Aurora DSQL Multi-Region Application Cleanup Script
# This script safely removes all resources created by the deploy.sh script

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Configuration and defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.env"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log "ERROR" "Cleanup failed with exit code ${exit_code}"
    log "ERROR" "Some resources may still exist. Check the log file at ${LOG_FILE} for details"
    log "ERROR" "You may need to manually clean up remaining resources"
    exit $exit_code
}

# Trap errors
trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Aurora DSQL Multi-Region Application Cleanup Script

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    --dry-run              Show what would be deleted without actually deleting
    --force                Skip all confirmation prompts
    --config FILE          Use specific deployment info file (default: deployment-info.env)

Environment Variables:
    DRY_RUN               Set to 'true' for dry run mode
    FORCE                 Set to 'true' to skip confirmations

Examples:
    $0                                          # Interactive cleanup
    $0 --dry-run                               # Show what would be deleted
    $0 --force                                 # Delete everything without prompts
    DRY_RUN=true $0                           # Dry run via environment variable

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --config)
            DEPLOYMENT_INFO_FILE="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Load deployment information
load_deployment_info() {
    log "INFO" "Loading deployment information..."
    
    if [[ ! -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log "ERROR" "Deployment info file not found: ${DEPLOYMENT_INFO_FILE}"
        log "ERROR" "Cannot proceed without deployment information"
        log "ERROR" "If you know the resource names, you can create the file manually or use AWS CLI directly"
        exit 1
    fi
    
    # Source the deployment info file
    source "$DEPLOYMENT_INFO_FILE"
    
    log "INFO" "Loaded deployment information from: ${DEPLOYMENT_INFO_FILE}"
    log "DEBUG" "Primary Region: ${PRIMARY_REGION}"
    log "DEBUG" "Secondary Region: ${SECONDARY_REGION}"
    log "DEBUG" "Witness Region: ${WITNESS_REGION}"
    log "DEBUG" "Primary Cluster: ${CLUSTER_NAME_PRIMARY}"
    log "DEBUG" "Secondary Cluster: ${CLUSTER_NAME_SECONDARY}"
}

# Validation functions
validate_aws_cli() {
    log "INFO" "Validating AWS CLI..."
    
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    local aws_identity=$(aws sts get-caller-identity --query 'Arn' --output text)
    log "INFO" "Authenticated as: ${aws_identity}"
}

# Check if resource exists
resource_exists() {
    local resource_type=$1
    local region=$2
    local identifier=$3
    
    case $resource_type in
        "dsql-cluster")
            aws dsql get-cluster --region "$region" --cluster-identifier "$identifier" &> /dev/null
            ;;
        "lambda-function")
            aws lambda get-function --region "$region" --function-name "$identifier" &> /dev/null
            ;;
        "api-gateway")
            aws apigateway get-rest-api --region "$region" --rest-api-id "$identifier" &> /dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$identifier" &> /dev/null
            ;;
        "iam-policy")
            aws iam get-policy --policy-arn "$identifier" &> /dev/null
            ;;
        *)
            log "ERROR" "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Discover existing resources
discover_resources() {
    log "INFO" "Discovering existing resources..."
    
    # Track which resources exist
    declare -A EXISTING_RESOURCES
    
    # Check Aurora DSQL clusters
    if resource_exists "dsql-cluster" "$PRIMARY_REGION" "$CLUSTER_NAME_PRIMARY"; then
        EXISTING_RESOURCES["dsql-primary"]=true
        log "DEBUG" "Found primary Aurora DSQL cluster"
    fi
    
    if resource_exists "dsql-cluster" "$SECONDARY_REGION" "$CLUSTER_NAME_SECONDARY"; then
        EXISTING_RESOURCES["dsql-secondary"]=true
        log "DEBUG" "Found secondary Aurora DSQL cluster"
    fi
    
    # Check Lambda functions
    if resource_exists "lambda-function" "$PRIMARY_REGION" "${LAMBDA_FUNCTION_NAME}-primary"; then
        EXISTING_RESOURCES["lambda-primary"]=true
        log "DEBUG" "Found primary Lambda function"
    fi
    
    if resource_exists "lambda-function" "$SECONDARY_REGION" "${LAMBDA_FUNCTION_NAME}-secondary"; then
        EXISTING_RESOURCES["lambda-secondary"]=true
        log "DEBUG" "Found secondary Lambda function"
    fi
    
    # Check API Gateway instances
    if [[ -n "${PRIMARY_API_ID:-}" ]] && resource_exists "api-gateway" "$PRIMARY_REGION" "$PRIMARY_API_ID"; then
        EXISTING_RESOURCES["api-primary"]=true
        log "DEBUG" "Found primary API Gateway"
    fi
    
    if [[ -n "${SECONDARY_API_ID:-}" ]] && resource_exists "api-gateway" "$SECONDARY_REGION" "$SECONDARY_API_ID"; then
        EXISTING_RESOURCES["api-secondary"]=true
        log "DEBUG" "Found secondary API Gateway"
    fi
    
    # Check IAM role
    if resource_exists "iam-role" "us-east-1" "$IAM_ROLE_NAME"; then
        EXISTING_RESOURCES["iam-role"]=true
        log "DEBUG" "Found IAM role"
    fi
    
    # Check IAM policy
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local policy_name="AuroraDSQLPolicy-${RANDOM_SUFFIX}"
    if resource_exists "iam-policy" "us-east-1" "arn:aws:iam::${account_id}:policy/${policy_name}"; then
        EXISTING_RESOURCES["iam-policy"]=true
        POLICY_ARN="arn:aws:iam::${account_id}:policy/${policy_name}"
        log "DEBUG" "Found IAM policy"
    fi
    
    # Export array for use in other functions
    declare -p EXISTING_RESOURCES > "${SCRIPT_DIR}/.existing_resources.tmp"
    
    local resource_count=0
    for key in "${!EXISTING_RESOURCES[@]}"; do
        ((resource_count++))
    done
    
    log "INFO" "Found ${resource_count} existing resources to clean up"
}

# Show cleanup plan
show_cleanup_plan() {
    log "INFO" "Cleanup plan:"
    
    # Load existing resources
    if [[ -f "${SCRIPT_DIR}/.existing_resources.tmp" ]]; then
        source "${SCRIPT_DIR}/.existing_resources.tmp"
    fi
    
    echo
    echo "📋 Resources to be deleted:"
    
    if [[ "${EXISTING_RESOURCES[dsql-primary]:-false}" == "true" ]]; then
        echo "   🗃️  Aurora DSQL Primary Cluster: ${CLUSTER_NAME_PRIMARY} (${PRIMARY_REGION})"
    fi
    
    if [[ "${EXISTING_RESOURCES[dsql-secondary]:-false}" == "true" ]]; then
        echo "   🗃️  Aurora DSQL Secondary Cluster: ${CLUSTER_NAME_SECONDARY} (${SECONDARY_REGION})"
    fi
    
    if [[ "${EXISTING_RESOURCES[lambda-primary]:-false}" == "true" ]]; then
        echo "   ⚡ Lambda Function: ${LAMBDA_FUNCTION_NAME}-primary (${PRIMARY_REGION})"
    fi
    
    if [[ "${EXISTING_RESOURCES[lambda-secondary]:-false}" == "true" ]]; then
        echo "   ⚡ Lambda Function: ${LAMBDA_FUNCTION_NAME}-secondary (${SECONDARY_REGION})"
    fi
    
    if [[ "${EXISTING_RESOURCES[api-primary]:-false}" == "true" ]]; then
        echo "   🌐 API Gateway: ${PRIMARY_API_ID:-unknown} (${PRIMARY_REGION})"
    fi
    
    if [[ "${EXISTING_RESOURCES[api-secondary]:-false}" == "true" ]]; then
        echo "   🌐 API Gateway: ${SECONDARY_API_ID:-unknown} (${SECONDARY_REGION})"
    fi
    
    if [[ "${EXISTING_RESOURCES[iam-role]:-false}" == "true" ]]; then
        echo "   👤 IAM Role: ${IAM_ROLE_NAME}"
    fi
    
    if [[ "${EXISTING_RESOURCES[iam-policy]:-false}" == "true" ]]; then
        echo "   📜 IAM Policy: AuroraDSQLPolicy-${RANDOM_SUFFIX}"
    fi
    
    echo
}

# Delete API Gateway instances
delete_api_gateways() {
    log "INFO" "Deleting API Gateway instances..."
    
    # Load existing resources
    source "${SCRIPT_DIR}/.existing_resources.tmp"
    
    if [[ "${EXISTING_RESOURCES[api-primary]:-false}" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete primary API Gateway: ${PRIMARY_API_ID}"
        else
            log "INFO" "Deleting primary API Gateway..."
            aws apigateway delete-rest-api \
                --region "$PRIMARY_REGION" \
                --rest-api-id "$PRIMARY_API_ID"
            log "INFO" "✅ Primary API Gateway deleted"
        fi
    fi
    
    if [[ "${EXISTING_RESOURCES[api-secondary]:-false}" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete secondary API Gateway: ${SECONDARY_API_ID}"
        else
            log "INFO" "Deleting secondary API Gateway..."
            aws apigateway delete-rest-api \
                --region "$SECONDARY_REGION" \
                --rest-api-id "$SECONDARY_API_ID"
            log "INFO" "✅ Secondary API Gateway deleted"
        fi
    fi
}

# Delete Lambda functions
delete_lambda_functions() {
    log "INFO" "Deleting Lambda functions..."
    
    # Load existing resources
    source "${SCRIPT_DIR}/.existing_resources.tmp"
    
    if [[ "${EXISTING_RESOURCES[lambda-primary]:-false}" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete primary Lambda function: ${LAMBDA_FUNCTION_NAME}-primary"
        else
            log "INFO" "Deleting primary Lambda function..."
            aws lambda delete-function \
                --region "$PRIMARY_REGION" \
                --function-name "${LAMBDA_FUNCTION_NAME}-primary"
            log "INFO" "✅ Primary Lambda function deleted"
        fi
    fi
    
    if [[ "${EXISTING_RESOURCES[lambda-secondary]:-false}" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete secondary Lambda function: ${LAMBDA_FUNCTION_NAME}-secondary"
        else
            log "INFO" "Deleting secondary Lambda function..."
            aws lambda delete-function \
                --region "$SECONDARY_REGION" \
                --function-name "${LAMBDA_FUNCTION_NAME}-secondary"
            log "INFO" "✅ Secondary Lambda function deleted"
        fi
    fi
}

# Delete IAM resources
delete_iam_resources() {
    log "INFO" "Deleting IAM resources..."
    
    # Load existing resources
    source "${SCRIPT_DIR}/.existing_resources.tmp"
    
    if [[ "${EXISTING_RESOURCES[iam-role]:-false}" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete IAM role and policies"
        else
            log "INFO" "Detaching policies from IAM role..."
            
            # Detach AWS managed policy
            aws iam detach-role-policy \
                --role-name "$IAM_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
                2>/dev/null || log "WARN" "AWS Lambda basic execution policy was not attached"
            
            # Detach and delete custom policy
            if [[ "${EXISTING_RESOURCES[iam-policy]:-false}" == "true" ]]; then
                aws iam detach-role-policy \
                    --role-name "$IAM_ROLE_NAME" \
                    --policy-arn "$POLICY_ARN" \
                    2>/dev/null || log "WARN" "Custom policy was not attached"
                
                aws iam delete-policy \
                    --policy-arn "$POLICY_ARN"
                log "INFO" "✅ Custom IAM policy deleted"
            fi
            
            # Delete IAM role
            aws iam delete-role \
                --role-name "$IAM_ROLE_NAME"
            log "INFO" "✅ IAM role deleted"
        fi
    fi
}

# Delete Aurora DSQL clusters
delete_dsql_clusters() {
    log "INFO" "Deleting Aurora DSQL clusters..."
    
    # Load existing resources
    source "${SCRIPT_DIR}/.existing_resources.tmp"
    
    # Disable deletion protection first
    if [[ "${EXISTING_RESOURCES[dsql-primary]:-false}" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would disable deletion protection and delete primary cluster"
        else
            log "INFO" "Disabling deletion protection for primary cluster..."
            aws dsql update-cluster \
                --region "$PRIMARY_REGION" \
                --cluster-identifier "$CLUSTER_NAME_PRIMARY" \
                --no-deletion-protection \
                2>/dev/null || log "WARN" "Failed to disable deletion protection for primary cluster"
        fi
    fi
    
    if [[ "${EXISTING_RESOURCES[dsql-secondary]:-false}" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would disable deletion protection and delete secondary cluster"
        else
            log "INFO" "Disabling deletion protection for secondary cluster..."
            aws dsql update-cluster \
                --region "$SECONDARY_REGION" \
                --cluster-identifier "$CLUSTER_NAME_SECONDARY" \
                --no-deletion-protection \
                2>/dev/null || log "WARN" "Failed to disable deletion protection for secondary cluster"
        fi
    fi
    
    # Wait a moment for the updates to propagate
    if [[ "$DRY_RUN" != "true" ]]; then
        sleep 5
    fi
    
    # Delete clusters
    if [[ "${EXISTING_RESOURCES[dsql-primary]:-false}" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete primary Aurora DSQL cluster"
        else
            log "INFO" "Deleting primary Aurora DSQL cluster..."
            aws dsql delete-cluster \
                --region "$PRIMARY_REGION" \
                --cluster-identifier "$CLUSTER_NAME_PRIMARY"
            log "INFO" "✅ Primary Aurora DSQL cluster deletion initiated"
        fi
    fi
    
    if [[ "${EXISTING_RESOURCES[dsql-secondary]:-false}" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete secondary Aurora DSQL cluster"
        else
            log "INFO" "Deleting secondary Aurora DSQL cluster..."
            aws dsql delete-cluster \
                --region "$SECONDARY_REGION" \
                --cluster-identifier "$CLUSTER_NAME_SECONDARY"
            log "INFO" "✅ Secondary Aurora DSQL cluster deletion initiated"
        fi
    fi
}

# Wait for cluster deletion
wait_for_cluster_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would wait for cluster deletion to complete"
        return 0
    fi
    
    log "INFO" "Waiting for cluster deletion to complete..."
    
    # Load existing resources
    source "${SCRIPT_DIR}/.existing_resources.tmp"
    
    local max_attempts=60
    local attempt=0
    
    # Wait for primary cluster deletion
    if [[ "${EXISTING_RESOURCES[dsql-primary]:-false}" == "true" ]]; then
        log "INFO" "Waiting for primary cluster deletion..."
        
        while [[ $attempt -lt $max_attempts ]]; do
            if ! resource_exists "dsql-cluster" "$PRIMARY_REGION" "$CLUSTER_NAME_PRIMARY"; then
                log "INFO" "✅ Primary cluster deleted successfully"
                break
            fi
            
            local status=$(aws dsql get-cluster \
                --region "$PRIMARY_REGION" \
                --cluster-identifier "$CLUSTER_NAME_PRIMARY" \
                --query 'Cluster.Status' --output text 2>/dev/null || echo "DELETED")
            
            if [[ "$status" == "DELETED" ]]; then
                log "INFO" "✅ Primary cluster deleted successfully"
                break
            fi
            
            log "DEBUG" "Primary cluster status: ${status} (attempt $((attempt + 1))/${max_attempts})"
            sleep 30
            ((attempt++))
        done
        
        if [[ $attempt -eq $max_attempts ]]; then
            log "WARN" "Primary cluster deletion did not complete within expected time"
        fi
    fi
    
    # Reset attempt counter for secondary cluster
    attempt=0
    
    # Wait for secondary cluster deletion
    if [[ "${EXISTING_RESOURCES[dsql-secondary]:-false}" == "true" ]]; then
        log "INFO" "Waiting for secondary cluster deletion..."
        
        while [[ $attempt -lt $max_attempts ]]; do
            if ! resource_exists "dsql-cluster" "$SECONDARY_REGION" "$CLUSTER_NAME_SECONDARY"; then
                log "INFO" "✅ Secondary cluster deleted successfully"
                break
            fi
            
            local status=$(aws dsql get-cluster \
                --region "$SECONDARY_REGION" \
                --cluster-identifier "$CLUSTER_NAME_SECONDARY" \
                --query 'Cluster.Status' --output text 2>/dev/null || echo "DELETED")
            
            if [[ "$status" == "DELETED" ]]; then
                log "INFO" "✅ Secondary cluster deleted successfully"
                break
            fi
            
            log "DEBUG" "Secondary cluster status: ${status} (attempt $((attempt + 1))/${max_attempts})"
            sleep 30
            ((attempt++))
        done
        
        if [[ $attempt -eq $max_attempts ]]; then
            log "WARN" "Secondary cluster deletion did not complete within expected time"
        fi
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "INFO" "Cleaning up temporary files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/.existing_resources.tmp"
        "${SCRIPT_DIR}/../lambda-temp"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "[DRY RUN] Would remove: ${file}"
            else
                rm -rf "$file"
                log "DEBUG" "Removed: ${file}"
            fi
        fi
    done
}

# Final verification
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would verify cleanup completion"
        return 0
    fi
    
    log "INFO" "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check for remaining resources
    if resource_exists "dsql-cluster" "$PRIMARY_REGION" "$CLUSTER_NAME_PRIMARY"; then
        log "WARN" "Primary Aurora DSQL cluster still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "dsql-cluster" "$SECONDARY_REGION" "$CLUSTER_NAME_SECONDARY"; then
        log "WARN" "Secondary Aurora DSQL cluster still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "lambda-function" "$PRIMARY_REGION" "${LAMBDA_FUNCTION_NAME}-primary"; then
        log "WARN" "Primary Lambda function still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "lambda-function" "$SECONDARY_REGION" "${LAMBDA_FUNCTION_NAME}-secondary"; then
        log "WARN" "Secondary Lambda function still exists"
        ((remaining_resources++))
    fi
    
    if [[ -n "${PRIMARY_API_ID:-}" ]] && resource_exists "api-gateway" "$PRIMARY_REGION" "$PRIMARY_API_ID"; then
        log "WARN" "Primary API Gateway still exists"
        ((remaining_resources++))
    fi
    
    if [[ -n "${SECONDARY_API_ID:-}" ]] && resource_exists "api-gateway" "$SECONDARY_REGION" "$SECONDARY_API_ID"; then
        log "WARN" "Secondary API Gateway still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "iam-role" "us-east-1" "$IAM_ROLE_NAME"; then
        log "WARN" "IAM role still exists"
        ((remaining_resources++))
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log "INFO" "✅ All resources successfully cleaned up"
    else
        log "WARN" "⚠️  ${remaining_resources} resources may still exist"
        log "WARN" "Check the AWS console to verify complete cleanup"
    fi
}

# Archive deployment info
archive_deployment_info() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would archive deployment info file"
        return 0
    fi
    
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        local archive_name="${DEPLOYMENT_INFO_FILE}.deleted-$(date +%Y%m%d-%H%M%S)"
        mv "$DEPLOYMENT_INFO_FILE" "$archive_name"
        log "INFO" "Deployment info archived to: ${archive_name}"
    fi
}

# Main cleanup function
main() {
    log "INFO" "Starting Aurora DSQL Multi-Region Application cleanup"
    log "INFO" "Dry Run Mode: ${DRY_RUN}"
    
    # Load deployment info and validate environment
    load_deployment_info
    validate_aws_cli
    discover_resources
    show_cleanup_plan
    
    # Show confirmation unless in force mode
    if [[ "$DRY_RUN" != "true" ]] && [[ "$FORCE" != "true" ]]; then
        echo
        echo "⚠️  WARNING: This will permanently delete all resources shown above!"
        echo "   This action cannot be undone."
        echo
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Cleanup cancelled by user"
            exit 0
        fi
        
        echo
        read -p "Type 'DELETE' to confirm: " confirm
        if [[ "$confirm" != "DELETE" ]]; then
            log "INFO" "Cleanup cancelled - confirmation not provided"
            exit 0
        fi
    fi
    
    # Run cleanup steps in reverse order of creation
    delete_api_gateways
    delete_lambda_functions
    delete_iam_resources
    delete_dsql_clusters
    wait_for_cluster_deletion
    cleanup_temp_files
    verify_cleanup
    archive_deployment_info
    
    log "INFO" "🎉 Cleanup completed!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo
        echo "📋 Cleanup Summary:"
        echo "   All multi-region application resources have been removed"
        echo "   Log file: ${LOG_FILE}"
        echo
        echo "💡 Note: Aurora DSQL clusters may take several minutes to fully delete"
        echo "   You can verify deletion in the AWS console"
    fi
}

# Initialize log file
echo "=== Aurora DSQL Multi-Region Application Cleanup $(date) ===" > "$LOG_FILE"

# Run main function
main "$@"