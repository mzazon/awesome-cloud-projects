#!/bin/bash

# Database Connection Pooling with RDS Proxy - Cleanup Script
# This script removes all resources created by the deploy.sh script

set -e
set -o pipefail

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
SUFFIX=""

# Helper functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up RDS Proxy deployment resources

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deleted without making changes
    -f, --force            Skip confirmation prompts
    -s, --suffix SUFFIX    Resource suffix to target for cleanup (required)
    -r, --region REGION    AWS region (default: current configured region)
    --skip-vpc             Skip VPC deletion (keep networking resources)
    --lambda-only          Delete only Lambda function and role
    --proxy-only           Delete only RDS Proxy resources

EXAMPLES:
    $0 --suffix abc123                   # Cleanup resources with suffix abc123
    $0 --suffix abc123 --dry-run         # Show what would be deleted
    $0 --suffix abc123 --force           # Skip confirmation prompts
    $0 --suffix abc123 --lambda-only     # Delete only Lambda resources

NOTES:
    - The suffix is required and should match the one from deployment
    - Use --dry-run first to verify what will be deleted
    - Some resources may take several minutes to delete

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
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
            -s|--suffix)
                SUFFIX="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            --skip-vpc)
                SKIP_VPC=true
                shift
                ;;
            --lambda-only)
                LAMBDA_ONLY=true
                shift
                ;;
            --proxy-only)
                PROXY_ONLY=true
                shift
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done

    if [ -z "$SUFFIX" ]; then
        error "Resource suffix is required. Use --suffix option."
    fi
}

# Validate prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please run 'aws configure'."
    fi

    # Check AWS region
    if [ -z "$AWS_REGION" ]; then
        AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            error "AWS region not configured. Use --region option or run 'aws configure'."
        fi
    fi

    # Get AWS Account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    log "Prerequisites check passed"
    info "AWS Account: $AWS_ACCOUNT_ID"
    info "AWS Region: $AWS_REGION"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."

    # Set resource names based on suffix
    export DB_INSTANCE_ID="rds-proxy-demo-${SUFFIX}"
    export PROXY_NAME="rds-proxy-demo-${SUFFIX}"
    export SECRET_NAME="rds-proxy-secret-${SUFFIX}"
    export LAMBDA_FUNCTION_NAME="rds-proxy-test-${SUFFIX}"

    # Try to load from deployment info file if it exists
    if [ -f "${SCRIPT_DIR}/deployment-info.txt" ]; then
        info "Found deployment info file"
        # Extract VPC ID if available
        VPC_ID=$(grep "VPC ID:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d: -f2 | xargs)
        SUBNET_ID_1=$(grep "Subnet 1:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d: -f2 | xargs)
        SUBNET_ID_2=$(grep "Subnet 2:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d: -f2 | xargs)
    fi

    info "Target resources:"
    info "  DB Instance: $DB_INSTANCE_ID"
    info "  RDS Proxy: $PROXY_NAME"
    info "  Secret: $SECRET_NAME"
    info "  Lambda: $LAMBDA_FUNCTION_NAME"
}

# Confirm deletion
confirm_deletion() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi

    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo ""
    echo "   • RDS Instance: $DB_INSTANCE_ID"
    echo "   • RDS Proxy: $PROXY_NAME"
    echo "   • Secrets Manager Secret: $SECRET_NAME"
    echo "   • Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "   • IAM Roles and Policies"
    
    if [ "$SKIP_VPC" != true ]; then
        echo "   • VPC and associated networking resources"
    fi
    
    echo ""
    echo "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Helper function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"

    case $resource_type in
        "lambda")
            aws lambda get-function --function-name "$resource_id" &>/dev/null
            ;;
        "rds-instance")
            aws rds describe-db-instances --db-instance-identifier "$resource_id" &>/dev/null
            ;;
        "rds-proxy")
            aws rds describe-db-proxies --db-proxy-name "$resource_id" &>/dev/null
            ;;
        "secret")
            aws secretsmanager describe-secret --secret-id "$resource_id" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_id" &>/dev/null
            ;;
        "iam-policy")
            aws iam get-policy --policy-arn "$resource_id" &>/dev/null
            ;;
        "vpc")
            aws ec2 describe-vpcs --vpc-ids "$resource_id" &>/dev/null
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids "$resource_id" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Delete Lambda function and role
delete_lambda_resources() {
    log "Cleaning up Lambda resources..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION_NAME"
        info "[DRY RUN] Would delete Lambda IAM role: LambdaRDSProxyRole-${SUFFIX}"
        return
    fi

    # Delete Lambda function
    if resource_exists "lambda" "$LAMBDA_FUNCTION_NAME"; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log "✅ Lambda function deleted: $LAMBDA_FUNCTION_NAME"
    else
        warn "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi

    # Delete Lambda IAM role
    local lambda_role="LambdaRDSProxyRole-${SUFFIX}"
    if resource_exists "iam-role" "$lambda_role"; then
        # Detach policies first
        aws iam detach-role-policy \
            --role-name "$lambda_role" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" 2>/dev/null || true

        aws iam delete-role --role-name "$lambda_role"
        log "✅ Lambda IAM role deleted: $lambda_role"
    else
        warn "Lambda IAM role not found: $lambda_role"
    fi
}

# Delete RDS Proxy
delete_rds_proxy() {
    log "Cleaning up RDS Proxy..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete RDS Proxy: $PROXY_NAME"
        return
    fi

    if resource_exists "rds-proxy" "$PROXY_NAME"; then
        aws rds delete-db-proxy --db-proxy-name "$PROXY_NAME"
        log "⏳ Deleting RDS Proxy (this may take a few minutes)..."
        
        # Wait for deletion to complete
        while aws rds describe-db-proxies --db-proxy-name "$PROXY_NAME" &>/dev/null; do
            sleep 30
            info "Still deleting RDS Proxy..."
        done
        
        log "✅ RDS Proxy deleted: $PROXY_NAME"
    else
        warn "RDS Proxy not found: $PROXY_NAME"
    fi
}

# Delete RDS instance
delete_rds_instance() {
    log "Cleaning up RDS instance..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete RDS instance: $DB_INSTANCE_ID"
        return
    fi

    if resource_exists "rds-instance" "$DB_INSTANCE_ID"; then
        aws rds delete-db-instance \
            --db-instance-identifier "$DB_INSTANCE_ID" \
            --skip-final-snapshot
        
        log "⏳ Deleting RDS instance (this will take 5-10 minutes)..."
        
        # Wait for deletion to complete
        aws rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_ID"
        
        log "✅ RDS instance deleted: $DB_INSTANCE_ID"
    else
        warn "RDS instance not found: $DB_INSTANCE_ID"
    fi
}

# Delete RDS Proxy IAM role and policy
delete_proxy_iam_resources() {
    log "Cleaning up RDS Proxy IAM resources..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete RDS Proxy IAM role and policy"
        return
    fi

    local proxy_role="RDSProxyRole-${SUFFIX}"
    local proxy_policy="RDSProxySecretsPolicy-${SUFFIX}"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${proxy_policy}"

    # Detach and delete policy
    if resource_exists "iam-role" "$proxy_role"; then
        aws iam detach-role-policy \
            --role-name "$proxy_role" \
            --policy-arn "$policy_arn" 2>/dev/null || true
        
        aws iam delete-role --role-name "$proxy_role"
        log "✅ RDS Proxy IAM role deleted: $proxy_role"
    else
        warn "RDS Proxy IAM role not found: $proxy_role"
    fi

    if resource_exists "iam-policy" "$policy_arn"; then
        aws iam delete-policy --policy-arn "$policy_arn"
        log "✅ RDS Proxy IAM policy deleted: $proxy_policy"
    else
        warn "RDS Proxy IAM policy not found: $proxy_policy"
    fi
}

# Delete Secrets Manager secret
delete_secret() {
    log "Cleaning up Secrets Manager secret..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete secret: $SECRET_NAME"
        return
    fi

    if resource_exists "secret" "$SECRET_NAME"; then
        aws secretsmanager delete-secret \
            --secret-id "$SECRET_NAME" \
            --force-delete-without-recovery
        
        log "✅ Secret deleted: $SECRET_NAME"
    else
        warn "Secret not found: $SECRET_NAME"
    fi
}

# Delete networking resources
delete_networking_resources() {
    if [ "$SKIP_VPC" = true ]; then
        log "Skipping VPC deletion (--skip-vpc specified)"
        return
    fi

    log "Cleaning up networking resources..."

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete DB subnet group"
        info "[DRY RUN] Would delete security groups"
        info "[DRY RUN] Would delete subnets and VPC"
        return
    fi

    # Delete DB subnet group
    local subnet_group="rds-proxy-subnet-group-${SUFFIX}"
    if aws rds describe-db-subnet-groups --db-subnet-group-name "$subnet_group" &>/dev/null; then
        aws rds delete-db-subnet-group --db-subnet-group-name "$subnet_group"
        log "✅ DB subnet group deleted: $subnet_group"
    else
        warn "DB subnet group not found: $subnet_group"
    fi

    # Find and delete security groups
    local proxy_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=rds-proxy-sg-${SUFFIX}" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
    
    local db_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=rds-proxy-db-sg-${SUFFIX}" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")

    # Delete security groups
    if [ "$proxy_sg" != "None" ] && [ "$proxy_sg" != "null" ]; then
        aws ec2 delete-security-group --group-id "$proxy_sg" 2>/dev/null || warn "Could not delete proxy security group: $proxy_sg"
        log "✅ Proxy security group deleted: $proxy_sg"
    fi

    if [ "$db_sg" != "None" ] && [ "$db_sg" != "null" ]; then
        aws ec2 delete-security-group --group-id "$db_sg" 2>/dev/null || warn "Could not delete DB security group: $db_sg"
        log "✅ DB security group deleted: $db_sg"
    fi

    # Delete VPC and subnets if we have the VPC ID
    if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
        # Find subnets in the VPC
        local subnet_ids=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'Subnets[].SubnetId' --output text 2>/dev/null)

        # Delete subnets
        for subnet_id in $subnet_ids; do
            if [ "$subnet_id" != "None" ]; then
                aws ec2 delete-subnet --subnet-id "$subnet_id" 2>/dev/null || warn "Could not delete subnet: $subnet_id"
                log "✅ Subnet deleted: $subnet_id"
            fi
        done

        # Delete VPC
        aws ec2 delete-vpc --vpc-id "$VPC_ID" 2>/dev/null || warn "Could not delete VPC: $VPC_ID"
        log "✅ VPC deleted: $VPC_ID"
    else
        warn "VPC ID not found - manual cleanup may be required"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."

    rm -f /tmp/rds-proxy-*.json /tmp/lambda-trust-policy.json /tmp/lambda_function.* 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/deployment-info.txt" 2>/dev/null || true

    log "✅ Temporary files cleaned up"
}

# Main cleanup function
main() {
    log "Starting RDS Proxy cleanup..."

    if [ "$DRY_RUN" = true ]; then
        info "Running in DRY RUN mode - no resources will be deleted"
    fi

    check_prerequisites
    load_deployment_info
    confirm_deletion

    # Perform cleanup based on options
    if [ "$LAMBDA_ONLY" = true ]; then
        delete_lambda_resources
    elif [ "$PROXY_ONLY" = true ]; then
        delete_rds_proxy
        delete_proxy_iam_resources
    else
        # Full cleanup
        delete_lambda_resources
        delete_rds_proxy
        delete_rds_instance
        delete_proxy_iam_resources
        delete_secret
        delete_networking_resources
    fi

    if [ "$DRY_RUN" = false ]; then
        cleanup_temp_files
    fi

    log "🎉 RDS Proxy cleanup completed successfully!"

    if [ "$DRY_RUN" = false ]; then
        echo ""
        echo "========================="
        echo "Cleanup Summary"
        echo "========================="
        echo "All targeted resources have been removed."
        echo ""
        echo "Note: Some resources may take additional time to fully terminate."
        echo "Check the AWS Console to verify complete removal."
    fi
}

# Cleanup function for script exit
cleanup() {
    rm -f /tmp/rds-proxy-*.json /tmp/lambda-trust-policy.json 2>/dev/null || true
}

trap cleanup EXIT

# Parse arguments and run main function
parse_args "$@"
main