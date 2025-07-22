#!/bin/bash

# Destroy script for Content Caching Strategies with CloudFront and ElastiCache
# This script safely removes all resources created by deploy.sh

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_id=$2
    local check_command=$3
    
    if eval "$check_command" &>/dev/null; then
        return 0  # exists
    else
        return 1  # doesn't exist
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_name=$1
    local check_command=$2
    local max_attempts=${3:-30}
    local sleep_time=${4:-10}
    
    log "Waiting for ${resource_name} deletion..."
    local attempts=0
    
    while [ $attempts -lt $max_attempts ]; do
        if ! eval "$check_command" &>/dev/null; then
            log_success "${resource_name} successfully deleted"
            return 0
        fi
        
        attempts=$((attempts + 1))
        log "Waiting for ${resource_name} deletion... (${attempts}/${max_attempts})"
        sleep $sleep_time
    done
    
    log_warning "${resource_name} deletion timeout - may still be processing"
    return 1
}

# Header
echo -e "${RED}"
echo "=================================================="
echo "  Content Caching Strategies Cleanup Script"
echo "  Removing CloudFront + ElastiCache + Lambda + API Gateway"
echo "=================================================="
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Cannot proceed with cleanup."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Check for deployment info file
if [ ! -f "deployment-info.txt" ]; then
    log_warning "deployment-info.txt not found. You'll need to provide resource names manually."
    echo ""
    log "Available cleanup options:"
    echo "1. Interactive cleanup (search and select resources)"
    echo "2. Manual cleanup (provide resource names)"
    echo "3. Exit"
    echo ""
    read -p "Select option (1/2/3): " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            log "Starting interactive cleanup..."
            INTERACTIVE_MODE=true
            ;;
        2)
            log "Starting manual cleanup..."
            MANUAL_MODE=true
            ;;
        3)
            log "Cleanup cancelled"
            exit 0
            ;;
        *)
            log_error "Invalid option selected"
            exit 1
            ;;
    esac
else
    log_success "Found deployment-info.txt"
    DEPLOYMENT_INFO_MODE=true
fi

# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Extract resource information
if [ "${DEPLOYMENT_INFO_MODE:-false}" = true ]; then
    log "Extracting resource information from deployment-info.txt..."
    
    BUCKET_NAME=$(grep "S3 Bucket:" deployment-info.txt | cut -d' ' -f3)
    CACHE_CLUSTER_ID=$(grep "ElastiCache Cluster:" deployment-info.txt | cut -d' ' -f3)
    FUNCTION_NAME=$(grep "Lambda Function:" deployment-info.txt | cut -d' ' -f3)
    API_ID=$(grep "API Gateway:" deployment-info.txt | cut -d' ' -f3)
    DISTRIBUTION_ID=$(grep "CloudFront Distribution:" deployment-info.txt | cut -d' ' -f3)
    
    # Extract random suffix from any resource name
    if [ -n "$BUCKET_NAME" ]; then
        RANDOM_SUFFIX=$(echo "$BUCKET_NAME" | sed 's/cache-demo-//')
    elif [ -n "$CACHE_CLUSTER_ID" ]; then
        RANDOM_SUFFIX=$(echo "$CACHE_CLUSTER_ID" | sed 's/demo-cache-//')
    elif [ -n "$FUNCTION_NAME" ]; then
        RANDOM_SUFFIX=$(echo "$FUNCTION_NAME" | sed 's/cache-demo-//')
    fi
    
elif [ "${INTERACTIVE_MODE:-false}" = true ]; then
    log "Searching for resources..."
    
    # Search for S3 buckets
    echo ""
    log "Searching for S3 buckets matching pattern 'cache-demo-*'..."
    BUCKET_LIST=$(aws s3 ls | grep "cache-demo-" | awk '{print $3}' || true)
    
    if [ -n "$BUCKET_LIST" ]; then
        echo "Found S3 buckets:"
        echo "$BUCKET_LIST" | nl
        read -p "Select bucket number (or 0 to skip): " bucket_choice
        if [ "$bucket_choice" -gt 0 ] 2>/dev/null; then
            BUCKET_NAME=$(echo "$BUCKET_LIST" | sed -n "${bucket_choice}p")
        fi
    fi
    
    # Search for ElastiCache clusters
    echo ""
    log "Searching for ElastiCache clusters matching pattern 'demo-cache-*'..."
    CACHE_LIST=$(aws elasticache describe-cache-clusters --query "CacheClusters[?starts_with(CacheClusterId, 'demo-cache-')].CacheClusterId" --output text || true)
    
    if [ -n "$CACHE_LIST" ]; then
        echo "Found ElastiCache clusters:"
        echo "$CACHE_LIST" | tr '\t' '\n' | nl
        read -p "Select cluster number (or 0 to skip): " cache_choice
        if [ "$cache_choice" -gt 0 ] 2>/dev/null; then
            CACHE_CLUSTER_ID=$(echo "$CACHE_LIST" | tr '\t' '\n' | sed -n "${cache_choice}p")
        fi
    fi
    
    # Search for Lambda functions
    echo ""
    log "Searching for Lambda functions matching pattern 'cache-demo-*'..."
    LAMBDA_LIST=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'cache-demo-')].FunctionName" --output text || true)
    
    if [ -n "$LAMBDA_LIST" ]; then
        echo "Found Lambda functions:"
        echo "$LAMBDA_LIST" | tr '\t' '\n' | nl
        read -p "Select function number (or 0 to skip): " lambda_choice
        if [ "$lambda_choice" -gt 0 ] 2>/dev/null; then
            FUNCTION_NAME=$(echo "$LAMBDA_LIST" | tr '\t' '\n' | sed -n "${lambda_choice}p")
        fi
    fi
    
    # Search for API Gateways
    echo ""
    log "Searching for API Gateways matching pattern 'cache-demo-api-*'..."
    API_LIST=$(aws apigatewayv2 get-apis --query "Items[?starts_with(Name, 'cache-demo-api-')].{Name:Name,Id:ApiId}" --output text || true)
    
    if [ -n "$API_LIST" ]; then
        echo "Found API Gateways:"
        echo "$API_LIST" | nl
        read -p "Select API number (or 0 to skip): " api_choice
        if [ "$api_choice" -gt 0 ] 2>/dev/null; then
            API_ID=$(echo "$API_LIST" | sed -n "${api_choice}p" | awk '{print $2}')
        fi
    fi
    
    # Search for CloudFront distributions
    echo ""
    log "Searching for CloudFront distributions with comment containing 'Multi-tier caching demo'..."
    DIST_LIST=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment, 'Multi-tier caching demo')].{Id:Id,Comment:Comment}" --output text || true)
    
    if [ -n "$DIST_LIST" ]; then
        echo "Found CloudFront distributions:"
        echo "$DIST_LIST" | nl
        read -p "Select distribution number (or 0 to skip): " dist_choice
        if [ "$dist_choice" -gt 0 ] 2>/dev/null; then
            DISTRIBUTION_ID=$(echo "$DIST_LIST" | sed -n "${dist_choice}p" | awk '{print $1}')
        fi
    fi
    
elif [ "${MANUAL_MODE:-false}" = true ]; then
    log "Manual cleanup mode - please provide resource names:"
    
    read -p "S3 Bucket name (or press Enter to skip): " BUCKET_NAME
    read -p "ElastiCache Cluster ID (or press Enter to skip): " CACHE_CLUSTER_ID
    read -p "Lambda Function name (or press Enter to skip): " FUNCTION_NAME
    read -p "API Gateway ID (or press Enter to skip): " API_ID
    read -p "CloudFront Distribution ID (or press Enter to skip): " DISTRIBUTION_ID
    read -p "Random suffix for IAM role (or press Enter to skip): " RANDOM_SUFFIX
fi

# Confirmation
echo ""
log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
log_warning "This will permanently delete the following resources:"
[ -n "${BUCKET_NAME:-}" ] && echo "   • S3 Bucket: ${BUCKET_NAME}"
[ -n "${CACHE_CLUSTER_ID:-}" ] && echo "   • ElastiCache Cluster: ${CACHE_CLUSTER_ID}"
[ -n "${FUNCTION_NAME:-}" ] && echo "   • Lambda Function: ${FUNCTION_NAME}"
[ -n "${API_ID:-}" ] && echo "   • API Gateway: ${API_ID}"
[ -n "${DISTRIBUTION_ID:-}" ] && echo "   • CloudFront Distribution: ${DISTRIBUTION_ID}"
[ -n "${RANDOM_SUFFIX:-}" ] && echo "   • IAM Role: CacheDemoLambdaRole-${RANDOM_SUFFIX}"
echo ""
echo "This action cannot be undone!"
echo ""
read -p "Type 'DELETE' to confirm (case sensitive): " confirm

if [ "$confirm" != "DELETE" ]; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo ""
log "Starting resource cleanup..."

# Step 1: Disable CloudFront distribution first (if exists)
if [ -n "${DISTRIBUTION_ID:-}" ]; then
    log "Step 1: Disabling CloudFront distribution..."
    
    if resource_exists "CloudFront Distribution" "$DISTRIBUTION_ID" "aws cloudfront get-distribution --id $DISTRIBUTION_ID"; then
        # Get current distribution config
        aws cloudfront get-distribution-config \
            --id ${DISTRIBUTION_ID} \
            --query "DistributionConfig" > current-config.json
        
        # Check if already disabled
        ENABLED=$(jq -r '.Enabled' current-config.json)
        
        if [ "$ENABLED" = "true" ]; then
            # Update configuration to disable
            jq '.Enabled = false' current-config.json > disabled-config.json
            
            ETAG=$(aws cloudfront get-distribution-config \
                --id ${DISTRIBUTION_ID} \
                --query "ETag" --output text)
            
            aws cloudfront update-distribution \
                --id ${DISTRIBUTION_ID} \
                --distribution-config file://disabled-config.json \
                --if-match ${ETAG} > /dev/null
            
            log "Waiting for CloudFront distribution to be disabled..."
            aws cloudfront wait distribution-deployed --id ${DISTRIBUTION_ID}
            log_success "CloudFront distribution disabled"
        else
            log_success "CloudFront distribution already disabled"
        fi
    else
        log_warning "CloudFront distribution ${DISTRIBUTION_ID} not found"
    fi
fi

# Step 2: Delete API Gateway
if [ -n "${API_ID:-}" ]; then
    log "Step 2: Deleting API Gateway..."
    
    if resource_exists "API Gateway" "$API_ID" "aws apigatewayv2 get-api --api-id $API_ID"; then
        aws apigatewayv2 delete-api --api-id ${API_ID}
        log_success "API Gateway deleted"
    else
        log_warning "API Gateway ${API_ID} not found"
    fi
fi

# Step 3: Delete Lambda function
if [ -n "${FUNCTION_NAME:-}" ]; then
    log "Step 3: Deleting Lambda function..."
    
    if resource_exists "Lambda function" "$FUNCTION_NAME" "aws lambda get-function --function-name $FUNCTION_NAME"; then
        aws lambda delete-function --function-name ${FUNCTION_NAME}
        log_success "Lambda function deleted"
    else
        log_warning "Lambda function ${FUNCTION_NAME} not found"
    fi
fi

# Step 4: Delete IAM role
if [ -n "${RANDOM_SUFFIX:-}" ]; then
    log "Step 4: Deleting IAM role..."
    ROLE_NAME="CacheDemoLambdaRole-${RANDOM_SUFFIX}"
    
    if resource_exists "IAM role" "$ROLE_NAME" "aws iam get-role --role-name $ROLE_NAME"; then
        # Detach policies
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$ROLE_NAME"
        log_success "IAM role deleted"
    else
        log_warning "IAM role ${ROLE_NAME} not found"
    fi
fi

# Step 5: Delete ElastiCache cluster
if [ -n "${CACHE_CLUSTER_ID:-}" ]; then
    log "Step 5: Deleting ElastiCache cluster..."
    
    if resource_exists "ElastiCache cluster" "$CACHE_CLUSTER_ID" "aws elasticache describe-cache-clusters --cache-cluster-id $CACHE_CLUSTER_ID"; then
        aws elasticache delete-cache-cluster \
            --cache-cluster-id ${CACHE_CLUSTER_ID}
        
        log "Waiting for ElastiCache cluster deletion..."
        wait_for_deletion "ElastiCache cluster" \
            "aws elasticache describe-cache-clusters --cache-cluster-id $CACHE_CLUSTER_ID" \
            30 20
        
        # Delete subnet group
        SUBNET_GROUP_NAME="${CACHE_CLUSTER_ID}-subnet-group"
        if resource_exists "ElastiCache subnet group" "$SUBNET_GROUP_NAME" "aws elasticache describe-cache-subnet-groups --cache-subnet-group-name $SUBNET_GROUP_NAME"; then
            aws elasticache delete-cache-subnet-group \
                --cache-subnet-group-name "$SUBNET_GROUP_NAME"
            log_success "ElastiCache subnet group deleted"
        fi
    else
        log_warning "ElastiCache cluster ${CACHE_CLUSTER_ID} not found"
    fi
fi

# Step 6: Delete CloudFront distribution
if [ -n "${DISTRIBUTION_ID:-}" ]; then
    log "Step 6: Deleting CloudFront distribution..."
    
    if resource_exists "CloudFront Distribution" "$DISTRIBUTION_ID" "aws cloudfront get-distribution --id $DISTRIBUTION_ID"; then
        # Get new ETag after disabling
        NEW_ETAG=$(aws cloudfront get-distribution-config \
            --id ${DISTRIBUTION_ID} \
            --query "ETag" --output text)
        
        aws cloudfront delete-distribution \
            --id ${DISTRIBUTION_ID} \
            --if-match ${NEW_ETAG}
        
        log_success "CloudFront distribution deletion initiated"
        log_warning "CloudFront distribution deletion may take 15-30 minutes to complete"
    else
        log_warning "CloudFront distribution ${DISTRIBUTION_ID} not found"
    fi
fi

# Step 7: Delete S3 bucket
if [ -n "${BUCKET_NAME:-}" ]; then
    log "Step 7: Deleting S3 bucket..."
    
    if resource_exists "S3 bucket" "$BUCKET_NAME" "aws s3 ls s3://$BUCKET_NAME"; then
        # Empty bucket first
        log "Emptying S3 bucket..."
        aws s3 rm s3://${BUCKET_NAME} --recursive --quiet
        
        # Remove bucket policy
        aws s3api delete-bucket-policy --bucket ${BUCKET_NAME} 2>/dev/null || true
        
        # Delete bucket
        aws s3 rb s3://${BUCKET_NAME}
        log_success "S3 bucket deleted"
    else
        log_warning "S3 bucket ${BUCKET_NAME} not found"
    fi
fi

# Step 8: Clean up CloudWatch resources
log "Step 8: Cleaning up CloudWatch resources..."

if [ -n "${RANDOM_SUFFIX:-}" ]; then
    # Delete log groups
    LOG_GROUP_NAME="/aws/cloudfront/cache-demo-${RANDOM_SUFFIX}"
    if resource_exists "CloudWatch log group" "$LOG_GROUP_NAME" "aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP_NAME"; then
        aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
        log_success "CloudWatch log group deleted"
    fi
    
    # Delete alarms
    ALARM_NAME="CloudFront-CacheHitRatio-Low-${RANDOM_SUFFIX}"
    if resource_exists "CloudWatch alarm" "$ALARM_NAME" "aws cloudwatch describe-alarms --alarm-names $ALARM_NAME"; then
        aws cloudwatch delete-alarms --alarm-names "$ALARM_NAME"
        log_success "CloudWatch alarm deleted"
    fi
fi

# Step 9: Clean up local files
log "Step 9: Cleaning up local files..."

# Remove temporary files
files_to_remove=(
    "current-config.json"
    "disabled-config.json"
    "test-invalidation.sh"
    "deployment-info.txt"
    "lambda_function.py"
    "lambda_function.zip"
    "index.html"
    "distribution-config.json"
    "bucket-policy.json"
)

for file in "${files_to_remove[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        log "Removed $file"
    fi
done

# Remove directories
dirs_to_remove=(
    "redis*"
    "__pycache__"
)

for dir in "${dirs_to_remove[@]}"; do
    if ls $dir 1> /dev/null 2>&1; then
        rm -rf $dir
        log "Removed $dir"
    fi
done

log_success "Local files cleaned up"

# Final success message
echo ""
log_success "🎉 Cleanup completed successfully!"
echo ""
echo -e "${GREEN}📋 Cleanup Summary:${NC}"
[ -n "${BUCKET_NAME:-}" ] && echo -e "   ✅ S3 Bucket: ${BUCKET_NAME}"
[ -n "${CACHE_CLUSTER_ID:-}" ] && echo -e "   ✅ ElastiCache: ${CACHE_CLUSTER_ID}"
[ -n "${FUNCTION_NAME:-}" ] && echo -e "   ✅ Lambda: ${FUNCTION_NAME}"
[ -n "${API_ID:-}" ] && echo -e "   ✅ API Gateway: ${API_ID}"
[ -n "${DISTRIBUTION_ID:-}" ] && echo -e "   ⏳ CloudFront: ${DISTRIBUTION_ID} (deletion in progress)"
[ -n "${RANDOM_SUFFIX:-}" ] && echo -e "   ✅ IAM Role: CacheDemoLambdaRole-${RANDOM_SUFFIX}"
echo ""
echo -e "${YELLOW}📝 Important Notes:${NC}"
echo -e "   • CloudFront distribution deletion continues in background (15-30 min)"
echo -e "   • Verify all resources are deleted in AWS Console"
echo -e "   • Check for any remaining charges in AWS Billing"
echo ""
echo -e "${BLUE}🔍 Verification:${NC}"
echo -e "   • AWS Console: https://console.aws.amazon.com"
echo -e "   • Billing Dashboard: https://console.aws.amazon.com/billing"
echo ""

log_success "Cleanup script completed"