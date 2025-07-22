#!/bin/bash

set -euo pipefail

# Multi-AZ Database Deployments for High Availability - Deployment Script
# This script deploys a complete Aurora Multi-AZ DB cluster with high availability configuration

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling function
handle_error() {
    log_error "Script failed at line $1. Exiting..."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║                Multi-AZ Database Deployments for High Availability           ║
║                                                                               ║
║  This script deploys an Aurora Multi-AZ DB cluster with comprehensive        ║
║  high availability configuration, monitoring, and failover capabilities.     ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    exit 1
fi

# Check if psql is available (we'll install it if not)
if ! command -v psql &> /dev/null; then
    log_warning "PostgreSQL client not found. Will attempt to install during deployment."
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Check for required IAM permissions
log "Verifying IAM permissions..."
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
log "Deploying as: $CALLER_ARN"

# Check if RDS enhanced monitoring role exists
RDS_MONITORING_ROLE_EXISTS=$(aws iam get-role --role-name rds-monitoring-role 2>/dev/null || echo "false")
if [[ "$RDS_MONITORING_ROLE_EXISTS" == "false" ]]; then
    log_warning "RDS enhanced monitoring role not found. Creating it..."
    
    # Create RDS enhanced monitoring role
    aws iam create-role \
        --role-name rds-monitoring-role \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "monitoring.rds.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' || true

    aws iam attach-role-policy \
        --role-name rds-monitoring-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole || true
    
    log_success "RDS enhanced monitoring role created"
fi

# Set environment variables
log "Setting up environment variables..."
export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    log_warning "No region configured, defaulting to us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export CLUSTER_NAME="multiaz-cluster-${RANDOM_SUFFIX}"
export DB_SUBNET_GROUP_NAME="multiaz-subnet-group-${RANDOM_SUFFIX}"
export DB_PARAMETER_GROUP_NAME="multiaz-param-group-${RANDOM_SUFFIX}"
export VPC_SECURITY_GROUP_NAME="multiaz-sg-${RANDOM_SUFFIX}"

log "Cluster Name: $CLUSTER_NAME"
log "Region: $AWS_REGION"
log "Account ID: $AWS_ACCOUNT_ID"

# Generate secure database password
log "Generating secure database password..."
DB_PASSWORD=$(aws secretsmanager get-random-password \
    --password-length 20 --exclude-characters '"@/\' \
    --require-each-included-type \
    --output text --query RandomPassword)

# Store password securely in Systems Manager Parameter Store
aws ssm put-parameter \
    --name "/rds/multiaz/${CLUSTER_NAME}/password" \
    --value "${DB_PASSWORD}" \
    --type "SecureString" \
    --description "Master password for Multi-AZ RDS cluster" \
    --overwrite

log_success "Environment variables set and password stored securely"

# Check for existing SNS topic for alarms
SNS_TOPIC_ARN=""
if aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:rds-alerts" &>/dev/null; then
    SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:rds-alerts"
    log "Using existing SNS topic: $SNS_TOPIC_ARN"
else
    log "Creating SNS topic for RDS alerts..."
    SNS_TOPIC_ARN=$(aws sns create-topic --name rds-alerts --query TopicArn --output text)
    log_success "SNS topic created: $SNS_TOPIC_ARN"
fi

# Step 1: Create VPC Security Group for Database Access
log "Step 1: Creating VPC Security Group for Database Access..."

# Get default VPC ID
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)

if [[ "$VPC_ID" == "None" ]]; then
    log_error "No default VPC found. Please create a VPC or use a custom VPC."
    exit 1
fi

log "Using VPC: $VPC_ID"

# Create security group for RDS cluster
SG_ID=$(aws ec2 create-security-group \
    --group-name "${VPC_SECURITY_GROUP_NAME}" \
    --description "Security group for Multi-AZ RDS cluster" \
    --vpc-id "${VPC_ID}" \
    --query 'GroupId' --output text)

# Get VPC CIDR
VPC_CIDR=$(aws ec2 describe-vpcs \
    --vpc-ids "${VPC_ID}" \
    --query 'Vpcs[0].CidrBlock' --output text)

# Allow PostgreSQL and MySQL access from VPC CIDR
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 5432 \
    --cidr "${VPC_CIDR}"

aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 3306 \
    --cidr "${VPC_CIDR}"

# Add tags to security group
aws ec2 create-tags \
    --resources "${SG_ID}" \
    --tags Key=Name,Value="${VPC_SECURITY_GROUP_NAME}" \
           Key=Purpose,Value="Multi-AZ RDS Cluster"

log_success "Security group created: ${SG_ID}"

# Step 2: Create DB Subnet Group Across Multiple AZs
log "Step 2: Creating DB Subnet Group Across Multiple AZs..."

# Get all subnets in the default VPC across different AZs
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[*].SubnetId' \
    --output text | tr '\t' ' ')

if [[ -z "$SUBNET_IDS" ]]; then
    log_error "No subnets found in VPC $VPC_ID"
    exit 1
fi

log "Using subnets: $SUBNET_IDS"

# Create DB subnet group
aws rds create-db-subnet-group \
    --db-subnet-group-name "${DB_SUBNET_GROUP_NAME}" \
    --db-subnet-group-description "Subnet group for Multi-AZ RDS cluster" \
    --subnet-ids ${SUBNET_IDS} \
    --tags Key=Name,Value="${DB_SUBNET_GROUP_NAME}" \
           Key=Purpose,Value="Multi-AZ RDS Cluster"

log_success "DB subnet group created: ${DB_SUBNET_GROUP_NAME}"

# Step 3: Create DB Cluster Parameter Group with Optimized Settings
log "Step 3: Creating DB Cluster Parameter Group with Optimized Settings..."

# Create parameter group for PostgreSQL Multi-AZ cluster
aws rds create-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "${DB_PARAMETER_GROUP_NAME}" \
    --db-parameter-group-family "aurora-postgresql15" \
    --description "Parameter group for Multi-AZ PostgreSQL cluster" \
    --tags Key=Name,Value="${DB_PARAMETER_GROUP_NAME}" \
           Key=Purpose,Value="Multi-AZ RDS Cluster"

# Set optimized parameters for high availability
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name "${DB_PARAMETER_GROUP_NAME}" \
    --parameters "ParameterName=log_statement,ParameterValue=all,ApplyMethod=pending-reboot" \
                 "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=pending-reboot" \
                 "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"

log_success "DB cluster parameter group created: ${DB_PARAMETER_GROUP_NAME}"

# Step 4: Create Multi-AZ RDS Cluster
log "Step 4: Creating Multi-AZ RDS Cluster with High Availability Configuration..."

# Create Multi-AZ DB cluster
aws rds create-db-cluster \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --engine aurora-postgresql \
    --engine-version "15.4" \
    --master-username dbadmin \
    --master-user-password "${DB_PASSWORD}" \
    --vpc-security-group-ids "${SG_ID}" \
    --db-subnet-group-name "${DB_SUBNET_GROUP_NAME}" \
    --db-cluster-parameter-group-name "${DB_PARAMETER_GROUP_NAME}" \
    --backup-retention-period 14 \
    --preferred-backup-window "03:00-04:00" \
    --preferred-maintenance-window "sun:04:00-sun:05:00" \
    --storage-encrypted \
    --enable-cloudwatch-logs-exports postgresql \
    --deletion-protection \
    --tags Key=Name,Value="${CLUSTER_NAME}" \
           Key=Purpose,Value="Multi-AZ High Availability" \
           Key=Environment,Value="Production"

# Wait for cluster to be available
log "Waiting for cluster to be available (this may take 10-15 minutes)..."
aws rds wait db-cluster-available --db-cluster-identifier "${CLUSTER_NAME}"

log_success "Multi-AZ DB cluster created: ${CLUSTER_NAME}"

# Step 5: Create Writer DB Instance
log "Step 5: Creating Writer DB Instance for the Cluster..."

aws rds create-db-instance \
    --db-instance-identifier "${CLUSTER_NAME}-writer" \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --engine aurora-postgresql \
    --db-instance-class db.r6g.large \
    --monitoring-interval 60 \
    --monitoring-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/rds-monitoring-role" \
    --performance-insights-retention-period 7 \
    --enable-performance-insights \
    --tags Key=Name,Value="${CLUSTER_NAME}-writer" \
           Key=Role,Value="Writer" \
           Key=Purpose,Value="Multi-AZ High Availability"

# Wait for writer instance to be available
log "Waiting for writer instance to be available (this may take 5-10 minutes)..."
aws rds wait db-instance-available --db-instance-identifier "${CLUSTER_NAME}-writer"

log_success "Writer DB instance created: ${CLUSTER_NAME}-writer"

# Step 6: Create Reader DB Instances
log "Step 6: Creating Reader DB Instances for High Availability..."

# Create first reader instance
aws rds create-db-instance \
    --db-instance-identifier "${CLUSTER_NAME}-reader-1" \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --engine aurora-postgresql \
    --db-instance-class db.r6g.large \
    --monitoring-interval 60 \
    --monitoring-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/rds-monitoring-role" \
    --performance-insights-retention-period 7 \
    --enable-performance-insights \
    --tags Key=Name,Value="${CLUSTER_NAME}-reader-1" \
           Key=Role,Value="Reader" \
           Key=Purpose,Value="Multi-AZ High Availability" &

# Create second reader instance
aws rds create-db-instance \
    --db-instance-identifier "${CLUSTER_NAME}-reader-2" \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --engine aurora-postgresql \
    --db-instance-class db.r6g.large \
    --monitoring-interval 60 \
    --monitoring-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/rds-monitoring-role" \
    --performance-insights-retention-period 7 \
    --enable-performance-insights \
    --tags Key=Name,Value="${CLUSTER_NAME}-reader-2" \
           Key=Role,Value="Reader" \
           Key=Purpose,Value="Multi-AZ High Availability" &

# Wait for both background processes to complete
wait

# Wait for both reader instances to be available
log "Waiting for reader instances to be available (this may take 5-10 minutes)..."
aws rds wait db-instance-available --db-instance-identifier "${CLUSTER_NAME}-reader-1" &
aws rds wait db-instance-available --db-instance-identifier "${CLUSTER_NAME}-reader-2" &
wait

log_success "Reader DB instances created: ${CLUSTER_NAME}-reader-1, ${CLUSTER_NAME}-reader-2"

# Step 7: Configure CloudWatch Alarms
log "Step 7: Configuring CloudWatch Alarms for Monitoring..."

# Create CloudWatch alarm for database connections
aws cloudwatch put-metric-alarm \
    --alarm-name "${CLUSTER_NAME}-high-connections" \
    --alarm-description "High database connections for Multi-AZ cluster" \
    --metric-name DatabaseConnections \
    --namespace AWS/RDS \
    --statistic Maximum \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "${SNS_TOPIC_ARN}" \
    --dimensions Name=DBClusterIdentifier,Value="${CLUSTER_NAME}" \
    --tags Key=Name,Value="${CLUSTER_NAME}-high-connections" \
           Key=Purpose,Value="Multi-AZ Monitoring"

# Create alarm for CPU utilization
aws cloudwatch put-metric-alarm \
    --alarm-name "${CLUSTER_NAME}-high-cpu" \
    --alarm-description "High CPU utilization for Multi-AZ cluster" \
    --metric-name CPUUtilization \
    --namespace AWS/RDS \
    --statistic Average \
    --period 300 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 3 \
    --alarm-actions "${SNS_TOPIC_ARN}" \
    --dimensions Name=DBClusterIdentifier,Value="${CLUSTER_NAME}" \
    --tags Key=Name,Value="${CLUSTER_NAME}-high-cpu" \
           Key=Purpose,Value="Multi-AZ Monitoring"

log_success "CloudWatch alarms configured for monitoring"

# Step 8: Store Database Connection Information
log "Step 8: Storing Database Connection Information in Parameter Store..."

# Get cluster endpoint information
WRITER_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --query 'DBClusters[0].Endpoint' --output text)

READER_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --query 'DBClusters[0].ReaderEndpoint' --output text)

# Store connection information in Parameter Store
aws ssm put-parameter \
    --name "/rds/multiaz/${CLUSTER_NAME}/writer-endpoint" \
    --value "${WRITER_ENDPOINT}" \
    --type "String" \
    --description "Writer endpoint for Multi-AZ RDS cluster" \
    --overwrite

aws ssm put-parameter \
    --name "/rds/multiaz/${CLUSTER_NAME}/reader-endpoint" \
    --value "${READER_ENDPOINT}" \
    --type "String" \
    --description "Reader endpoint for Multi-AZ RDS cluster" \
    --overwrite

aws ssm put-parameter \
    --name "/rds/multiaz/${CLUSTER_NAME}/username" \
    --value "dbadmin" \
    --type "String" \
    --description "Database username for Multi-AZ RDS cluster" \
    --overwrite

log_success "Database connection information stored in Parameter Store"

# Step 9: Install PostgreSQL Client and Create Test Database
log "Step 9: Creating Test Database and Tables..."

# Install PostgreSQL client if not available
if ! command -v psql &> /dev/null; then
    log "Installing PostgreSQL client..."
    if command -v yum &> /dev/null; then
        sudo yum install -y postgresql15 || sudo yum install -y postgresql
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y postgresql-client
    else
        log_warning "Could not install PostgreSQL client automatically. Please install manually."
    fi
fi

# Connect to database and create test schema
if command -v psql &> /dev/null; then
    log "Creating test database and schema..."
    
    # Create test database
    PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${WRITER_ENDPOINT}" \
        -U dbadmin \
        -d postgres \
        -c "CREATE DATABASE testdb;" || log_warning "Test database may already exist"

    # Create test table with sample data
    PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${WRITER_ENDPOINT}" \
        -U dbadmin \
        -d testdb \
        -c "CREATE TABLE IF NOT EXISTS orders (
            order_id SERIAL PRIMARY KEY,
            customer_id INTEGER NOT NULL,
            order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            total_amount DECIMAL(10,2) NOT NULL,
            status VARCHAR(20) DEFAULT 'pending'
        );"

    # Insert sample data
    PGPASSWORD="${DB_PASSWORD}" psql \
        -h "${WRITER_ENDPOINT}" \
        -U dbadmin \
        -d testdb \
        -c "INSERT INTO orders (customer_id, total_amount) VALUES 
            (1001, 249.99),
            (1002, 89.50),
            (1003, 156.75)
        ON CONFLICT DO NOTHING;"

    log_success "Test database and tables created with sample data"
else
    log_warning "PostgreSQL client not available. Skipping test database creation."
fi

# Step 10: Create Baseline Snapshot
log "Step 10: Creating Baseline Snapshot..."

aws rds create-db-cluster-snapshot \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --db-cluster-snapshot-identifier "${CLUSTER_NAME}-baseline-snapshot" \
    --tags Key=Name,Value="${CLUSTER_NAME}-baseline-snapshot" \
           Key=Purpose,Value="Baseline snapshot" \
           Key=CreatedBy,Value="deployment-script"

log_success "Automated backups configured and baseline snapshot creation initiated"

# Step 11: Create CloudWatch Dashboard
log "Step 11: Creating Performance Monitoring Dashboard..."

aws cloudwatch put-dashboard \
    --dashboard-name "${CLUSTER_NAME}-monitoring" \
    --dashboard-body "{
        \"widgets\": [
            {
                \"type\": \"metric\",
                \"x\": 0,
                \"y\": 0,
                \"width\": 12,
                \"height\": 6,
                \"properties\": {
                    \"metrics\": [
                        [\"AWS/RDS\", \"CPUUtilization\", \"DBClusterIdentifier\", \"${CLUSTER_NAME}\"],
                        [\"AWS/RDS\", \"DatabaseConnections\", \"DBClusterIdentifier\", \"${CLUSTER_NAME}\"],
                        [\"AWS/RDS\", \"FreeableMemory\", \"DBClusterIdentifier\", \"${CLUSTER_NAME}\"]
                    ],
                    \"period\": 300,
                    \"stat\": \"Average\",
                    \"region\": \"${AWS_REGION}\",
                    \"title\": \"Multi-AZ Cluster Performance\",
                    \"view\": \"timeSeries\"
                }
            },
            {
                \"type\": \"metric\",
                \"x\": 0,
                \"y\": 6,
                \"width\": 12,
                \"height\": 6,
                \"properties\": {
                    \"metrics\": [
                        [\"AWS/RDS\", \"ReadLatency\", \"DBClusterIdentifier\", \"${CLUSTER_NAME}\"],
                        [\"AWS/RDS\", \"WriteLatency\", \"DBClusterIdentifier\", \"${CLUSTER_NAME}\"]
                    ],
                    \"period\": 300,
                    \"stat\": \"Average\",
                    \"region\": \"${AWS_REGION}\",
                    \"title\": \"Database Latency Metrics\",
                    \"view\": \"timeSeries\"
                }
            }
        ]
    }"

log_success "Performance monitoring dashboard created"

# Save deployment information
cat > /tmp/multiaz-deployment-info.txt << EOF
Multi-AZ Database Deployment Summary
====================================
Deployment Date: $(date)
Region: ${AWS_REGION}
Account ID: ${AWS_ACCOUNT_ID}

Resources Created:
- Cluster Name: ${CLUSTER_NAME}
- Writer Endpoint: ${WRITER_ENDPOINT}
- Reader Endpoint: ${READER_ENDPOINT}
- Security Group: ${SG_ID}
- Subnet Group: ${DB_SUBNET_GROUP_NAME}
- Parameter Group: ${DB_PARAMETER_GROUP_NAME}
- SNS Topic: ${SNS_TOPIC_ARN}

Parameter Store Paths:
- /rds/multiaz/${CLUSTER_NAME}/password
- /rds/multiaz/${CLUSTER_NAME}/writer-endpoint
- /rds/multiaz/${CLUSTER_NAME}/reader-endpoint
- /rds/multiaz/${CLUSTER_NAME}/username

CloudWatch Resources:
- Dashboard: ${CLUSTER_NAME}-monitoring
- Alarms: ${CLUSTER_NAME}-high-connections, ${CLUSTER_NAME}-high-cpu

Connection Information:
- Username: dbadmin
- Writer Endpoint: ${WRITER_ENDPOINT}
- Reader Endpoint: ${READER_ENDPOINT}
- Database: testdb
- Port: 5432

To retrieve the password:
aws ssm get-parameter --name "/rds/multiaz/${CLUSTER_NAME}/password" --with-decryption --query Parameter.Value --output text

Cleanup Command:
./destroy.sh
EOF

log_success "Deployment information saved to /tmp/multiaz-deployment-info.txt"

# Final deployment summary
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║                         DEPLOYMENT COMPLETED SUCCESSFULLY!                   ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_success "Multi-AZ Database deployment completed successfully!"
echo ""
log "📊 CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${CLUSTER_NAME}-monitoring"
log "🗄️  RDS Console: https://${AWS_REGION}.console.aws.amazon.com/rds/home?region=${AWS_REGION}#database:id=${CLUSTER_NAME}"
log "📋 Deployment Summary: cat /tmp/multiaz-deployment-info.txt"
echo ""
log "🔒 To connect to the database:"
echo "  Writer: psql -h ${WRITER_ENDPOINT} -U dbadmin -d testdb"
echo "  Reader: psql -h ${READER_ENDPOINT} -U dbadmin -d testdb"
echo ""
log "🔑 To get the password:"
echo "  aws ssm get-parameter --name \"/rds/multiaz/${CLUSTER_NAME}/password\" --with-decryption --query Parameter.Value --output text"
echo ""
log_warning "💰 Remember to run ./destroy.sh when you're done to avoid ongoing charges!"

exit 0