#!/bin/bash

# =============================================================================
# AWS Lake Formation Cross-Account Data Access Deployment Script
# =============================================================================
# This script deploys the infrastructure for cross-account data sharing using
# AWS Lake Formation with tag-based access control (LF-TBAC).
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for Lake Formation, S3, Glue, RAM, IAM
# - Two AWS accounts (producer and consumer)
# - Environment variables set for both account IDs
#
# Usage:
#   ./deploy.sh [--consumer-account-id ACCOUNT_ID] [--dry-run] [--debug]
#
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
DEBUG=false
CONSUMER_ACCOUNT_ID=""

# =============================================================================
# Helper Functions
# =============================================================================

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

info() {
    log "${BLUE}INFO: $1${NC}"
}

debug() {
    if [[ "$DEBUG" == "true" ]]; then
        log "${BLUE}DEBUG: $1${NC}"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --consumer-account-id)
                CONSUMER_ACCOUNT_ID="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

show_help() {
    cat << EOF
AWS Lake Formation Cross-Account Data Access Deployment Script

Usage: $0 [OPTIONS]

Options:
    --consumer-account-id ID    Consumer AWS account ID (required)
    --dry-run                   Show what would be done without executing
    --debug                     Enable debug logging
    --help                      Show this help message

Environment Variables:
    AWS_REGION                  AWS region (default: from AWS CLI config)
    PRODUCER_ACCOUNT_ID         Producer AWS account ID (auto-detected)

Examples:
    $0 --consumer-account-id 123456789012
    $0 --consumer-account-id 123456789012 --dry-run
    $0 --consumer-account-id 123456789012 --debug

EOF
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! "$AWS_CLI_VERSION" =~ ^2\. ]]; then
        warning "AWS CLI v2 is recommended. Current version: $AWS_CLI_VERSION"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
    fi
    
    # Validate consumer account ID
    if [[ -z "$CONSUMER_ACCOUNT_ID" ]]; then
        error "Consumer account ID is required. Use --consumer-account-id option."
    fi
    
    if [[ ! "$CONSUMER_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
        error "Invalid consumer account ID format: $CONSUMER_ACCOUNT_ID"
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    export PRODUCER_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export DATA_LAKE_BUCKET="data-lake-${PRODUCER_ACCOUNT_ID}-$(date +%s)"
    
    # Validate environment
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Configure with 'aws configure' or set AWS_REGION environment variable."
    fi
    
    if [[ "$PRODUCER_ACCOUNT_ID" == "$CONSUMER_ACCOUNT_ID" ]]; then
        error "Producer and consumer account IDs cannot be the same"
    fi
    
    info "Producer Account ID: $PRODUCER_ACCOUNT_ID"
    info "Consumer Account ID: $CONSUMER_ACCOUNT_ID"
    info "AWS Region: $AWS_REGION"
    info "Data Lake Bucket: $DATA_LAKE_BUCKET"
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    debug "Executing: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would execute: $description"
        return 0
    fi
    
    if eval "$cmd"; then
        success "$description"
        return 0
    else
        error "Failed to execute: $description"
        return 1
    fi
}

# Create sample data
create_sample_data() {
    info "Creating sample data..."
    
    # Create directories
    execute_cmd "mkdir -p sample-data/financial-reports sample-data/customer-data" \
        "Created sample data directories"
    
    # Create financial reports sample data
    cat > sample-data/financial-reports/2024-q1.csv << 'EOF'
department,revenue,expenses,profit,quarter
finance,1000000,800000,200000,Q1
marketing,500000,450000,50000,Q1
engineering,750000,700000,50000,Q1
EOF
    
    # Create customer data sample
    cat > sample-data/customer-data/customers.csv << 'EOF'
customer_id,name,department,region
1001,Acme Corp,finance,us-east
1002,TechStart Inc,engineering,us-west
1003,Marketing Pro,marketing,eu-west
EOF
    
    success "Sample data files created"
}

# Setup S3 data lake
setup_data_lake() {
    info "Setting up S3 data lake..."
    
    # Create S3 bucket
    execute_cmd "aws s3 mb s3://$DATA_LAKE_BUCKET" \
        "Created S3 bucket: $DATA_LAKE_BUCKET"
    
    # Upload sample data
    if [[ "$DRY_RUN" == "false" ]]; then
        execute_cmd "aws s3 cp sample-data/ s3://$DATA_LAKE_BUCKET/ --recursive" \
            "Uploaded sample data to S3"
    fi
    
    # Enable versioning
    execute_cmd "aws s3api put-bucket-versioning --bucket $DATA_LAKE_BUCKET --versioning-configuration Status=Enabled" \
        "Enabled S3 bucket versioning"
    
    success "Data lake setup completed"
}

# Configure Lake Formation
configure_lake_formation() {
    info "Configuring Lake Formation..."
    
    # Register Lake Formation service
    local admin_arn="arn:aws:iam::${PRODUCER_ACCOUNT_ID}:root"
    execute_cmd "aws lakeformation register-data-lake-settings --data-lake-settings 'DataLakeAdministrators=[{DataLakePrincipalIdentifier=$admin_arn}]'" \
        "Registered Lake Formation data lake administrators"
    
    # Configure Lake Formation settings
    execute_cmd "aws lakeformation register-data-lake-settings --data-lake-settings 'CreateDatabaseDefaultPermissions=[],CreateTableDefaultPermissions=[],DataLakeAdministrators=[{DataLakePrincipalIdentifier=$admin_arn}]'" \
        "Configured Lake Formation default permissions"
    
    # Register S3 location
    execute_cmd "aws lakeformation register-resource --resource-arn arn:aws:s3:::$DATA_LAKE_BUCKET --use-service-linked-role" \
        "Registered S3 location with Lake Formation"
    
    success "Lake Formation configuration completed"
}

# Create LF-Tags taxonomy
create_lf_tags() {
    info "Creating LF-Tags taxonomy..."
    
    # Create department LF-Tag
    execute_cmd "aws lakeformation create-lf-tag --tag-key department --tag-values finance marketing engineering hr" \
        "Created department LF-Tag"
    
    # Create classification LF-Tag
    execute_cmd "aws lakeformation create-lf-tag --tag-key classification --tag-values public internal confidential restricted" \
        "Created classification LF-Tag"
    
    # Create data-category LF-Tag
    execute_cmd "aws lakeformation create-lf-tag --tag-key data-category --tag-values financial customer operational analytics" \
        "Created data-category LF-Tag"
    
    success "LF-Tags taxonomy created"
}

# Setup Glue crawler and catalog
setup_glue_catalog() {
    info "Setting up Glue Data Catalog..."
    
    # Create databases
    execute_cmd "aws glue create-database --database-input Name=financial_db,Description='Financial reporting database'" \
        "Created financial_db database"
    
    execute_cmd "aws glue create-database --database-input Name=customer_db,Description='Customer information database'" \
        "Created customer_db database"
    
    # Create/Update Glue service role
    local trust_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {"Service": "glue.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    
    # Create role (ignore error if exists)
    aws iam create-role --role-name AWSGlueServiceRole --assume-role-policy-document "$trust_policy" 2>/dev/null || true
    
    # Attach policies
    execute_cmd "aws iam attach-role-policy --role-name AWSGlueServiceRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole" \
        "Attached Glue service policy"
    
    execute_cmd "aws iam attach-role-policy --role-name AWSGlueServiceRole --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess" \
        "Attached S3 access policy to Glue role"
    
    # Create crawler configuration
    local crawler_config="{
        \"Name\": \"financial-reports-crawler\",
        \"Role\": \"arn:aws:iam::${PRODUCER_ACCOUNT_ID}:role/AWSGlueServiceRole\",
        \"DatabaseName\": \"financial_db\",
        \"Targets\": {
            \"S3Targets\": [
                {
                    \"Path\": \"s3://${DATA_LAKE_BUCKET}/financial-reports/\"
                }
            ]
        },
        \"SchemaChangePolicy\": {
            \"UpdateBehavior\": \"UPDATE_IN_DATABASE\",
            \"DeleteBehavior\": \"LOG\"
        }
    }"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "$crawler_config" > financial-crawler-config.json
        
        # Create and start crawler
        execute_cmd "aws glue create-crawler --cli-input-json file://financial-crawler-config.json" \
            "Created Glue crawler"
        
        execute_cmd "aws glue start-crawler --name financial-reports-crawler" \
            "Started Glue crawler"
        
        info "Waiting for crawler to complete (60 seconds)..."
        sleep 60
        
        rm -f financial-crawler-config.json
    fi
    
    success "Glue Data Catalog setup completed"
}

# Assign LF-Tags to resources
assign_lf_tags() {
    info "Assigning LF-Tags to Data Catalog resources..."
    
    # Assign tags to financial database
    local financial_tags='[
        {TagKey=department,TagValues=[finance]},
        {TagKey=classification,TagValues=[confidential]},
        {TagKey=data-category,TagValues=[financial]}
    ]'
    
    execute_cmd "aws lakeformation add-lf-tags-to-resource --resource Database='{Name=financial_db}' --lf-tags '$financial_tags'" \
        "Assigned LF-Tags to financial_db"
    
    # Assign tags to customer database
    local customer_tags='[
        {TagKey=department,TagValues=[marketing]},
        {TagKey=classification,TagValues=[internal]},
        {TagKey=data-category,TagValues=[customer]}
    ]'
    
    execute_cmd "aws lakeformation add-lf-tags-to-resource --resource Database='{Name=customer_db}' --lf-tags '$customer_tags'" \
        "Assigned LF-Tags to customer_db"
    
    # Tag tables if they exist
    if [[ "$DRY_RUN" == "false" ]]; then
        local tables=$(aws glue get-tables --database-name financial_db --query 'TableList[*].Name' --output text 2>/dev/null || echo "")
        for table in $tables; do
            if [[ -n "$table" ]]; then
                execute_cmd "aws lakeformation add-lf-tags-to-resource --resource Table='{DatabaseName=financial_db,Name=$table}' --lf-tags '[{TagKey=department,TagValues=[finance]},{TagKey=classification,TagValues=[confidential]}]'" \
                    "Assigned LF-Tags to table: $table"
            fi
        done
    fi
    
    success "LF-Tags assignment completed"
}

# Create cross-account resource share
create_resource_share() {
    info "Creating cross-account resource share..."
    
    # Create resource share
    local share_command="aws ram create-resource-share \
        --name lake-formation-cross-account-share \
        --resource-arns arn:aws:glue:$AWS_REGION:$PRODUCER_ACCOUNT_ID:database/financial_db \
        --principals $CONSUMER_ACCOUNT_ID \
        --allow-external-principals \
        --query 'resourceShare.resourceShareArn' \
        --output text"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        RESOURCE_SHARE_ARN=$(eval "$share_command")
        export RESOURCE_SHARE_ARN
        echo "RESOURCE_SHARE_ARN=$RESOURCE_SHARE_ARN" >> "${SCRIPT_DIR}/.deployment_vars"
        success "Created resource share: $RESOURCE_SHARE_ARN"
    else
        info "[DRY-RUN] Would create resource share"
    fi
    
    # Grant Lake Formation permissions
    execute_cmd "aws lakeformation grant-permissions \
        --principal DataLakePrincipalIdentifier='$CONSUMER_ACCOUNT_ID' \
        --resource LFTag='{TagKey=department,TagValues=[finance]}' \
        --permissions ASSOCIATE DESCRIBE \
        --permissions-with-grant-option ASSOCIATE" \
        "Granted Lake Formation permissions to consumer account"
    
    success "Cross-account resource share created"
}

# Generate consumer account setup script
generate_consumer_script() {
    info "Generating consumer account setup script..."
    
    cat > "${SCRIPT_DIR}/consumer-account-setup.sh" << EOF
#!/bin/bash

# =============================================================================
# Consumer Account Setup Script for Lake Formation Cross-Account Data Access
# =============================================================================
# This script should be run in the consumer account to complete the setup.
#
# Prerequisites:
# - AWS CLI configured for consumer account
# - Appropriate IAM permissions
#
# Usage: ./consumer-account-setup.sh
# =============================================================================

set -euo pipefail

# Environment variables from producer account
export PRODUCER_ACCOUNT_ID="$PRODUCER_ACCOUNT_ID"
export CONSUMER_ACCOUNT_ID="$CONSUMER_ACCOUNT_ID"
export AWS_REGION="$AWS_REGION"
export RESOURCE_SHARE_ARN="\${RESOURCE_SHARE_ARN:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1"
}

error() {
    log "\${RED}ERROR: \$1\${NC}"
    exit 1
}

success() {
    log "\${GREEN}SUCCESS: \$1\${NC}"
}

info() {
    log "\${BLUE}INFO: \$1\${NC}"
}

info "Starting consumer account setup..."

# Accept RAM resource share invitation
if [[ -n "\$RESOURCE_SHARE_ARN" ]]; then
    INVITATION_ID=\$(aws ram get-resource-share-invitations \\
        --resource-share-arns "\$RESOURCE_SHARE_ARN" \\
        --query 'resourceShareInvitations[0].resourceShareInvitationArn' \\
        --output text)
    
    if [[ "\$INVITATION_ID" != "None" && "\$INVITATION_ID" != "" ]]; then
        aws ram accept-resource-share-invitation \\
            --resource-share-invitation-arn "\$INVITATION_ID"
        success "Accepted RAM resource share invitation"
    else
        info "No pending invitations found"
    fi
fi

# Configure Lake Formation in consumer account
aws lakeformation register-data-lake-settings \\
    --data-lake-settings 'DataLakeAdministrators=[{DataLakePrincipalIdentifier=arn:aws:iam::'\$CONSUMER_ACCOUNT_ID':root}]'
success "Configured Lake Formation in consumer account"

# Create resource link to shared database
aws glue create-database \\
    --database-input '{
        "Name": "shared_financial_db",
        "Description": "Resource link to shared financial database",
        "TargetDatabase": {
            "CatalogId": "'\$PRODUCER_ACCOUNT_ID'",
            "DatabaseName": "financial_db"
        }
    }'
success "Created resource link to shared database"

# Create data analyst role
cat > data-analyst-trust-policy.json << 'POLICY_EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::'\$CONSUMER_ACCOUNT_ID':root"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
POLICY_EOF

aws iam create-role \\
    --role-name DataAnalystRole \\
    --assume-role-policy-document file://data-analyst-trust-policy.json
success "Created DataAnalystRole"

# Attach policies to analyst role
aws iam attach-role-policy \\
    --role-name DataAnalystRole \\
    --policy-arn arn:aws:iam::aws:policy/AmazonAthenaFullAccess

aws iam attach-role-policy \\
    --role-name DataAnalystRole \\
    --policy-arn arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess
success "Attached policies to DataAnalystRole"

# Grant Lake Formation permissions to analyst role
aws lakeformation grant-permissions \\
    --principal DataLakePrincipalIdentifier="arn:aws:iam::\$CONSUMER_ACCOUNT_ID:role/DataAnalystRole" \\
    --resource LFTag='{TagKey=department,TagValues=[finance]}' \\
    --permissions SELECT DESCRIBE
success "Granted LF-Tag permissions to DataAnalystRole"

# Grant permissions on resource link
aws lakeformation grant-permissions \\
    --principal DataLakePrincipalIdentifier="arn:aws:iam::\$CONSUMER_ACCOUNT_ID:role/DataAnalystRole" \\
    --resource Database='{Name=shared_financial_db}' \\
    --permissions DESCRIBE
success "Granted database permissions to DataAnalystRole"

# Configure table-level permissions for shared tables
SHARED_TABLES=\$(aws glue get-tables --database-name shared_financial_db \\
    --query 'TableList[*].Name' --output text 2>/dev/null || echo "")

for table in \$SHARED_TABLES; do
    if [[ -n "\$table" ]]; then
        aws lakeformation grant-permissions \\
            --principal DataLakePrincipalIdentifier="arn:aws:iam::\$CONSUMER_ACCOUNT_ID:role/DataAnalystRole" \\
            --resource Table='{CatalogId='\$PRODUCER_ACCOUNT_ID',DatabaseName=financial_db,Name='\$table'}' \\
            --permissions SELECT
        info "Granted table permissions for: \$table"
    fi
done

# Cleanup temporary files
rm -f data-analyst-trust-policy.json

success "Consumer account setup completed successfully!"

info "Next steps:"
info "1. Test access by assuming the DataAnalystRole"
info "2. Query shared data using Amazon Athena"
info "3. Verify permissions work as expected"

EOF
    
    chmod +x "${SCRIPT_DIR}/consumer-account-setup.sh"
    success "Consumer account setup script generated"
}

# Main deployment function
main() {
    info "Starting AWS Lake Formation Cross-Account Data Access deployment..."
    info "Deployment started at: $(date)"
    
    # Initialize deployment variables file
    echo "# Deployment variables for Lake Formation cross-account setup" > "${SCRIPT_DIR}/.deployment_vars"
    echo "DEPLOYMENT_TIMESTAMP=$TIMESTAMP" >> "${SCRIPT_DIR}/.deployment_vars"
    echo "PRODUCER_ACCOUNT_ID=$PRODUCER_ACCOUNT_ID" >> "${SCRIPT_DIR}/.deployment_vars"
    echo "CONSUMER_ACCOUNT_ID=$CONSUMER_ACCOUNT_ID" >> "${SCRIPT_DIR}/.deployment_vars"
    echo "AWS_REGION=$AWS_REGION" >> "${SCRIPT_DIR}/.deployment_vars"
    echo "DATA_LAKE_BUCKET=$DATA_LAKE_BUCKET" >> "${SCRIPT_DIR}/.deployment_vars"
    
    # Execute deployment steps
    create_sample_data
    setup_data_lake
    configure_lake_formation
    create_lf_tags
    setup_glue_catalog
    assign_lf_tags
    create_resource_share
    generate_consumer_script
    
    success "Deployment completed successfully!"
    
    info "=============================================================================="
    info "DEPLOYMENT SUMMARY"
    info "==============================================================================" 
    info "Producer Account ID: $PRODUCER_ACCOUNT_ID"
    info "Consumer Account ID: $CONSUMER_ACCOUNT_ID"
    info "AWS Region: $AWS_REGION"
    info "Data Lake Bucket: $DATA_LAKE_BUCKET"
    info "Consumer Setup Script: ${SCRIPT_DIR}/consumer-account-setup.sh"
    info ""
    info "NEXT STEPS:"
    info "1. Run the consumer setup script in the consumer account:"
    info "   ${SCRIPT_DIR}/consumer-account-setup.sh"
    info "2. Test cross-account data access using Amazon Athena"
    info "3. Monitor access patterns using CloudTrail"
    info ""
    info "Deployment variables saved to: ${SCRIPT_DIR}/.deployment_vars"
    info "==============================================================================" 
}

# =============================================================================
# Script Execution
# =============================================================================

# Initialize logging
info "Initializing deployment script..."
debug "Script directory: $SCRIPT_DIR"
debug "Log file: $LOG_FILE"

# Parse command line arguments
parse_args "$@"

# Execute main deployment
check_prerequisites
setup_environment
main

info "Script execution completed at: $(date)"