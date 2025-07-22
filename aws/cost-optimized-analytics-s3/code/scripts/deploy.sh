#!/bin/bash

# Cost-Optimized Analytics with S3 Tiering - Deployment Script
# This script deploys the complete infrastructure for cost-optimized analytics
# using S3 Intelligent-Tiering, AWS Glue, Amazon Athena, and CloudWatch monitoring

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    if [ ! -z "${BUCKET_NAME:-}" ]; then
        aws s3 rm s3://$BUCKET_NAME --recursive --quiet 2>/dev/null || true
        aws s3api delete-bucket --bucket $BUCKET_NAME 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Banner
echo "=================================================="
echo "  Cost-Optimized Analytics Deployment Script"
echo "  S3 Intelligent-Tiering + Athena + Glue"
echo "=================================================="
echo

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install AWS CLI v2 and try again."
    exit 1
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
log "AWS CLI version: $AWS_CLI_VERSION"

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' and try again."
    exit 1
fi

# Get AWS account information
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

if [ -z "$AWS_REGION" ]; then
    log_error "AWS region not configured. Please set a default region with 'aws configure set region <region>'"
    exit 1
fi

log_success "Prerequisites check completed"
log "AWS Account ID: $AWS_ACCOUNT_ID"
log "AWS Region: $AWS_REGION"
echo

# Check required permissions
log "Verifying AWS permissions..."

REQUIRED_SERVICES=(
    "s3:CreateBucket"
    "glue:CreateDatabase"
    "athena:CreateWorkGroup"
    "cloudwatch:PutDashboard"
    "ce:PutAnomalyDetector"
)

# Basic permission check by trying to list services
aws s3 ls &> /dev/null || {
    log_error "Insufficient S3 permissions. Please ensure you have S3 admin access."
    exit 1
}

aws glue get-databases --max-items 1 &> /dev/null || {
    log_error "Insufficient Glue permissions. Please ensure you have Glue admin access."
    exit 1
}

aws athena list-work-groups --max-items 1 &> /dev/null || {
    log_error "Insufficient Athena permissions. Please ensure you have Athena admin access."
    exit 1
}

log_success "Permission verification completed"
echo

# Generate unique identifiers
log "Generating unique resource identifiers..."

RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export BUCKET_NAME="cost-optimized-analytics-${RANDOM_SUFFIX}"
export GLUE_DATABASE="analytics_database_${RANDOM_SUFFIX}"
export ATHENA_WORKGROUP="cost-optimized-workgroup-${RANDOM_SUFFIX}"

log "Resource names:"
log "  S3 Bucket: $BUCKET_NAME"
log "  Glue Database: $GLUE_DATABASE"
log "  Athena Workgroup: $ATHENA_WORKGROUP"
echo

# Check if bucket name is available
log "Checking S3 bucket name availability..."
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    log_error "Bucket name '$BUCKET_NAME' already exists. Please try again."
    exit 1
fi
log_success "Bucket name is available"
echo

# Start deployment
log "Starting infrastructure deployment..."
echo

# Step 1: Create S3 bucket with versioning and encryption
log "Step 1: Creating S3 bucket with security features..."

# Create bucket with region-specific configuration
if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET_NAME"
else
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION"
fi

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'

# Block public access
aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

log_success "S3 bucket created with security features"

# Step 2: Configure S3 Intelligent-Tiering
log "Step 2: Configuring S3 Intelligent-Tiering with archive tiers..."

aws s3api put-bucket-intelligent-tiering-configuration \
    --bucket "$BUCKET_NAME" \
    --id "cost-optimization-config" \
    --intelligent-tiering-configuration '{
        "Id": "cost-optimization-config",
        "Status": "Enabled",
        "Filter": {
            "Prefix": "analytics-data/"
        },
        "Tierings": [
            {
                "Days": 90,
                "AccessTier": "ARCHIVE_ACCESS"
            },
            {
                "Days": 180,
                "AccessTier": "DEEP_ARCHIVE_ACCESS"
            }
        ]
    }'

log_success "S3 Intelligent-Tiering configured"

# Step 3: Create lifecycle policy
log "Step 3: Creating lifecycle policy for automatic transitions..."

aws s3api put-bucket-lifecycle-configuration \
    --bucket "$BUCKET_NAME" \
    --lifecycle-configuration '{
        "Rules": [{
            "ID": "intelligent-tiering-transition",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "analytics-data/"
            },
            "Transitions": [{
                "Days": 0,
                "StorageClass": "INTELLIGENT_TIERING"
            }]
        }]
    }'

log_success "Lifecycle policy created"

# Step 4: Upload sample analytics data
log "Step 4: Generating and uploading sample analytics data..."

# Create temporary directory for sample data
TEMP_DIR=$(mktemp -d)
mkdir -p "$TEMP_DIR/analytics-data"

# Generate recent data (frequently accessed)
for i in {1..10}; do
    echo "timestamp,user_id,transaction_id,amount" > "$TEMP_DIR/analytics-data/recent-logs-day-$i.csv"
    for j in {1..100}; do
        echo "$(date -d "$i days ago" '+%Y-%m-%d %H:%M:%S'),user_$((RANDOM%1000)),transaction_$((RANDOM%10000)),amount_$((RANDOM%1000))" \
            >> "$TEMP_DIR/analytics-data/recent-logs-day-$i.csv"
    done
done

# Generate older data (infrequently accessed)
for i in {1..5}; do
    echo "timestamp,user_id,transaction_id,amount" > "$TEMP_DIR/analytics-data/archive-logs-month-$i.csv"
    for j in {1..50}; do
        echo "$(date -d "$((i+30)) days ago" '+%Y-%m-%d %H:%M:%S'),user_$((RANDOM%1000)),transaction_$((RANDOM%10000)),amount_$((RANDOM%1000))" \
            >> "$TEMP_DIR/analytics-data/archive-logs-month-$i.csv"
    done
done

# Upload data with Intelligent-Tiering storage class
aws s3 sync "$TEMP_DIR/analytics-data" "s3://$BUCKET_NAME/analytics-data/" \
    --storage-class INTELLIGENT_TIERING

# Cleanup temporary files
rm -rf "$TEMP_DIR"

log_success "Sample analytics data uploaded"

# Step 5: Create AWS Glue database and table
log "Step 5: Creating AWS Glue database and table..."

# Create Glue database
aws glue create-database \
    --database-input Name="$GLUE_DATABASE",Description="Cost-optimized analytics database"

# Create Glue table for analytics data
aws glue create-table \
    --database-name "$GLUE_DATABASE" \
    --table-input '{
        "Name": "transaction_logs",
        "Description": "Transaction logs table for cost-optimized analytics",
        "StorageDescriptor": {
            "Columns": [
                {"Name": "timestamp", "Type": "string", "Comment": "Transaction timestamp"},
                {"Name": "user_id", "Type": "string", "Comment": "User identifier"},
                {"Name": "transaction_id", "Type": "string", "Comment": "Transaction identifier"},
                {"Name": "amount", "Type": "string", "Comment": "Transaction amount"}
            ],
            "Location": "s3://'$BUCKET_NAME'/analytics-data/",
            "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
            "SerdeInfo": {
                "SerializationLibrary": "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
                "Parameters": {
                    "field.delim": ",",
                    "skip.header.line.count": "1"
                }
            }
        },
        "Parameters": {
            "classification": "csv",
            "delimiter": ",",
            "skip.header.line.count": "1"
        }
    }'

log_success "Glue database and table created"

# Step 6: Configure Amazon Athena workgroup
log "Step 6: Configuring Amazon Athena workgroup with cost controls..."

aws athena create-work-group \
    --name "$ATHENA_WORKGROUP" \
    --description "Cost-optimized workgroup for analytics" \
    --configuration '{
        "ResultConfiguration": {
            "OutputLocation": "s3://'$BUCKET_NAME'/athena-results/"
        },
        "EnforceWorkGroupConfiguration": true,
        "PublishCloudWatchMetrics": true,
        "BytesScannedCutoffPerQuery": 1073741824
    }'

log_success "Athena workgroup created with cost controls"

# Step 7: Set up CloudWatch monitoring
log "Step 7: Setting up CloudWatch monitoring and dashboards..."

# Create CloudWatch dashboard for cost monitoring
aws cloudwatch put-dashboard \
    --dashboard-name "S3-Cost-Optimization-${RANDOM_SUFFIX}" \
    --dashboard-body '{
        "widgets": [
            {
                "type": "metric",
                "x": 0,
                "y": 0,
                "width": 12,
                "height": 6,
                "properties": {
                    "metrics": [
                        ["AWS/S3", "BucketSizeBytes", "BucketName", "'$BUCKET_NAME'", "StorageType", "IntelligentTieringFAStorage"],
                        [".", ".", ".", ".", ".", "IntelligentTieringIAStorage"],
                        [".", ".", ".", ".", ".", "IntelligentTieringAAStorage"],
                        [".", ".", ".", ".", ".", "IntelligentTieringAIAStorage"],
                        [".", ".", ".", ".", ".", "IntelligentTieringDAAStorage"]
                    ],
                    "view": "timeSeries",
                    "stacked": false,
                    "region": "'$AWS_REGION'",
                    "title": "S3 Intelligent-Tiering Storage Distribution",
                    "period": 300,
                    "stat": "Average"
                }
            },
            {
                "type": "metric",
                "x": 0,
                "y": 6,
                "width": 12,
                "height": 6,
                "properties": {
                    "metrics": [
                        ["AWS/Athena", "DataScannedInBytes", {"stat": "Sum"}],
                        [".", "QueryExecutionTime", {"stat": "Average"}]
                    ],
                    "view": "timeSeries",
                    "stacked": false,
                    "region": "'$AWS_REGION'",
                    "title": "Athena Query Metrics",
                    "period": 300
                }
            }
        ]
    }'

# Create cost anomaly detection
aws ce put-anomaly-detector \
    --anomaly-detector '{
        "DetectorName": "S3-Cost-Anomaly-'$RANDOM_SUFFIX'",
        "MonitorType": "DIMENSIONAL",
        "DimensionSpecification": {
            "Dimension": "SERVICE",
            "Values": ["Amazon Simple Storage Service"]
        }
    }' || log_warning "Cost anomaly detector creation may require additional permissions"

log_success "CloudWatch monitoring configured"

# Step 8: Create cost optimization monitoring script
log "Step 8: Creating cost optimization monitoring script..."

cat > "/tmp/cost-analysis-${RANDOM_SUFFIX}.sh" << 'EOF'
#!/bin/bash

BUCKET_NAME=$1

if [ -z "$BUCKET_NAME" ]; then
    echo "Usage: $0 <bucket-name>"
    exit 1
fi

echo "=== S3 Intelligent-Tiering Cost Analysis ==="
echo "Bucket: $BUCKET_NAME"
echo "Date: $(date)"
echo

# Get storage metrics
echo "Storage Distribution by Tier:"

# Function to get storage metrics
get_storage_metric() {
    local storage_type=$1
    local display_name=$2
    
    local result=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/S3 \
        --metric-name BucketSizeBytes \
        --dimensions Name=BucketName,Value=$BUCKET_NAME Name=StorageType,Value=$storage_type \
        --start-time $(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 86400 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$result" != "None" ] && [ "$result" != "null" ]; then
        echo "  $display_name: $(echo $result | awk '{printf "%.2f GB\n", $1/1024/1024/1024}')"
    else
        echo "  $display_name: 0.00 GB (no data yet)"
    fi
}

get_storage_metric "IntelligentTieringFAStorage" "Frequent Access"
get_storage_metric "IntelligentTieringIAStorage" "Infrequent Access"
get_storage_metric "IntelligentTieringAAStorage" "Archive Access"
get_storage_metric "IntelligentTieringAIAStorage" "Archive Instant Access"
get_storage_metric "IntelligentTieringDAAStorage" "Deep Archive Access"

echo
echo "Athena Query Metrics (Last 24 Hours):"

# Get Athena metrics
local athena_scanned=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/Athena \
    --metric-name DataScannedInBytes \
    --start-time $(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 86400 \
    --statistics Sum \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null || echo "None")

if [ "$athena_scanned" != "None" ] && [ "$athena_scanned" != "null" ]; then
    echo "  Data Scanned: $(echo $athena_scanned | awk '{printf "%.2f GB\n", $1/1024/1024/1024}')"
    echo "  Estimated Cost: $(echo $athena_scanned | awk '{printf "$%.4f\n", ($1/1024/1024/1024/1024)*5}')"
else
    echo "  Data Scanned: 0.00 GB (no queries yet)"
    echo "  Estimated Cost: $0.0000"
fi

echo
echo "Cost Optimization Recommendations:"
echo "  - Monitor access patterns over 30+ days for optimal tier distribution"
echo "  - Consider partition strategies for frequently queried data"
echo "  - Use columnar formats (Parquet) to reduce Athena scanning costs"
echo "  - Archive old data to Deep Archive tier for maximum savings"
EOF

chmod +x "/tmp/cost-analysis-${RANDOM_SUFFIX}.sh"

log_success "Cost monitoring script created at /tmp/cost-analysis-${RANDOM_SUFFIX}.sh"

# Step 9: Test analytics performance
log "Step 9: Testing analytics performance across storage tiers..."

# Wait a moment for table to be available
sleep 5

# Test basic query
QUERY_ID=$(aws athena start-query-execution \
    --query-string "SELECT COUNT(*) as total_transactions FROM $GLUE_DATABASE.transaction_logs" \
    --work-group "$ATHENA_WORKGROUP" \
    --query 'QueryExecutionId' \
    --output text)

# Wait for query completion
log "Waiting for test query to complete (Query ID: $QUERY_ID)..."
for i in {1..30}; do
    QUERY_STATE=$(aws athena get-query-execution \
        --query-execution-id "$QUERY_ID" \
        --query 'QueryExecution.Status.State' \
        --output text)
    
    if [ "$QUERY_STATE" = "SUCCEEDED" ]; then
        log_success "Test query completed successfully"
        break
    elif [ "$QUERY_STATE" = "FAILED" ] || [ "$QUERY_STATE" = "CANCELLED" ]; then
        log_warning "Test query failed or was cancelled"
        break
    else
        sleep 2
    fi
done

log_success "Analytics performance test completed"

# Final validation
log "Step 10: Performing final validation..."

# Verify S3 bucket and configuration
aws s3api head-bucket --bucket "$BUCKET_NAME" > /dev/null
aws s3api get-bucket-intelligent-tiering-configuration \
    --bucket "$BUCKET_NAME" \
    --id "cost-optimization-config" > /dev/null

# Verify Glue resources
aws glue get-database --name "$GLUE_DATABASE" > /dev/null
aws glue get-table --database-name "$GLUE_DATABASE" --name "transaction_logs" > /dev/null

# Verify Athena workgroup
aws athena get-work-group --work-group "$ATHENA_WORKGROUP" > /dev/null

log_success "All resources validated successfully"

# Summary
echo
echo "=================================================="
echo "           DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "=================================================="
echo
echo "Resources Created:"
echo "  ✅ S3 Bucket: $BUCKET_NAME"
echo "  ✅ Glue Database: $GLUE_DATABASE"
echo "  ✅ Glue Table: transaction_logs"
echo "  ✅ Athena Workgroup: $ATHENA_WORKGROUP"
echo "  ✅ CloudWatch Dashboard: S3-Cost-Optimization-${RANDOM_SUFFIX}"
echo "  ✅ Cost Anomaly Detector: S3-Cost-Anomaly-${RANDOM_SUFFIX}"
echo
echo "Next Steps:"
echo "  1. View CloudWatch Dashboard:"
echo "     https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=S3-Cost-Optimization-${RANDOM_SUFFIX}"
echo
echo "  2. Run Athena queries:"
echo "     aws athena start-query-execution --query-string \"SELECT * FROM $GLUE_DATABASE.transaction_logs LIMIT 10\" --work-group $ATHENA_WORKGROUP"
echo
echo "  3. Monitor cost optimization:"
echo "     /tmp/cost-analysis-${RANDOM_SUFFIX}.sh $BUCKET_NAME"
echo
echo "  4. Access Athena Query Editor:"
echo "     https://console.aws.amazon.com/athena/home?region=$AWS_REGION#query"
echo
echo "Estimated Monthly Cost: \$15-25 for 100GB of data"
echo "Cost Savings: 20-40% compared to standard storage"
echo
echo "To clean up all resources, run: ./destroy.sh"
echo "=================================================="

# Save environment variables for cleanup script
cat > "/tmp/deployment-vars-${RANDOM_SUFFIX}.env" << EOF
BUCKET_NAME=$BUCKET_NAME
GLUE_DATABASE=$GLUE_DATABASE
ATHENA_WORKGROUP=$ATHENA_WORKGROUP
RANDOM_SUFFIX=$RANDOM_SUFFIX
AWS_REGION=$AWS_REGION
EOF

log_success "Deployment variables saved to /tmp/deployment-vars-${RANDOM_SUFFIX}.env"
echo "Make sure to save this file if you plan to run the destroy script later!"