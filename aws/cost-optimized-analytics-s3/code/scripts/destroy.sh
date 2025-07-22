#!/bin/bash

# Cost-Optimized Analytics with S3 Tiering - Cleanup Script
# This script safely removes all infrastructure created by the deployment script
# with proper confirmation prompts and error handling

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Banner
echo "=================================================="
echo "   Cost-Optimized Analytics Cleanup Script"
echo "   S3 Intelligent-Tiering + Athena + Glue"
echo "=================================================="
echo

# Function to prompt for confirmation
confirm_action() {
    local action="$1"
    local resource="$2"
    
    echo -e "${YELLOW}⚠️  About to $action: $resource${NC}"
    read -p "Are you sure you want to proceed? (yes/no): " choice
    case "$choice" in 
        yes|YES|y|Y ) return 0;;
        * ) echo "Skipping $action for $resource"; return 1;;
    esac
}

# Function to load deployment variables
load_deployment_vars() {
    local env_file="$1"
    if [ -f "$env_file" ]; then
        log "Loading deployment variables from $env_file"
        source "$env_file"
        return 0
    else
        return 1
    fi
}

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install AWS CLI v2 and try again."
    exit 1
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' and try again."
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

log_success "Prerequisites check completed"
log "AWS Account ID: $AWS_ACCOUNT_ID"
log "AWS Region: $AWS_REGION"
echo

# Try to load deployment variables from various sources
DEPLOYMENT_VARS_LOADED=false

# Method 1: Command line arguments
if [ $# -eq 1 ] && [ -f "$1" ]; then
    if load_deployment_vars "$1"; then
        DEPLOYMENT_VARS_LOADED=true
        log_success "Loaded deployment variables from provided file: $1"
    fi
fi

# Method 2: Look for recent deployment files in /tmp
if [ "$DEPLOYMENT_VARS_LOADED" = false ]; then
    log "Searching for recent deployment variable files..."
    RECENT_ENV_FILE=$(find /tmp -name "deployment-vars-*.env" -type f -mtime -1 2>/dev/null | head -1)
    if [ ! -z "$RECENT_ENV_FILE" ] && [ -f "$RECENT_ENV_FILE" ]; then
        if load_deployment_vars "$RECENT_ENV_FILE"; then
            DEPLOYMENT_VARS_LOADED=true
            log_success "Found and loaded recent deployment variables from: $RECENT_ENV_FILE"
        fi
    fi
fi

# Method 3: Manual input if variables not found
if [ "$DEPLOYMENT_VARS_LOADED" = false ]; then
    log_warning "Deployment variables file not found. Please provide resource details manually."
    echo
    
    echo "Please enter the resource names (or press Enter to search for resources):"
    read -p "S3 Bucket Name (or Enter to search): " BUCKET_NAME
    read -p "Glue Database Name (or Enter to search): " GLUE_DATABASE
    read -p "Athena Workgroup Name (or Enter to search): " ATHENA_WORKGROUP
    read -p "Random Suffix (used in resource names): " RANDOM_SUFFIX
    
    # If still empty, try to discover resources
    if [ -z "$BUCKET_NAME" ] || [ -z "$GLUE_DATABASE" ] || [ -z "$ATHENA_WORKGROUP" ]; then
        log "Attempting to discover resources automatically..."
        
        if [ -z "$BUCKET_NAME" ]; then
            log "Searching for S3 buckets with 'cost-optimized-analytics' prefix..."
            BUCKET_NAME=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `cost-optimized-analytics`)].Name' --output text | head -1)
        fi
        
        if [ -z "$GLUE_DATABASE" ]; then
            log "Searching for Glue databases with 'analytics_database' prefix..."
            GLUE_DATABASE=$(aws glue get-databases --query 'DatabaseList[?contains(Name, `analytics_database`)].Name' --output text | head -1)
        fi
        
        if [ -z "$ATHENA_WORKGROUP" ]; then
            log "Searching for Athena workgroups with 'cost-optimized-workgroup' prefix..."
            ATHENA_WORKGROUP=$(aws athena list-work-groups --query 'WorkGroups[?contains(Name, `cost-optimized-workgroup`)].Name' --output text | head -1)
        fi
    fi
fi

# Validate that we have the required variables
if [ -z "${BUCKET_NAME:-}" ] && [ -z "${GLUE_DATABASE:-}" ] && [ -z "${ATHENA_WORKGROUP:-}" ]; then
    log_error "Could not find any resources to clean up. Please ensure:"
    echo "  1. You provide the deployment variables file as an argument"
    echo "  2. Or the resources were created with the expected naming convention"
    echo "  3. Or manually specify the resource names when prompted"
    echo
    echo "Usage: $0 [deployment-vars-file.env]"
    exit 1
fi

# Display resources that will be deleted
echo "Resources to be deleted:"
echo "======================="
[ ! -z "${BUCKET_NAME:-}" ] && echo "  🗑️  S3 Bucket: $BUCKET_NAME"
[ ! -z "${GLUE_DATABASE:-}" ] && echo "  🗑️  Glue Database: $GLUE_DATABASE"
[ ! -z "${ATHENA_WORKGROUP:-}" ] && echo "  🗑️  Athena Workgroup: $ATHENA_WORKGROUP"
[ ! -z "${RANDOM_SUFFIX:-}" ] && echo "  🗑️  CloudWatch Dashboard: S3-Cost-Optimization-${RANDOM_SUFFIX}"
[ ! -z "${RANDOM_SUFFIX:-}" ] && echo "  🗑️  Cost Anomaly Detector: S3-Cost-Anomaly-${RANDOM_SUFFIX}"
echo "======================="
echo

# Final confirmation
echo -e "${RED}⚠️  WARNING: This action will permanently delete all resources and data!${NC}"
echo -e "${RED}⚠️  This action cannot be undone!${NC}"
echo
if ! confirm_action "DELETE ALL RESOURCES" "Cost-Optimized Analytics Infrastructure"; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo
log "Starting infrastructure cleanup..."

# Step 1: Remove Athena resources
if [ ! -z "${ATHENA_WORKGROUP:-}" ]; then
    log "Step 1: Removing Athena workgroup..."
    
    # Check if workgroup exists
    if aws athena get-work-group --work-group "$ATHENA_WORKGROUP" &> /dev/null; then
        # Cancel any running queries first
        log "Checking for running queries in workgroup..."
        RUNNING_QUERIES=$(aws athena list-query-executions \
            --work-group "$ATHENA_WORKGROUP" \
            --query 'QueryExecutionIds' \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$RUNNING_QUERIES" ]; then
            log_warning "Found running queries. Attempting to cancel them..."
            for query_id in $RUNNING_QUERIES; do
                aws athena stop-query-execution --query-execution-id "$query_id" 2>/dev/null || true
            done
            sleep 5
        fi
        
        # Delete workgroup
        aws athena delete-work-group \
            --work-group "$ATHENA_WORKGROUP" \
            --recursive-delete-option
        
        log_success "Athena workgroup deleted: $ATHENA_WORKGROUP"
    else
        log_warning "Athena workgroup not found: $ATHENA_WORKGROUP"
    fi
else
    log_warning "Athena workgroup name not provided, skipping..."
fi

# Step 2: Remove Glue resources
if [ ! -z "${GLUE_DATABASE:-}" ]; then
    log "Step 2: Removing Glue database and tables..."
    
    # Check if database exists
    if aws glue get-database --name "$GLUE_DATABASE" &> /dev/null; then
        # Delete table first
        if aws glue get-table --database-name "$GLUE_DATABASE" --name "transaction_logs" &> /dev/null; then
            aws glue delete-table \
                --database-name "$GLUE_DATABASE" \
                --name "transaction_logs"
            log_success "Glue table deleted: transaction_logs"
        fi
        
        # Delete database
        aws glue delete-database --name "$GLUE_DATABASE"
        log_success "Glue database deleted: $GLUE_DATABASE"
    else
        log_warning "Glue database not found: $GLUE_DATABASE"
    fi
else
    log_warning "Glue database name not provided, skipping..."
fi

# Step 3: Remove CloudWatch resources
if [ ! -z "${RANDOM_SUFFIX:-}" ]; then
    log "Step 3: Removing CloudWatch dashboard and cost anomaly detector..."
    
    # Delete CloudWatch dashboard
    DASHBOARD_NAME="S3-Cost-Optimization-${RANDOM_SUFFIX}"
    if aws cloudwatch describe-dashboards --dashboard-names "$DASHBOARD_NAME" &> /dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME"
        log_success "CloudWatch dashboard deleted: $DASHBOARD_NAME"
    else
        log_warning "CloudWatch dashboard not found: $DASHBOARD_NAME"
    fi
    
    # Delete cost anomaly detector
    DETECTOR_NAME="S3-Cost-Anomaly-${RANDOM_SUFFIX}"
    DETECTOR_ARN=$(aws ce get-anomaly-detectors \
        --query "AnomalyDetectors[?DetectorName=='$DETECTOR_NAME'].DetectorArn" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$DETECTOR_ARN" ] && [ "$DETECTOR_ARN" != "None" ]; then
        aws ce delete-anomaly-detector --detector-arn "$DETECTOR_ARN"
        log_success "Cost anomaly detector deleted: $DETECTOR_NAME"
    else
        log_warning "Cost anomaly detector not found: $DETECTOR_NAME"
    fi
else
    log_warning "Random suffix not provided, skipping CloudWatch resources..."
fi

# Step 4: Empty and delete S3 bucket
if [ ! -z "${BUCKET_NAME:-}" ]; then
    log "Step 4: Emptying and deleting S3 bucket..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &> /dev/null; then
        log "Emptying S3 bucket contents..."
        
        # Remove all objects
        aws s3 rm "s3://$BUCKET_NAME" --recursive --quiet
        
        # Remove all object versions and delete markers (for versioned buckets)
        log "Removing object versions and delete markers..."
        aws s3api list-object-versions --bucket "$BUCKET_NAME" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" --quiet
            fi
        done
        
        aws s3api list-object-versions --bucket "$BUCKET_NAME" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" --quiet
            fi
        done
        
        # Wait a moment for eventual consistency
        sleep 5
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "$BUCKET_NAME"
        log_success "S3 bucket deleted: $BUCKET_NAME"
    else
        log_warning "S3 bucket not found: $BUCKET_NAME"
    fi
else
    log_warning "S3 bucket name not provided, skipping..."
fi

# Step 5: Clean up temporary files
log "Step 5: Cleaning up temporary files..."

# Remove cost analysis script
if [ ! -z "${RANDOM_SUFFIX:-}" ]; then
    COST_ANALYSIS_SCRIPT="/tmp/cost-analysis-${RANDOM_SUFFIX}.sh"
    if [ -f "$COST_ANALYSIS_SCRIPT" ]; then
        rm -f "$COST_ANALYSIS_SCRIPT"
        log_success "Removed cost analysis script: $COST_ANALYSIS_SCRIPT"
    fi
    
    # Remove deployment variables file
    DEPLOYMENT_VARS_FILE="/tmp/deployment-vars-${RANDOM_SUFFIX}.env"
    if [ -f "$DEPLOYMENT_VARS_FILE" ]; then
        rm -f "$DEPLOYMENT_VARS_FILE"
        log_success "Removed deployment variables file: $DEPLOYMENT_VARS_FILE"
    fi
fi

# Remove any remaining temporary files
rm -f /tmp/test-download.csv 2>/dev/null || true

log_success "Temporary files cleaned up"

# Final verification
log "Step 6: Performing final verification..."

CLEANUP_ERRORS=0

# Verify S3 bucket deletion
if [ ! -z "${BUCKET_NAME:-}" ]; then
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &> /dev/null; then
        log_error "S3 bucket still exists: $BUCKET_NAME"
        CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
    fi
fi

# Verify Glue database deletion
if [ ! -z "${GLUE_DATABASE:-}" ]; then
    if aws glue get-database --name "$GLUE_DATABASE" &> /dev/null; then
        log_error "Glue database still exists: $GLUE_DATABASE"
        CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
    fi
fi

# Verify Athena workgroup deletion
if [ ! -z "${ATHENA_WORKGROUP:-}" ]; then
    if aws athena get-work-group --work-group "$ATHENA_WORKGROUP" &> /dev/null; then
        log_error "Athena workgroup still exists: $ATHENA_WORKGROUP"
        CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
    fi
fi

if [ $CLEANUP_ERRORS -eq 0 ]; then
    log_success "All resources verified as deleted"
else
    log_warning "$CLEANUP_ERRORS resource(s) may still exist. Please check manually."
fi

# Summary
echo
echo "=================================================="
if [ $CLEANUP_ERRORS -eq 0 ]; then
    echo "         CLEANUP COMPLETED SUCCESSFULLY"
else
    echo "         CLEANUP COMPLETED WITH WARNINGS"
fi
echo "=================================================="
echo

if [ $CLEANUP_ERRORS -eq 0 ]; then
    echo "✅ All resources have been successfully removed:"
    [ ! -z "${BUCKET_NAME:-}" ] && echo "  ✅ S3 Bucket: $BUCKET_NAME"
    [ ! -z "${GLUE_DATABASE:-}" ] && echo "  ✅ Glue Database: $GLUE_DATABASE"
    [ ! -z "${ATHENA_WORKGROUP:-}" ] && echo "  ✅ Athena Workgroup: $ATHENA_WORKGROUP"
    [ ! -z "${RANDOM_SUFFIX:-}" ] && echo "  ✅ CloudWatch Dashboard: S3-Cost-Optimization-${RANDOM_SUFFIX}"
    [ ! -z "${RANDOM_SUFFIX:-}" ] && echo "  ✅ Cost Anomaly Detector: S3-Cost-Anomaly-${RANDOM_SUFFIX}"
    [ ! -z "${RANDOM_SUFFIX:-}" ] && echo "  ✅ Temporary Files: /tmp/*-${RANDOM_SUFFIX}.*"
else
    echo "⚠️  Some resources may still exist. Please verify manually:"
    echo
    echo "To check remaining resources:"
    echo "  aws s3 ls | grep cost-optimized-analytics"
    echo "  aws glue get-databases --query 'DatabaseList[?contains(Name, \`analytics_database\`)].Name'"
    echo "  aws athena list-work-groups --query 'WorkGroups[?contains(Name, \`cost-optimized-workgroup\`)].Name'"
fi

echo
echo "Cost Impact:"
echo "  💰 No more charges for S3 storage, Athena queries, or Glue catalog"
echo "  💰 CloudWatch dashboard and cost anomaly detector charges stopped"
echo
echo "Next Steps:"
echo "  1. Verify no unexpected charges in AWS Cost Explorer"
echo "  2. Check CloudWatch billing alarms if configured"
echo "  3. Review AWS Config rules if they were monitoring these resources"

if [ $CLEANUP_ERRORS -eq 0 ]; then
    echo
    echo "🎉 Cost-Optimized Analytics infrastructure successfully removed!"
else
    echo
    echo "⚠️  Please manually verify and remove any remaining resources."
fi

echo "=================================================="

exit $CLEANUP_ERRORS