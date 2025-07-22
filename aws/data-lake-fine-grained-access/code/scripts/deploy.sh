#!/bin/bash

# Deploy script for AWS Lake Formation Fine-Grained Access Control
# This script automates the deployment of Lake Formation with fine-grained access controls

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=${DRY_RUN:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Error handler
error_handler() {
    local line_number=$1
    log ERROR "Script failed at line $line_number"
    log ERROR "Check the log file: $LOG_FILE"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Lake Formation Fine-Grained Access Control

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without actually deploying
    -r, --region        AWS region (default: current AWS CLI region)
    -p, --prefix        Resource name prefix (default: data-lake-fgac)
    --skip-prereq       Skip prerequisite checks
    --debug             Enable debug logging

ENVIRONMENT VARIABLES:
    AWS_REGION          AWS region to deploy to
    RESOURCE_PREFIX     Prefix for resource names
    
EXAMPLES:
    $0                  # Deploy with default settings
    $0 --dry-run        # Show deployment plan
    $0 --region us-west-2 --prefix my-lake
    
EOF
}

# Prerequisites check
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    if [ "$major_version" -lt 2 ]; then
        log WARN "AWS CLI version $aws_version detected. Version 2+ recommended."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    for tool in jq; do
        if ! command -v $tool &> /dev/null; then
            log ERROR "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    # Check AWS permissions
    local caller_arn=$(aws sts get-caller-identity --query Arn --output text)
    log INFO "Deploying as: $caller_arn"
    
    # Verify Lake Formation permissions
    if ! aws lakeformation get-data-lake-settings &> /dev/null; then
        log WARN "Unable to access Lake Formation. Ensure you have appropriate permissions."
    fi
    
    log INFO "Prerequisites check completed successfully"
}

# Environment setup
setup_environment() {
    log INFO "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        log ERROR "AWS region not set. Use --region flag or set AWS_REGION environment variable."
        exit 1
    fi
    
    # Set AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    if [ -z "${RESOURCE_PREFIX:-}" ]; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
        export DATA_LAKE_BUCKET="${RESOURCE_PREFIX:-data-lake-fgac}-${RANDOM_SUFFIX}"
    else
        export DATA_LAKE_BUCKET="${RESOURCE_PREFIX}-bucket"
    fi
    
    export DATABASE_NAME="sample_database"
    export TABLE_NAME="customer_data"
    
    log INFO "Environment variables set:"
    log INFO "  AWS_REGION: $AWS_REGION"
    log INFO "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log INFO "  DATA_LAKE_BUCKET: $DATA_LAKE_BUCKET"
    log INFO "  DATABASE_NAME: $DATABASE_NAME"
    log INFO "  TABLE_NAME: $TABLE_NAME"
}

# Create sample data
create_sample_data() {
    log INFO "Creating sample data..."
    
    local temp_dir=$(mktemp -d)
    local sample_file="$temp_dir/sample_data.csv"
    
    cat > "$sample_file" << 'EOF'
customer_id,name,email,department,salary,ssn
1,John Doe,john@example.com,Engineering,75000,123-45-6789
2,Jane Smith,jane@example.com,Marketing,65000,987-65-4321
3,Bob Johnson,bob@example.com,Finance,80000,456-78-9012
4,Alice Brown,alice@example.com,Engineering,70000,321-54-9876
5,Charlie Wilson,charlie@example.com,HR,60000,654-32-1098
EOF
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would create sample data file: $sample_file"
        return 0
    fi
    
    # Store the path for cleanup
    echo "$temp_dir" > "${SCRIPT_DIR}/.temp_dir"
    
    log INFO "Sample data created at: $sample_file"
}

# Create S3 bucket
create_s3_bucket() {
    log INFO "Creating S3 bucket: $DATA_LAKE_BUCKET..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would create S3 bucket: $DATA_LAKE_BUCKET"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3 ls "s3://$DATA_LAKE_BUCKET" 2>/dev/null; then
        log WARN "Bucket $DATA_LAKE_BUCKET already exists. Skipping creation."
        return 0
    fi
    
    # Create bucket with appropriate location constraint
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://$DATA_LAKE_BUCKET"
    else
        aws s3 mb "s3://$DATA_LAKE_BUCKET" --region "$AWS_REGION"
    fi
    
    # Enable versioning for better data protection
    aws s3api put-bucket-versioning \
        --bucket "$DATA_LAKE_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Upload sample data
    local temp_dir=$(cat "${SCRIPT_DIR}/.temp_dir" 2>/dev/null || echo "/tmp")
    local sample_file="$temp_dir/sample_data.csv"
    
    if [ -f "$sample_file" ]; then
        aws s3 cp "$sample_file" "s3://$DATA_LAKE_BUCKET/customer_data/"
        log INFO "Sample data uploaded to S3"
    else
        log WARN "Sample data file not found. Creating inline..."
        echo "customer_id,name,email,department,salary,ssn
1,John Doe,john@example.com,Engineering,75000,123-45-6789
2,Jane Smith,jane@example.com,Marketing,65000,987-65-4321
3,Bob Johnson,bob@example.com,Finance,80000,456-78-9012
4,Alice Brown,alice@example.com,Engineering,70000,321-54-9876
5,Charlie Wilson,charlie@example.com,HR,60000,654-32-1098" | aws s3 cp - "s3://$DATA_LAKE_BUCKET/customer_data/sample_data.csv"
    fi
    
    log INFO "S3 bucket created and configured successfully"
}

# Configure Lake Formation
configure_lake_formation() {
    log INFO "Configuring Lake Formation..."
    
    local current_user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would configure Lake Formation with admin: $current_user_arn"
        return 0
    fi
    
    # Add current user as data lake administrator
    aws lakeformation put-data-lake-settings \
        --data-lake-settings "DataLakeAdmins=[{DataLakePrincipalIdentifier=$current_user_arn}]" || {
        log WARN "Failed to set Lake Formation admin. Continuing with existing settings..."
    }
    
    log INFO "Lake Formation configured with administrator: $current_user_arn"
}

# Register S3 location
register_s3_location() {
    log INFO "Registering S3 location with Lake Formation..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would register S3 location: arn:aws:s3:::$DATA_LAKE_BUCKET"
        return 0
    fi
    
    # Check if already registered
    if aws lakeformation describe-resource --resource-arn "arn:aws:s3:::$DATA_LAKE_BUCKET" &>/dev/null; then
        log WARN "S3 location already registered. Skipping registration."
        return 0
    fi
    
    # Register S3 location with Lake Formation
    aws lakeformation register-resource \
        --resource-arn "arn:aws:s3:::$DATA_LAKE_BUCKET" \
        --use-service-linked-role || {
        log WARN "Failed to register S3 location. This may be expected if already registered."
    }
    
    log INFO "S3 location registered with Lake Formation"
}

# Create Glue resources
create_glue_resources() {
    log INFO "Creating Glue database and table..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would create Glue database: $DATABASE_NAME"
        log INFO "[DRY RUN] Would create Glue table: $TABLE_NAME"
        return 0
    fi
    
    # Create Glue database
    if aws glue get-database --name "$DATABASE_NAME" &>/dev/null; then
        log WARN "Database $DATABASE_NAME already exists. Skipping creation."
    else
        aws glue create-database \
            --database-input "Name=$DATABASE_NAME,Description=Sample database for fine-grained access control"
        log INFO "Glue database created: $DATABASE_NAME"
    fi
    
    # Create Glue table
    if aws glue get-table --database-name "$DATABASE_NAME" --name "$TABLE_NAME" &>/dev/null; then
        log WARN "Table $TABLE_NAME already exists. Skipping creation."
    else
        aws glue create-table \
            --database-name "$DATABASE_NAME" \
            --table-input '{
                "Name": "'$TABLE_NAME'",
                "StorageDescriptor": {
                    "Columns": [
                        {"Name": "customer_id", "Type": "bigint"},
                        {"Name": "name", "Type": "string"},
                        {"Name": "email", "Type": "string"},
                        {"Name": "department", "Type": "string"},
                        {"Name": "salary", "Type": "bigint"},
                        {"Name": "ssn", "Type": "string"}
                    ],
                    "Location": "s3://'$DATA_LAKE_BUCKET'/customer_data/",
                    "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
                    "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
                    "SerdeInfo": {
                        "SerializationLibrary": "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
                        "Parameters": {
                            "field.delim": ",",
                            "skip.header.line.count": "1"
                        }
                    }
                }
            }'
        log INFO "Glue table created: $TABLE_NAME"
    fi
}

# Create IAM roles
create_iam_roles() {
    log INFO "Creating IAM roles for different user types..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would create IAM roles: DataAnalystRole, FinanceTeamRole, HRRole"
        return 0
    fi
    
    # Create trust policy file
    local trust_policy_file=$(mktemp)
    cat > "$trust_policy_file" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "glue.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::$AWS_ACCOUNT_ID:root"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create roles
    for role in DataAnalystRole FinanceTeamRole HRRole; do
        if aws iam get-role --role-name "$role" &>/dev/null; then
            log WARN "Role $role already exists. Skipping creation."
        else
            aws iam create-role \
                --role-name "$role" \
                --assume-role-policy-document "file://$trust_policy_file"
            log INFO "Created IAM role: $role"
        fi
    done
    
    # Clean up temporary file
    rm -f "$trust_policy_file"
    
    log INFO "IAM roles created successfully"
}

# Grant Lake Formation permissions
grant_lake_formation_permissions() {
    log INFO "Granting fine-grained Lake Formation permissions..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would grant Lake Formation permissions to all roles"
        return 0
    fi
    
    # Grant full table access to data analyst
    aws lakeformation grant-permissions \
        --principal "DataLakePrincipalIdentifier=arn:aws:iam::$AWS_ACCOUNT_ID:role/DataAnalystRole" \
        --permissions "SELECT" \
        --resource '{
            "Table": {
                "DatabaseName": "'$DATABASE_NAME'",
                "Name": "'$TABLE_NAME'"
            }
        }' || log WARN "Failed to grant permissions to DataAnalystRole"
    
    # Grant limited column access to finance team (no SSN)
    aws lakeformation grant-permissions \
        --principal "DataLakePrincipalIdentifier=arn:aws:iam::$AWS_ACCOUNT_ID:role/FinanceTeamRole" \
        --permissions "SELECT" \
        --resource '{
            "TableWithColumns": {
                "DatabaseName": "'$DATABASE_NAME'",
                "Name": "'$TABLE_NAME'",
                "ColumnNames": ["customer_id", "name", "department", "salary"]
            }
        }' || log WARN "Failed to grant permissions to FinanceTeamRole"
    
    # Grant very limited access to HR (only name and department)
    aws lakeformation grant-permissions \
        --principal "DataLakePrincipalIdentifier=arn:aws:iam::$AWS_ACCOUNT_ID:role/HRRole" \
        --permissions "SELECT" \
        --resource '{
            "TableWithColumns": {
                "DatabaseName": "'$DATABASE_NAME'",
                "Name": "'$TABLE_NAME'",
                "ColumnNames": ["customer_id", "name", "department"]
            }
        }' || log WARN "Failed to grant permissions to HRRole"
    
    log INFO "Fine-grained permissions granted to all roles"
}

# Configure advanced Lake Formation settings
configure_advanced_settings() {
    log INFO "Configuring advanced Lake Formation settings..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would disable default IAM access control"
        return 0
    fi
    
    local current_user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    # Disable default IAM access control for new tables
    aws lakeformation put-data-lake-settings \
        --data-lake-settings '{
            "DataLakeAdmins": [
                {"DataLakePrincipalIdentifier": "'$current_user_arn'"}
            ],
            "CreateDatabaseDefaultPermissions": [],
            "CreateTableDefaultPermissions": []
        }' || log WARN "Failed to update Lake Formation settings"
    
    log INFO "Advanced Lake Formation settings configured"
}

# Create data filters for row-level security
create_data_filters() {
    log INFO "Creating data filters for row-level security..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would create data filter: engineering-only-filter"
        return 0
    fi
    
    # Create data filter for finance team (only Engineering department)
    aws lakeformation create-data-cells-filter \
        --table-data '{
            "TableCatalogId": "'$AWS_ACCOUNT_ID'",
            "DatabaseName": "'$DATABASE_NAME'",
            "TableName": "'$TABLE_NAME'",
            "Name": "engineering-only-filter",
            "RowFilter": {
                "FilterExpression": "department = \"Engineering\""
            },
            "ColumnNames": ["customer_id", "name", "department", "salary"]
        }' || log WARN "Failed to create data filter"
    
    log INFO "Row-level security filter created"
}

# Save deployment information
save_deployment_info() {
    log INFO "Saving deployment information..."
    
    local deployment_file="${SCRIPT_DIR}/.deployment_info"
    cat > "$deployment_file" << EOF
# Lake Formation Fine-Grained Access Control Deployment Info
# Generated on: $(date)

AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
DATA_LAKE_BUCKET=$DATA_LAKE_BUCKET
DATABASE_NAME=$DATABASE_NAME
TABLE_NAME=$TABLE_NAME

# Resources created:
# - S3 Bucket: $DATA_LAKE_BUCKET
# - Glue Database: $DATABASE_NAME
# - Glue Table: $TABLE_NAME
# - IAM Roles: DataAnalystRole, FinanceTeamRole, HRRole
# - Lake Formation permissions and data filters

DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log INFO "Deployment information saved to: $deployment_file"
}

# Validation
validate_deployment() {
    log INFO "Validating deployment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "[DRY RUN] Would validate all deployed resources"
        return 0
    fi
    
    local validation_errors=0
    
    # Check S3 bucket
    if ! aws s3 ls "s3://$DATA_LAKE_BUCKET" &>/dev/null; then
        log ERROR "S3 bucket validation failed"
        ((validation_errors++))
    fi
    
    # Check Glue database
    if ! aws glue get-database --name "$DATABASE_NAME" &>/dev/null; then
        log ERROR "Glue database validation failed"
        ((validation_errors++))
    fi
    
    # Check Glue table
    if ! aws glue get-table --database-name "$DATABASE_NAME" --name "$TABLE_NAME" &>/dev/null; then
        log ERROR "Glue table validation failed"
        ((validation_errors++))
    fi
    
    # Check IAM roles
    for role in DataAnalystRole FinanceTeamRole HRRole; do
        if ! aws iam get-role --role-name "$role" &>/dev/null; then
            log ERROR "IAM role $role validation failed"
            ((validation_errors++))
        fi
    done
    
    # Check Lake Formation registration
    if ! aws lakeformation describe-resource --resource-arn "arn:aws:s3:::$DATA_LAKE_BUCKET" &>/dev/null; then
        log WARN "Lake Formation registration validation failed (may be expected)"
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log INFO "All resources validated successfully"
        return 0
    else
        log ERROR "$validation_errors validation errors found"
        return 1
    fi
}

# Main deployment function
main() {
    log INFO "Starting Lake Formation Fine-Grained Access Control deployment..."
    log INFO "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                RESOURCE_PREFIX="$2"
                shift 2
                ;;
            --skip-prereq)
                SKIP_PREREQ=true
                shift
                ;;
            --debug)
                set -x
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites unless skipped
    if [ "${SKIP_PREREQ:-false}" != "true" ]; then
        check_prerequisites
    fi
    
    # Setup environment
    setup_environment
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    create_sample_data
    create_s3_bucket
    configure_lake_formation
    register_s3_location
    create_glue_resources
    create_iam_roles
    grant_lake_formation_permissions
    configure_advanced_settings
    create_data_filters
    
    # Save deployment info and validate
    if [ "$DRY_RUN" != "true" ]; then
        save_deployment_info
        validate_deployment
    fi
    
    log INFO "Lake Formation Fine-Grained Access Control deployment completed successfully!"
    
    if [ "$DRY_RUN" != "true" ]; then
        log INFO ""
        log INFO "Next steps:"
        log INFO "1. Test access controls using Amazon Athena"
        log INFO "2. Review Lake Formation permissions in the AWS Console"
        log INFO "3. Monitor access patterns using CloudTrail"
        log INFO ""
        log INFO "To clean up resources, run: ./destroy.sh"
    fi
}

# Run main function
main "$@"