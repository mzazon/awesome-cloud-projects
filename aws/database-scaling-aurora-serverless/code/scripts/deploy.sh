#!/bin/bash

# Deploy script for Aurora Serverless Database Scaling Recipe
# This script deploys an Aurora Serverless v2 cluster with auto-scaling capabilities

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please run 'aws configure' or set AWS credentials."
    fi
    
    # Check if jq is available (optional but helpful)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Output parsing may be limited."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export CLUSTER_ID="aurora-serverless-${RANDOM_SUFFIX}"
    export DB_USERNAME="admin"
    export DB_PASSWORD="ServerlessTest123!"
    export SUBNET_GROUP_NAME="aurora-serverless-subnet-group-${RANDOM_SUFFIX}"
    export PARAMETER_GROUP_NAME="aurora-serverless-params-${RANDOM_SUFFIX}"
    
    # Get default VPC and subnets
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        error "No default VPC found. Please create a VPC or specify VPC_ID environment variable."
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[0:2].SubnetId' --output text)
    
    if [ -z "$SUBNET_IDS" ]; then
        error "No subnets found in VPC $VPC_ID"
    fi
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export CLUSTER_ID="$CLUSTER_ID"
export DB_USERNAME="$DB_USERNAME"
export DB_PASSWORD="$DB_PASSWORD"
export SUBNET_GROUP_NAME="$SUBNET_GROUP_NAME"
export PARAMETER_GROUP_NAME="$PARAMETER_GROUP_NAME"
export VPC_ID="$VPC_ID"
export SUBNET_IDS="$SUBNET_IDS"
EOF
    
    log "Environment setup completed"
    log "Cluster ID: $CLUSTER_ID"
    log "Region: $AWS_REGION"
    log "VPC ID: $VPC_ID"
}

# Function to create DB subnet group
create_subnet_group() {
    log "Creating DB subnet group..."
    
    if aws rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP_NAME" &>/dev/null; then
        warning "Subnet group $SUBNET_GROUP_NAME already exists, skipping creation"
        return
    fi
    
    aws rds create-db-subnet-group \
        --db-subnet-group-name "$SUBNET_GROUP_NAME" \
        --db-subnet-group-description "Subnet group for Aurora Serverless" \
        --subnet-ids $SUBNET_IDS
    
    success "DB subnet group created: $SUBNET_GROUP_NAME"
}

# Function to create security group
create_security_group() {
    log "Creating security group..."
    
    # Check if security group already exists
    if SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=aurora-serverless-sg-${RANDOM_SUFFIX}" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null) && [ "$SG_ID" != "None" ]; then
        warning "Security group already exists: $SG_ID"
        export SG_ID
        echo "export SG_ID=\"$SG_ID\"" >> .env
        return
    fi
    
    export SG_ID=$(aws ec2 create-security-group \
        --group-name "aurora-serverless-sg-${RANDOM_SUFFIX}" \
        --description "Security group for Aurora Serverless cluster" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' --output text)
    
    # Add MySQL access rule
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 3306 \
        --cidr 10.0.0.0/8
    
    echo "export SG_ID=\"$SG_ID\"" >> .env
    success "Security group created: $SG_ID"
}

# Function to create parameter group
create_parameter_group() {
    log "Creating DB cluster parameter group..."
    
    if aws rds describe-db-cluster-parameter-groups \
        --db-cluster-parameter-group-name "$PARAMETER_GROUP_NAME" &>/dev/null; then
        warning "Parameter group $PARAMETER_GROUP_NAME already exists, skipping creation"
        return
    fi
    
    aws rds create-db-cluster-parameter-group \
        --db-cluster-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --db-parameter-group-family aurora-mysql8.0 \
        --description "Custom parameters for Aurora Serverless"
    
    success "DB cluster parameter group created: $PARAMETER_GROUP_NAME"
}

# Function to create Aurora cluster
create_aurora_cluster() {
    log "Creating Aurora Serverless v2 cluster..."
    
    if aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER_ID" &>/dev/null; then
        warning "Aurora cluster $CLUSTER_ID already exists, skipping creation"
        return
    fi
    
    aws rds create-db-cluster \
        --db-cluster-identifier "$CLUSTER_ID" \
        --engine aurora-mysql \
        --engine-version 8.0.mysql_aurora.3.02.0 \
        --master-username "$DB_USERNAME" \
        --master-user-password "$DB_PASSWORD" \
        --db-subnet-group-name "$SUBNET_GROUP_NAME" \
        --vpc-security-group-ids "$SG_ID" \
        --db-cluster-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16 \
        --enable-cloudwatch-logs-exports error,general,slowquery \
        --backup-retention-period 7 \
        --deletion-protection
    
    success "Aurora cluster creation initiated: $CLUSTER_ID"
}

# Function to create writer instance
create_writer_instance() {
    log "Creating writer instance..."
    
    WRITER_ID="${CLUSTER_ID}-writer"
    
    if aws rds describe-db-instances --db-instance-identifier "$WRITER_ID" &>/dev/null; then
        warning "Writer instance $WRITER_ID already exists, skipping creation"
        return
    fi
    
    aws rds create-db-instance \
        --db-instance-identifier "$WRITER_ID" \
        --db-cluster-identifier "$CLUSTER_ID" \
        --engine aurora-mysql \
        --db-instance-class db.serverless \
        --promotion-tier 1 \
        --enable-performance-insights \
        --performance-insights-retention-period 7
    
    log "Waiting for cluster to become available..."
    aws rds wait db-cluster-available --db-cluster-identifier "$CLUSTER_ID"
    
    success "Writer instance created and cluster is available: $WRITER_ID"
}

# Function to create read replica
create_read_replica() {
    log "Creating read replica..."
    
    READER_ID="${CLUSTER_ID}-reader"
    
    if aws rds describe-db-instances --db-instance-identifier "$READER_ID" &>/dev/null; then
        warning "Read replica $READER_ID already exists, skipping creation"
        return
    fi
    
    aws rds create-db-instance \
        --db-instance-identifier "$READER_ID" \
        --db-cluster-identifier "$CLUSTER_ID" \
        --engine aurora-mysql \
        --db-instance-class db.serverless \
        --promotion-tier 2 \
        --enable-performance-insights \
        --performance-insights-retention-period 7
    
    log "Waiting for reader instance to become available..."
    aws rds wait db-instance-available --db-instance-identifier "$READER_ID"
    
    success "Read replica created and available: $READER_ID"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    # High ACU utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "Aurora-${CLUSTER_ID}-High-ACU" \
        --alarm-description "Alert when ACU usage is high" \
        --metric-name ServerlessDatabaseCapacity \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 12 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=DBClusterIdentifier,Value="$CLUSTER_ID"
    
    # Low ACU utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "Aurora-${CLUSTER_ID}-Low-ACU" \
        --alarm-description "Alert when ACU usage is consistently low" \
        --metric-name ServerlessDatabaseCapacity \
        --namespace AWS/RDS \
        --statistic Average \
        --period 900 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 4 \
        --dimensions Name=DBClusterIdentifier,Value="$CLUSTER_ID"
    
    success "CloudWatch alarms created for capacity monitoring"
}

# Function to get connection endpoints
get_connection_endpoints() {
    log "Retrieving connection endpoints..."
    
    export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_ID" \
        --query 'DBClusters[0].Endpoint' --output text)
    
    export READER_ENDPOINT=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_ID" \
        --query 'DBClusters[0].ReaderEndpoint' --output text)
    
    echo "export CLUSTER_ENDPOINT=\"$CLUSTER_ENDPOINT\"" >> .env
    echo "export READER_ENDPOINT=\"$READER_ENDPOINT\"" >> .env
    
    success "Connection endpoints retrieved"
    log "Writer Endpoint: $CLUSTER_ENDPOINT"
    log "Reader Endpoint: $READER_ENDPOINT"
}

# Function to create test SQL script
create_test_script() {
    log "Creating test SQL script..."
    
    cat > aurora_connection_test.sql << 'EOF'
-- Create sample database and table for testing
CREATE DATABASE IF NOT EXISTS ecommerce;
USE ecommerce;

CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(10,2),
    category VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_category (category),
    INDEX idx_price (price)
);

-- Insert sample data
INSERT INTO products (name, price, category) VALUES
('Laptop Pro', 1299.99, 'Electronics'),
('Wireless Headphones', 199.99, 'Electronics'),
('Coffee Maker', 89.99, 'Kitchen'),
('Running Shoes', 129.99, 'Sports'),
('Tablet', 399.99, 'Electronics');

-- Sample queries to test scaling
SELECT COUNT(*) FROM products;
SELECT * FROM products WHERE category = 'Electronics';
SELECT AVG(price) FROM products GROUP BY category;
EOF
    
    success "Test SQL script created: aurora_connection_test.sql"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Cluster ID: $CLUSTER_ID"
    echo "Writer Endpoint: $CLUSTER_ENDPOINT"
    echo "Reader Endpoint: $READER_ENDPOINT"
    echo "Database Username: $DB_USERNAME"
    echo "Database Password: $DB_PASSWORD"
    echo "Region: $AWS_REGION"
    echo ""
    echo "Connection Command:"
    echo "mysql -h $CLUSTER_ENDPOINT -u $DB_USERNAME -p"
    echo ""
    echo "Test Script: aurora_connection_test.sql"
    echo ""
    echo "CloudWatch Alarms:"
    echo "- Aurora-${CLUSTER_ID}-High-ACU"
    echo "- Aurora-${CLUSTER_ID}-Low-ACU"
    echo ""
    echo "Environment variables saved to .env file"
    echo "Use ./destroy.sh to clean up resources"
}

# Main deployment function
main() {
    log "Starting Aurora Serverless deployment..."
    
    check_prerequisites
    setup_environment
    create_subnet_group
    create_security_group
    create_parameter_group
    create_aurora_cluster
    create_writer_instance
    create_read_replica
    create_cloudwatch_alarms
    get_connection_endpoints
    create_test_script
    
    success "Aurora Serverless deployment completed successfully!"
    display_summary
}

# Trap errors and cleanup
trap 'error "Deployment failed at line $LINENO"' ERR

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi