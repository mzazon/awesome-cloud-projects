#!/bin/bash

# Storage Cost Optimization with S3 Storage Classes - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warning "Running in DRY-RUN mode - no resources will be deleted"
fi

# Banner
echo "======================================================="
echo "   S3 Storage Cost Optimization - Cleanup Script"
echo "======================================================="
echo

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI v2"
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure'"
fi

# Get AWS account information
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
    warning "No region configured, using default: $AWS_REGION"
fi

log "AWS Account ID: $AWS_ACCOUNT_ID"
log "AWS Region: $AWS_REGION"

# Load deployment information if available
if [ -f "deployment-info.json" ]; then
    log "Loading deployment information from deployment-info.json"
    
    BUCKET_NAME=$(jq -r '.bucket_name' deployment-info.json 2>/dev/null || echo "")
    ANALYTICS_CONFIG_ID=$(jq -r '.analytics_config_id' deployment-info.json 2>/dev/null || echo "")
    LIFECYCLE_CONFIG_ID=$(jq -r '.lifecycle_config_id' deployment-info.json 2>/dev/null || echo "")
    BUDGET_NAME=$(jq -r '.budget_name' deployment-info.json 2>/dev/null || echo "")
    RANDOM_SUFFIX=$(jq -r '.random_suffix' deployment-info.json 2>/dev/null || echo "")
    DASHBOARD_NAME=$(jq -r '.dashboard_name' deployment-info.json 2>/dev/null || echo "")
    
    if [ -n "$BUCKET_NAME" ] && [ "$BUCKET_NAME" != "null" ]; then
        log "Found deployment info - Bucket: $BUCKET_NAME"
    else
        warning "Could not load deployment info from deployment-info.json"
        BUCKET_NAME=""
    fi
else
    warning "deployment-info.json not found. You'll need to provide resource names manually."
    BUCKET_NAME=""
fi

# If no deployment info found, prompt for bucket name
if [ -z "$BUCKET_NAME" ]; then
    echo
    read -p "Enter the S3 bucket name to clean up (or press Enter to search): " BUCKET_NAME
    
    if [ -z "$BUCKET_NAME" ]; then
        log "Searching for storage optimization buckets..."
        BUCKET_LIST=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `storage-optimization-demo-`)].Name' --output text 2>/dev/null || echo "")
        
        if [ -n "$BUCKET_LIST" ]; then
            echo "Found potential buckets:"
            echo "$BUCKET_LIST" | tr '\t' '\n' | nl
            echo
            read -p "Enter the bucket name from the list above: " BUCKET_NAME
        else
            warning "No storage optimization buckets found. Exiting."
            exit 0
        fi
    fi
    
    # Extract suffix from bucket name if possible
    if [[ "$BUCKET_NAME" =~ storage-optimization-demo-([a-z0-9]+)$ ]]; then
        RANDOM_SUFFIX="${BASH_REMATCH[1]}"
        log "Extracted suffix: $RANDOM_SUFFIX"
    else
        RANDOM_SUFFIX=""
    fi
fi

# Confirm deletion
if [ "$DRY_RUN" != "true" ]; then
    echo
    warning "This will permanently delete the following resources:"
    echo "  • S3 Bucket: $BUCKET_NAME (and all contents)"
    echo "  • CloudWatch Dashboard: S3-Storage-Cost-Optimization-${RANDOM_SUFFIX}"
    echo "  • Cost Budget: S3-Storage-Cost-Budget-${RANDOM_SUFFIX}"
    echo "  • Storage Analytics Configuration"
    echo "  • Lifecycle Policies"
    echo "  • Intelligent Tiering Configuration"
    echo
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

# Start cleanup process
log "Starting cleanup process..."

# Remove CloudWatch dashboard
if [ -n "$RANDOM_SUFFIX" ]; then
    log "Removing CloudWatch dashboard..."
    DASHBOARD_NAME="S3-Storage-Cost-Optimization-${RANDOM_SUFFIX}"
    
    if [ "$DRY_RUN" != "true" ]; then
        if aws cloudwatch describe-dashboards --dashboard-names "$DASHBOARD_NAME" &>/dev/null; then
            aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME"
            success "Deleted CloudWatch dashboard: $DASHBOARD_NAME"
        else
            warning "CloudWatch dashboard not found: $DASHBOARD_NAME"
        fi
    else
        log "DRY-RUN: Would delete CloudWatch dashboard: $DASHBOARD_NAME"
    fi
else
    warning "Cannot determine dashboard name without suffix"
fi

# Remove cost budget
if [ -n "$RANDOM_SUFFIX" ]; then
    log "Removing cost budget..."
    BUDGET_NAME="S3-Storage-Cost-Budget-${RANDOM_SUFFIX}"
    
    if [ "$DRY_RUN" != "true" ]; then
        if aws budgets describe-budget --account-id "$AWS_ACCOUNT_ID" --budget-name "$BUDGET_NAME" &>/dev/null; then
            aws budgets delete-budget --account-id "$AWS_ACCOUNT_ID" --budget-name "$BUDGET_NAME"
            success "Deleted cost budget: $BUDGET_NAME"
        else
            warning "Cost budget not found: $BUDGET_NAME"
        fi
    else
        log "DRY-RUN: Would delete cost budget: $BUDGET_NAME"
    fi
else
    warning "Cannot determine budget name without suffix"
fi

# Remove S3 bucket configurations
if [ -n "$BUCKET_NAME" ]; then
    log "Checking if bucket exists..."
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log "Bucket $BUCKET_NAME exists, proceeding with cleanup..."
        
        # Remove lifecycle configuration
        log "Removing lifecycle configuration..."
        if [ "$DRY_RUN" != "true" ]; then
            if aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET_NAME" &>/dev/null; then
                aws s3api delete-bucket-lifecycle --bucket "$BUCKET_NAME"
                success "Removed lifecycle configuration"
            else
                warning "No lifecycle configuration found"
            fi
        else
            log "DRY-RUN: Would remove lifecycle configuration"
        fi
        
        # Remove analytics configuration
        log "Removing analytics configuration..."
        if [ "$DRY_RUN" != "true" ]; then
            # List and remove all analytics configurations
            ANALYTICS_IDS=$(aws s3api list-bucket-analytics-configurations --bucket "$BUCKET_NAME" --query 'AnalyticsConfigurationList[].Id' --output text 2>/dev/null || echo "")
            
            if [ -n "$ANALYTICS_IDS" ]; then
                for ANALYTICS_ID in $ANALYTICS_IDS; do
                    aws s3api delete-bucket-analytics-configuration --bucket "$BUCKET_NAME" --id "$ANALYTICS_ID"
                    success "Removed analytics configuration: $ANALYTICS_ID"
                done
            else
                warning "No analytics configurations found"
            fi
        else
            log "DRY-RUN: Would remove analytics configurations"
        fi
        
        # Remove intelligent tiering configuration
        log "Removing intelligent tiering configuration..."
        if [ "$DRY_RUN" != "true" ]; then
            # List and remove all intelligent tiering configurations
            TIERING_IDS=$(aws s3api list-bucket-intelligent-tiering-configurations --bucket "$BUCKET_NAME" --query 'IntelligentTieringConfigurationList[].Id' --output text 2>/dev/null || echo "")
            
            if [ -n "$TIERING_IDS" ]; then
                for TIERING_ID in $TIERING_IDS; do
                    aws s3api delete-bucket-intelligent-tiering-configuration --bucket "$BUCKET_NAME" --id "$TIERING_ID"
                    success "Removed intelligent tiering configuration: $TIERING_ID"
                done
            else
                warning "No intelligent tiering configurations found"
            fi
        else
            log "DRY-RUN: Would remove intelligent tiering configurations"
        fi
        
        # Check if bucket has versioning enabled
        log "Checking bucket versioning..."
        if [ "$DRY_RUN" != "true" ]; then
            VERSIONING_STATUS=$(aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" --query 'Status' --output text 2>/dev/null || echo "")
            
            if [ "$VERSIONING_STATUS" = "Enabled" ]; then
                warning "Bucket has versioning enabled. Deleting all object versions..."
                
                # Delete all object versions
                aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | while read -r key version_id; do
                    if [ -n "$key" ] && [ -n "$version_id" ]; then
                        aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id"
                    fi
                done
                
                # Delete all delete markers
                aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | while read -r key version_id; do
                    if [ -n "$key" ] && [ -n "$version_id" ]; then
                        aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id"
                    fi
                done
            fi
        fi
        
        # Remove all objects from bucket
        log "Removing all objects from bucket..."
        if [ "$DRY_RUN" != "true" ]; then
            OBJECT_COUNT=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --query 'KeyCount' --output text 2>/dev/null || echo "0")
            
            if [ "$OBJECT_COUNT" -gt 0 ]; then
                aws s3 rm s3://"$BUCKET_NAME" --recursive
                success "Removed all objects from bucket"
            else
                log "No objects found in bucket"
            fi
        else
            log "DRY-RUN: Would remove all objects from bucket"
        fi
        
        # Wait for objects to be fully deleted
        if [ "$DRY_RUN" != "true" ]; then
            log "Waiting for objects to be fully deleted..."
            sleep 5
        fi
        
        # Delete the bucket
        log "Deleting S3 bucket..."
        if [ "$DRY_RUN" != "true" ]; then
            aws s3api delete-bucket --bucket "$BUCKET_NAME"
            success "Deleted S3 bucket: $BUCKET_NAME"
        else
            log "DRY-RUN: Would delete S3 bucket: $BUCKET_NAME"
        fi
        
    else
        warning "Bucket $BUCKET_NAME does not exist or is not accessible"
    fi
else
    warning "No bucket name provided, skipping S3 cleanup"
fi

# Clean up local files
log "Cleaning up local files..."
if [ "$DRY_RUN" != "true" ]; then
    LOCAL_FILES=("temp-data" "analytics-config.json" "intelligent-tiering-config.json" "lifecycle-policy.json" "storage-dashboard.json" "cost-budget.json" "budget-notifications.json" "cost-analysis-script.py" "optimization-recommendations.py" "deployment-info.json")
    
    for file in "${LOCAL_FILES[@]}"; do
        if [ -e "$file" ]; then
            if [ -d "$file" ]; then
                rm -rf "$file"
            else
                rm -f "$file"
            fi
            success "Removed local file/directory: $file"
        fi
    done
else
    log "DRY-RUN: Would remove local files and directories"
fi

# Final verification
log "Performing final verification..."
if [ "$DRY_RUN" != "true" ]; then
    if [ -n "$BUCKET_NAME" ]; then
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            error "Bucket still exists after cleanup attempt"
        else
            success "Bucket deletion verified"
        fi
    fi
    
    if [ -n "$DASHBOARD_NAME" ]; then
        if aws cloudwatch describe-dashboards --dashboard-names "$DASHBOARD_NAME" &>/dev/null; then
            warning "Dashboard still exists after cleanup"
        else
            success "Dashboard deletion verified"
        fi
    fi
    
    if [ -n "$BUDGET_NAME" ]; then
        if aws budgets describe-budget --account-id "$AWS_ACCOUNT_ID" --budget-name "$BUDGET_NAME" &>/dev/null; then
            warning "Budget still exists after cleanup"
        else
            success "Budget deletion verified"
        fi
    fi
fi

echo
echo "======================================================="
echo "                   CLEANUP COMPLETE"
echo "======================================================="
echo

if [ "$DRY_RUN" != "true" ]; then
    echo "Successfully cleaned up the following resources:"
    echo "  ✅ S3 Bucket and all contents"
    echo "  ✅ CloudWatch Dashboard"
    echo "  ✅ Cost Budget"
    echo "  ✅ Storage Analytics Configuration"
    echo "  ✅ Lifecycle Policies"
    echo "  ✅ Intelligent Tiering Configuration"
    echo "  ✅ Local temporary files"
    echo
    echo "All resources have been successfully removed."
    echo "You may want to check your AWS bill to confirm no ongoing charges."
else
    echo "DRY-RUN completed successfully. No resources were deleted."
    echo "To perform actual cleanup, run: ./destroy.sh"
fi
echo
echo "Note: Some CloudWatch metrics may take up to 24 hours to stop appearing"
echo "in the AWS console, but no further charges will be incurred."