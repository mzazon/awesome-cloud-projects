#!/bin/bash

# Traffic Analytics with VPC Lattice and OpenSearch - Cleanup Script
# This script safely removes all resources created by the deployment script
# Recipe: traffic-analytics-lattice-opensearch

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON parsing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ ! -f "deployment_info.json" ]; then
        log_error "deployment_info.json not found. Please provide deployment details manually or run this script from the deployment directory."
        echo ""
        echo "You can also set environment variables manually:"
        echo "export AWS_REGION=your-region"
        echo "export OPENSEARCH_DOMAIN_NAME=your-domain-name"
        echo "export FIREHOSE_DELIVERY_STREAM=your-stream-name"
        echo "export LAMBDA_FUNCTION_NAME=your-function-name"
        echo "export S3_BACKUP_BUCKET=your-bucket-name"
        echo "export SERVICE_NETWORK_NAME=your-network-name"
        echo "export RANDOM_SUFFIX=your-suffix"
        exit 1
    fi
    
    # Load variables from deployment info
    export AWS_REGION=$(jq -r '.aws_region // empty' deployment_info.json)
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // empty' deployment_info.json)
    export OPENSEARCH_DOMAIN_NAME=$(jq -r '.opensearch_domain_name // empty' deployment_info.json)
    export FIREHOSE_DELIVERY_STREAM=$(jq -r '.firehose_delivery_stream // empty' deployment_info.json)
    export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name // empty' deployment_info.json)
    export S3_BACKUP_BUCKET=$(jq -r '.s3_backup_bucket // empty' deployment_info.json)
    export SERVICE_NETWORK_NAME=$(jq -r '.service_network_name // empty' deployment_info.json)
    export RANDOM_SUFFIX=$(jq -r '.random_suffix // empty' deployment_info.json)
    export OPENSEARCH_ENDPOINT=$(jq -r '.opensearch_endpoint // empty' deployment_info.json)
    export SERVICE_NETWORK_ARN=$(jq -r '.service_network_arn // empty' deployment_info.json)
    export SERVICE_NETWORK_ID=$(jq -r '.service_network_id // empty' deployment_info.json)
    export ACCESS_LOG_SUBSCRIPTION_ARN=$(jq -r '.access_log_subscription_arn // empty' deployment_info.json)
    
    # Validate required variables
    if [ -z "$AWS_REGION" ] || [ -z "$OPENSEARCH_DOMAIN_NAME" ] || [ -z "$FIREHOSE_DELIVERY_STREAM" ] || [ -z "$LAMBDA_FUNCTION_NAME" ] || [ -z "$S3_BACKUP_BUCKET" ]; then
        log_error "Invalid or incomplete deployment_info.json file"
        exit 1
    fi
    
    log_success "Deployment information loaded successfully"
    log_info "AWS Region: $AWS_REGION"
    log_info "Resources to be deleted:"
    log_info "  - OpenSearch Domain: $OPENSEARCH_DOMAIN_NAME"
    log_info "  - Firehose Stream: $FIREHOSE_DELIVERY_STREAM"
    log_info "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
    log_info "  - S3 Bucket: $S3_BACKUP_BUCKET"
    log_info "  - Service Network: $SERVICE_NETWORK_NAME"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    echo "==========================================================================================================="
    echo -e "${YELLOW}⚠️  DESTRUCTIVE OPERATION WARNING ⚠️${NC}"
    echo "==========================================================================================================="
    echo ""
    echo "This script will permanently delete the following AWS resources:"
    echo ""
    echo "🔍 OpenSearch Domain: $OPENSEARCH_DOMAIN_NAME"
    echo "🚀 Kinesis Firehose Stream: $FIREHOSE_DELIVERY_STREAM"
    echo "⚡ Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "🗂️  S3 Bucket and Contents: $S3_BACKUP_BUCKET"
    echo "🌐 VPC Lattice Service Network: $SERVICE_NETWORK_NAME"
    echo "🔑 IAM Roles and Policies"
    echo "📊 Access Log Subscriptions"
    echo ""
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""
    echo "Data stored in OpenSearch and S3 will be permanently lost."
    echo ""
    
    read -p "Are you sure you want to proceed with deletion? (type 'yes' to confirm): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Please type the OpenSearch domain name to confirm: " DOMAIN_CONFIRM
    
    if [ "$DOMAIN_CONFIRM" != "$OPENSEARCH_DOMAIN_NAME" ]; then
        log_error "Domain name confirmation failed. Cleanup cancelled."
        exit 1
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Function to delete access log subscription
delete_access_log_subscription() {
    log_info "Deleting VPC Lattice access log subscription..."
    
    # Get service network ARN if not loaded
    if [ -z "$SERVICE_NETWORK_ARN" ] && [ -n "$SERVICE_NETWORK_NAME" ]; then
        SERVICE_NETWORK_ARN=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${SERVICE_NETWORK_NAME}'].arn" --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "$SERVICE_NETWORK_ARN" ]; then
        # Get access log subscription ARN
        if [ -z "$ACCESS_LOG_SUBSCRIPTION_ARN" ]; then
            ACCESS_LOG_SUBSCRIPTION_ARN=$(aws vpc-lattice list-access-log-subscriptions \
                --resource-identifier "$SERVICE_NETWORK_ARN" \
                --query 'items[0].arn' --output text 2>/dev/null || echo "None")
        fi
        
        if [ "$ACCESS_LOG_SUBSCRIPTION_ARN" != "None" ] && [ -n "$ACCESS_LOG_SUBSCRIPTION_ARN" ]; then
            aws vpc-lattice delete-access-log-subscription \
                --access-log-subscription-identifier "$ACCESS_LOG_SUBSCRIPTION_ARN" 2>/dev/null || true
            log_success "Access log subscription deleted"
        else
            log_warning "No access log subscription found to delete"
        fi
    else
        log_warning "Service network ARN not found, skipping access log subscription deletion"
    fi
}

# Function to delete VPC Lattice resources
delete_vpc_lattice_resources() {
    log_info "Deleting VPC Lattice service network and associated services..."
    
    # Get service network details if not loaded
    if [ -z "$SERVICE_NETWORK_ID" ] && [ -n "$SERVICE_NETWORK_NAME" ]; then
        SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "$SERVICE_NETWORK_ID" ]; then
        # Delete associated services first
        log_info "Deleting associated demo services..."
        DEMO_SERVICE_ID=$(aws vpc-lattice list-services \
            --query "items[?name=='demo-service-${RANDOM_SUFFIX}'].id" --output text 2>/dev/null || echo "")
        
        if [ -n "$DEMO_SERVICE_ID" ] && [ "$DEMO_SERVICE_ID" != "None" ]; then
            # Delete service network service associations first
            aws vpc-lattice list-service-network-service-associations \
                --service-network-identifier "$SERVICE_NETWORK_ID" \
                --query 'items[].id' --output text 2>/dev/null | while read -r ASSOC_ID; do
                if [ -n "$ASSOC_ID" ] && [ "$ASSOC_ID" != "None" ]; then
                    aws vpc-lattice delete-service-network-service-association \
                        --service-network-service-association-identifier "$ASSOC_ID" 2>/dev/null || true
                fi
            done
            
            # Wait a moment for associations to be deleted
            sleep 5
            
            # Delete the demo service
            aws vpc-lattice delete-service --service-identifier "$DEMO_SERVICE_ID" 2>/dev/null || true
            log_success "Demo service deleted"
        fi
        
        # Delete the service network
        aws vpc-lattice delete-service-network --service-network-identifier "$SERVICE_NETWORK_ID" 2>/dev/null || true
        log_success "VPC Lattice service network deleted"
    else
        log_warning "VPC Lattice service network not found or already deleted"
    fi
}

# Function to delete Kinesis Data Firehose
delete_firehose_stream() {
    log_info "Deleting Kinesis Data Firehose delivery stream: $FIREHOSE_DELIVERY_STREAM"
    
    # Check if delivery stream exists
    if aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE_DELIVERY_STREAM" &> /dev/null; then
        aws firehose delete-delivery-stream --delivery-stream-name "$FIREHOSE_DELIVERY_STREAM"
        log_success "Kinesis Data Firehose delivery stream deleted"
        
        # Wait for stream to be deleted before proceeding
        log_info "Waiting for Firehose stream deletion to complete..."
        while aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE_DELIVERY_STREAM" &> /dev/null; do
            sleep 10
            echo -n "."
        done
        echo ""
        log_success "Firehose stream deletion completed"
    else
        log_warning "Firehose delivery stream not found or already deleted"
    fi
}

# Function to delete Lambda function and IAM roles
delete_lambda_function() {
    log_info "Deleting Lambda function and associated IAM roles..."
    
    # Delete Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log_success "Lambda function deleted"
    else
        log_warning "Lambda function not found or already deleted"
    fi
    
    # Delete Lambda IAM role
    if [ -n "$RANDOM_SUFFIX" ]; then
        LAMBDA_ROLE_NAME="vpc-lattice-transform-role-${RANDOM_SUFFIX}"
        if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
            # Detach policies first
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
            
            # Delete the role
            aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null || true
            log_success "Lambda IAM role deleted"
        else
            log_warning "Lambda IAM role not found or already deleted"
        fi
        
        # Delete Firehose IAM role
        FIREHOSE_ROLE_NAME="firehose-opensearch-role-${RANDOM_SUFFIX}"
        if aws iam get-role --role-name "$FIREHOSE_ROLE_NAME" &> /dev/null; then
            # Delete inline policies first
            aws iam delete-role-policy \
                --role-name "$FIREHOSE_ROLE_NAME" \
                --policy-name FirehoseOpenSearchPolicy 2>/dev/null || true
            
            # Delete the role
            aws iam delete-role --role-name "$FIREHOSE_ROLE_NAME" 2>/dev/null || true
            log_success "Firehose IAM role deleted"
        else
            log_warning "Firehose IAM role not found or already deleted"
        fi
    else
        log_warning "RANDOM_SUFFIX not available, skipping IAM role cleanup"
    fi
}

# Function to delete OpenSearch domain
delete_opensearch_domain() {
    log_info "Deleting OpenSearch Service domain: $OPENSEARCH_DOMAIN_NAME"
    
    # Check if domain exists
    if aws opensearch describe-domain --domain-name "$OPENSEARCH_DOMAIN_NAME" &> /dev/null; then
        aws opensearch delete-domain --domain-name "$OPENSEARCH_DOMAIN_NAME"
        log_success "OpenSearch domain deletion initiated"
        log_info "Note: OpenSearch domain deletion takes 10-15 minutes to complete"
        
        # Optional: Wait for domain deletion (this takes a long time)
        read -p "Do you want to wait for OpenSearch domain deletion to complete? (y/N): " WAIT_OPENSEARCH
        if [ "$WAIT_OPENSEARCH" = "y" ] || [ "$WAIT_OPENSEARCH" = "Y" ]; then
            log_info "Waiting for OpenSearch domain deletion... This may take 10-15 minutes"
            while aws opensearch describe-domain --domain-name "$OPENSEARCH_DOMAIN_NAME" &> /dev/null; do
                sleep 30
                echo -n "."
            done
            echo ""
            log_success "OpenSearch domain deletion completed"
        fi
    else
        log_warning "OpenSearch domain not found or already deleted"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log_info "Deleting S3 backup bucket: $S3_BACKUP_BUCKET"
    
    # Check if bucket exists
    if aws s3 ls "s3://${S3_BACKUP_BUCKET}" &> /dev/null; then
        # Empty the bucket first (including versions if versioning is enabled)
        log_info "Emptying S3 bucket contents..."
        aws s3 rm "s3://${S3_BACKUP_BUCKET}" --recursive 2>/dev/null || true
        
        # Delete object versions if versioning is enabled
        aws s3api list-object-versions --bucket "$S3_BACKUP_BUCKET" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | \
        while read -r KEY VERSION_ID; do
            if [ -n "$KEY" ] && [ -n "$VERSION_ID" ]; then
                aws s3api delete-object --bucket "$S3_BACKUP_BUCKET" --key "$KEY" --version-id "$VERSION_ID" 2>/dev/null || true
            fi
        done
        
        # Delete delete markers if any
        aws s3api list-object-versions --bucket "$S3_BACKUP_BUCKET" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | \
        while read -r KEY VERSION_ID; do
            if [ -n "$KEY" ] && [ -n "$VERSION_ID" ]; then
                aws s3api delete-object --bucket "$S3_BACKUP_BUCKET" --key "$KEY" --version-id "$VERSION_ID" 2>/dev/null || true
            fi
        done
        
        # Delete the bucket
        aws s3 rb "s3://${S3_BACKUP_BUCKET}" --force 2>/dev/null || true
        log_success "S3 backup bucket deleted"
    else
        log_warning "S3 bucket not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files that might have been created
    rm -f transform_function.py transform_function.zip 2>/dev/null || true
    
    # Ask user if they want to remove deployment_info.json
    read -p "Do you want to remove the deployment_info.json file? (y/N): " REMOVE_INFO
    if [ "$REMOVE_INFO" = "y" ] || [ "$REMOVE_INFO" = "Y" ]; then
        rm -f deployment_info.json
        log_success "deployment_info.json removed"
    else
        log_info "deployment_info.json preserved for reference"
    fi
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local CLEANUP_ERRORS=0
    
    # Check OpenSearch domain
    if aws opensearch describe-domain --domain-name "$OPENSEARCH_DOMAIN_NAME" &> /dev/null; then
        DOMAIN_STATUS=$(aws opensearch describe-domain --domain-name "$OPENSEARCH_DOMAIN_NAME" --query 'DomainStatus.Processing' --output text)
        if [ "$DOMAIN_STATUS" = "true" ]; then
            log_info "OpenSearch domain is being deleted (Processing: true)"
        else
            log_warning "OpenSearch domain still exists"
            ((CLEANUP_ERRORS++))
        fi
    else
        log_success "OpenSearch domain successfully deleted"
    fi
    
    # Check Firehose delivery stream
    if aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE_DELIVERY_STREAM" &> /dev/null; then
        log_warning "Firehose delivery stream still exists"
        ((CLEANUP_ERRORS++))
    else
        log_success "Firehose delivery stream successfully deleted"
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_warning "Lambda function still exists"
        ((CLEANUP_ERRORS++))
    else
        log_success "Lambda function successfully deleted"
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://${S3_BACKUP_BUCKET}" &> /dev/null; then
        log_warning "S3 bucket still exists"
        ((CLEANUP_ERRORS++))
    else
        log_success "S3 bucket successfully deleted"
    fi
    
    # Check VPC Lattice service network
    if [ -n "$SERVICE_NETWORK_NAME" ]; then
        if aws vpc-lattice list-service-networks --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" --output text | grep -q .; then
            log_warning "VPC Lattice service network still exists"
            ((CLEANUP_ERRORS++))
        else
            log_success "VPC Lattice service network successfully deleted"
        fi
    fi
    
    if [ $CLEANUP_ERRORS -eq 0 ]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warning "$CLEANUP_ERRORS resource(s) may still exist. Please check manually."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "==========================================================================================================="
    echo -e "${GREEN}🗑️  Traffic Analytics Infrastructure - Cleanup Complete${NC}"
    echo "==========================================================================================================="
    echo ""
    echo "The following resources have been deleted:"
    echo ""
    echo "✅ VPC Lattice access log subscription"
    echo "✅ VPC Lattice service network and demo services"
    echo "✅ Kinesis Data Firehose delivery stream"
    echo "✅ Lambda transformation function"
    echo "✅ IAM roles and policies"
    echo "✅ OpenSearch Service domain (deletion in progress)"
    echo "✅ S3 backup bucket and contents"
    echo ""
    echo "📋 Important Notes:"
    echo "   • OpenSearch domain deletion may take 10-15 minutes to complete"
    echo "   • CloudWatch logs for Lambda and Firehose will be retained"
    echo "   • Any VPC associations were automatically cleaned up"
    echo ""
    echo "💡 To monitor OpenSearch domain deletion:"
    echo "   aws opensearch describe-domain --domain-name $OPENSEARCH_DOMAIN_NAME"
    echo ""
    echo "🔍 To verify complete cleanup:"
    echo "   aws opensearch list-domain-names"
    echo "   aws firehose list-delivery-streams"
    echo "   aws lambda list-functions --query 'Functions[?FunctionName==\"$LAMBDA_FUNCTION_NAME\"]'"
    echo ""
    echo "==========================================================================================================="
}

# Main cleanup function
main() {
    echo "==========================================================================================================="
    echo "🗑️  Traffic Analytics with VPC Lattice and OpenSearch - Cleanup Script"
    echo "==========================================================================================================="
    echo ""
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_info
    confirm_deletion
    
    echo ""
    log_info "Starting resource cleanup process..."
    
    delete_access_log_subscription
    delete_vpc_lattice_resources
    delete_firehose_stream
    delete_lambda_function
    delete_opensearch_domain
    delete_s3_bucket
    cleanup_local_files
    
    echo ""
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup process completed! 🎉"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may not have been deleted."; exit 1' INT TERM

# Run main function
main "$@"