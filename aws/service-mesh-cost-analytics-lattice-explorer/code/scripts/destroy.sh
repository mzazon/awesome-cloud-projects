#!/bin/bash

# destroy.sh - Cleanup script for Service Mesh Cost Analytics with VPC Lattice and Cost Explorer
# Recipe: service-mesh-cost-analytics-lattice-explorer
# Version: 1.1
# Last Updated: 2025-07-12

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE_CLEANUP=${FORCE_CLEANUP:-false}
DRY_RUN=${DRY_RUN:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "${LOG_FILE}"
    echo "Check ${LOG_FILE} for detailed logs"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${LOG_FILE}"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "${LOG_FILE}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment variables
load_deployment_variables() {
    log "Loading deployment variables..."
    
    # Try to load variables from deployment
    if [[ -f "${SCRIPT_DIR}/deployment_vars.env" ]]; then
        source "${SCRIPT_DIR}/deployment_vars.env"
        info "Loaded variables from deployment_vars.env"
        success "Deployment variables loaded successfully"
    else
        warning "deployment_vars.env not found. Manual variable entry required."
        
        # Manual variable entry
        read -p "Enter AWS Region (default: $(aws configure get region)): " AWS_REGION
        AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        
        read -p "Enter random suffix used during deployment: " RANDOM_SUFFIX
        if [[ -z "$RANDOM_SUFFIX" ]]; then
            error_exit "Random suffix is required for cleanup. Check deployment logs."
        fi
        
        # Set derived variables
        export AWS_REGION
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export PROJECT_NAME="lattice-cost-analytics"
        export FUNCTION_NAME="lattice-cost-processor-${RANDOM_SUFFIX}"
        export BUCKET_NAME="lattice-analytics-${RANDOM_SUFFIX}"
        export ROLE_NAME="LatticeAnalyticsRole-${RANDOM_SUFFIX}"
        export SERVICE_NETWORK_NAME="cost-demo-network-${RANDOM_SUFFIX}"
        export SERVICE_NAME="demo-service-${RANDOM_SUFFIX}"
        
        success "Manual variables configured"
    fi
    
    info "Cleanup will target resources with suffix: $RANDOM_SUFFIX"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        info "Force cleanup enabled, skipping confirmation"
        return 0
    fi
    
    echo
    echo "🚨 DESTRUCTIVE OPERATION WARNING 🚨"
    echo "====================================="
    echo
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo "  • IAM Role: ${ROLE_NAME}"
    echo "  • Lambda Function: ${FUNCTION_NAME}"
    echo "  • S3 Bucket: ${BUCKET_NAME} (and ALL contents)"
    echo "  • Service Network: ${SERVICE_NETWORK_NAME}"
    echo "  • Service: ${SERVICE_NAME}"
    echo "  • CloudWatch Dashboard: VPCLattice-CostAnalytics-${RANDOM_SUFFIX}"
    echo "  • EventBridge Rule: lattice-cost-analysis-${RANDOM_SUFFIX}"
    echo "  • All associated policies and configurations"
    echo
    echo "💾 Data Loss Warning: S3 bucket contents will be permanently deleted!"
    echo
    echo "🔍 Double-check the resource suffix: ${RANDOM_SUFFIX}"
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 DRY RUN MODE - No resources will be deleted"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "DELETE" ]]; then
        echo "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    info "Cleanup confirmed. Starting resource destruction..."
}

# Function to remove EventBridge automation
remove_eventbridge_automation() {
    log "Removing EventBridge automation..."
    
    local rule_name="lattice-cost-analysis-${RANDOM_SUFFIX}"
    
    # Check if rule exists
    if ! aws events describe-rule --name "${rule_name}" &> /dev/null; then
        warning "EventBridge rule ${rule_name} not found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Remove targets first
        aws events remove-targets \
            --rule "${rule_name}" \
            --ids 1 2>/dev/null || true
        
        # Delete the rule
        aws events delete-rule \
            --name "${rule_name}" || true
        
        # Remove Lambda permission
        aws lambda remove-permission \
            --function-name "${FUNCTION_NAME}" \
            --statement-id lattice-cost-analysis-trigger 2>/dev/null || true
    fi
    
    success "EventBridge automation removed"
}

# Function to delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    local dashboard_name="VPCLattice-CostAnalytics-${RANDOM_SUFFIX}"
    
    # Check if dashboard exists
    if ! aws cloudwatch list-dashboards \
        --query "DashboardEntries[?DashboardName=='${dashboard_name}']" \
        --output text | grep -q .; then
        warning "CloudWatch dashboard ${dashboard_name} not found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "${dashboard_name}" || true
    fi
    
    success "CloudWatch dashboard deleted"
}

# Function to remove VPC Lattice resources
remove_vpc_lattice_resources() {
    log "Removing VPC Lattice resources..."
    
    # Get service network ID if it exists
    local service_network_id=$(aws vpc-lattice list-service-networks \
        --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" \
        --output text 2>/dev/null || echo "")
    
    # Get service ID if it exists
    local service_id=$(aws vpc-lattice list-services \
        --query "items[?name=='${SERVICE_NAME}'].id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$service_network_id" && -z "$service_id" ]]; then
        warning "No VPC Lattice resources found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Remove service network association if both exist
        if [[ -n "$service_network_id" && -n "$service_id" ]]; then
            local association_id=$(aws vpc-lattice list-service-network-service-associations \
                --service-network-identifier "${service_network_id}" \
                --query "items[?serviceId=='${service_id}'].id" \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$association_id" && "$association_id" != "None" ]]; then
                info "Removing service network association: $association_id"
                aws vpc-lattice delete-service-network-service-association \
                    --service-network-service-association-identifier "${association_id}" || true
                
                # Wait for association removal
                sleep 10
            fi
        fi
        
        # Delete service
        if [[ -n "$service_id" && "$service_id" != "None" ]]; then
            info "Deleting service: $service_id"
            aws vpc-lattice delete-service \
                --service-identifier "${service_id}" || true
            
            # Wait for service deletion
            sleep 5
        fi
        
        # Delete service network
        if [[ -n "$service_network_id" && "$service_network_id" != "None" ]]; then
            info "Deleting service network: $service_network_id"
            aws vpc-lattice delete-service-network \
                --service-network-identifier "${service_network_id}" || true
        fi
    fi
    
    success "VPC Lattice resources removed"
}

# Function to delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    # Check if function exists
    if ! aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        warning "Lambda function ${FUNCTION_NAME} not found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        aws lambda delete-function \
            --function-name "${FUNCTION_NAME}" || true
    fi
    
    success "Lambda function deleted"
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        warning "S3 bucket ${BUCKET_NAME} not found, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # List contents for confirmation
        local object_count=$(aws s3 ls "s3://${BUCKET_NAME}" --recursive | wc -l)
        if [[ $object_count -gt 0 ]]; then
            info "Bucket contains $object_count objects. Deleting all contents..."
        fi
        
        # Empty bucket completely (including versioned objects)
        aws s3 rm "s3://${BUCKET_NAME}" --recursive || true
        
        # Remove versioned objects if versioning is enabled
        aws s3api delete-objects \
            --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_NAME}" \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
        
        # Remove delete markers
        aws s3api delete-objects \
            --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${BUCKET_NAME}" \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --output json)" 2>/dev/null || true
        
        # Delete bucket
        aws s3 rb "s3://${BUCKET_NAME}" || true
    fi
    
    success "S3 bucket deleted"
}

# Function to remove IAM resources
remove_iam_resources() {
    log "Removing IAM resources..."
    
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LatticeAnalyticsPolicy-${RANDOM_SUFFIX}"
    
    # Check if role exists
    if ! aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${ROLE_NAME} not found, skipping IAM cleanup"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Detach policies from role
        info "Detaching policies from role..."
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn "${policy_arn}" 2>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete custom policy
        info "Deleting custom policy..."
        aws iam delete-policy \
            --policy-arn "${policy_arn}" 2>/dev/null || true
        
        # Delete IAM role
        info "Deleting IAM role..."
        aws iam delete-role \
            --role-name "${ROLE_NAME}" || true
    fi
    
    success "IAM resources removed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/trust-policy.json"
        "${SCRIPT_DIR}/cost-analytics-policy.json"
        "${SCRIPT_DIR}/dashboard-config.json"
        "${SCRIPT_DIR}/lambda_function.py"
        "${SCRIPT_DIR}/lambda-package.zip"
        "${SCRIPT_DIR}/test-response.json"
        "${SCRIPT_DIR}/deployment_vars.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "false" ]]; then
                rm -f "$file"
            fi
            info "Removed: $(basename "$file")"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Lambda function
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        warning "Lambda function ${FUNCTION_NAME} still exists"
        ((cleanup_issues++))
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        warning "S3 bucket ${BUCKET_NAME} still exists"
        ((cleanup_issues++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${ROLE_NAME} still exists"
        ((cleanup_issues++))
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "lattice-cost-analysis-${RANDOM_SUFFIX}" &> /dev/null; then
        warning "EventBridge rule still exists"
        ((cleanup_issues++))
    fi
    
    # Check VPC Lattice resources
    if aws vpc-lattice list-service-networks \
        --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" \
        --output text | grep -q .; then
        warning "VPC Lattice service network still exists"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "All resources successfully removed"
    else
        warning "$cleanup_issues resources may still exist. Manual cleanup may be required."
        echo "Check the AWS console for any remaining resources with suffix: ${RANDOM_SUFFIX}"
    fi
}

# Function to display cleanup summary
display_summary() {
    echo
    echo "======================================"
    echo "🧹 CLEANUP COMPLETED 🧹"
    echo "======================================"
    echo
    echo "📊 Removed Resources:"
    echo "  • IAM Role: ${ROLE_NAME}"
    echo "  • Lambda Function: ${FUNCTION_NAME}"
    echo "  • S3 Bucket: ${BUCKET_NAME}"
    echo "  • Service Network: ${SERVICE_NETWORK_NAME}"
    echo "  • Service: ${SERVICE_NAME}"
    echo "  • CloudWatch Dashboard: VPCLattice-CostAnalytics-${RANDOM_SUFFIX}"
    echo "  • EventBridge Rule: lattice-cost-analysis-${RANDOM_SUFFIX}"
    echo
    echo "📝 Post-Cleanup Notes:"
    echo "  • Cost Explorer data may still show historical usage"
    echo "  • CloudWatch metrics will be retained per AWS policy"
    echo "  • Any manual changes to resources may require manual cleanup"
    echo
    echo "💰 Cost Impact: Infrastructure costs should return to baseline"
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "⚠️  This was a DRY RUN - no resources were actually deleted"
    fi
    echo "🔍 Check AWS console to verify all resources are removed"
}

# Main cleanup function
main() {
    echo "🧹 Starting Service Mesh Cost Analytics Cleanup"
    echo "==============================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 DRY RUN MODE - No resources will be deleted"
    fi
    
    echo "📋 Cleanup started at: $(date)"
    echo "📁 Working directory: ${SCRIPT_DIR}"
    echo "📊 Log file: ${LOG_FILE}"
    echo
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_variables
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_eventbridge_automation
    delete_cloudwatch_dashboard
    remove_vpc_lattice_resources
    delete_lambda_function
    delete_s3_bucket
    remove_iam_resources
    cleanup_local_files
    
    if [[ "$DRY_RUN" == "false" ]]; then
        verify_cleanup
    fi
    
    display_summary
    
    log "Cleanup completed at $(date)"
}

# Handle script interruption
trap 'echo -e "\n${RED}Cleanup interrupted. Some resources may still exist.${NC}"; exit 1' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--dry-run] [--help]"
            echo "  --force      Skip confirmation prompts"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --help       Show this help message"
            echo
            echo "Environment Variables:"
            echo "  FORCE_CLEANUP=true    Same as --force"
            echo "  DRY_RUN=true         Same as --dry-run"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main "$@"