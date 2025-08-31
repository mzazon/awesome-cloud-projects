#!/bin/bash
set -e

# Website Monitoring with CloudWatch Synthetics - Cleanup Script
# This script safely removes all resources created by the deployment script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "=========================================="
    echo "⚠️  RESOURCE DESTRUCTION WARNING"
    echo "=========================================="
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "• CloudWatch Synthetics Canary: ${CANARY_NAME:-'Unknown'}"
    echo "• S3 Bucket and all artifacts: ${S3_BUCKET:-'Unknown'}"
    echo "• IAM Role: SyntheticsCanaryRole-${RANDOM_SUFFIX:-'Unknown'}"
    echo "• CloudWatch Alarms and Dashboard"
    echo "• SNS Topic and subscriptions"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    if [[ "$1" != "--force" ]]; then
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            echo "Destruction cancelled."
            exit 0
        fi
        
        echo ""
        read -p "Please type 'DELETE' to confirm resource destruction: " final_confirmation
        if [[ "$final_confirmation" != "DELETE" ]]; then
            echo "Destruction cancelled."
            exit 0
        fi
    fi
    
    echo ""
    log "Starting resource cleanup..."
}

echo "=========================================="
echo "Website Monitoring with CloudWatch Synthetics"
echo "Cleanup Script v1.0"
echo "=========================================="

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI v2.15 or later."
    exit 1
fi

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured or you don't have valid credentials."
    error "Please run 'aws configure' or set up your AWS credentials."
    exit 1
fi

# Load deployment info if available
if [[ -f ".deployment-info" ]]; then
    log "Loading deployment information..."
    source .deployment-info
    success "Loaded deployment info from previous deployment"
else
    warn "No deployment info file found. You may need to provide resource names manually."
    
    # Get user input for resource names
    echo ""
    read -p "Enter canary name (press Enter to skip): " input_canary
    CANARY_NAME="$input_canary"
    
    read -p "Enter S3 bucket name (press Enter to skip): " input_bucket
    S3_BUCKET="$input_bucket"
    
    read -p "Enter random suffix used in deployment (press Enter to skip): " input_suffix
    RANDOM_SUFFIX="$input_suffix"
    
    read -p "Enter AWS region (default: current CLI region): " input_region
    AWS_REGION=${input_region:-$(aws configure get region)}
    
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region is required. Please specify a region or configure AWS CLI with a default region."
        exit 1
    fi
    
    # Construct resource names based on input
    if [[ -n "$RANDOM_SUFFIX" ]]; then
        SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):synthetics-alerts-${RANDOM_SUFFIX}"
        DASHBOARD_NAME="Website-Monitoring-${RANDOM_SUFFIX}"
    fi
fi

# Show confirmation dialog
confirm_destruction "$1"

# Step 1: Stop and Delete Synthetics Canary
if [[ -n "$CANARY_NAME" ]]; then
    log "Step 1: Removing synthetics canary..."
    
    # Check if canary exists
    if aws synthetics get-canary --name "$CANARY_NAME" &>/dev/null; then
        # Stop the canary first
        log "Stopping canary: ${CANARY_NAME}"
        aws synthetics stop-canary --name "$CANARY_NAME" || warn "Failed to stop canary (may already be stopped)"
        
        # Wait for canary to stop
        log "Waiting for canary to stop..."
        sleep 30
        
        # Delete the canary
        log "Deleting canary: ${CANARY_NAME}"
        aws synthetics delete-canary --name "$CANARY_NAME"
        success "Deleted canary: ${CANARY_NAME}"
    else
        warn "Canary ${CANARY_NAME} not found or already deleted"
    fi
else
    warn "No canary name provided, skipping canary deletion"
fi

# Step 2: Delete CloudWatch Alarms
if [[ -n "$CANARY_NAME" ]]; then
    log "Step 2: Removing CloudWatch alarms..."
    
    # List of alarms to delete
    ALARMS_TO_DELETE=(
        "${CANARY_NAME}-FailureAlarm"
        "${CANARY_NAME}-ResponseTimeAlarm"
    )
    
    for alarm in "${ALARMS_TO_DELETE[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm"; then
            log "Deleting alarm: ${alarm}"
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            success "Deleted alarm: ${alarm}"
        else
            warn "Alarm ${alarm} not found or already deleted"
        fi
    done
else
    warn "No canary name provided, skipping alarm deletion"
fi

# Step 3: Delete CloudWatch Dashboard
if [[ -n "$DASHBOARD_NAME" ]]; then
    log "Step 3: Removing CloudWatch dashboard..."
    
    if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME"
        success "Deleted dashboard: ${DASHBOARD_NAME}"
    else
        warn "Dashboard ${DASHBOARD_NAME} not found or already deleted"
    fi
else
    warn "No dashboard name available, skipping dashboard deletion"
fi

# Step 4: Delete SNS Topic and Subscriptions
if [[ -n "$SNS_TOPIC_ARN" ]]; then
    log "Step 4: Removing SNS topic and subscriptions..."
    
    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
        # List and delete all subscriptions first
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$SUBSCRIPTIONS" && "$SUBSCRIPTIONS" != "None" ]]; then
            for sub_arn in $SUBSCRIPTIONS; do
                if [[ "$sub_arn" != "PendingConfirmation" ]]; then
                    log "Deleting subscription: ${sub_arn}"
                    aws sns unsubscribe --subscription-arn "$sub_arn" || warn "Failed to delete subscription"
                fi
            done
        fi
        
        # Delete the topic
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
        success "Deleted SNS topic and subscriptions"
    else
        warn "SNS topic not found or already deleted"
    fi
else
    warn "No SNS topic ARN available, skipping SNS cleanup"
fi

# Step 5: Delete IAM Role
if [[ -n "$RANDOM_SUFFIX" ]]; then
    log "Step 5: Removing IAM role..."
    
    ROLE_NAME="SyntheticsCanaryRole-${RANDOM_SUFFIX}"
    
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        # Detach managed policies
        log "Detaching policies from role: ${ROLE_NAME}"
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchSyntheticsExecutionRolePolicy || warn "Failed to detach policy"
        
        # Delete the role
        aws iam delete-role --role-name "$ROLE_NAME"
        success "Deleted IAM role: ${ROLE_NAME}"
    else
        warn "IAM role ${ROLE_NAME} not found or already deleted"
    fi
else
    warn "No random suffix available, skipping IAM role deletion"
fi

# Step 6: Empty and Delete S3 Bucket
if [[ -n "$S3_BUCKET" ]]; then
    log "Step 6: Removing S3 bucket and artifacts..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        # List objects first to show what will be deleted
        OBJECT_COUNT=$(aws s3api list-objects-v2 --bucket "$S3_BUCKET" --query 'KeyCount' --output text 2>/dev/null || echo "0")
        
        if [[ "$OBJECT_COUNT" != "0" ]]; then
            log "Deleting ${OBJECT_COUNT} objects from bucket: ${S3_BUCKET}"
            
            # Delete all object versions (for versioned buckets)
            aws s3api list-object-versions --bucket "$S3_BUCKET" --query 'Versions[].[Key,VersionId]' --output text 2>/dev/null | \
            while read key version; do
                if [[ -n "$key" && -n "$version" ]]; then
                    aws s3api delete-object --bucket "$S3_BUCKET" --key "$key" --version-id "$version" &>/dev/null || true
                fi
            done
            
            # Delete all delete markers (for versioned buckets)
            aws s3api list-object-versions --bucket "$S3_BUCKET" --query 'DeleteMarkers[].[Key,VersionId]' --output text 2>/dev/null | \
            while read key version; do
                if [[ -n "$key" && -n "$version" ]]; then
                    aws s3api delete-object --bucket "$S3_BUCKET" --key "$key" --version-id "$version" &>/dev/null || true
                fi
            done
            
            # Final cleanup with recursive delete
            aws s3 rm "s3://${S3_BUCKET}" --recursive &>/dev/null || true
        fi
        
        # Delete the bucket
        aws s3 rb "s3://${S3_BUCKET}" --force
        success "Deleted S3 bucket: ${S3_BUCKET}"
    else
        warn "S3 bucket ${S3_BUCKET} not found or already deleted"
    fi
else
    warn "No S3 bucket name available, skipping bucket deletion"
fi

# Step 7: Clean up local files
log "Step 7: Cleaning up local files..."

# Remove deployment info file
if [[ -f ".deployment-info" ]]; then
    rm -f .deployment-info
    success "Removed deployment info file"
fi

# Remove any temporary files that might still exist
rm -f synthetics-trust-policy.json canary-script.js canary-package.zip dashboard-config.json

success "Cleaned up local temporary files"

echo ""
echo "=========================================="
echo "✅ CLEANUP COMPLETED SUCCESSFULLY!"
echo "=========================================="
echo ""
echo "All resources have been removed from AWS."
echo "Your AWS account will no longer incur charges for these resources."
echo ""

# Final verification
if [[ -n "$CANARY_NAME" ]]; then
    log "Performing final verification..."
    
    # Check if canary still exists
    if aws synthetics get-canary --name "$CANARY_NAME" &>/dev/null; then
        warn "Canary ${CANARY_NAME} still exists - deletion may take a few minutes"
    else
        success "Verified: Canary ${CANARY_NAME} has been deleted"
    fi
    
    # Check if S3 bucket still exists
    if [[ -n "$S3_BUCKET" ]] && aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        warn "S3 bucket ${S3_BUCKET} still exists - deletion may take a few minutes"
    elif [[ -n "$S3_BUCKET" ]]; then
        success "Verified: S3 bucket ${S3_BUCKET} has been deleted"
    fi
fi

echo ""
echo "Thank you for using the Website Monitoring with CloudWatch Synthetics solution!"
echo ""