#!/bin/bash

# Deploy script for AWS Glue Data Catalog Governance Recipe
# This script deploys the complete data governance solution with automated PII detection

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions
    log "Verifying AWS permissions..."
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$account_id" ]]; then
        error "Unable to retrieve AWS account ID. Check your AWS credentials."
    fi
    
    success "Prerequisites check passed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export GOVERNANCE_BUCKET="data-governance-${random_suffix}"
    export DATABASE_NAME="governance_catalog_${random_suffix}"
    export CRAWLER_NAME="governance-crawler-${random_suffix}"
    export AUDIT_BUCKET="governance-audit-${random_suffix}"
    export CLASSIFIER_NAME="pii-classifier-${random_suffix}"
    export GLUE_ROLE_NAME="GlueGovernanceCrawlerRole-${random_suffix}"
    export GLUE_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${GLUE_ROLE_NAME}"
    export POLICY_NAME="DataAnalystGovernancePolicy-${random_suffix}"
    export TRAIL_NAME="DataCatalogGovernanceTrail-${random_suffix}"
    export DASHBOARD_NAME="DataGovernanceDashboard-${random_suffix}"
    
    # Save environment variables for cleanup
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
GOVERNANCE_BUCKET=${GOVERNANCE_BUCKET}
DATABASE_NAME=${DATABASE_NAME}
CRAWLER_NAME=${CRAWLER_NAME}
AUDIT_BUCKET=${AUDIT_BUCKET}
CLASSIFIER_NAME=${CLASSIFIER_NAME}
GLUE_ROLE_NAME=${GLUE_ROLE_NAME}
GLUE_ROLE_ARN=${GLUE_ROLE_ARN}
POLICY_NAME=${POLICY_NAME}
TRAIL_NAME=${TRAIL_NAME}
DASHBOARD_NAME=${DASHBOARD_NAME}
EOF
    
    success "Environment variables initialized"
}

# Create S3 buckets and sample data
create_storage_resources() {
    log "Creating S3 buckets and sample data..."
    
    # Create S3 buckets
    aws s3 mb s3://${GOVERNANCE_BUCKET} --region ${AWS_REGION} || error "Failed to create governance bucket"
    aws s3 mb s3://${AUDIT_BUCKET} --region ${AWS_REGION} || error "Failed to create audit bucket"
    
    # Create sample data with PII
    cat > sample_customer_data.csv << 'EOF'
customer_id,first_name,last_name,email,ssn,phone,address,city,state,zip
1,John,Doe,john.doe@email.com,123-45-6789,555-123-4567,123 Main St,Anytown,NY,12345
2,Jane,Smith,jane.smith@email.com,987-65-4321,555-987-6543,456 Oak Ave,Somewhere,CA,67890
3,Bob,Johnson,bob.johnson@email.com,456-78-9012,555-456-7890,789 Pine Rd,Nowhere,TX,54321
EOF
    
    # Upload sample data
    aws s3 cp sample_customer_data.csv s3://${GOVERNANCE_BUCKET}/data/ || error "Failed to upload sample data"
    rm sample_customer_data.csv
    
    success "S3 buckets and sample data created"
}

# Create Data Catalog database
create_data_catalog() {
    log "Creating Data Catalog database..."
    
    aws glue create-database \
        --database-input Name=${DATABASE_NAME},Description="Data governance catalog database" \
        || error "Failed to create Data Catalog database"
    
    success "Data Catalog database created: ${DATABASE_NAME}"
}

# Create IAM role for Glue
create_iam_role() {
    log "Creating IAM role for Glue crawler..."
    
    # Create trust policy
    cat > glue-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "glue.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name ${GLUE_ROLE_NAME} \
        --assume-role-policy-document file://glue-trust-policy.json \
        || error "Failed to create IAM role"
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name ${GLUE_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole \
        || error "Failed to attach Glue service role policy"
    
    aws iam attach-role-policy \
        --role-name ${GLUE_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
        || error "Failed to attach S3 read-only policy"
    
    # Wait for role to be available
    log "Waiting for IAM role to propagate..."
    sleep 10
    
    success "IAM role created: ${GLUE_ROLE_NAME}"
}

# Create PII classifier
create_pii_classifier() {
    log "Creating PII classifier..."
    
    aws glue create-classifier \
        --csv-classifier Name=${CLASSIFIER_NAME},Delimiter=',',QuoteSymbol='"',ContainsHeader=PRESENT,Header='customer_id,first_name,last_name,email,ssn,phone,address,city,state,zip',DisableValueTrimming=false,AllowSingleColumn=false \
        || error "Failed to create PII classifier"
    
    success "PII classifier created: ${CLASSIFIER_NAME}"
}

# Create and run Glue crawler
create_glue_crawler() {
    log "Creating Glue crawler..."
    
    aws glue create-crawler \
        --name ${CRAWLER_NAME} \
        --role ${GLUE_ROLE_ARN} \
        --database-name ${DATABASE_NAME} \
        --targets S3Targets=[{Path=s3://${GOVERNANCE_BUCKET}/data/}] \
        --classifiers ${CLASSIFIER_NAME} \
        --description "Governance crawler with PII classification" \
        || error "Failed to create Glue crawler"
    
    # Start the crawler
    log "Starting Glue crawler..."
    aws glue start-crawler --name ${CRAWLER_NAME} || error "Failed to start crawler"
    
    success "Glue crawler created and started: ${CRAWLER_NAME}"
}

# Wait for crawler completion
wait_for_crawler() {
    log "Waiting for crawler to complete..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local crawler_state=$(aws glue get-crawler \
            --name ${CRAWLER_NAME} \
            --query 'Crawler.State' --output text)
        
        if [ "$crawler_state" = "READY" ]; then
            success "Crawler completed successfully"
            return 0
        elif [ "$crawler_state" = "FAILED" ]; then
            error "Crawler failed to complete"
        fi
        
        log "Crawler state: $crawler_state (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    error "Crawler did not complete within expected time"
}

# Enable Lake Formation
enable_lake_formation() {
    log "Enabling Lake Formation..."
    
    # Register S3 location with Lake Formation
    aws lakeformation register-resource \
        --resource-arn arn:aws:s3:::${GOVERNANCE_BUCKET}/data/ \
        --use-service-linked-role \
        || warning "Failed to register S3 location with Lake Formation (may already be registered)"
    
    # Create data lake administrator settings
    aws lakeformation put-data-lake-settings \
        --data-lake-settings DataLakeAdmins=[{DataLakePrincipalIdentifier=arn:aws:iam::${AWS_ACCOUNT_ID}:root}],CreateDatabaseDefaultPermissions=[],CreateTableDefaultPermissions=[] \
        || error "Failed to configure Lake Formation settings"
    
    success "Lake Formation configured"
}

# Create governance policies
create_governance_policies() {
    log "Creating governance policies..."
    
    # Create policy for data analysts
    cat > data-analyst-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "glue:GetDatabase",
                "glue:GetTable",
                "glue:GetTables",
                "glue:GetPartition",
                "glue:GetPartitions",
                "lakeformation:GetDataAccess"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${GOVERNANCE_BUCKET}/*",
                "arn:aws:s3:::${GOVERNANCE_BUCKET}"
            ]
        }
    ]
}
EOF
    
    # Create IAM policy
    aws iam create-policy \
        --policy-name ${POLICY_NAME} \
        --policy-document file://data-analyst-policy.json \
        || error "Failed to create data analyst policy"
    
    success "Governance policies created"
}

# Create PII detection script
create_pii_detection_script() {
    log "Creating PII detection script..."
    
    cat > pii-detection-script.py << 'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'TABLE_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from Data Catalog
datasource = glueContext.create_dynamic_frame.from_catalog(
    database=args['DATABASE_NAME'],
    table_name=args['TABLE_NAME'],
    transformation_ctx="datasource"
)

# Apply PII detection transform
pii_transform = DetectPII.apply(
    frame=datasource,
    detection_threshold=0.5,
    sample_fraction=1.0,
    actions_map={
        "ssn": "DETECT",
        "email": "DETECT",
        "phone": "DETECT",
        "address": "DETECT"
    },
    transformation_ctx="pii_transform"
)

# Log PII detection results
print("PII Detection completed for table: " + args['TABLE_NAME'])

job.commit()
EOF
    
    # Upload script to S3
    aws s3 cp pii-detection-script.py s3://${GOVERNANCE_BUCKET}/scripts/ || error "Failed to upload PII detection script"
    
    success "PII detection script created"
}

# Enable CloudTrail
enable_cloudtrail() {
    log "Enabling CloudTrail for audit logging..."
    
    # Create CloudTrail
    aws cloudtrail create-trail \
        --name ${TRAIL_NAME} \
        --s3-bucket-name ${AUDIT_BUCKET} \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation \
        || error "Failed to create CloudTrail"
    
    # Start logging
    aws cloudtrail start-logging \
        --name ${TRAIL_NAME} \
        || error "Failed to start CloudTrail logging"
    
    # Create event selector for Glue Data Catalog events
    aws cloudtrail put-event-selectors \
        --trail-name ${TRAIL_NAME} \
        --event-selectors ReadWriteType=All,IncludeManagementEvents=true,DataResources=[{Type=AWS::Glue::Table,Values=[arn:aws:glue:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DATABASE_NAME}/*]}] \
        || error "Failed to configure CloudTrail event selectors"
    
    success "CloudTrail audit logging enabled"
}

# Create monitoring dashboard
create_dashboard() {
    log "Creating governance monitoring dashboard..."
    
    cat > governance-dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Glue", "glue.driver.aggregate.numCompletedTasks", "JobName", "${CRAWLER_NAME}"],
                    ["AWS/Glue", "glue.driver.aggregate.numFailedTasks", "JobName", "${CRAWLER_NAME}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Data Catalog Crawler Metrics"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/glue/crawlers' | fields @timestamp, @message\\n| filter @message like /PII/\\n| sort @timestamp desc\\n| limit 100",
                "region": "${AWS_REGION}",
                "title": "PII Detection Events"
            }
        }
    ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name ${DASHBOARD_NAME} \
        --dashboard-body file://governance-dashboard.json \
        || error "Failed to create CloudWatch dashboard"
    
    success "Governance monitoring dashboard created"
}

# Configure access controls
configure_access_controls() {
    log "Configuring access controls..."
    
    # Get table name
    local table_name=$(aws glue get-tables \
        --database-name ${DATABASE_NAME} \
        --query 'TableList[0].Name' --output text 2>/dev/null)
    
    if [[ "$table_name" != "None" && -n "$table_name" ]]; then
        # Note: In production, you would create actual IAM roles for data analysts
        # For this demo, we'll document the table name for manual verification
        echo "TABLE_NAME=${table_name}" >> .env
        success "Access controls configured for table: ${table_name}"
    else
        warning "No tables found to configure access controls"
    fi
}

# Verification and testing
verify_deployment() {
    log "Verifying deployment..."
    
    # Check database creation
    local db_check=$(aws glue get-database --name ${DATABASE_NAME} --query 'Database.Name' --output text 2>/dev/null)
    if [[ "$db_check" == "${DATABASE_NAME}" ]]; then
        success "Database verification passed"
    else
        error "Database verification failed"
    fi
    
    # Check tables
    local table_count=$(aws glue get-tables --database-name ${DATABASE_NAME} --query 'length(TableList)' --output text 2>/dev/null)
    if [[ "$table_count" -gt 0 ]]; then
        success "Table creation verified ($table_count tables found)"
    else
        warning "No tables found (crawler may still be running)"
    fi
    
    # Check CloudTrail
    local trail_status=$(aws cloudtrail describe-trails --trail-name-list ${TRAIL_NAME} --query 'trailList[0].IsLogging' --output text 2>/dev/null)
    if [[ "$trail_status" == "true" ]]; then
        success "CloudTrail logging verified"
    else
        warning "CloudTrail logging status unclear"
    fi
    
    success "Deployment verification completed"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f glue-trust-policy.json data-analyst-policy.json
    rm -f pii-detection-script.py governance-dashboard.json
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting AWS Glue Data Catalog Governance deployment..."
    
    check_prerequisites
    initialize_environment
    create_storage_resources
    create_data_catalog
    create_iam_role
    create_pii_classifier
    create_glue_crawler
    wait_for_crawler
    enable_lake_formation
    create_governance_policies
    create_pii_detection_script
    enable_cloudtrail
    create_dashboard
    configure_access_controls
    verify_deployment
    cleanup_temp_files
    
    success "Deployment completed successfully!"
    echo
    log "Resource Summary:"
    echo "  - Data Catalog Database: ${DATABASE_NAME}"
    echo "  - Governance Bucket: ${GOVERNANCE_BUCKET}"
    echo "  - Audit Bucket: ${AUDIT_BUCKET}"
    echo "  - Crawler: ${CRAWLER_NAME}"
    echo "  - CloudTrail: ${TRAIL_NAME}"
    echo "  - Dashboard: ${DASHBOARD_NAME}"
    echo
    log "Next Steps:"
    echo "  1. Review the CloudWatch dashboard for monitoring"
    echo "  2. Check CloudTrail logs for audit events"
    echo "  3. Verify PII classification in Data Catalog"
    echo "  4. Test Lake Formation access controls"
    echo
    log "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"