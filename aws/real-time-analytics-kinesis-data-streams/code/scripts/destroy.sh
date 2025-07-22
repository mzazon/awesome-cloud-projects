#!/bin/bash

# ==============================================================================
# AWS Real-Time Analytics with Kinesis Data Streams - Cleanup Script
# ==============================================================================
# This script safely removes all resources created by the deployment script:
# - Amazon Kinesis Data Streams
# - AWS Lambda functions and event source mappings
# - Amazon S3 buckets and data
# - IAM roles and policies
# - CloudWatch dashboards and alarms
# ==============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for force flag
FORCE_DELETE=false
if [[ "$1" == "--force" ]]; then
    FORCE_DELETE=true
    log_warning "Force delete mode enabled - skipping confirmations"
fi

# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================

log_info "Setting up environment for cleanup..."

# Check if environment variables file exists
if [[ -f ".env_vars" ]]; then
    log_info "Loading environment variables from .env_vars file..."
    source .env_vars
else
    log_warning "No .env_vars file found, using default naming patterns"
    
    # Try to determine environment variables
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        log_error "Cannot determine AWS account ID. Please ensure AWS CLI is configured."
        exit 1
    fi
    
    # If no env file, try to find resources by pattern
    log_info "Scanning for resources with common patterns..."
    
    # Find Kinesis streams with analytics pattern
    STREAMS=$(aws kinesis list-streams --query 'StreamNames[?contains(@, `analytics-stream`)]' --output text 2>/dev/null || echo "")
    if [[ -n "$STREAMS" ]]; then
        export STREAM_NAME=$(echo "$STREAMS" | head -n1)
        # Extract suffix from stream name
        RANDOM_SUFFIX=${STREAM_NAME#*analytics-stream-}
        export RANDOM_SUFFIX="$RANDOM_SUFFIX"
        export LAMBDA_FUNCTION_NAME="stream-processor-${RANDOM_SUFFIX}"
        export S3_BUCKET_NAME="kinesis-analytics-${RANDOM_SUFFIX}"
        export IAM_ROLE_NAME="KinesisAnalyticsRole-${RANDOM_SUFFIX}"
    fi
fi

# Display current environment
log_info "Cleanup environment:"
log_info "  AWS Region: ${AWS_REGION:-'Not set'}"
log_info "  AWS Account ID: ${AWS_ACCOUNT_ID:-'Not set'}"
log_info "  Stream Name: ${STREAM_NAME:-'Not set'}"
log_info "  Lambda Function: ${LAMBDA_FUNCTION_NAME:-'Not set'}"
log_info "  S3 Bucket: ${S3_BUCKET_NAME:-'Not set'}"
log_info "  IAM Role: ${IAM_ROLE_NAME:-'Not set'}"
log_info "  Random Suffix: ${RANDOM_SUFFIX:-'Not set'}"

# ==============================================================================
# CONFIRMATION PROMPT
# ==============================================================================

if [[ "$FORCE_DELETE" == "false" ]]; then
    echo ""
    echo "===================================================================================="
    echo "                              ⚠️  RESOURCE CLEANUP WARNING  ⚠️"
    echo "===================================================================================="
    echo ""
    echo "This script will DELETE the following AWS resources:"
    echo ""
    if [[ -n "$STREAM_NAME" ]]; then
        echo "🔄 Kinesis Data Stream: $STREAM_NAME"
    fi
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        echo "⚡ Lambda Function: $LAMBDA_FUNCTION_NAME"
    fi
    if [[ -n "$S3_BUCKET_NAME" ]]; then
        echo "🗄️  S3 Bucket: $S3_BUCKET_NAME (including ALL data)"
    fi
    if [[ -n "$IAM_ROLE_NAME" ]]; then
        echo "🔐 IAM Role: $IAM_ROLE_NAME"
    fi
    if [[ -n "$RANDOM_SUFFIX" ]]; then
        echo "📈 CloudWatch Dashboard: KinesisAnalytics-${RANDOM_SUFFIX}"
        echo "🚨 CloudWatch Alarms: KinesisHighIncomingRecords-${RANDOM_SUFFIX}, LambdaProcessingErrors-${RANDOM_SUFFIX}"
    fi
    echo ""
    echo "⚠️  THIS ACTION CANNOT BE UNDONE! ⚠️"
    echo ""
    echo "All streaming data, processed analytics, and configurations will be permanently lost."
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_info "Proceeding with resource cleanup..."
fi

# ==============================================================================
# LAMBDA EVENT SOURCE MAPPING CLEANUP
# ==============================================================================

log_info "Removing Lambda event source mappings..."

if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
    # Get all event source mappings for the function
    EVENT_SOURCE_MAPPINGS=$(aws lambda list-event-source-mappings \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'EventSourceMappings[].UUID' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$EVENT_SOURCE_MAPPINGS" && "$EVENT_SOURCE_MAPPINGS" != "None" ]]; then
        for uuid in $EVENT_SOURCE_MAPPINGS; do
            log_info "Deleting event source mapping: $uuid"
            aws lambda delete-event-source-mapping --uuid "$uuid" >/dev/null 2>&1 || {
                log_warning "Failed to delete event source mapping: $uuid"
            }
        done
        log_success "Event source mappings removed"
    else
        log_info "No event source mappings found"
    fi
else
    log_warning "Lambda function name not available, skipping event source mapping cleanup"
fi

# ==============================================================================
# LAMBDA FUNCTION CLEANUP
# ==============================================================================

log_info "Removing Lambda function..."

if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log_success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
    else
        log_info "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi
else
    # Try to find and delete Lambda functions with common pattern
    log_info "Searching for Lambda functions with stream-processor pattern..."
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `stream-processor`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$LAMBDA_FUNCTIONS" ]]; then
        for func in $LAMBDA_FUNCTIONS; do
            log_info "Found Lambda function: $func"
            if [[ "$FORCE_DELETE" == "true" ]]; then
                aws lambda delete-function --function-name "$func" 2>/dev/null || {
                    log_warning "Failed to delete Lambda function: $func"
                }
                log_success "Lambda function deleted: $func"
            else
                read -p "Delete Lambda function $func? (y/n): " delete_func
                if [[ "$delete_func" == "y" ]]; then
                    aws lambda delete-function --function-name "$func"
                    log_success "Lambda function deleted: $func"
                fi
            fi
        done
    else
        log_info "No Lambda functions found with stream-processor pattern"
    fi
fi

# ==============================================================================
# CLOUDWATCH RESOURCES CLEANUP
# ==============================================================================

log_info "Removing CloudWatch resources..."

if [[ -n "$RANDOM_SUFFIX" ]]; then
    # Delete CloudWatch alarms
    ALARM_NAMES=(
        "KinesisHighIncomingRecords-${RANDOM_SUFFIX}"
        "LambdaProcessingErrors-${RANDOM_SUFFIX}"
    )
    
    for alarm in "${ALARM_NAMES[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm"; then
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            log_success "CloudWatch alarm deleted: $alarm"
        else
            log_info "CloudWatch alarm not found: $alarm"
        fi
    done
    
    # Delete CloudWatch dashboard
    DASHBOARD_NAME="KinesisAnalytics-${RANDOM_SUFFIX}"
    if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" >/dev/null 2>&1; then
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME"
        log_success "CloudWatch dashboard deleted: $DASHBOARD_NAME"
    else
        log_info "CloudWatch dashboard not found: $DASHBOARD_NAME"
    fi
else
    log_warning "Random suffix not available, searching for resources with pattern..."
    
    # Find and delete alarms with pattern
    KINESIS_ALARMS=$(aws cloudwatch describe-alarms \
        --query 'MetricAlarms[?contains(AlarmName, `KinesisHighIncomingRecords`)].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    LAMBDA_ALARMS=$(aws cloudwatch describe-alarms \
        --query 'MetricAlarms[?contains(AlarmName, `LambdaProcessingErrors`)].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    ALL_ALARMS="$KINESIS_ALARMS $LAMBDA_ALARMS"
    
    if [[ -n "$ALL_ALARMS" && "$ALL_ALARMS" != " " ]]; then
        for alarm in $ALL_ALARMS; do
            if [[ "$FORCE_DELETE" == "true" ]]; then
                aws cloudwatch delete-alarms --alarm-names "$alarm" 2>/dev/null || {
                    log_warning "Failed to delete alarm: $alarm"
                }
                log_success "CloudWatch alarm deleted: $alarm"
            else
                read -p "Delete CloudWatch alarm $alarm? (y/n): " delete_alarm
                if [[ "$delete_alarm" == "y" ]]; then
                    aws cloudwatch delete-alarms --alarm-names "$alarm"
                    log_success "CloudWatch alarm deleted: $alarm"
                fi
            fi
        done
    fi
    
    # Find and delete dashboards with pattern
    DASHBOARDS=$(aws cloudwatch list-dashboards \
        --query 'DashboardEntries[?contains(DashboardName, `KinesisAnalytics`)].DashboardName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$DASHBOARDS" ]]; then
        for dashboard in $DASHBOARDS; do
            if [[ "$FORCE_DELETE" == "true" ]]; then
                aws cloudwatch delete-dashboards --dashboard-names "$dashboard" 2>/dev/null || {
                    log_warning "Failed to delete dashboard: $dashboard"
                }
                log_success "CloudWatch dashboard deleted: $dashboard"
            else
                read -p "Delete CloudWatch dashboard $dashboard? (y/n): " delete_dashboard
                if [[ "$delete_dashboard" == "y" ]]; then
                    aws cloudwatch delete-dashboards --dashboard-names "$dashboard"
                    log_success "CloudWatch dashboard deleted: $dashboard"
                fi
            fi
        done
    fi
fi

# ==============================================================================
# KINESIS STREAM CLEANUP
# ==============================================================================

log_info "Removing Kinesis Data Stream..."

if [[ -n "$STREAM_NAME" ]]; then
    if aws kinesis describe-stream --stream-name "$STREAM_NAME" >/dev/null 2>&1; then
        log_info "Disabling enhanced monitoring..."
        aws kinesis disable-enhanced-monitoring \
            --stream-name "$STREAM_NAME" \
            --shard-level-metrics ALL 2>/dev/null || {
            log_warning "Failed to disable enhanced monitoring"
        }
        
        log_info "Deleting stream: $STREAM_NAME"
        aws kinesis delete-stream --stream-name "$STREAM_NAME"
        
        log_info "Waiting for stream deletion to complete..."
        # Wait up to 5 minutes for deletion
        for i in {1..60}; do
            if ! aws kinesis describe-stream --stream-name "$STREAM_NAME" >/dev/null 2>&1; then
                break
            fi
            sleep 5
        done
        
        log_success "Kinesis stream deleted: $STREAM_NAME"
    else
        log_info "Kinesis stream not found: $STREAM_NAME"
    fi
else
    # Find streams with analytics pattern
    log_info "Searching for Kinesis streams with analytics pattern..."
    STREAMS=$(aws kinesis list-streams \
        --query 'StreamNames[?contains(@, `analytics-stream`)]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$STREAMS" ]]; then
        for stream in $STREAMS; do
            log_info "Found Kinesis stream: $stream"
            if [[ "$FORCE_DELETE" == "true" ]]; then
                aws kinesis delete-stream --stream-name "$stream" 2>/dev/null || {
                    log_warning "Failed to delete stream: $stream"
                }
                log_success "Kinesis stream deleted: $stream"
            else
                read -p "Delete Kinesis stream $stream? (y/n): " delete_stream
                if [[ "$delete_stream" == "y" ]]; then
                    aws kinesis delete-stream --stream-name "$stream"
                    log_success "Kinesis stream deleted: $stream"
                fi
            fi
        done
    else
        log_info "No Kinesis streams found with analytics pattern"
    fi
fi

# ==============================================================================
# S3 BUCKET CLEANUP
# ==============================================================================

log_info "Removing S3 bucket and data..."

if [[ -n "$S3_BUCKET_NAME" ]]; then
    if aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        log_info "Emptying S3 bucket: $S3_BUCKET_NAME"
        
        # Delete all objects and versions
        aws s3api delete-objects \
            --bucket "$S3_BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$S3_BUCKET_NAME" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
        
        # Delete all delete markers
        aws s3api delete-objects \
            --bucket "$S3_BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$S3_BUCKET_NAME" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
        
        # Remove all objects (simple deletion)
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || true
        
        # Delete the bucket
        aws s3 rb "s3://${S3_BUCKET_NAME}" --force
        log_success "S3 bucket deleted: $S3_BUCKET_NAME"
    else
        log_info "S3 bucket not found: $S3_BUCKET_NAME"
    fi
else
    # Find buckets with kinesis-analytics pattern
    log_info "Searching for S3 buckets with kinesis-analytics pattern..."
    BUCKETS=$(aws s3 ls | grep "kinesis-analytics" | awk '{print $3}' 2>/dev/null || echo "")
    
    if [[ -n "$BUCKETS" ]]; then
        for bucket in $BUCKETS; do
            log_info "Found S3 bucket: $bucket"
            if [[ "$FORCE_DELETE" == "true" ]]; then
                aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true
                aws s3 rb "s3://${bucket}" --force 2>/dev/null || {
                    log_warning "Failed to delete bucket: $bucket"
                }
                log_success "S3 bucket deleted: $bucket"
            else
                read -p "Delete S3 bucket $bucket and ALL its data? (y/n): " delete_bucket
                if [[ "$delete_bucket" == "y" ]]; then
                    aws s3 rm "s3://${bucket}" --recursive
                    aws s3 rb "s3://${bucket}" --force
                    log_success "S3 bucket deleted: $bucket"
                fi
            fi
        done
    else
        log_info "No S3 buckets found with kinesis-analytics pattern"
    fi
fi

# ==============================================================================
# IAM ROLE AND POLICY CLEANUP
# ==============================================================================

log_info "Removing IAM role and policies..."

if [[ -n "$IAM_ROLE_NAME" ]]; then
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        # Detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$IAM_ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$ATTACHED_POLICIES" ]]; then
            for policy_arn in $ATTACHED_POLICIES; do
                aws iam detach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn "$policy_arn"
                log_info "Detached policy: $policy_arn"
            done
        fi
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$IAM_ROLE_NAME" \
            --query 'PolicyNames[]' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$INLINE_POLICIES" ]]; then
            for policy_name in $INLINE_POLICIES; do
                aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "$policy_name"
                log_info "Deleted inline policy: $policy_name"
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name "$IAM_ROLE_NAME"
        log_success "IAM role deleted: $IAM_ROLE_NAME"
    else
        log_info "IAM role not found: $IAM_ROLE_NAME"
    fi
else
    # Find roles with KinesisAnalyticsRole pattern
    log_info "Searching for IAM roles with KinesisAnalyticsRole pattern..."
    ROLES=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `KinesisAnalyticsRole`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$ROLES" ]]; then
        for role in $ROLES; do
            log_info "Found IAM role: $role"
            if [[ "$FORCE_DELETE" == "true" ]]; then
                # Detach and delete policies
                ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
                    --role-name "$role" \
                    --query 'AttachedPolicies[].PolicyArn' \
                    --output text 2>/dev/null || echo "")
                
                for policy_arn in $ATTACHED_POLICIES; do
                    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
                done
                
                INLINE_POLICIES=$(aws iam list-role-policies \
                    --role-name "$role" \
                    --query 'PolicyNames[]' \
                    --output text 2>/dev/null || echo "")
                
                for policy_name in $INLINE_POLICIES; do
                    aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name" 2>/dev/null || true
                done
                
                aws iam delete-role --role-name "$role" 2>/dev/null || {
                    log_warning "Failed to delete role: $role"
                }
                log_success "IAM role deleted: $role"
            else
                read -p "Delete IAM role $role? (y/n): " delete_role
                if [[ "$delete_role" == "y" ]]; then
                    # Same cleanup process as above
                    ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
                        --role-name "$role" \
                        --query 'AttachedPolicies[].PolicyArn' \
                        --output text 2>/dev/null || echo "")
                    
                    for policy_arn in $ATTACHED_POLICIES; do
                        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
                    done
                    
                    INLINE_POLICIES=$(aws iam list-role-policies \
                        --role-name "$role" \
                        --query 'PolicyNames[]' \
                        --output text 2>/dev/null || echo "")
                    
                    for policy_name in $INLINE_POLICIES; do
                        aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name"
                    done
                    
                    aws iam delete-role --role-name "$role"
                    log_success "IAM role deleted: $role"
                fi
            fi
        done
    else
        log_info "No IAM roles found with KinesisAnalyticsRole pattern"
    fi
fi

# ==============================================================================
# CLEANUP LOCAL FILES
# ==============================================================================

log_info "Cleaning up local files..."

# Remove utility scripts
LOCAL_FILES=(
    "data_producer.py"
    "stream_monitor.py"
    ".env_vars"
)

for file in "${LOCAL_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        log_info "Removed local file: $file"
    fi
done

log_success "Local files cleaned up"

# ==============================================================================
# FINAL VALIDATION
# ==============================================================================

log_info "Performing final validation..."

CLEANUP_ISSUES=()

# Check if any resources still exist
if [[ -n "$STREAM_NAME" ]] && aws kinesis describe-stream --stream-name "$STREAM_NAME" >/dev/null 2>&1; then
    CLEANUP_ISSUES+=("Kinesis stream still exists: $STREAM_NAME")
fi

if [[ -n "$LAMBDA_FUNCTION_NAME" ]] && aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
    CLEANUP_ISSUES+=("Lambda function still exists: $LAMBDA_FUNCTION_NAME")
fi

if [[ -n "$S3_BUCKET_NAME" ]] && aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
    CLEANUP_ISSUES+=("S3 bucket still exists: $S3_BUCKET_NAME")
fi

if [[ -n "$IAM_ROLE_NAME" ]] && aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
    CLEANUP_ISSUES+=("IAM role still exists: $IAM_ROLE_NAME")
fi

# Report cleanup status
if [[ ${#CLEANUP_ISSUES[@]} -eq 0 ]]; then
    log_success "All resources have been successfully cleaned up"
else
    log_warning "Some resources may still exist:"
    for issue in "${CLEANUP_ISSUES[@]}"; do
        log_warning "  - $issue"
    done
fi

# ==============================================================================
# CLEANUP SUMMARY
# ==============================================================================

echo ""
echo "===================================================================================="
echo "                           CLEANUP COMPLETED"
echo "===================================================================================="
echo ""
echo "🧹 Resource cleanup summary:"
echo ""
echo "✅ Lambda event source mappings: Removed"
echo "✅ Lambda functions: Removed"
echo "✅ CloudWatch alarms: Removed"
echo "✅ CloudWatch dashboards: Removed"
echo "✅ Kinesis Data Streams: Removed"
echo "✅ S3 buckets and data: Removed"
echo "✅ IAM roles and policies: Removed"
echo "✅ Local utility files: Removed"
echo ""

if [[ ${#CLEANUP_ISSUES[@]} -eq 0 ]]; then
    echo "🎉 All real-time analytics pipeline resources have been successfully removed!"
    echo ""
    echo "💡 Next steps:"
    echo "   • Verify your AWS bill shows no charges from removed resources"
    echo "   • Check CloudWatch logs retention if you want to remove log groups"
    echo "   • Review any custom IAM policies if you created additional ones"
else
    echo "⚠️  Some resources may require manual cleanup:"
    for issue in "${CLEANUP_ISSUES[@]}"; do
        echo "   • $issue"
    done
    echo ""
    echo "Please check the AWS console and remove any remaining resources manually."
fi

echo ""
echo "💰 Cost Impact: All ongoing charges from this pipeline should stop within 24 hours"
echo "📊 Data Recovery: All processed analytics data has been permanently deleted"
echo ""
echo "Thank you for using the AWS Real-Time Analytics pipeline! 🚀"
echo "===================================================================================="
echo ""

log_success "Cleanup process completed! 🧹"