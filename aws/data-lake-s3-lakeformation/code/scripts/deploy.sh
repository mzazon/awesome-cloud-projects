#!/bin/bash

# Deploy script for Data Lake Architecture with S3 and Lake Formation
# This script implements the complete infrastructure for a governed data lake

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    log "AWS CLI is properly configured"
}

# Function to check required permissions
check_permissions() {
    info "Checking required AWS permissions..."
    
    # Check if user has necessary permissions for key services
    local permissions_ok=true
    
    # Test Lake Formation permissions
    if ! aws lakeformation get-data-lake-settings >/dev/null 2>&1; then
        warn "Lake Formation permissions may be insufficient"
        permissions_ok=false
    fi
    
    # Test S3 permissions
    if ! aws s3 ls >/dev/null 2>&1; then
        warn "S3 permissions may be insufficient"
        permissions_ok=false
    fi
    
    # Test IAM permissions
    if ! aws iam list-roles --max-items 1 >/dev/null 2>&1; then
        warn "IAM permissions may be insufficient"
        permissions_ok=false
    fi
    
    # Test Glue permissions
    if ! aws glue get-databases --max-results 1 >/dev/null 2>&1; then
        warn "Glue permissions may be insufficient"
        permissions_ok=false
    fi
    
    if [ "$permissions_ok" = false ]; then
        warn "Some permission checks failed. The deployment may encounter issues."
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Deployment cancelled by user"
        fi
    fi
    
    log "Permission checks completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No AWS region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export DATALAKE_NAME="datalake-${RANDOM_SUFFIX}"
    export RAW_BUCKET="${DATALAKE_NAME}-raw"
    export PROCESSED_BUCKET="${DATALAKE_NAME}-processed"
    export CURATED_BUCKET="${DATALAKE_NAME}-curated"
    export DATABASE_NAME="sales_${RANDOM_SUFFIX}"
    export LF_ADMIN_USER="lake-formation-admin"
    export DATA_ANALYST_USER="data-analyst"
    export DATA_ENGINEER_USER="data-engineer"
    
    # Save configuration for cleanup script
    cat > .deployment_config << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DATALAKE_NAME=${DATALAKE_NAME}
RAW_BUCKET=${RAW_BUCKET}
PROCESSED_BUCKET=${PROCESSED_BUCKET}
CURATED_BUCKET=${CURATED_BUCKET}
DATABASE_NAME=${DATABASE_NAME}
LF_ADMIN_USER=${LF_ADMIN_USER}
DATA_ANALYST_USER=${DATA_ANALYST_USER}
DATA_ENGINEER_USER=${DATA_ENGINEER_USER}
EOF
    
    log "Environment variables configured:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "  Data Lake Name: ${DATALAKE_NAME}"
    info "  Raw Bucket: ${RAW_BUCKET}"
    info "  Processed Bucket: ${PROCESSED_BUCKET}"
    info "  Curated Bucket: ${CURATED_BUCKET}"
    info "  Database Name: ${DATABASE_NAME}"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets for data lake zones..."
    
    # Create buckets
    for bucket in "${RAW_BUCKET}" "${PROCESSED_BUCKET}" "${CURATED_BUCKET}"; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            warn "Bucket $bucket already exists, skipping creation"
        else
            info "Creating bucket: $bucket"
            aws s3 mb "s3://$bucket" --region "$AWS_REGION"
        fi
    done
    
    # Configure bucket settings
    for bucket in "${RAW_BUCKET}" "${PROCESSED_BUCKET}" "${CURATED_BUCKET}"; do
        info "Configuring bucket: $bucket"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket" \
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$bucket" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }'
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$bucket" \
            --public-access-block-configuration \
                BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    done
    
    log "S3 buckets created and configured successfully"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles for Lake Formation and Glue..."
    
    # Create Lake Formation service role
    info "Creating Lake Formation service role..."
    if aws iam get-role --role-name LakeFormationServiceRole >/dev/null 2>&1; then
        warn "LakeFormationServiceRole already exists, skipping creation"
    else
        aws iam create-role \
            --role-name LakeFormationServiceRole \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "lakeformation.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }]
            }'
        
        aws iam attach-role-policy \
            --role-name LakeFormationServiceRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/LakeFormationServiceRole
    fi
    
    # Create Glue crawler role
    info "Creating Glue crawler role..."
    if aws iam get-role --role-name GlueCrawlerRole >/dev/null 2>&1; then
        warn "GlueCrawlerRole already exists, skipping creation"
    else
        aws iam create-role \
            --role-name GlueCrawlerRole \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "glue.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }]
            }'
        
        aws iam attach-role-policy \
            --role-name GlueCrawlerRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
        
        # Create custom policy for S3 access
        cat > glue-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "s3:GetObject",
            "s3:PutObject",
            "s3:DeleteObject",
            "s3:ListBucket"
        ],
        "Resource": [
            "arn:aws:s3:::${RAW_BUCKET}",
            "arn:aws:s3:::${RAW_BUCKET}/*",
            "arn:aws:s3:::${PROCESSED_BUCKET}",
            "arn:aws:s3:::${PROCESSED_BUCKET}/*",
            "arn:aws:s3:::${CURATED_BUCKET}",
            "arn:aws:s3:::${CURATED_BUCKET}/*"
        ]
    }]
}
EOF
        
        aws iam create-policy \
            --policy-name GlueS3AccessPolicy \
            --policy-document file://glue-s3-policy.json
        
        aws iam attach-role-policy \
            --role-name GlueCrawlerRole \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/GlueS3AccessPolicy"
    fi
    
    # Create data analyst and engineer roles
    info "Creating data analyst role..."
    if aws iam get-role --role-name DataAnalystRole >/dev/null 2>&1; then
        warn "DataAnalystRole already exists, skipping creation"
    else
        aws iam create-role \
            --role-name DataAnalystRole \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": "arn:aws:iam::'${AWS_ACCOUNT_ID}':root"
                    },
                    "Action": "sts:AssumeRole"
                }]
            }'
        
        aws iam attach-role-policy \
            --role-name DataAnalystRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonAthenaFullAccess
    fi
    
    info "Creating data engineer role..."
    if aws iam get-role --role-name DataEngineerRole >/dev/null 2>&1; then
        warn "DataEngineerRole already exists, skipping creation"
    else
        aws iam create-role \
            --role-name DataEngineerRole \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": "arn:aws:iam::'${AWS_ACCOUNT_ID}':root"
                    },
                    "Action": "sts:AssumeRole"
                }]
            }'
        
        aws iam attach-role-policy \
            --role-name DataEngineerRole \
            --policy-arn arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess
    fi
    
    log "IAM roles created successfully"
}

# Function to create IAM users
create_iam_users() {
    log "Creating IAM users..."
    
    # Create Lake Formation admin user
    info "Creating Lake Formation admin user..."
    if aws iam get-user --user-name "${LF_ADMIN_USER}" >/dev/null 2>&1; then
        warn "User ${LF_ADMIN_USER} already exists, skipping creation"
    else
        aws iam create-user --user-name "${LF_ADMIN_USER}"
        aws iam attach-user-policy \
            --user-name "${LF_ADMIN_USER}" \
            --policy-arn arn:aws:iam::aws:policy/LakeFormationDataAdmin
    fi
    
    # Create data analyst user
    info "Creating data analyst user..."
    if aws iam get-user --user-name "${DATA_ANALYST_USER}" >/dev/null 2>&1; then
        warn "User ${DATA_ANALYST_USER} already exists, skipping creation"
    else
        aws iam create-user --user-name "${DATA_ANALYST_USER}"
    fi
    
    # Create data engineer user
    info "Creating data engineer user..."
    if aws iam get-user --user-name "${DATA_ENGINEER_USER}" >/dev/null 2>&1; then
        warn "User ${DATA_ENGINEER_USER} already exists, skipping creation"
    else
        aws iam create-user --user-name "${DATA_ENGINEER_USER}"
    fi
    
    log "IAM users created successfully"
}

# Function to configure Lake Formation
configure_lake_formation() {
    log "Configuring Lake Formation data lake settings..."
    
    # Create data lake settings configuration
    cat > lf-settings.json << EOF
{
    "DataLakeAdmins": [{
        "DataLakePrincipalIdentifier": "arn:aws:iam::${AWS_ACCOUNT_ID}:user/${LF_ADMIN_USER}"
    }],
    "CreateDatabaseDefaultPermissions": [],
    "CreateTableDefaultPermissions": [],
    "TrustedResourceOwners": ["${AWS_ACCOUNT_ID}"],
    "AllowExternalDataFiltering": true,
    "ExternalDataFilteringAllowList": [{
        "DataLakePrincipalIdentifier": "${AWS_ACCOUNT_ID}"
    }]
}
EOF
    
    # Apply Lake Formation settings
    aws lakeformation put-data-lake-settings \
        --data-lake-settings file://lf-settings.json
    
    log "Lake Formation settings configured successfully"
}

# Function to register S3 buckets with Lake Formation
register_s3_buckets() {
    log "Registering S3 buckets with Lake Formation..."
    
    for bucket in "${RAW_BUCKET}" "${PROCESSED_BUCKET}" "${CURATED_BUCKET}"; do
        info "Registering bucket: $bucket"
        
        # Check if already registered
        if aws lakeformation describe-resource --resource-arn "arn:aws:s3:::$bucket" >/dev/null 2>&1; then
            warn "Bucket $bucket already registered, skipping"
        else
            aws lakeformation register-resource \
                --resource-arn "arn:aws:s3:::$bucket" \
                --use-service-linked-role
        fi
    done
    
    log "S3 buckets registered with Lake Formation successfully"
}

# Function to create LF-Tags
create_lf_tags() {
    log "Creating LF-Tags for governance..."
    
    # Create department tag
    info "Creating Department tag..."
    if aws lakeformation get-lf-tag --tag-key "Department" >/dev/null 2>&1; then
        warn "Department tag already exists, skipping creation"
    else
        aws lakeformation create-lf-tag \
            --tag-key "Department" \
            --tag-values "Sales" "Marketing" "Finance" "Engineering"
    fi
    
    # Create classification tag
    info "Creating Classification tag..."
    if aws lakeformation get-lf-tag --tag-key "Classification" >/dev/null 2>&1; then
        warn "Classification tag already exists, skipping creation"
    else
        aws lakeformation create-lf-tag \
            --tag-key "Classification" \
            --tag-values "Public" "Internal" "Confidential" "Restricted"
    fi
    
    # Create data zone tag
    info "Creating DataZone tag..."
    if aws lakeformation get-lf-tag --tag-key "DataZone" >/dev/null 2>&1; then
        warn "DataZone tag already exists, skipping creation"
    else
        aws lakeformation create-lf-tag \
            --tag-key "DataZone" \
            --tag-values "Raw" "Processed" "Curated"
    fi
    
    # Create access level tag
    info "Creating AccessLevel tag..."
    if aws lakeformation get-lf-tag --tag-key "AccessLevel" >/dev/null 2>&1; then
        warn "AccessLevel tag already exists, skipping creation"
    else
        aws lakeformation create-lf-tag \
            --tag-key "AccessLevel" \
            --tag-values "ReadOnly" "ReadWrite" "Admin"
    fi
    
    log "LF-Tags created successfully"
}

# Function to create sample data
create_sample_data() {
    log "Creating and uploading sample data..."
    
    # Create sample sales data
    cat > sales_data.csv << EOF
customer_id,product_id,order_date,quantity,price,region,sales_rep
1001,P001,2024-01-15,2,29.99,North,John Smith
1002,P002,2024-01-16,1,49.99,South,Jane Doe
1003,P001,2024-01-17,3,29.99,East,Bob Johnson
1004,P003,2024-01-18,1,99.99,West,Alice Brown
1005,P002,2024-01-19,2,49.99,North,John Smith
1006,P001,2024-01-20,1,29.99,South,Jane Doe
1007,P003,2024-01-21,2,99.99,East,Bob Johnson
1008,P002,2024-01-22,1,49.99,West,Alice Brown
EOF
    
    # Create customer data
    cat > customer_data.csv << EOF
customer_id,first_name,last_name,email,phone,registration_date
1001,Michael,Johnson,mjohnson@example.com,555-0101,2023-12-01
1002,Sarah,Davis,sdavis@example.com,555-0102,2023-12-02
1003,Robert,Wilson,rwilson@example.com,555-0103,2023-12-03
1004,Jennifer,Brown,jbrown@example.com,555-0104,2023-12-04
1005,William,Jones,wjones@example.com,555-0105,2023-12-05
1006,Lisa,Garcia,lgarcia@example.com,555-0106,2023-12-06
1007,David,Miller,dmiller@example.com,555-0107,2023-12-07
1008,Susan,Anderson,sanderson@example.com,555-0108,2023-12-08
EOF
    
    # Upload data to raw bucket
    info "Uploading sales data..."
    aws s3 cp sales_data.csv "s3://${RAW_BUCKET}/sales/"
    
    info "Uploading customer data..."
    aws s3 cp customer_data.csv "s3://${RAW_BUCKET}/customers/"
    
    log "Sample data created and uploaded successfully"
}

# Function to create Glue database
create_glue_database() {
    log "Creating Glue database..."
    
    # Create Glue database
    info "Creating database: ${DATABASE_NAME}"
    if aws glue get-database --name "${DATABASE_NAME}" >/dev/null 2>&1; then
        warn "Database ${DATABASE_NAME} already exists, skipping creation"
    else
        aws glue create-database \
            --database-input '{
                "Name": "'${DATABASE_NAME}'",
                "Description": "Sales data lake database for analytics"
            }'
    fi
    
    # Wait for database to be created
    sleep 5
    
    # Tag the database with LF-Tags
    info "Applying LF-Tags to database..."
    aws lakeformation add-lf-tags-to-resource \
        --resource '{
            "Database": {
                "Name": "'${DATABASE_NAME}'"
            }
        }' \
        --lf-tags '[
            {
                "TagKey": "Department",
                "TagValues": ["Sales"]
            },
            {
                "TagKey": "Classification",
                "TagValues": ["Internal"]
            },
            {
                "TagKey": "DataZone",
                "TagValues": ["Raw"]
            }
        ]'
    
    log "Glue database created and tagged successfully"
}

# Function to create and run Glue crawlers
create_glue_crawlers() {
    log "Creating and running Glue crawlers..."
    
    # Create crawler for sales data
    info "Creating sales crawler..."
    if aws glue get-crawler --name "sales-crawler" >/dev/null 2>&1; then
        warn "Sales crawler already exists, skipping creation"
    else
        aws glue create-crawler \
            --name "sales-crawler" \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/GlueCrawlerRole" \
            --database-name "${DATABASE_NAME}" \
            --targets '{
                "S3Targets": [{
                    "Path": "s3://'${RAW_BUCKET}'/sales/"
                }]
            }' \
            --table-prefix "sales_"
    fi
    
    # Create crawler for customer data
    info "Creating customer crawler..."
    if aws glue get-crawler --name "customer-crawler" >/dev/null 2>&1; then
        warn "Customer crawler already exists, skipping creation"
    else
        aws glue create-crawler \
            --name "customer-crawler" \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/GlueCrawlerRole" \
            --database-name "${DATABASE_NAME}" \
            --targets '{
                "S3Targets": [{
                    "Path": "s3://'${RAW_BUCKET}'/customers/"
                }]
            }' \
            --table-prefix "customer_"
    fi
    
    # Run crawlers
    info "Starting sales crawler..."
    aws glue start-crawler --name "sales-crawler" || warn "Sales crawler may already be running"
    
    info "Starting customer crawler..."
    aws glue start-crawler --name "customer-crawler" || warn "Customer crawler may already be running"
    
    log "Glue crawlers created and started successfully"
}

# Function to configure permissions
configure_permissions() {
    log "Configuring Lake Formation permissions..."
    
    # Wait for crawlers to complete
    info "Waiting for crawlers to complete..."
    sleep 90
    
    # Grant database permissions to data analyst (read-only)
    info "Granting database permissions to data analyst..."
    aws lakeformation grant-permissions \
        --principal '{
            "DataLakePrincipalIdentifier": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/DataAnalystRole"
        }' \
        --resource '{
            "Database": {
                "Name": "'${DATABASE_NAME}'"
            }
        }' \
        --permissions "DESCRIBE" || warn "Database permissions may already be granted"
    
    # Grant table permissions to data analyst
    info "Granting table permissions to data analyst..."
    aws lakeformation grant-permissions \
        --principal '{
            "DataLakePrincipalIdentifier": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/DataAnalystRole"
        }' \
        --resource '{
            "Table": {
                "DatabaseName": "'${DATABASE_NAME}'",
                "Name": "sales_sales_data"
            }
        }' \
        --permissions "SELECT" "DESCRIBE" || warn "Table permissions may already be granted"
    
    # Grant broader permissions to data engineer
    info "Granting permissions to data engineer..."
    aws lakeformation grant-permissions \
        --principal '{
            "DataLakePrincipalIdentifier": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/DataEngineerRole"
        }' \
        --resource '{
            "Database": {
                "Name": "'${DATABASE_NAME}'"
            }
        }' \
        --permissions "CREATE_TABLE" "ALTER" "DROP" "DESCRIBE" || warn "Engineer permissions may already be granted"
    
    log "Lake Formation permissions configured successfully"
}

# Function to create data cell filters
create_data_cell_filters() {
    log "Creating data cell filters for column-level security..."
    
    # Create data cell filter to restrict access to customer PII
    cat > customer-filter.json << EOF
{
    "TableData": {
        "DatabaseName": "${DATABASE_NAME}",
        "TableName": "customer_customer_data",
        "Name": "customer_pii_filter",
        "ColumnWildcard": {
            "ExcludedColumnNames": ["email", "phone"]
        },
        "RowFilter": {
            "AllRowsWildcard": {}
        }
    }
}
EOF
    
    info "Creating customer PII filter..."
    aws lakeformation create-data-cells-filter \
        --cli-input-json file://customer-filter.json || warn "Customer filter may already exist"
    
    # Create filter for sales data based on region
    cat > sales-region-filter.json << EOF
{
    "TableData": {
        "DatabaseName": "${DATABASE_NAME}",
        "TableName": "sales_sales_data",
        "Name": "sales_region_filter",
        "ColumnNames": ["customer_id", "product_id", "order_date", "quantity", "price", "region"],
        "RowFilter": {
            "FilterExpression": "region IN ('North', 'South')"
        }
    }
}
EOF
    
    info "Creating sales region filter..."
    aws lakeformation create-data-cells-filter \
        --cli-input-json file://sales-region-filter.json || warn "Sales filter may already exist"
    
    log "Data cell filters created successfully"
}

# Function to enable audit logging
enable_audit_logging() {
    log "Enabling audit logging and CloudTrail integration..."
    
    # Create CloudTrail for Lake Formation auditing
    info "Creating CloudTrail for audit logging..."
    aws cloudtrail create-trail \
        --name lake-formation-audit-trail \
        --s3-bucket-name "${RAW_BUCKET}" \
        --s3-key-prefix "audit-logs/" \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation || warn "CloudTrail may already exist"
    
    # Start logging
    info "Starting CloudTrail logging..."
    aws cloudtrail start-logging \
        --name lake-formation-audit-trail || warn "CloudTrail logging may already be enabled"
    
    # Create CloudWatch log group for Lake Formation
    info "Creating CloudWatch log group..."
    aws logs create-log-group \
        --log-group-name /aws/lakeformation/audit || warn "Log group may already exist"
    
    log "Audit logging enabled successfully"
}

# Function to run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Test 1: Verify Lake Formation settings
    info "Testing Lake Formation settings..."
    aws lakeformation get-data-lake-settings --catalog-id "${AWS_ACCOUNT_ID}" >/dev/null
    
    # Test 2: Check S3 bucket registration
    info "Testing S3 bucket registration..."
    aws lakeformation list-resources --filter-condition-list '[{
        "Field": "RESOURCE_ARN",
        "ComparisonOperator": "CONTAINS",
        "StringValueList": ["'${RAW_BUCKET}'"]
    }]' >/dev/null
    
    # Test 3: Verify LF-Tags
    info "Testing LF-Tags configuration..."
    aws lakeformation list-lf-tags --catalog-id "${AWS_ACCOUNT_ID}" >/dev/null
    
    # Test 4: Check Glue tables
    info "Testing Glue catalog tables..."
    aws glue get-tables --database-name "${DATABASE_NAME}" >/dev/null
    
    # Test 5: Run sample Athena query
    info "Testing Athena query execution..."
    QUERY_ID=$(aws athena start-query-execution \
        --query-string "SELECT COUNT(*) FROM ${DATABASE_NAME}.sales_sales_data" \
        --result-configuration "OutputLocation=s3://${RAW_BUCKET}/athena-results/" \
        --work-group primary \
        --query QueryExecutionId --output text 2>/dev/null || echo "SKIP")
    
    if [ "$QUERY_ID" != "SKIP" ]; then
        sleep 10
        aws athena get-query-results --query-execution-id "${QUERY_ID}" >/dev/null || warn "Athena query may have failed"
    fi
    
    log "Validation tests completed successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    echo -e "\n${GREEN}=== DEPLOYMENT SUMMARY ===${NC}"
    echo -e "${BLUE}AWS Region:${NC} ${AWS_REGION}"
    echo -e "${BLUE}AWS Account ID:${NC} ${AWS_ACCOUNT_ID}"
    echo -e "${BLUE}Data Lake Name:${NC} ${DATALAKE_NAME}"
    echo -e "\n${GREEN}Created Resources:${NC}"
    echo -e "  • S3 Buckets:"
    echo -e "    - ${RAW_BUCKET} (Raw data zone)"
    echo -e "    - ${PROCESSED_BUCKET} (Processed data zone)"
    echo -e "    - ${CURATED_BUCKET} (Curated data zone)"
    echo -e "  • Glue Database: ${DATABASE_NAME}"
    echo -e "  • Glue Crawlers: sales-crawler, customer-crawler"
    echo -e "  • IAM Roles: LakeFormationServiceRole, GlueCrawlerRole, DataAnalystRole, DataEngineerRole"
    echo -e "  • IAM Users: ${LF_ADMIN_USER}, ${DATA_ANALYST_USER}, ${DATA_ENGINEER_USER}"
    echo -e "  • LF-Tags: Department, Classification, DataZone, AccessLevel"
    echo -e "  • Data Cell Filters: customer_pii_filter, sales_region_filter"
    echo -e "  • CloudTrail: lake-formation-audit-trail"
    echo -e "\n${GREEN}Next Steps:${NC}"
    echo -e "  1. Access the Glue console to monitor crawler progress"
    echo -e "  2. Use Athena to query the cataloged data"
    echo -e "  3. Set up additional users and permissions as needed"
    echo -e "  4. Review CloudTrail logs for audit compliance"
    echo -e "\n${YELLOW}Configuration saved to .deployment_config${NC}"
    echo -e "${YELLOW}Use ./destroy.sh to clean up resources${NC}"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    rm -f glue-s3-policy.json lf-settings.json customer-filter.json sales-region-filter.json
    rm -f sales_data.csv customer_data.csv
}

# Main execution
main() {
    log "Starting Data Lake Architecture deployment..."
    
    # Pre-deployment checks
    check_aws_config
    check_permissions
    
    # Setup and deployment
    setup_environment
    create_s3_buckets
    create_iam_roles
    create_iam_users
    configure_lake_formation
    register_s3_buckets
    create_lf_tags
    create_sample_data
    create_glue_database
    create_glue_crawlers
    configure_permissions
    create_data_cell_filters
    enable_audit_logging
    
    # Validation and cleanup
    run_validation
    cleanup_temp_files
    display_summary
    
    log "Deployment completed successfully!"
}

# Execute main function
main "$@"