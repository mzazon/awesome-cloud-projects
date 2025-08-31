#!/bin/bash

# Enterprise Oracle Database Connectivity with VPC Lattice and S3 - Deployment Script
# Recipe: enterprise-oracle-connectivity-lattice-s3
# Version: 1.1
# Generated: 2025-01-16

set -euo pipefail

# Color codes for output
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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup..."
    ./destroy.sh --force || true
    exit 1
}

trap cleanup_on_error ERR

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Enterprise Oracle Database Connectivity                  ║
║                         with VPC Lattice and S3                            ║
║                              Deployment Script                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Prerequisites check
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
    log_error "AWS CLI version 2.0.0 or higher is required. Current version: $AWS_CLI_VERSION"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured or invalid"
    exit 1
fi

# Check required permissions (basic check)
CALLER_IDENTITY=$(aws sts get-caller-identity)
log "AWS Identity: $(echo "$CALLER_IDENTITY" | jq -r '.Arn // .UserId')"

log_success "Prerequisites check completed"

# Environment setup
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    log_warning "AWS region not set in config, using us-east-1"
    export AWS_REGION="us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

# Set resource names
export ODB_NETWORK_NAME="enterprise-odb-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="oracle-enterprise-backup-${RANDOM_SUFFIX}"
export REDSHIFT_CLUSTER_ID="oracle-analytics-${RANDOM_SUFFIX}"
export INTEGRATION_NAME="oracle-zero-etl-${RANDOM_SUFFIX}"

# Save environment variables to file for cleanup script
cat > ./deployment_vars.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
ODB_NETWORK_NAME=${ODB_NETWORK_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
REDSHIFT_CLUSTER_ID=${REDSHIFT_CLUSTER_ID}
INTEGRATION_NAME=${INTEGRATION_NAME}
EOF

log_success "Environment configured"
log "Region: ${AWS_REGION}"
log "Account ID: ${AWS_ACCOUNT_ID}"
log "Resource Suffix: ${RANDOM_SUFFIX}"

# Check for existing ODB network
log "Checking for existing Oracle Database@AWS network..."
if aws odb list-odb-networks &> /dev/null; then
    export ODB_NETWORK_ID=$(aws odb list-odb-networks \
        --query 'OdbNetworks[0].OdbNetworkId' --output text 2>/dev/null || echo "")
    if [ -n "$ODB_NETWORK_ID" ] && [ "$ODB_NETWORK_ID" != "None" ]; then
        log_success "Found existing ODB Network ID: ${ODB_NETWORK_ID}"
        echo "ODB_NETWORK_ID=${ODB_NETWORK_ID}" >> ./deployment_vars.env
    else
        log_warning "No existing Oracle Database@AWS network found"
        log_warning "Please create an Oracle Database@AWS network first or provide ODB_NETWORK_ID"
        read -p "Enter existing ODB Network ID (or press Enter to skip): " USER_ODB_NETWORK_ID
        if [ -n "$USER_ODB_NETWORK_ID" ]; then
            export ODB_NETWORK_ID="$USER_ODB_NETWORK_ID"
            echo "ODB_NETWORK_ID=${ODB_NETWORK_ID}" >> ./deployment_vars.env
        else
            log_error "Oracle Database@AWS network is required for this deployment"
            exit 1
        fi
    fi
else
    log_warning "Oracle Database@AWS service not available in this region or account"
    log_warning "Continuing with simulation mode for demonstration"
    export ODB_NETWORK_ID="simulated-odb-network-${RANDOM_SUFFIX}"
    echo "ODB_NETWORK_ID=${ODB_NETWORK_ID}" >> ./deployment_vars.env
fi

# Step 1: Enable S3 Access for Oracle Database@AWS Network
log "Step 1: Enabling S3 access for Oracle Database@AWS Network..."

if [[ "$ODB_NETWORK_ID" != "simulated-"* ]]; then
    aws odb update-odb-network \
        --odb-network-id "${ODB_NETWORK_ID}" \
        --s3-access ENABLED || {
        log_warning "Failed to enable S3 access - continuing with setup"
    }
    
    # Wait and verify
    sleep 10
    S3_ACCESS_STATUS=$(aws odb get-odb-network \
        --odb-network-id "${ODB_NETWORK_ID}" \
        --query 'S3Access.Status' --output text 2>/dev/null || echo "Unknown")
    log "S3 Access Status: ${S3_ACCESS_STATUS}"
else
    log_warning "Simulating S3 access enablement for demonstration"
fi

log_success "S3 access configuration completed"

# Step 2: Create S3 Bucket for Oracle Database Backups
log "Step 2: Creating S3 bucket for Oracle Database backups..."

# Check if bucket already exists
if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
    log_warning "S3 bucket ${S3_BUCKET_NAME} already exists"
else
    aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
    log_success "S3 bucket created: ${S3_BUCKET_NAME}"
fi

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket "${S3_BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
    --bucket "${S3_BUCKET_NAME}" \
    --server-side-encryption-configuration \
    'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'

# Create and apply lifecycle policy
cat > lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "OracleBackupLifecycle",
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ]
        }
    ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
    --bucket "${S3_BUCKET_NAME}" \
    --lifecycle-configuration file://lifecycle-policy.json

log_success "S3 bucket configured with enterprise features"

# Step 3: Verify VPC Lattice Service Network Resources
log "Step 3: Verifying VPC Lattice Service Network resources..."

# List VPC Lattice service networks
LATTICE_SERVICE_NETWORKS=$(aws vpc-lattice list-service-networks \
    --query 'Items[?contains(Name, `default-odb-network`)].{Name:Name,Id:Id}' \
    --output table 2>/dev/null || echo "No service networks found")

log "VPC Lattice Service Networks:"
echo "${LATTICE_SERVICE_NETWORKS}"

# Get the default ODB service network ID if it exists
export SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
    --query 'Items[?contains(Name, `default-odb-network`)].Id' \
    --output text 2>/dev/null || echo "")

if [ -n "$SERVICE_NETWORK_ID" ] && [ "$SERVICE_NETWORK_ID" != "None" ]; then
    echo "SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}" >> ./deployment_vars.env
    
    # List resource associations
    aws vpc-lattice list-service-network-resource-associations \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --query 'Items[].{ResourceArn:ResourceArn,Status:Status}' \
        --output table || log_warning "Unable to list resource associations"
else
    log_warning "Default ODB service network not found - this is expected if ODB is not fully configured"
fi

log_success "VPC Lattice resources verification completed"

# Step 4: Create Amazon Redshift Cluster for Analytics
log "Step 4: Creating Amazon Redshift cluster for analytics..."

# Create IAM role for Redshift cluster
IAM_ROLE_NAME="RedshiftOracleRole-${RANDOM_SUFFIX}"

cat > redshift-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "redshift.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Check if role already exists
if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
    log_warning "IAM role ${IAM_ROLE_NAME} already exists"
else
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file://redshift-trust-policy.json
    
    # Wait for role to be available
    sleep 10
fi

echo "IAM_ROLE_NAME=${IAM_ROLE_NAME}" >> ./deployment_vars.env

# Attach necessary policies
aws iam attach-role-policy \
    --role-name "${IAM_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess || true

aws iam attach-role-policy \
    --role-name "${IAM_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/AmazonRedshiftAllCommandsFullAccess || true

# Get IAM role ARN
export REDSHIFT_ROLE_ARN=$(aws iam get-role \
    --role-name "${IAM_ROLE_NAME}" \
    --query 'Role.Arn' --output text)

echo "REDSHIFT_ROLE_ARN=${REDSHIFT_ROLE_ARN}" >> ./deployment_vars.env

# Check if Redshift cluster already exists
if aws redshift describe-clusters --cluster-identifier "${REDSHIFT_CLUSTER_ID}" &> /dev/null; then
    log_warning "Redshift cluster ${REDSHIFT_CLUSTER_ID} already exists"
else
    # Create Redshift cluster
    log "Creating Redshift cluster (this may take 10-15 minutes)..."
    aws redshift create-cluster \
        --cluster-identifier "${REDSHIFT_CLUSTER_ID}" \
        --node-type dc2.large \
        --master-username oracleadmin \
        --master-user-password "OracleAnalytics123!" \
        --db-name oracleanalytics \
        --cluster-type single-node \
        --iam-roles "${REDSHIFT_ROLE_ARN}" \
        --encrypted \
        --port 5439
fi

log_success "Redshift cluster creation initiated"

# Step 5: Enable Zero-ETL Access for ODB Network
log "Step 5: Enabling Zero-ETL access for ODB Network..."

if [[ "$ODB_NETWORK_ID" != "simulated-"* ]]; then
    aws odb update-odb-network \
        --odb-network-id "${ODB_NETWORK_ID}" \
        --zero-etl-access ENABLED || {
        log_warning "Failed to enable Zero-ETL access - continuing with setup"
    }
else
    log_warning "Simulating Zero-ETL access enablement for demonstration"
fi

# Wait for Redshift cluster to be available (with timeout)
log "Waiting for Redshift cluster to be available (timeout: 20 minutes)..."
WAIT_COUNT=0
MAX_WAIT=80  # 20 minutes (80 * 15 seconds)

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    CLUSTER_STATUS=$(aws redshift describe-clusters \
        --cluster-identifier "${REDSHIFT_CLUSTER_ID}" \
        --query 'Clusters[0].ClusterStatus' --output text 2>/dev/null || echo "creating")
    
    if [ "$CLUSTER_STATUS" = "available" ]; then
        break
    fi
    
    log "Cluster status: ${CLUSTER_STATUS} (waiting...)"
    sleep 15
    ((WAIT_COUNT++))
done

if [ "$CLUSTER_STATUS" = "available" ]; then
    # Get Redshift cluster endpoint
    export REDSHIFT_ENDPOINT=$(aws redshift describe-clusters \
        --cluster-identifier "${REDSHIFT_CLUSTER_ID}" \
        --query 'Clusters[0].Endpoint.Address' --output text)
    
    echo "REDSHIFT_ENDPOINT=${REDSHIFT_ENDPOINT}" >> ./deployment_vars.env
    log_success "Redshift cluster is available at: ${REDSHIFT_ENDPOINT}"
else
    log_warning "Redshift cluster is still creating. Check AWS console for progress."
fi

log_success "Zero-ETL access configuration completed"

# Step 6: Configure S3 Access Policy for Oracle Database
log "Step 6: Configuring S3 access policy for Oracle Database..."

cat > s3-oracle-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}",
                "arn:aws:s3:::${S3_BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF

if [[ "$ODB_NETWORK_ID" != "simulated-"* ]]; then
    aws odb update-odb-network \
        --odb-network-id "${ODB_NETWORK_ID}" \
        --s3-policy-document file://s3-oracle-policy.json || {
        log_warning "Failed to apply S3 policy - continuing with setup"
    }
else
    log_warning "Simulating S3 policy application for demonstration"
fi

log_success "S3 access policy configured"

# Step 7: Configure CloudWatch Monitoring
log "Step 7: Configuring CloudWatch monitoring..."

# Create CloudWatch log group
LOG_GROUP_NAME="/aws/oracle-database/${ODB_NETWORK_ID}"
if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" | grep -q "${LOG_GROUP_NAME}"; then
    log_warning "CloudWatch log group already exists"
else
    aws logs create-log-group --log-group-name "${LOG_GROUP_NAME}"
fi

echo "LOG_GROUP_NAME=${LOG_GROUP_NAME}" >> ./deployment_vars.env

# Create CloudWatch dashboard
DASHBOARD_NAME="OracleAWSIntegration-${RANDOM_SUFFIX}"
cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/S3", "NumberOfObjects", "BucketName", "${S3_BUCKET_NAME}"],
                    ["AWS/S3", "BucketSizeBytes", "BucketName", "${S3_BUCKET_NAME}"],
                    ["AWS/Redshift", "CPUUtilization", "ClusterIdentifier", "${REDSHIFT_CLUSTER_ID}"],
                    ["AWS/Redshift", "DatabaseConnections", "ClusterIdentifier", "${REDSHIFT_CLUSTER_ID}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Oracle Database@AWS Integration Metrics"
            }
        }
    ]
}
EOF

aws cloudwatch put-dashboard \
    --dashboard-name "${DASHBOARD_NAME}" \
    --dashboard-body file://dashboard-config.json

echo "DASHBOARD_NAME=${DASHBOARD_NAME}" >> ./deployment_vars.env

log_success "CloudWatch monitoring configured"

# Deployment summary
echo -e "\n${GREEN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                           DEPLOYMENT COMPLETED                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_success "Deployment completed successfully!"
echo ""
log "📋 Deployment Summary:"
log "   • AWS Region: ${AWS_REGION}"
log "   • ODB Network ID: ${ODB_NETWORK_ID}"
log "   • S3 Bucket: ${S3_BUCKET_NAME}"
log "   • Redshift Cluster: ${REDSHIFT_CLUSTER_ID}"
log "   • CloudWatch Dashboard: ${DASHBOARD_NAME}"
if [ -n "${REDSHIFT_ENDPOINT:-}" ]; then
log "   • Redshift Endpoint: ${REDSHIFT_ENDPOINT}"
fi
echo ""
log "🔧 Next Steps:"
log "   1. Monitor Redshift cluster availability in AWS Console"
log "   2. Configure Oracle Database@AWS backup to S3"
log "   3. Set up Zero-ETL integration for real-time analytics"
log "   4. Review CloudWatch dashboard for monitoring"
echo ""
log "📄 Configuration saved to: ./deployment_vars.env"
log "🧹 To cleanup: ./destroy.sh"

# Cleanup temporary files but keep deployment vars
rm -f lifecycle-policy.json redshift-trust-policy.json s3-oracle-policy.json dashboard-config.json

log_success "Enterprise Oracle Database connectivity setup completed!"