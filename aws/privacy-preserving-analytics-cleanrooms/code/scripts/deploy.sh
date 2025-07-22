#!/bin/bash

# Privacy-Preserving Analytics with Clean Rooms - Deployment Script
# This script deploys infrastructure for privacy-preserving analytics using AWS Clean Rooms and QuickSight

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
        error "Unable to retrieve AWS account information."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Initialize environment variables
init_environment() {
    log "Initializing environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS_REGION not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export CLEAN_ROOMS_NAME="analytics-collaboration-${random_suffix}"
    export S3_BUCKET_ORG_A="clean-rooms-data-a-${random_suffix}"
    export S3_BUCKET_ORG_B="clean-rooms-data-b-${random_suffix}"
    export GLUE_DATABASE="clean_rooms_analytics_${random_suffix//-/_}"
    export QUICKSIGHT_ANALYSIS="privacy-analytics-${random_suffix}"
    export RESULTS_BUCKET="clean-rooms-results-${random_suffix}"
    
    # Save environment variables for cleanup script
    cat > .deployment_env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
CLEAN_ROOMS_NAME=${CLEAN_ROOMS_NAME}
S3_BUCKET_ORG_A=${S3_BUCKET_ORG_A}
S3_BUCKET_ORG_B=${S3_BUCKET_ORG_B}
GLUE_DATABASE=${GLUE_DATABASE}
QUICKSIGHT_ANALYSIS=${QUICKSIGHT_ANALYSIS}
RESULTS_BUCKET=${RESULTS_BUCKET}
EOF
    
    success "Environment initialized with region: ${AWS_REGION}"
}

# Create S3 buckets with security features
create_s3_buckets() {
    log "Creating S3 buckets with security features..."
    
    # Create buckets
    for bucket in "$S3_BUCKET_ORG_A" "$S3_BUCKET_ORG_B" "$RESULTS_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            warning "Bucket $bucket already exists, skipping creation"
            continue
        fi
        
        log "Creating bucket: $bucket"
        aws s3 mb "s3://${bucket}" --region "${AWS_REGION}"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket" \
            --versioning-configuration Status=Enabled
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$bucket" \
            --server-side-encryption-configuration \
            'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$bucket" \
            --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    done
    
    success "S3 buckets created with security features enabled"
}

# Create sample datasets
create_sample_datasets() {
    log "Creating sample datasets..."
    
    # Create sample customer data for Organization A
    cat > customer_data_org_a.csv << 'EOF'
customer_id,age_group,region,purchase_amount,product_category,registration_date
1001,25-34,east,250.00,electronics,2023-01-15
1002,35-44,west,180.50,clothing,2023-02-20
1003,45-54,central,320.75,home,2023-01-10
1004,25-34,east,95.25,books,2023-03-05
1005,55-64,west,450.00,electronics,2023-02-28
1006,25-34,central,180.00,electronics,2023-01-25
1007,35-44,east,275.50,clothing,2023-02-15
1008,45-54,west,395.25,home,2023-03-01
1009,25-34,central,125.75,books,2023-02-10
1010,55-64,east,520.00,electronics,2023-03-12
EOF

    # Create sample customer data for Organization B
    cat > customer_data_org_b.csv << 'EOF'
customer_id,age_group,region,engagement_score,channel_preference,last_interaction
2001,25-34,east,85,email,2023-03-15
2002,35-44,west,72,social,2023-03-20
2003,45-54,central,91,email,2023-03-10
2004,25-34,east,68,mobile,2023-03-25
2005,55-64,west,88,email,2023-03-18
2006,25-34,central,76,mobile,2023-03-08
2007,35-44,east,82,email,2023-03-22
2008,45-54,west,94,social,2023-03-05
2009,25-34,central,69,mobile,2023-03-14
2010,55-64,east,87,email,2023-03-20
EOF
    
    # Upload datasets to S3
    aws s3 cp customer_data_org_a.csv "s3://${S3_BUCKET_ORG_A}/data/"
    aws s3 cp customer_data_org_b.csv "s3://${S3_BUCKET_ORG_B}/data/"
    
    success "Sample datasets created and uploaded"
}

# Create IAM roles for Clean Rooms and Glue
create_iam_roles() {
    log "Creating IAM roles for Clean Rooms and Glue..."
    
    # Create Clean Rooms service role trust policy
    cat > clean-rooms-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cleanrooms.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    # Create Clean Rooms role if it doesn't exist
    if ! aws iam get-role --role-name CleanRoomsAnalyticsRole &>/dev/null; then
        log "Creating Clean Rooms IAM role..."
        aws iam create-role \
            --role-name CleanRoomsAnalyticsRole \
            --assume-role-policy-document file://clean-rooms-trust-policy.json
        
        # Attach AWS managed policy
        aws iam attach-role-policy \
            --role-name CleanRoomsAnalyticsRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSCleanRoomsService
    else
        warning "CleanRoomsAnalyticsRole already exists, skipping creation"
    fi
    
    # Create custom S3 access policy
    cat > clean-rooms-s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_ORG_A}",
        "arn:aws:s3:::${S3_BUCKET_ORG_A}/*",
        "arn:aws:s3:::${S3_BUCKET_ORG_B}",
        "arn:aws:s3:::${S3_BUCKET_ORG_B}/*",
        "arn:aws:s3:::${RESULTS_BUCKET}",
        "arn:aws:s3:::${RESULTS_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "glue:GetTable",
        "glue:GetTables",
        "glue:GetDatabase"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    # Create and attach S3 access policy
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access" &>/dev/null; then
        aws iam create-policy \
            --policy-name CleanRoomsS3Access \
            --policy-document file://clean-rooms-s3-policy.json
    fi
    
    aws iam attach-role-policy \
        --role-name CleanRoomsAnalyticsRole \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access" 2>/dev/null || true
    
    # Create Glue role
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

    if ! aws iam get-role --role-name GlueCleanRoomsRole &>/dev/null; then
        log "Creating Glue IAM role..."
        aws iam create-role \
            --role-name GlueCleanRoomsRole \
            --assume-role-policy-document file://glue-trust-policy.json
        
        # Attach policies
        aws iam attach-role-policy \
            --role-name GlueCleanRoomsRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
        
        aws iam attach-role-policy \
            --role-name GlueCleanRoomsRole \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CleanRoomsS3Access"
    else
        warning "GlueCleanRoomsRole already exists, skipping creation"
    fi
    
    # Wait for role propagation
    sleep 10
    
    success "IAM roles created and configured"
}

# Create Glue database and crawlers
create_glue_resources() {
    log "Creating Glue database and crawlers..."
    
    # Create Glue database
    if ! aws glue get-database --name "${GLUE_DATABASE}" &>/dev/null; then
        aws glue create-database \
            --database-input "{\"Name\":\"${GLUE_DATABASE}\", \"Description\":\"Clean Rooms analytics database for privacy-preserving collaboration\"}"
    else
        warning "Glue database ${GLUE_DATABASE} already exists"
    fi
    
    # Create crawlers
    local crawler_org_a="crawler-org-a-${CLEAN_ROOMS_NAME##*-}"
    local crawler_org_b="crawler-org-b-${CLEAN_ROOMS_NAME##*-}"
    
    # Create crawler for Organization A
    if ! aws glue get-crawler --name "$crawler_org_a" &>/dev/null; then
        aws glue create-crawler \
            --name "$crawler_org_a" \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/GlueCleanRoomsRole" \
            --database-name "${GLUE_DATABASE}" \
            --description "Crawler for Organization A customer data" \
            --targets "{\"S3Targets\": [{\"Path\": \"s3://${S3_BUCKET_ORG_A}/data/\"}]}"
    fi
    
    # Create crawler for Organization B
    if ! aws glue get-crawler --name "$crawler_org_b" &>/dev/null; then
        aws glue create-crawler \
            --name "$crawler_org_b" \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/GlueCleanRoomsRole" \
            --database-name "${GLUE_DATABASE}" \
            --description "Crawler for Organization B customer data" \
            --targets "{\"S3Targets\": [{\"Path\": \"s3://${S3_BUCKET_ORG_B}/data/\"}]}"
    fi
    
    # Run crawlers
    log "Running Glue crawlers to discover schemas..."
    aws glue start-crawler --name "$crawler_org_a" 2>/dev/null || warning "Crawler $crawler_org_a may already be running"
    aws glue start-crawler --name "$crawler_org_b" 2>/dev/null || warning "Crawler $crawler_org_b may already be running"
    
    # Wait for crawlers to complete
    log "Waiting for crawlers to complete (this may take a few minutes)..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local crawler_a_state=$(aws glue get-crawler --name "$crawler_org_a" --query 'Crawler.State' --output text 2>/dev/null || echo "UNKNOWN")
        local crawler_b_state=$(aws glue get-crawler --name "$crawler_org_b" --query 'Crawler.State' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$crawler_a_state" == "READY" ]] && [[ "$crawler_b_state" == "READY" ]]; then
            success "Crawlers completed successfully"
            break
        fi
        
        sleep 30
        wait_time=$((wait_time + 30))
        log "Waiting for crawlers... (${wait_time}s elapsed)"
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        warning "Crawlers may still be running. Proceeding with deployment..."
    fi
    
    success "Glue resources created"
}

# Create Clean Rooms collaboration
create_clean_rooms_collaboration() {
    log "Creating Clean Rooms collaboration..."
    
    # Check if collaboration already exists
    local existing_collab=$(aws cleanrooms list-collaborations \
        --query "collaborationList[?name=='${CLEAN_ROOMS_NAME}'].id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$existing_collab" ]]; then
        warning "Collaboration ${CLEAN_ROOMS_NAME} already exists"
        echo "COLLABORATION_ID=${existing_collab}" >> .deployment_env
        return
    fi
    
    # Create collaboration
    aws cleanrooms create-collaboration \
        --name "${CLEAN_ROOMS_NAME}" \
        --description "Privacy-preserving analytics collaboration for cross-organizational insights" \
        --member-abilities "CAN_QUERY,CAN_RECEIVE_RESULTS" \
        --query-log-status "ENABLED" \
        --data-encryption-metadata "{\"preserveNulls\": true, \"allowCleartext\": false, \"allowDuplicates\": false, \"allowJoinsOnColumnsWithDifferentNames\": false}"
    
    # Wait for collaboration creation
    sleep 15
    
    # Get collaboration ID
    local collaboration_id=$(aws cleanrooms list-collaborations \
        --query "collaborationList[?name=='${CLEAN_ROOMS_NAME}'].id" \
        --output text)
    
    if [[ -z "$collaboration_id" ]]; then
        error "Failed to create or find collaboration"
        exit 1
    fi
    
    echo "COLLABORATION_ID=${collaboration_id}" >> .deployment_env
    success "Clean Rooms collaboration created: ${collaboration_id}"
}

# Configure Clean Rooms tables
configure_clean_rooms_tables() {
    log "Configuring Clean Rooms tables..."
    
    # Source collaboration ID
    source .deployment_env
    
    # Wait for tables to be available in Glue
    local max_wait=180
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local org_a_table=$(aws glue get-tables \
            --database-name "${GLUE_DATABASE}" \
            --query "TableList[?contains(Name, 'customer_data_org_a')].Name" \
            --output text 2>/dev/null || echo "")
        
        local org_b_table=$(aws glue get-tables \
            --database-name "${GLUE_DATABASE}" \
            --query "TableList[?contains(Name, 'customer_data_org_b')].Name" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$org_a_table" ]] && [[ -n "$org_b_table" ]]; then
            log "Found tables: $org_a_table, $org_b_table"
            break
        fi
        
        sleep 30
        wait_time=$((wait_time + 30))
        log "Waiting for Glue tables... (${wait_time}s elapsed)"
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        error "Timeout waiting for Glue tables to be available"
        exit 1
    fi
    
    # Configure tables in Clean Rooms
    local org_a_table=$(aws glue get-tables \
        --database-name "${GLUE_DATABASE}" \
        --query "TableList[?contains(Name, 'customer_data_org_a')].Name" \
        --output text)
    
    local org_b_table=$(aws glue get-tables \
        --database-name "${GLUE_DATABASE}" \
        --query "TableList[?contains(Name, 'customer_data_org_b')].Name" \
        --output text)
    
    # Create configured tables
    aws cleanrooms create-configured-table \
        --name "org-a-customers" \
        --description "Organization A customer data for privacy-preserving analytics" \
        --table-reference "{\"glue\": {\"tableName\": \"${org_a_table}\", \"databaseName\": \"${GLUE_DATABASE}\"}}" \
        --allowed-columns "age_group,region,product_category,purchase_amount" \
        --analysis-method "DIRECT_QUERY" || warning "Table org-a-customers may already exist"
    
    aws cleanrooms create-configured-table \
        --name "org-b-customers" \
        --description "Organization B customer data for privacy-preserving analytics" \
        --table-reference "{\"glue\": {\"tableName\": \"${org_b_table}\", \"databaseName\": \"${GLUE_DATABASE}\"}}" \
        --allowed-columns "age_group,region,channel_preference,engagement_score" \
        --analysis-method "DIRECT_QUERY" || warning "Table org-b-customers may already exist"
    
    # Wait for table creation
    sleep 10
    
    # Associate tables with collaboration
    local org_a_table_id=$(aws cleanrooms list-configured-tables \
        --query "configuredTableSummaries[?name=='org-a-customers'].id" \
        --output text)
    
    local org_b_table_id=$(aws cleanrooms list-configured-tables \
        --query "configuredTableSummaries[?name=='org-b-customers'].id" \
        --output text)
    
    if [[ -n "$org_a_table_id" ]] && [[ -n "$org_b_table_id" ]]; then
        aws cleanrooms create-configured-table-association \
            --name "org-a-association" \
            --description "Association for Organization A data with privacy controls" \
            --membership-identifier "${COLLABORATION_ID}" \
            --configured-table-identifier "${org_a_table_id}" \
            --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/CleanRoomsAnalyticsRole" || warning "Association may already exist"
        
        aws cleanrooms create-configured-table-association \
            --name "org-b-association" \
            --description "Association for Organization B data with privacy controls" \
            --membership-identifier "${COLLABORATION_ID}" \
            --configured-table-identifier "${org_b_table_id}" \
            --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/CleanRoomsAnalyticsRole" || warning "Association may already exist"
    fi
    
    success "Clean Rooms tables configured and associated"
}

# Execute sample privacy-preserving query
execute_sample_query() {
    log "Executing sample privacy-preserving query..."
    
    # Source environment variables
    source .deployment_env
    
    # Create privacy query
    cat > privacy_query.sql << 'EOF'
SELECT 
    age_group,
    region,
    COUNT(*) as customer_count,
    AVG(purchase_amount) as avg_purchase_amount,
    AVG(engagement_score) as avg_engagement_score
FROM org_a_customers a
INNER JOIN org_b_customers b 
    ON a.age_group = b.age_group 
    AND a.region = b.region
GROUP BY age_group, region
HAVING COUNT(*) >= 3
EOF
    
    # Execute query
    local query_string=$(cat privacy_query.sql | tr '\n' ' ')
    local query_id=$(aws cleanrooms start-protected-query \
        --type "SQL" \
        --membership-identifier "${COLLABORATION_ID}" \
        --sql-parameters "{\"queryString\": \"${query_string}\"}" \
        --result-configuration "{\"outputConfiguration\": {\"s3\": {\"resultFormat\": \"CSV\", \"bucket\": \"${RESULTS_BUCKET}\", \"keyPrefix\": \"query-results/\"}}}" \
        --query "protectedQueryId" --output text 2>/dev/null || echo "")
    
    if [[ -n "$query_id" ]]; then
        echo "QUERY_ID=${query_id}" >> .deployment_env
        success "Privacy-preserving query executed: ${query_id}"
    else
        warning "Failed to execute query - this may be expected if Clean Rooms features are not fully available in your region"
    fi
}

# Setup QuickSight (basic configuration)
setup_quicksight() {
    log "Setting up QuickSight basic configuration..."
    
    # Check if QuickSight is available in region
    if ! aws quicksight describe-account-settings --aws-account-id "${AWS_ACCOUNT_ID}" &>/dev/null; then
        warning "QuickSight not available or not configured in this region/account"
        warning "Please configure QuickSight manually through the AWS Console"
        return
    fi
    
    # Create QuickSight data source
    aws quicksight create-data-source \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --data-source-id "clean-rooms-results-${CLEAN_ROOMS_NAME##*-}" \
        --name "Clean Rooms Analytics Results" \
        --type "S3" \
        --data-source-parameters "{\"S3Parameters\": {\"ManifestFileLocation\": {\"Bucket\": \"${RESULTS_BUCKET}\", \"Key\": \"query-results/\"}}}" \
        --permissions "[{\"Principal\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:root\", \"Actions\": [\"quicksight:DescribeDataSource\", \"quicksight:DescribeDataSourcePermissions\", \"quicksight:PassDataSource\", \"quicksight:UpdateDataSource\", \"quicksight:DeleteDataSource\", \"quicksight:UpdateDataSourcePermissions\"]}]" \
        2>/dev/null || warning "QuickSight data source creation failed - please configure manually"
    
    success "QuickSight basic configuration completed"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f customer_data_org_*.csv privacy_query.sql
    rm -f *-trust-policy.json *-policy.json
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting AWS Clean Rooms Privacy Analytics deployment..."
    
    check_prerequisites
    init_environment
    create_s3_buckets
    create_sample_datasets
    create_iam_roles
    create_glue_resources
    create_clean_rooms_collaboration
    configure_clean_rooms_tables
    execute_sample_query
    setup_quicksight
    cleanup_temp_files
    
    success "🎉 Deployment completed successfully!"
    echo ""
    echo "=================================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=================================================="
    echo "Clean Rooms Collaboration: ${CLEAN_ROOMS_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "S3 Buckets:"
    echo "  - Organization A: ${S3_BUCKET_ORG_A}"
    echo "  - Organization B: ${S3_BUCKET_ORG_B}"
    echo "  - Results: ${RESULTS_BUCKET}"
    echo "Glue Database: ${GLUE_DATABASE}"
    echo ""
    echo "Next steps:"
    echo "1. Access AWS Clean Rooms console to view collaboration"
    echo "2. Configure QuickSight dashboards for visualization"
    echo "3. Run additional privacy-preserving queries"
    echo "4. Use './destroy.sh' to clean up resources when done"
    echo "=================================================="
}

# Execute main function
main "$@"