#!/bin/bash

# Cleanup script for Operational Analytics with Amazon Redshift Spectrum
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Safe resource deletion with error handling
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    
    log_info "Deleting ${resource_type}: ${resource_name}"
    if eval "${delete_command}" 2>/dev/null; then
        log_success "Deleted ${resource_type}: ${resource_name}"
    else
        log_warning "Failed to delete ${resource_type}: ${resource_name} (may not exist)"
    fi
}

# Confirmation prompt
confirm_destruction() {
    echo "=================================================="
    echo "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "=================================================="
    echo ""
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo ""
    echo "🗄️ AWS Resources to be deleted:"
    if [[ -n "${REDSHIFT_CLUSTER:-}" ]]; then
        echo "   • Redshift Cluster: ${REDSHIFT_CLUSTER}"
    fi
    if [[ -n "${DATA_LAKE_BUCKET:-}" ]]; then
        echo "   • S3 Bucket: ${DATA_LAKE_BUCKET} (and ALL contents)"
    fi
    if [[ -n "${GLUE_DATABASE:-}" ]]; then
        echo "   • Glue Database: ${GLUE_DATABASE}"
        echo "   • Glue Crawlers: sales-crawler-*, customers-crawler-*, products-crawler-*"
    fi
    if [[ -n "${REDSHIFT_ROLE_NAME:-}" ]]; then
        echo "   • IAM Role: ${REDSHIFT_ROLE_NAME}"
    fi
    if [[ -n "${GLUE_ROLE_NAME:-}" ]]; then
        echo "   • IAM Role: ${GLUE_ROLE_NAME}"
    fi
    if [[ -n "${SPECTRUM_POLICY_ARN:-}" ]]; then
        echo "   • IAM Policy: Custom Spectrum Policy"
    fi
    echo ""
    echo "💰 This will stop all charges for these resources."
    echo ""
    echo "⚠️  This action CANNOT be undone!"
    echo ""
    
    while true; do
        read -p "Do you want to proceed with deletion? (yes/no): " choice
        case $choice in
            [Yy][Ee][Ss])
                log_warning "Proceeding with resource deletion..."
                break
                ;;
            [Nn][Oo])
                log_info "Cleanup cancelled by user"
                exit 0
                ;;
            *)
                echo "Please answer 'yes' or 'no'"
                ;;
        esac
    done
}

# Banner
echo "=================================================="
echo "Redshift Spectrum Analytics Cleanup Script"
echo "=================================================="

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed. Cannot proceed with cleanup."
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error_exit "AWS credentials not configured. Run 'aws configure' first."
fi

# Load deployment information if available
if [[ -f "deployment-info.env" ]]; then
    log_info "Loading deployment information from deployment-info.env"
    source deployment-info.env
    log_info "Loaded configuration for cleanup"
else
    log_warning "deployment-info.env not found. You may need to provide resource names manually."
    
    # Try to get current AWS region
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
    if [[ -z "${AWS_REGION}" ]]; then
        error_exit "AWS region not configured and deployment-info.env not found"
    fi
    
    # Prompt for resource identifiers if not available
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        echo ""
        log_warning "Unable to automatically determine resource names."
        echo "You can find resource names in the AWS console or provide them manually:"
        echo ""
        
        read -p "Enter Redshift cluster identifier (or press Enter to skip): " REDSHIFT_CLUSTER
        read -p "Enter S3 bucket name (or press Enter to skip): " DATA_LAKE_BUCKET
        read -p "Enter Glue database name (or press Enter to skip): " GLUE_DATABASE
        read -p "Enter Redshift IAM role name (or press Enter to skip): " REDSHIFT_ROLE_NAME
        read -p "Enter Glue IAM role name (or press Enter to skip): " GLUE_ROLE_NAME
        read -p "Enter random suffix used during deployment (or press Enter to skip): " RANDOM_SUFFIX
    fi
fi

# Validate that we have some resources to delete
if [[ -z "${REDSHIFT_CLUSTER:-}" && -z "${DATA_LAKE_BUCKET:-}" && -z "${GLUE_DATABASE:-}" && -z "${REDSHIFT_ROLE_NAME:-}" ]]; then
    log_warning "No resources identified for cleanup. Exiting."
    exit 0
fi

# Show confirmation prompt
confirm_destruction

# Start cleanup process
log_info "Starting cleanup process..."

# Step 1: Delete Redshift cluster
if [[ -n "${REDSHIFT_CLUSTER:-}" ]]; then
    log_info "Step 1/6: Deleting Redshift cluster..."
    
    # Check if cluster exists
    if aws redshift describe-clusters --cluster-identifier "${REDSHIFT_CLUSTER}" &> /dev/null; then
        log_info "Initiating Redshift cluster deletion (this may take several minutes)..."
        
        safe_delete "Redshift cluster" "${REDSHIFT_CLUSTER}" \
            "aws redshift delete-cluster --cluster-identifier '${REDSHIFT_CLUSTER}' --skip-final-cluster-snapshot"
        
        # Wait for cluster deletion with timeout
        log_info "Waiting for cluster deletion to complete..."
        TIMEOUT=900 # 15 minutes
        ELAPSED=0
        INTERVAL=30
        
        while [[ ${ELAPSED} -lt ${TIMEOUT} ]]; do
            if ! aws redshift describe-clusters --cluster-identifier "${REDSHIFT_CLUSTER}" &> /dev/null; then
                log_success "Redshift cluster deleted successfully"
                break
            fi
            
            CLUSTER_STATUS=$(aws redshift describe-clusters \
                --cluster-identifier "${REDSHIFT_CLUSTER}" \
                --query 'Clusters[0].ClusterStatus' --output text 2>/dev/null || echo "unknown")
            
            log_info "Cluster status: ${CLUSTER_STATUS}. Waiting for deletion..."
            sleep ${INTERVAL}
            ELAPSED=$((ELAPSED + INTERVAL))
        done
        
        if [[ ${ELAPSED} -ge ${TIMEOUT} ]]; then
            log_warning "Timeout waiting for cluster deletion. Check AWS console for status."
        fi
    else
        log_warning "Redshift cluster ${REDSHIFT_CLUSTER} not found or already deleted"
    fi
else
    log_info "Step 1/6: Skipping Redshift cluster deletion (not specified)"
fi

# Step 2: Delete Glue crawlers
if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
    log_info "Step 2/6: Deleting Glue crawlers..."
    
    for crawler_type in "sales" "customers" "products"; do
        CRAWLER_NAME="${crawler_type}-crawler-${RANDOM_SUFFIX}"
        safe_delete "Glue crawler" "${CRAWLER_NAME}" \
            "aws glue delete-crawler --name '${CRAWLER_NAME}'"
    done
else
    log_info "Step 2/6: Skipping Glue crawler deletion (random suffix not available)"
fi

# Step 3: Delete Glue database
if [[ -n "${GLUE_DATABASE:-}" ]]; then
    log_info "Step 3/6: Deleting Glue database..."
    
    safe_delete "Glue database" "${GLUE_DATABASE}" \
        "aws glue delete-database --name '${GLUE_DATABASE}'"
else
    log_info "Step 3/6: Skipping Glue database deletion (not specified)"
fi

# Step 4: Clean up S3 data lake
if [[ -n "${DATA_LAKE_BUCKET:-}" ]]; then
    log_info "Step 4/6: Cleaning up S3 data lake..."
    
    # Check if bucket exists
    if aws s3 ls "s3://${DATA_LAKE_BUCKET}" &> /dev/null; then
        log_info "Removing all objects from S3 bucket..."
        safe_delete "S3 bucket contents" "${DATA_LAKE_BUCKET}" \
            "aws s3 rm 's3://${DATA_LAKE_BUCKET}' --recursive"
        
        log_info "Deleting S3 bucket..."
        safe_delete "S3 bucket" "${DATA_LAKE_BUCKET}" \
            "aws s3 rb 's3://${DATA_LAKE_BUCKET}'"
    else
        log_warning "S3 bucket ${DATA_LAKE_BUCKET} not found or already deleted"
    fi
else
    log_info "Step 4/6: Skipping S3 cleanup (bucket not specified)"
fi

# Step 5: Remove IAM roles and policies
if [[ -n "${REDSHIFT_ROLE_NAME:-}" ]]; then
    log_info "Step 5/6: Removing Redshift IAM resources..."
    
    # Detach policies from Redshift role
    if [[ -n "${SPECTRUM_POLICY_ARN:-}" ]]; then
        safe_delete "policy attachment" "${REDSHIFT_ROLE_NAME}" \
            "aws iam detach-role-policy --role-name '${REDSHIFT_ROLE_NAME}' --policy-arn '${SPECTRUM_POLICY_ARN}'"
    fi
    
    # Delete custom policy
    if [[ -n "${SPECTRUM_POLICY_ARN:-}" ]]; then
        safe_delete "IAM policy" "${SPECTRUM_POLICY_ARN}" \
            "aws iam delete-policy --policy-arn '${SPECTRUM_POLICY_ARN}'"
    else
        # Try to find and delete the policy by name
        POLICY_ARN=$(aws iam list-policies \
            --query "Policies[?PolicyName=='${REDSHIFT_ROLE_NAME}-Policy'].Arn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${POLICY_ARN}" && "${POLICY_ARN}" != "None" ]]; then
            safe_delete "policy attachment" "${REDSHIFT_ROLE_NAME}" \
                "aws iam detach-role-policy --role-name '${REDSHIFT_ROLE_NAME}' --policy-arn '${POLICY_ARN}'"
            safe_delete "IAM policy" "${POLICY_ARN}" \
                "aws iam delete-policy --policy-arn '${POLICY_ARN}'"
        fi
    fi
    
    # Delete Redshift role
    safe_delete "IAM role" "${REDSHIFT_ROLE_NAME}" \
        "aws iam delete-role --role-name '${REDSHIFT_ROLE_NAME}'"
else
    log_info "Step 5/6: Skipping Redshift IAM cleanup (role not specified)"
fi

# Step 6: Remove Glue IAM role
if [[ -n "${GLUE_ROLE_NAME:-}" ]]; then
    log_info "Step 6/6: Removing Glue IAM resources..."
    
    # Detach AWS managed policy
    safe_delete "Glue service policy attachment" "${GLUE_ROLE_NAME}" \
        "aws iam detach-role-policy --role-name '${GLUE_ROLE_NAME}' --policy-arn 'arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole'"
    
    # Detach custom Spectrum policy if it exists
    if [[ -n "${SPECTRUM_POLICY_ARN:-}" ]]; then
        safe_delete "Spectrum policy attachment" "${GLUE_ROLE_NAME}" \
            "aws iam detach-role-policy --role-name '${GLUE_ROLE_NAME}' --policy-arn '${SPECTRUM_POLICY_ARN}'"
    fi
    
    # Delete Glue role
    safe_delete "IAM role" "${GLUE_ROLE_NAME}" \
        "aws iam delete-role --role-name '${GLUE_ROLE_NAME}'"
else
    log_info "Step 6/6: Skipping Glue IAM cleanup (role not specified)"
fi

# Clean up local files
log_info "Cleaning up local files..."
LOCAL_FILES=(
    "deployment-info.env"
    "setup-spectrum.sql"
    "operational-queries.sql"
    "performance-check.sql"
    "sales_transactions.csv"
    "customers.csv"
    "products.csv"
    "redshift-trust-policy.json"
    "redshift-spectrum-policy.json"
    "glue-trust-policy.json"
)

for file in "${LOCAL_FILES[@]}"; do
    if [[ -f "${file}" ]]; then
        rm -f "${file}"
        log_info "Removed local file: ${file}"
    fi
done

# Final cleanup summary
echo ""
echo "=================================================="
echo "CLEANUP COMPLETED!"
echo "=================================================="
echo ""
echo "🧹 Resource Cleanup Summary:"
echo ""
if [[ -n "${REDSHIFT_CLUSTER:-}" ]]; then
    echo "   ✅ Redshift Cluster: ${REDSHIFT_CLUSTER}"
fi
if [[ -n "${DATA_LAKE_BUCKET:-}" ]]; then
    echo "   ✅ S3 Data Lake: ${DATA_LAKE_BUCKET}"
fi
if [[ -n "${GLUE_DATABASE:-}" ]]; then
    echo "   ✅ Glue Database: ${GLUE_DATABASE}"
fi
if [[ -n "${REDSHIFT_ROLE_NAME:-}" ]]; then
    echo "   ✅ IAM Role: ${REDSHIFT_ROLE_NAME}"
fi
if [[ -n "${GLUE_ROLE_NAME:-}" ]]; then
    echo "   ✅ IAM Role: ${GLUE_ROLE_NAME}"
fi
echo "   ✅ Local configuration files"
echo ""
echo "💰 All charges for these resources have been stopped."
echo ""
echo "📋 What's Next:"
echo "   • Check AWS Console to verify all resources are deleted"
echo "   • Review your AWS bill to confirm charges have stopped"
echo "   • Keep deployment scripts for future use"
echo ""
echo "⚠️  Note: Some resources may take additional time to fully delete."
echo "   Monitor the AWS Console for final deletion confirmation."
echo ""
echo "=================================================="

log_success "Cleanup completed successfully!"