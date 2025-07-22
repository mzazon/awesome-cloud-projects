#!/bin/bash

# CloudFront Advanced CDN Cleanup Script
# This script safely removes all resources created by the deploy.sh script
# including CloudFront distribution, Lambda@Edge, WAF, monitoring, and S3 resources

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
FORCE_DELETE=false
SKIP_CONFIRMATION=false

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Load deployment state
load_deployment_state() {
    if [ -f /tmp/cdn-deployment-state.env ]; then
        log "Loading deployment state from /tmp/cdn-deployment-state.env"
        source /tmp/cdn-deployment-state.env
    else
        error "Deployment state file not found. Cannot proceed with cleanup."
    fi
}

# Confirmation prompt
confirm_deletion() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    echo ""
    echo "======================================================"
    echo "⚠️  WARNING: DESTRUCTIVE OPERATION"
    echo "======================================================"
    echo ""
    echo "This will permanently delete the following resources:"
    echo ""
    echo "📊 CloudFront Resources:"
    echo "  • Distribution: ${DISTRIBUTION_ID:-Unknown}"
    echo "  • Function: ${CLOUDFRONT_FUNCTION_NAME:-Unknown}"
    echo "  • Origin Access Control"
    echo "  • KeyValueStore: ${KVS_NAME:-Unknown}"
    echo ""
    echo "🔒 Security Resources:"
    echo "  • WAF Web ACL: ${WAF_WEBACL_NAME:-Unknown}"
    echo ""
    echo "⚡ Compute Resources:"
    echo "  • Lambda@Edge Function: ${LAMBDA_FUNCTION_NAME:-Unknown}"
    echo "  • IAM Role: ${LAMBDA_FUNCTION_NAME:-Unknown}-role"
    echo ""
    echo "📈 Monitoring Resources:"
    echo "  • CloudWatch Dashboard"
    echo "  • Kinesis Stream: cloudfront-realtime-logs-${RANDOM_SUFFIX:-Unknown}"
    echo "  • CloudWatch Log Group"
    echo "  • Real-time Logs IAM Role"
    echo ""
    echo "💾 Storage Resources:"
    echo "  • S3 Bucket: ${S3_BUCKET_NAME:-Unknown} (and all contents)"
    echo ""
    echo "💰 Estimated savings: \$50-100/month"
    echo ""
    echo "======================================================"
    echo ""
    
    read -p "Are you sure you want to delete all these resources? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
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
        error "AWS credentials not configured. Please run 'aws configure'."
    fi
    
    # Check required tools
    for tool in jq; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed. Please install $tool."
        fi
    done
    
    success "Prerequisites check passed"
}

# Disable and delete CloudFront distribution
delete_cloudfront_distribution() {
    if [ -z "$DISTRIBUTION_ID" ]; then
        warning "No distribution ID found, skipping CloudFront distribution deletion"
        return 0
    fi
    
    log "Disabling and deleting CloudFront distribution: ${DISTRIBUTION_ID}"
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id ${DISTRIBUTION_ID} &>/dev/null; then
        warning "CloudFront distribution ${DISTRIBUTION_ID} not found, may already be deleted"
        return 0
    fi
    
    # Get current distribution config
    log "Getting current distribution configuration..."
    DIST_CONFIG=$(aws cloudfront get-distribution-config --id ${DISTRIBUTION_ID})
    ETAG=$(echo $DIST_CONFIG | jq -r '.ETag')
    
    # Check if already disabled
    ENABLED=$(echo $DIST_CONFIG | jq -r '.DistributionConfig.Enabled')
    
    if [ "$ENABLED" = "true" ]; then
        log "Disabling CloudFront distribution..."
        
        # Disable distribution
        echo $DIST_CONFIG | jq '.DistributionConfig.Enabled = false' | \
            jq '.DistributionConfig' > /tmp/disable-dist.json
        
        aws cloudfront update-distribution \
            --id ${DISTRIBUTION_ID} \
            --distribution-config file:///tmp/disable-dist.json \
            --if-match ${ETAG}
        
        # Wait for distribution to be disabled
        log "Waiting for distribution to be disabled (this may take 5-10 minutes)..."
        while true; do
            STATUS=$(aws cloudfront get-distribution \
                --id ${DISTRIBUTION_ID} \
                --query 'Distribution.Status' --output text)
            
            if [ "$STATUS" = "Deployed" ]; then
                break
            fi
            
            log "Distribution status: ${STATUS}. Waiting 30 seconds..."
            sleep 30
        done
    else
        log "Distribution is already disabled"
    fi
    
    # Get new ETag and delete
    log "Deleting CloudFront distribution..."
    NEW_ETAG=$(aws cloudfront get-distribution \
        --id ${DISTRIBUTION_ID} \
        --query 'ETag' --output text)
    
    aws cloudfront delete-distribution \
        --id ${DISTRIBUTION_ID} \
        --if-match ${NEW_ETAG}
    
    success "CloudFront distribution deleted"
}

# Delete CloudFront Function
delete_cloudfront_function() {
    if [ -z "$CLOUDFRONT_FUNCTION_NAME" ]; then
        warning "No CloudFront function name found, skipping"
        return 0
    fi
    
    log "Deleting CloudFront Function: ${CLOUDFRONT_FUNCTION_NAME}"
    
    # Check if function exists
    if ! aws cloudfront describe-function --name ${CLOUDFRONT_FUNCTION_NAME} &>/dev/null; then
        warning "CloudFront function ${CLOUDFRONT_FUNCTION_NAME} not found, may already be deleted"
        return 0
    fi
    
    # Delete CloudFront Function
    FUNCTION_ETAG=$(aws cloudfront describe-function \
        --name ${CLOUDFRONT_FUNCTION_NAME} \
        --query 'ETag' --output text 2>/dev/null || echo "")
    
    if [ -n "$FUNCTION_ETAG" ]; then
        aws cloudfront delete-function \
            --name ${CLOUDFRONT_FUNCTION_NAME} \
            --if-match ${FUNCTION_ETAG}
        
        success "CloudFront Function deleted"
    else
        warning "Could not get function ETag, function may already be deleted"
    fi
}

# Delete Lambda@Edge function and IAM role
delete_lambda_edge_function() {
    if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
        warning "No Lambda function name found, skipping"
        return 0
    fi
    
    log "Deleting Lambda@Edge function: ${LAMBDA_FUNCTION_NAME}"
    
    # Delete Lambda function (must be in us-east-1 for Lambda@Edge)
    if aws lambda get-function --region us-east-1 --function-name ${LAMBDA_FUNCTION_NAME} &>/dev/null; then
        aws lambda delete-function \
            --region us-east-1 \
            --function-name ${LAMBDA_FUNCTION_NAME}
        success "Lambda@Edge function deleted"
    else
        warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found, may already be deleted"
    fi
    
    # Delete IAM role
    log "Deleting IAM role: ${LAMBDA_FUNCTION_NAME}-role"
    
    if aws iam get-role --role-name ${LAMBDA_FUNCTION_NAME}-role &>/dev/null; then
        # Detach policies
        aws iam detach-role-policy \
            --role-name ${LAMBDA_FUNCTION_NAME}-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete role
        aws iam delete-role \
            --role-name ${LAMBDA_FUNCTION_NAME}-role
        
        success "IAM role deleted"
    else
        warning "IAM role ${LAMBDA_FUNCTION_NAME}-role not found, may already be deleted"
    fi
}

# Delete WAF Web ACL
delete_waf_webacl() {
    if [ -z "$WAF_WEBACL_ID" ] || [ -z "$WAF_WEBACL_NAME" ]; then
        warning "No WAF Web ACL ID or name found, skipping"
        return 0
    fi
    
    log "Deleting WAF Web ACL: ${WAF_WEBACL_NAME}"
    
    # Check if Web ACL exists and get lock token
    if WAF_INFO=$(aws wafv2 get-web-acl --scope CLOUDFRONT --id ${WAF_WEBACL_ID} 2>/dev/null); then
        LOCK_TOKEN=$(echo $WAF_INFO | jq -r '.LockToken')
        
        aws wafv2 delete-web-acl \
            --scope CLOUDFRONT \
            --id ${WAF_WEBACL_ID} \
            --lock-token ${LOCK_TOKEN}
        
        success "WAF Web ACL deleted"
    else
        warning "WAF Web ACL ${WAF_WEBACL_NAME} not found, may already be deleted"
    fi
}

# Delete Origin Access Control
delete_origin_access_control() {
    if [ -z "$OAC_ID" ]; then
        warning "No Origin Access Control ID found, skipping"
        return 0
    fi
    
    log "Deleting Origin Access Control: ${OAC_ID}"
    
    # Check if OAC exists
    if aws cloudfront get-origin-access-control --id ${OAC_ID} &>/dev/null; then
        aws cloudfront delete-origin-access-control --id ${OAC_ID}
        success "Origin Access Control deleted"
    else
        warning "Origin Access Control ${OAC_ID} not found, may already be deleted"
    fi
}

# Delete CloudFront KeyValueStore
delete_keyvalue_store() {
    if [ -z "$KVS_NAME" ]; then
        warning "No KeyValueStore name found, skipping"
        return 0
    fi
    
    log "Deleting CloudFront KeyValueStore: ${KVS_NAME}"
    
    # Check if KVS exists
    if aws cloudfront describe-key-value-store --name ${KVS_NAME} &>/dev/null; then
        aws cloudfront delete-key-value-store --name ${KVS_NAME}
        success "CloudFront KeyValueStore deleted"
    else
        warning "KeyValueStore ${KVS_NAME} not found, may already be deleted"
    fi
}

# Delete monitoring resources
delete_monitoring_resources() {
    if [ -z "$RANDOM_SUFFIX" ]; then
        warning "No random suffix found, skipping monitoring resources"
        return 0
    fi
    
    log "Deleting monitoring resources..."
    
    # Delete CloudWatch dashboard
    log "Deleting CloudWatch dashboard..."
    aws cloudwatch delete-dashboards \
        --dashboard-names "CloudFront-Advanced-CDN-${RANDOM_SUFFIX}" 2>/dev/null || \
        warning "Dashboard CloudFront-Advanced-CDN-${RANDOM_SUFFIX} not found"
    
    # Delete real-time log configuration
    log "Deleting real-time log configuration..."
    if aws cloudfront describe-realtime-log-config --name "realtime-logs-${RANDOM_SUFFIX}" &>/dev/null; then
        aws cloudfront delete-realtime-log-config --name "realtime-logs-${RANDOM_SUFFIX}"
        success "Real-time log configuration deleted"
    else
        warning "Real-time log configuration not found"
    fi
    
    # Delete Kinesis stream
    log "Deleting Kinesis stream..."
    if aws kinesis describe-stream --stream-name cloudfront-realtime-logs-${RANDOM_SUFFIX} &>/dev/null; then
        aws kinesis delete-stream --stream-name cloudfront-realtime-logs-${RANDOM_SUFFIX}
        success "Kinesis stream deleted"
    else
        warning "Kinesis stream cloudfront-realtime-logs-${RANDOM_SUFFIX} not found"
    fi
    
    # Delete CloudWatch log group
    log "Deleting CloudWatch log group..."
    if [ -n "$CDN_PROJECT_NAME" ]; then
        aws logs delete-log-group \
            --log-group-name /aws/cloudfront/realtime-logs/${CDN_PROJECT_NAME} 2>/dev/null || \
            warning "Log group not found"
    fi
    
    # Delete real-time logs IAM role
    log "Deleting real-time logs IAM role..."
    REALTIME_ROLE_NAME="CloudFront-RealTimeLogs-${RANDOM_SUFFIX}"
    
    if aws iam get-role --role-name ${REALTIME_ROLE_NAME} &>/dev/null; then
        # Delete inline policy
        aws iam delete-role-policy \
            --role-name ${REALTIME_ROLE_NAME} \
            --policy-name KinesisAccess 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name ${REALTIME_ROLE_NAME}
        success "Real-time logs IAM role deleted"
    else
        warning "Real-time logs IAM role not found"
    fi
}

# Delete S3 resources
delete_s3_resources() {
    if [ -z "$S3_BUCKET_NAME" ]; then
        warning "No S3 bucket name found, skipping"
        return 0
    fi
    
    log "Deleting S3 resources..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${S3_BUCKET_NAME} 2>/dev/null; then
        # Remove bucket policy first
        log "Removing S3 bucket policy..."
        aws s3api delete-bucket-policy --bucket ${S3_BUCKET_NAME} 2>/dev/null || \
            warning "No bucket policy to delete"
        
        # Delete all objects in bucket
        log "Deleting all objects in S3 bucket..."
        aws s3 rm s3://${S3_BUCKET_NAME} --recursive
        
        # Delete bucket
        log "Deleting S3 bucket..."
        aws s3 rb s3://${S3_BUCKET_NAME}
        
        success "S3 bucket and contents deleted"
    else
        warning "S3 bucket ${S3_BUCKET_NAME} not found, may already be deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove temporary files
    rm -rf /tmp/cdn-content /tmp/lambda-edge 2>/dev/null || true
    rm -f /tmp/cloudfront-function.js /tmp/waf-webacl.json 2>/dev/null || true
    rm -f /tmp/oac-config.json /tmp/distribution-config.json 2>/dev/null || true
    rm -f /tmp/s3-policy.json /tmp/dashboard-config.json 2>/dev/null || true
    rm -f /tmp/lambda-edge-trust-policy.json /tmp/realtime-logs-trust-policy.json 2>/dev/null || true
    rm -f /tmp/realtime-logs-policy.json /tmp/disable-dist.json 2>/dev/null || true
    rm -f /tmp/*.json.bak 2>/dev/null || true
    
    # Remove deployment state file
    if [ "$FORCE_DELETE" = true ]; then
        rm -f /tmp/cdn-deployment-state.env 2>/dev/null || true
    else
        warning "Keeping deployment state file for reference: /tmp/cdn-deployment-state.env"
    fi
    
    success "Local files cleaned up"
}

# Display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo ""
    echo "======================================================"
    echo "Advanced CloudFront CDN Cleanup Complete"
    echo "======================================================"
    echo ""
    echo "🗑️  Resources Deleted:"
    echo "  • CloudFront Distribution: ${DISTRIBUTION_ID:-N/A}"
    echo "  • CloudFront Function: ${CLOUDFRONT_FUNCTION_NAME:-N/A}"
    echo "  • Lambda@Edge Function: ${LAMBDA_FUNCTION_NAME:-N/A}"
    echo "  • WAF Web ACL: ${WAF_WEBACL_NAME:-N/A}"
    echo "  • S3 Bucket: ${S3_BUCKET_NAME:-N/A}"
    echo "  • Monitoring Resources: Dashboard, Logs, Kinesis"
    echo ""
    echo "💰 Cost Savings: ~\$50-100/month"
    echo ""
    echo "✅ All resources have been successfully removed!"
    echo "   Your AWS account will no longer incur charges for these resources."
    echo ""
    if [ "$FORCE_DELETE" != true ]; then
        echo "📄 Deployment state file preserved at:"
        echo "   /tmp/cdn-deployment-state.env"
        echo ""
    fi
    echo "======================================================"
}

# Error handling
handle_cleanup_error() {
    local exit_code=$1
    error "Cleanup encountered an error (exit code: $exit_code)"
    echo ""
    echo "Some resources may not have been deleted."
    echo "Please check the AWS console and clean up manually if needed."
    echo ""
    echo "Common issues:"
    echo "• CloudFront distributions take time to disable"
    echo "• Lambda@Edge functions may have replicas in multiple regions"
    echo "• WAF Web ACLs may still be associated with resources"
    echo ""
    exit $exit_code
}

# Main cleanup function
main() {
    log "Starting Advanced CloudFront CDN Cleanup"
    
    # Set error handler
    trap 'handle_cleanup_error $?' ERR
    
    load_deployment_state
    check_prerequisites
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_cloudfront_distribution
    delete_keyvalue_store
    delete_monitoring_resources
    delete_origin_access_control
    delete_waf_webacl
    delete_lambda_edge_function
    delete_cloudfront_function
    delete_s3_resources
    cleanup_local_files
    
    display_cleanup_summary
    
    success "Advanced CloudFront CDN cleanup completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Safely delete all resources created by the CloudFront CDN deployment."
            echo ""
            echo "Options:"
            echo "  --help, -h        Show this help message"
            echo "  --force           Skip confirmation prompts and delete deployment state"
            echo "  --yes             Skip confirmation prompts (keep deployment state)"
            echo ""
            echo "This script deletes:"
            echo "  • CloudFront distribution and related resources"
            echo "  • Lambda@Edge functions and IAM roles"
            echo "  • WAF Web ACL and security rules"
            echo "  • S3 bucket and all contents"
            echo "  • Monitoring resources (CloudWatch, Kinesis)"
            echo "  • All temporary files"
            echo ""
            echo "Safety features:"
            echo "  • Requires confirmation before deletion"
            echo "  • Gracefully handles missing resources"
            echo "  • Preserves deployment state file for reference"
            echo ""
            echo "Estimated cleanup time: 10-15 minutes"
            echo "Cost savings: \$50-100/month"
            exit 0
            ;;
        --force)
            FORCE_DELETE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Run main cleanup
main