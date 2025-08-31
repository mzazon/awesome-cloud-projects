#!/bin/bash

#######################################################################
# Deploy Script for DynamoDB TTL Recipe
# 
# This script deploys the infrastructure for the DynamoDB TTL recipe,
# including creating a DynamoDB table, enabling TTL, and inserting
# sample data with various expiration times.
#
# Prerequisites:
# - AWS CLI installed and configured
# - Appropriate IAM permissions for DynamoDB operations
#######################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
}

# Cleanup function for script termination
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        print_error "Deployment failed with exit code $exit_code"
        print_info "Check the log file at: ${LOG_FILE}"
        print_info "To clean up partial deployment, run: ./destroy.sh"
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version (require v2.0+)
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    if [ "$major_version" -lt 2 ]; then
        print_error "AWS CLI version 2.0+ is required. Current version: $aws_version"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions by attempting to list tables
    if ! aws dynamodb list-tables &> /dev/null; then
        print_error "Insufficient DynamoDB permissions. Please ensure you have the following permissions:"
        print_error "- dynamodb:CreateTable"
        print_error "- dynamodb:UpdateTimeToLive"
        print_error "- dynamodb:PutItem"
        print_error "- dynamodb:Scan"
        print_error "- dynamodb:DescribeTimeToLive"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Initialize environment variables
initialize_environment() {
    print_info "Initializing environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        print_warning "No AWS region configured, defaulting to us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export TABLE_NAME="session-data-${RANDOM_SUFFIX}"
    export TTL_ATTRIBUTE="expires_at"
    
    # Save configuration for cleanup script
    cat > "${CONFIG_FILE}" << EOF
TABLE_NAME=${TABLE_NAME}
TTL_ATTRIBUTE=${TTL_ATTRIBUTE}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    print_success "Environment initialized"
    print_info "Table Name: ${TABLE_NAME}"
    print_info "TTL Attribute: ${TTL_ATTRIBUTE}"
    print_info "AWS Region: ${AWS_REGION}"
}

# Create DynamoDB table
create_dynamodb_table() {
    print_info "Creating DynamoDB table: ${TABLE_NAME}..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "${TABLE_NAME}" &> /dev/null; then
        print_warning "Table ${TABLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create the table
    aws dynamodb create-table \
        --table-name "${TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=user_id,AttributeType=S \
            AttributeName=session_id,AttributeType=S \
        --key-schema \
            AttributeName=user_id,KeyType=HASH \
            AttributeName=session_id,KeyType=RANGE \
        --billing-mode ON_DEMAND \
        --region "${AWS_REGION}" \
        --tags Key=Purpose,Value="DynamoDB-TTL-Recipe" \
               Key=Recipe,Value="simple-data-expiration-dynamodb-ttl" \
               Key=CreatedBy,Value="deploy-script"
    
    # Wait for table to become active
    print_info "Waiting for table to become active..."
    aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${AWS_REGION}"
    
    print_success "DynamoDB table ${TABLE_NAME} created successfully"
}

# Enable TTL on the table
enable_ttl() {
    print_info "Enabling TTL on table ${TABLE_NAME}..."
    
    # Check current TTL status
    local ttl_status=$(aws dynamodb describe-time-to-live \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}" \
        --query 'TimeToLiveDescription.TimeToLiveStatus' \
        --output text 2>/dev/null || echo "DISABLED")
    
    if [ "$ttl_status" = "ENABLED" ]; then
        print_warning "TTL is already enabled on table ${TABLE_NAME}"
        return 0
    fi
    
    # Enable TTL
    aws dynamodb update-time-to-live \
        --table-name "${TABLE_NAME}" \
        --time-to-live-specification \
            Enabled=true,AttributeName="${TTL_ATTRIBUTE}" \
        --region "${AWS_REGION}"
    
    # Verify TTL configuration
    local enabled_attribute=$(aws dynamodb describe-time-to-live \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}" \
        --query 'TimeToLiveDescription.AttributeName' \
        --output text)
    
    if [ "$enabled_attribute" = "${TTL_ATTRIBUTE}" ]; then
        print_success "TTL enabled on ${TABLE_NAME} using attribute ${TTL_ATTRIBUTE}"
    else
        print_error "Failed to enable TTL on table ${TABLE_NAME}"
        exit 1
    fi
}

# Insert sample data with TTL values
insert_sample_data() {
    print_info "Inserting sample data with various TTL values..."
    
    # Calculate timestamps
    local current_time=$(date +%s)
    local short_ttl=$((current_time + 300))    # 5 minutes
    local medium_ttl=$((current_time + 900))   # 15 minutes
    local long_ttl=$((current_time + 1800))    # 30 minutes
    local past_ttl=$((current_time - 3600))    # 1 hour ago (expired)
    
    # Insert active session (long TTL)
    print_info "Inserting active session data..."
    aws dynamodb put-item \
        --table-name "${TABLE_NAME}" \
        --item '{
            "user_id": {"S": "user123"},
            "session_id": {"S": "session_active"},
            "login_time": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"},
            "last_activity": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"},
            "session_type": {"S": "standard"},
            "'${TTL_ATTRIBUTE}'": {"N": "'${long_ttl}'"}
        }' \
        --region "${AWS_REGION}"
    
    # Insert short-lived session
    print_info "Inserting temporary session data..."
    aws dynamodb put-item \
        --table-name "${TABLE_NAME}" \
        --item '{
            "user_id": {"S": "user456"},
            "session_id": {"S": "session_temp"},
            "login_time": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"},
            "session_type": {"S": "temporary"},
            "device": {"S": "mobile"},
            "'${TTL_ATTRIBUTE}'": {"N": "'${short_ttl}'"}
        }' \
        --region "${AWS_REGION}"
    
    # Insert medium duration session
    print_info "Inserting medium duration session data..."
    aws dynamodb put-item \
        --table-name "${TABLE_NAME}" \
        --item '{
            "user_id": {"S": "user789"},
            "session_id": {"S": "session_medium"},
            "login_time": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"},
            "session_type": {"S": "extended"},
            "privileges": {"S": "admin"},
            "'${TTL_ATTRIBUTE}'": {"N": "'${medium_ttl}'"}
        }' \
        --region "${AWS_REGION}"
    
    # Insert expired session for demonstration
    print_info "Inserting expired session data (for demonstration)..."
    aws dynamodb put-item \
        --table-name "${TABLE_NAME}" \
        --item '{
            "user_id": {"S": "user000"},
            "session_id": {"S": "session_expired"},
            "login_time": {"S": "'$(date -u -d "2 hours ago" +"%Y-%m-%dT%H:%M:%SZ")'"},
            "session_type": {"S": "expired"},
            "last_activity": {"S": "'$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")'"},
            "'${TTL_ATTRIBUTE}'": {"N": "'${past_ttl}'"}
        }' \
        --region "${AWS_REGION}"
    
    print_success "Sample data inserted successfully"
    print_info "Expiration schedule:"
    print_info "  - Short TTL expires at: $(date -d @${short_ttl} 2>/dev/null || date -r ${short_ttl} 2>/dev/null || echo "5 minutes from now")"
    print_info "  - Medium TTL expires at: $(date -d @${medium_ttl} 2>/dev/null || date -r ${medium_ttl} 2>/dev/null || echo "15 minutes from now")"
    print_info "  - Long TTL expires at: $(date -d @${long_ttl} 2>/dev/null || date -r ${long_ttl} 2>/dev/null || echo "30 minutes from now")"
    print_info "  - Expired item should be cleaned up automatically by DynamoDB"
}

# Validate deployment
validate_deployment() {
    print_info "Validating deployment..."
    
    # Check table status
    local table_status=$(aws dynamodb describe-table \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}" \
        --query 'Table.TableStatus' \
        --output text)
    
    if [ "$table_status" != "ACTIVE" ]; then
        print_error "Table is not in ACTIVE state: $table_status"
        exit 1
    fi
    
    # Check TTL status
    local ttl_status=$(aws dynamodb describe-time-to-live \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}" \
        --query 'TimeToLiveDescription.TimeToLiveStatus' \
        --output text)
    
    if [ "$ttl_status" != "ENABLED" ]; then
        print_error "TTL is not enabled: $ttl_status"
        exit 1
    fi
    
    # Count items in table
    local item_count=$(aws dynamodb scan \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}" \
        --select COUNT \
        --query 'Count' \
        --output text)
    
    if [ "$item_count" -lt 4 ]; then
        print_error "Expected at least 4 items, found $item_count"
        exit 1
    fi
    
    # Test filter expression for active items
    local current_epoch=$(date +%s)
    local active_count=$(aws dynamodb scan \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}" \
        --filter-expression "#ttl > :now" \
        --expression-attribute-names '{"#ttl": "'${TTL_ATTRIBUTE}'"}' \
        --expression-attribute-values '{":now": {"N": "'${current_epoch}'"}}' \
        --select COUNT \
        --query 'Count' \
        --output text)
    
    print_success "Deployment validation completed"
    print_info "Table Status: ${table_status}"
    print_info "TTL Status: ${ttl_status}"
    print_info "Total Items: ${item_count}"
    print_info "Active Items: ${active_count}"
}

# Display deployment summary
display_summary() {
    print_success "DynamoDB TTL Recipe deployment completed successfully!"
    echo
    print_info "=== DEPLOYMENT SUMMARY ==="
    print_info "Table Name: ${TABLE_NAME}"
    print_info "TTL Attribute: ${TTL_ATTRIBUTE}"
    print_info "AWS Region: ${AWS_REGION}"
    print_info "Account ID: ${AWS_ACCOUNT_ID}"
    echo
    print_info "=== NEXT STEPS ==="
    print_info "1. Test the TTL functionality:"
    print_info "   aws dynamodb scan --table-name ${TABLE_NAME} --region ${AWS_REGION}"
    echo
    print_info "2. Query only active (non-expired) items:"
    echo "   aws dynamodb scan --table-name ${TABLE_NAME} \\"
    echo "     --filter-expression \"#ttl > :now\" \\"
    echo "     --expression-attribute-names '{\"#ttl\": \"${TTL_ATTRIBUTE}\"}' \\"
    echo "     --expression-attribute-values '{\":now\": {\"N\": \"$(date +%s)\"}}' \\"
    echo "     --region ${AWS_REGION}"
    echo
    print_info "3. Monitor TTL deletions in CloudWatch:"
    print_info "   Metric: AWS/DynamoDB -> TimeToLiveDeletedItemCount"
    echo
    print_info "4. To clean up resources, run: ./destroy.sh"
    echo
    print_info "Configuration saved to: ${CONFIG_FILE}"
    print_info "Deployment log saved to: ${LOG_FILE}"
}

# Main execution
main() {
    print_info "Starting DynamoDB TTL Recipe deployment..."
    print_info "Log file: ${LOG_FILE}"
    echo
    
    check_prerequisites
    initialize_environment
    create_dynamodb_table
    enable_ttl
    insert_sample_data
    validate_deployment
    display_summary
    
    print_success "Deployment completed successfully!"
}

# Handle script options
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --dry-run      Show what would be done without executing"
        echo "  --force        Force deployment even if resources exist"
        echo
        echo "This script deploys the DynamoDB TTL Recipe infrastructure."
        exit 0
        ;;
    --dry-run)
        print_info "DRY RUN MODE - No resources will be created"
        print_info "This deployment would create:"
        print_info "- DynamoDB table with composite primary key"
        print_info "- TTL configuration on the table"
        print_info "- Sample data with various expiration times"
        exit 0
        ;;
    --force)
        print_warning "Force mode enabled - existing resources may be overwritten"
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        print_error "Unknown option: $1"
        print_info "Use --help for usage information"
        exit 1
        ;;
esac

# Execute main function
main "$@"