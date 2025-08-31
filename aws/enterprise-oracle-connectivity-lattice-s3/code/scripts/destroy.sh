#!/bin/bash

# Enterprise Oracle Database Connectivity with VPC Lattice and S3 - Cleanup Script
# Recipe: enterprise-oracle-connectivity-lattice-s3
# Version: 1.1
# Generated: 2025-01-16

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Command line options
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --yes|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force        Force cleanup without confirmation and continue on errors"
            echo "  --yes, -y      Skip confirmation prompts"
            echo "  --help, -h     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Banner
echo -e "${RED}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Enterprise Oracle Database Connectivity                  ║
║                         with VPC Lattice and S3                            ║
║                              CLEANUP SCRIPT                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Load environment variables if available
if [ -f "./deployment_vars.env" ]; then
    log "Loading deployment variables from ./deployment_vars.env"
    source ./deployment_vars.env
    log_success "Environment variables loaded"
else
    log_warning "deployment_vars.env not found. Some cleanup operations may require manual intervention."
    
    # Try to get some basic info
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "Unable to determine AWS account. Please ensure AWS CLI is configured."
        exit 1
    fi
fi

# Safety confirmation
if [ "$SKIP_CONFIRMATION" = false ]; then
    echo ""
    log_warning "This will DELETE the following resources:"
    echo "   • Redshift cluster: ${REDSHIFT_CLUSTER_ID:-unknown}"
    echo "   • S3 bucket and contents: ${S3_BUCKET_NAME:-unknown}"
    echo "   • IAM role: ${IAM_ROLE_NAME:-unknown}"
    echo "   • CloudWatch dashboard: ${DASHBOARD_NAME:-unknown}"
    echo "   • CloudWatch log group: ${LOG_GROUP_NAME:-unknown}"
    echo "   • Oracle Database@AWS integrations (disabled)"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRMATION
    
    if [ "$CONFIRMATION" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

log "Starting cleanup process..."

# Error handling for force mode
if [ "$FORCE_CLEANUP" = true ]; then
    set +e  # Don't exit on errors in force mode
    log_warning "Force mode enabled - continuing on errors"
fi

# Step 1: Disable Oracle Database@AWS integrations
log "Step 1: Disabling Oracle Database@AWS integrations..."

if [ -n "${ODB_NETWORK_ID:-}" ] && [[ "$ODB_NETWORK_ID" != "simulated-"* ]]; then
    # Disable Zero-ETL access
    aws odb update-odb-network \
        --odb-network-id "${ODB_NETWORK_ID}" \
        --zero-etl-access DISABLED 2>/dev/null || {
        log_warning "Failed to disable Zero-ETL access (may not exist)"
    }
    
    # Disable S3 access
    aws odb update-odb-network \
        --odb-network-id "${ODB_NETWORK_ID}" \
        --s3-access DISABLED 2>/dev/null || {
        log_warning "Failed to disable S3 access (may not exist)"
    }
    
    log_success "Oracle Database@AWS integrations disabled"
else
    log_warning "No ODB Network ID found or simulated - skipping ODB integration cleanup"
fi

# Step 2: Delete Redshift cluster
log "Step 2: Deleting Redshift cluster..."

if [ -n "${REDSHIFT_CLUSTER_ID:-}" ]; then
    # Check if cluster exists
    if aws redshift describe-clusters --cluster-identifier "${REDSHIFT_CLUSTER_ID}" &>/dev/null; then
        log "Deleting Redshift cluster: ${REDSHIFT_CLUSTER_ID}"
        aws redshift delete-cluster \
            --cluster-identifier "${REDSHIFT_CLUSTER_ID}" \
            --skip-final-cluster-snapshot 2>/dev/null || {
            log_warning "Failed to delete Redshift cluster (may already be deleted)"
        }
        
        # Wait for deletion to start (optional check)
        sleep 5
        CLUSTER_STATUS=$(aws redshift describe-clusters \
            --cluster-identifier "${REDSHIFT_CLUSTER_ID}" \
            --query 'Clusters[0].ClusterStatus' --output text 2>/dev/null || echo "deleted")
        
        if [ "$CLUSTER_STATUS" = "deleting" ]; then
            log "Redshift cluster deletion in progress..."
        fi
        
        log_success "Redshift cluster deletion initiated"
    else
        log_warning "Redshift cluster not found (may already be deleted)"
    fi
else
    log_warning "No Redshift cluster ID found - skipping"
fi

# Step 3: Delete IAM role and policies
log "Step 3: Cleaning up IAM role..."

if [ -n "${IAM_ROLE_NAME:-}" ]; then
    # Detach policies
    aws iam detach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess 2>/dev/null || {
        log_warning "Failed to detach S3 policy (may not be attached)"
    }
    
    aws iam detach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonRedshiftAllCommandsFullAccess 2>/dev/null || {
        log_warning "Failed to detach Redshift policy (may not be attached)"
    }
    
    # Delete IAM role
    aws iam delete-role --role-name "${IAM_ROLE_NAME}" 2>/dev/null || {
        log_warning "Failed to delete IAM role (may not exist)"
    }
    
    log_success "IAM role cleanup completed"
else
    log_warning "No IAM role name found - skipping"
fi

# Step 4: Delete S3 bucket and contents
log "Step 4: Deleting S3 bucket and contents..."

if [ -n "${S3_BUCKET_NAME:-}" ]; then
    # Check if bucket exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &>/dev/null; then
        log "Removing all objects from S3 bucket: ${S3_BUCKET_NAME}"
        
        # Remove all object versions and delete markers (for versioned buckets)
        aws s3api list-object-versions \
            --bucket "${S3_BUCKET_NAME}" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object \
                    --bucket "${S3_BUCKET_NAME}" \
                    --key "$key" \
                    --version-id "$version" 2>/dev/null || true
            fi
        done
        
        # Remove delete markers
        aws s3api list-object-versions \
            --bucket "${S3_BUCKET_NAME}" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object \
                    --bucket "${S3_BUCKET_NAME}" \
                    --key "$key" \
                    --version-id "$version" 2>/dev/null || true
            fi
        done
        
        # Remove any remaining objects
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || true
        
        # Delete the bucket
        aws s3 rb "s3://${S3_BUCKET_NAME}" 2>/dev/null || {
            log_warning "Failed to delete S3 bucket (may have remaining objects)"
        }
        
        log_success "S3 bucket and contents removed"
    else
        log_warning "S3 bucket not found (may already be deleted)"
    fi
else
    log_warning "No S3 bucket name found - skipping"
fi

# Step 5: Delete CloudWatch resources
log "Step 5: Cleaning up CloudWatch resources..."

# Delete CloudWatch dashboard
if [ -n "${DASHBOARD_NAME:-}" ]; then
    aws cloudwatch delete-dashboards \
        --dashboard-names "${DASHBOARD_NAME}" 2>/dev/null || {
        log_warning "Failed to delete CloudWatch dashboard (may not exist)"
    }
    log_success "CloudWatch dashboard cleanup completed"
else
    log_warning "No dashboard name found - skipping"
fi

# Delete CloudWatch log group
if [ -n "${LOG_GROUP_NAME:-}" ]; then
    aws logs delete-log-group \
        --log-group-name "${LOG_GROUP_NAME}" 2>/dev/null || {
        log_warning "Failed to delete CloudWatch log group (may not exist)"
    }
    log_success "CloudWatch log group cleanup completed"
else
    log_warning "No log group name found - skipping"
fi

# Step 6: Clean up local files
log "Step 6: Cleaning up local files..."

# Remove temporary files
rm -f lifecycle-policy.json s3-oracle-policy.json redshift-trust-policy.json dashboard-config.json

# Clean up deployment vars file
if [ -f "./deployment_vars.env" ]; then
    if [ "$SKIP_CONFIRMATION" = false ]; then
        read -p "Remove deployment_vars.env file? (y/N): " REMOVE_VARS
        if [[ "$REMOVE_VARS" =~ ^[Yy]$ ]]; then
            rm -f ./deployment_vars.env
            log_success "Deployment variables file removed"
        else
            log "Keeping deployment_vars.env file"
        fi
    else
        rm -f ./deployment_vars.env
        log_success "Deployment variables file removed"
    fi
fi

log_success "Local files cleanup completed"

# Final verification
log "Step 7: Verifying cleanup..."

CLEANUP_ISSUES=()

# Check Redshift cluster
if [ -n "${REDSHIFT_CLUSTER_ID:-}" ]; then
    if aws redshift describe-clusters --cluster-identifier "${REDSHIFT_CLUSTER_ID}" &>/dev/null; then
        CLUSTER_STATUS=$(aws redshift describe-clusters \
            --cluster-identifier "${REDSHIFT_CLUSTER_ID}" \
            --query 'Clusters[0].ClusterStatus' --output text 2>/dev/null)
        if [ "$CLUSTER_STATUS" != "deleting" ]; then
            CLEANUP_ISSUES+=("Redshift cluster still exists: ${REDSHIFT_CLUSTER_ID}")
        else
            log "Redshift cluster deletion in progress"
        fi
    fi
fi

# Check S3 bucket
if [ -n "${S3_BUCKET_NAME:-}" ]; then
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &>/dev/null; then
        CLEANUP_ISSUES+=("S3 bucket still exists: ${S3_BUCKET_NAME}")
    fi
fi

# Check IAM role
if [ -n "${IAM_ROLE_NAME:-}" ]; then
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        CLEANUP_ISSUES+=("IAM role still exists: ${IAM_ROLE_NAME}")
    fi
fi

# Report results
echo ""
if [ ${#CLEANUP_ISSUES[@]} -eq 0 ]; then
    echo -e "${GREEN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                             CLEANUP COMPLETED                               ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    log_success "All resources have been successfully cleaned up!"
else
    echo -e "${YELLOW}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                         CLEANUP PARTIALLY COMPLETE                          ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    log_warning "Some resources may still exist:"
    for issue in "${CLEANUP_ISSUES[@]}"; do
        log_warning "  • $issue"
    done
    echo ""
    log "Please check the AWS Console to verify complete cleanup"
    log "Some resources may take additional time to fully delete"
fi

echo ""
log "🔍 Cleanup Summary:"
log "   • Oracle Database@AWS integrations: Disabled"
log "   • Redshift cluster: Deletion initiated"
log "   • S3 bucket: Removed"
log "   • IAM role: Deleted"
log "   • CloudWatch resources: Cleaned up"
log "   • Local files: Cleaned up"
echo ""

if [ ${#CLEANUP_ISSUES[@]} -gt 0 ]; then
    log_warning "If resources persist, you may need to:"
    log "   1. Check the AWS Console for resource status"
    log "   2. Manually delete any remaining resources"
    log "   3. Verify IAM permissions for resource deletion"
    echo ""
fi

log_success "Cleanup process completed!"

# Reset error handling if it was changed
if [ "$FORCE_CLEANUP" = true ]; then
    set -e
fi