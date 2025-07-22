#!/bin/bash

# Database Performance Tuning with Parameter Groups - Deployment Script
# This script deploys the complete infrastructure for PostgreSQL performance tuning
# using RDS Parameter Groups, CloudWatch monitoring, and Performance Insights

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if psql is installed (optional but recommended)
    if ! command -v psql &> /dev/null; then
        warning "psql is not installed. Database operations will be limited."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
    fi
    
    # Check if required AWS region is set
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please configure your default region."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export DB_INSTANCE_ID="perf-tuning-db-${RANDOM_SUFFIX}"
    export PARAMETER_GROUP_NAME="perf-tuning-pg-${RANDOM_SUFFIX}"
    export SUBNET_GROUP_NAME="perf-tuning-subnet-${RANDOM_SUFFIX}"
    export SECURITY_GROUP_NAME="perf-tuning-sg-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="Database-Performance-Tuning-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup script
    cat > /tmp/perf-tuning-env.sh << EOF
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export DB_INSTANCE_ID=${DB_INSTANCE_ID}
export PARAMETER_GROUP_NAME=${PARAMETER_GROUP_NAME}
export SUBNET_GROUP_NAME=${SUBNET_GROUP_NAME}
export SECURITY_GROUP_NAME=${SECURITY_GROUP_NAME}
export DASHBOARD_NAME=${DASHBOARD_NAME}
export RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    log "Random suffix: ${RANDOM_SUFFIX}"
}

# Function to create VPC and networking resources
create_networking() {
    log "Creating VPC and networking resources..."
    
    # Create VPC
    export VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text)
    
    if [[ -z "$VPC_ID" ]]; then
        error "Failed to create VPC"
    fi
    
    # Tag VPC
    aws ec2 create-tags \
        --resources $VPC_ID \
        --tags Key=Name,Value=perf-tuning-vpc Key=Purpose,Value=PerformanceTuning
    
    # Create subnets in different AZs
    export SUBNET_1_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.0.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --query 'Subnet.SubnetId' --output text)
    
    export SUBNET_2_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.0.2.0/24 \
        --availability-zone ${AWS_REGION}b \
        --query 'Subnet.SubnetId' --output text)
    
    if [[ -z "$SUBNET_1_ID" ]] || [[ -z "$SUBNET_2_ID" ]]; then
        error "Failed to create subnets"
    fi
    
    # Tag subnets
    aws ec2 create-tags \
        --resources $SUBNET_1_ID $SUBNET_2_ID \
        --tags Key=Purpose,Value=PerformanceTuning
    
    # Create security group
    export SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name $SECURITY_GROUP_NAME \
        --description "Security group for performance tuning database" \
        --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    
    if [[ -z "$SECURITY_GROUP_ID" ]]; then
        error "Failed to create security group"
    fi
    
    # Allow PostgreSQL access from VPC
    aws ec2 authorize-security-group-ingress \
        --group-id $SECURITY_GROUP_ID \
        --protocol tcp \
        --port 5432 \
        --cidr 10.0.0.0/16
    
    # Save networking info to environment file
    cat >> /tmp/perf-tuning-env.sh << EOF
export VPC_ID=${VPC_ID}
export SUBNET_1_ID=${SUBNET_1_ID}
export SUBNET_2_ID=${SUBNET_2_ID}
export SECURITY_GROUP_ID=${SECURITY_GROUP_ID}
EOF
    
    success "VPC and networking resources created"
    log "VPC ID: ${VPC_ID}"
    log "Security Group ID: ${SECURITY_GROUP_ID}"
}

# Function to create RDS monitoring role (if it doesn't exist)
create_monitoring_role() {
    log "Checking for RDS monitoring role..."
    
    # Check if role exists
    if aws iam get-role --role-name rds-monitoring-role &> /dev/null; then
        log "RDS monitoring role already exists"
        return 0
    fi
    
    log "Creating RDS monitoring role..."
    
    # Create trust policy
    cat > /tmp/rds-monitoring-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "monitoring.rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name rds-monitoring-role \
        --assume-role-policy-document file:///tmp/rds-monitoring-trust-policy.json
    
    # Attach policy
    aws iam attach-role-policy \
        --role-name rds-monitoring-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole
    
    # Wait for role to be available
    sleep 10
    
    success "RDS monitoring role created"
}

# Function to create parameter group
create_parameter_group() {
    log "Creating custom parameter group..."
    
    # Create parameter group
    aws rds create-db-parameter-group \
        --db-parameter-group-name $PARAMETER_GROUP_NAME \
        --db-parameter-group-family postgres15 \
        --description "Performance tuning parameter group for PostgreSQL"
    
    success "Parameter group created: ${PARAMETER_GROUP_NAME}"
}

# Function to optimize database parameters
optimize_parameters() {
    log "Configuring optimized database parameters..."
    
    # Memory-related parameters (conservative approach for t3.medium)
    aws rds modify-db-parameter-group \
        --db-parameter-group-name $PARAMETER_GROUP_NAME \
        --parameters \
            "ParameterName=shared_buffers,ParameterValue=1024MB,ApplyMethod=pending-reboot" \
            "ParameterName=work_mem,ParameterValue=16MB,ApplyMethod=immediate" \
            "ParameterName=maintenance_work_mem,ParameterValue=256MB,ApplyMethod=immediate" \
            "ParameterName=effective_cache_size,ParameterValue=3GB,ApplyMethod=immediate"
    
    # Connection and query optimization parameters
    aws rds modify-db-parameter-group \
        --db-parameter-group-name $PARAMETER_GROUP_NAME \
        --parameters \
            "ParameterName=max_connections,ParameterValue=200,ApplyMethod=pending-reboot" \
            "ParameterName=random_page_cost,ParameterValue=1.1,ApplyMethod=immediate" \
            "ParameterName=seq_page_cost,ParameterValue=1.0,ApplyMethod=immediate" \
            "ParameterName=effective_io_concurrency,ParameterValue=200,ApplyMethod=immediate"
    
    # Query planner and statistics parameters
    aws rds modify-db-parameter-group \
        --db-parameter-group-name $PARAMETER_GROUP_NAME \
        --parameters \
            "ParameterName=default_statistics_target,ParameterValue=500,ApplyMethod=immediate" \
            "ParameterName=constraint_exclusion,ParameterValue=partition,ApplyMethod=immediate" \
            "ParameterName=cpu_tuple_cost,ParameterValue=0.01,ApplyMethod=immediate" \
            "ParameterName=cpu_index_tuple_cost,ParameterValue=0.005,ApplyMethod=immediate"
    
    # Logging and monitoring parameters
    aws rds modify-db-parameter-group \
        --db-parameter-group-name $PARAMETER_GROUP_NAME \
        --parameters \
            "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate" \
            "ParameterName=log_checkpoints,ParameterValue=1,ApplyMethod=immediate" \
            "ParameterName=log_connections,ParameterValue=1,ApplyMethod=immediate" \
            "ParameterName=log_disconnections,ParameterValue=1,ApplyMethod=immediate"
    
    # Checkpoint and WAL optimization
    aws rds modify-db-parameter-group \
        --db-parameter-group-name $PARAMETER_GROUP_NAME \
        --parameters \
            "ParameterName=checkpoint_completion_target,ParameterValue=0.9,ApplyMethod=immediate" \
            "ParameterName=wal_buffers,ParameterValue=16MB,ApplyMethod=pending-reboot" \
            "ParameterName=checkpoint_timeout,ParameterValue=15min,ApplyMethod=immediate"
    
    success "Database parameters optimized"
}

# Function to create RDS instance
create_rds_instance() {
    log "Creating RDS instance..."
    
    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name $SUBNET_GROUP_NAME \
        --db-subnet-group-description "Subnet group for performance tuning" \
        --subnet-ids $SUBNET_1_ID $SUBNET_2_ID
    
    # Create RDS instance with Performance Insights enabled
    aws rds create-db-instance \
        --db-instance-identifier $DB_INSTANCE_ID \
        --db-instance-class db.t3.medium \
        --engine postgres \
        --engine-version 15.4 \
        --master-username dbadmin \
        --master-user-password TuningTest123! \
        --allocated-storage 100 \
        --storage-type gp3 \
        --db-parameter-group-name $PARAMETER_GROUP_NAME \
        --vpc-security-group-ids $SECURITY_GROUP_ID \
        --db-subnet-group-name $SUBNET_GROUP_NAME \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --monitoring-interval 60 \
        --monitoring-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/rds-monitoring-role \
        --backup-retention-period 7 \
        --storage-encrypted \
        --copy-tags-to-snapshot \
        --tags Key=Purpose,Value=PerformanceTuning Key=Recipe,Value=database-performance-tuning
    
    success "RDS instance creation initiated: ${DB_INSTANCE_ID}"
    log "Waiting for database to become available (this may take 5-10 minutes)..."
    
    # Wait for database to become available
    aws rds wait db-instance-available --db-instance-identifier $DB_INSTANCE_ID
    
    # Get database endpoint
    export DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier $DB_INSTANCE_ID \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Save DB endpoint to environment file
    echo "export DB_ENDPOINT=${DB_ENDPOINT}" >> /tmp/perf-tuning-env.sh
    
    # Reboot database to apply pending-reboot parameters
    log "Rebooting database to apply memory-related parameters..."
    aws rds reboot-db-instance --db-instance-identifier $DB_INSTANCE_ID
    aws rds wait db-instance-available --db-instance-identifier $DB_INSTANCE_ID
    
    success "Database available at: ${DB_ENDPOINT}"
}

# Function to create CloudWatch dashboard
create_monitoring_dashboard() {
    log "Creating CloudWatch monitoring dashboard..."
    
    # Create dashboard configuration
    cat > /tmp/dashboard.json << EOF
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
                    ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "$DB_INSTANCE_ID"],
                    [".", "CPUUtilization", ".", "."],
                    [".", "FreeableMemory", ".", "."],
                    [".", "ReadLatency", ".", "."],
                    [".", "WriteLatency", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Database Performance Overview"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", "$DB_INSTANCE_ID"],
                    [".", "WriteIOPS", ".", "."],
                    [".", "ReadThroughput", ".", "."],
                    [".", "WriteThroughput", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Database I/O Performance"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body file:///tmp/dashboard.json
    
    success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
}

# Function to create CloudWatch alarms
create_monitoring_alarms() {
    log "Creating CloudWatch performance alarms..."
    
    # High CPU alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "Database-High-CPU-${RANDOM_SUFFIX}" \
        --alarm-description "High CPU utilization on tuned database" \
        --metric-name CPUUtilization \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID \
        --tags Key=Purpose,Value=PerformanceTuning
    
    # High connections alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "Database-High-Connections-${RANDOM_SUFFIX}" \
        --alarm-description "High connection count on tuned database" \
        --metric-name DatabaseConnections \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 150 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID \
        --tags Key=Purpose,Value=PerformanceTuning
    
    # High read latency alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "Database-High-Read-Latency-${RANDOM_SUFFIX}" \
        --alarm-description "High read latency on tuned database" \
        --metric-name ReadLatency \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 0.1 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 3 \
        --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID \
        --tags Key=Purpose,Value=PerformanceTuning
    
    success "CloudWatch alarms created"
}

# Function to create test data
create_test_data() {
    log "Creating test data for performance validation..."
    
    if ! command -v psql &> /dev/null; then
        warning "psql not available, skipping test data creation"
        return 0
    fi
    
    # Create test data script
    cat > /tmp/create_test_data.sql << 'EOF'
-- Create test tables for performance benchmarking
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    profile_data JSONB
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    order_total DECIMAL(10,2),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20),
    items JSONB
);

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    price DECIMAL(10,2),
    category VARCHAR(50),
    inventory_count INTEGER,
    description TEXT
);

-- Insert sample data
INSERT INTO users (username, email, profile_data)
SELECT 
    'user' || i,
    'user' || i || '@example.com',
    jsonb_build_object('age', 20 + (i % 50), 'preferences', array['electronics', 'books'])
FROM generate_series(1, 10000) i;

INSERT INTO products (name, price, category, inventory_count, description)
SELECT 
    'Product ' || i,
    (random() * 1000)::DECIMAL(10,2),
    CASE (i % 5) 
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Books'
        WHEN 2 THEN 'Clothing'
        WHEN 3 THEN 'Sports'
        ELSE 'Home'
    END,
    (random() * 1000)::INTEGER,
    'Description for product ' || i
FROM generate_series(1, 5000) i;

INSERT INTO orders (user_id, order_total, status, items)
SELECT 
    (random() * 9999 + 1)::INTEGER,
    (random() * 500 + 10)::DECIMAL(10,2),
    CASE (random() * 3)::INTEGER
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'completed'
        ELSE 'cancelled'
    END,
    jsonb_build_array(
        jsonb_build_object('product_id', (random() * 4999 + 1)::INTEGER, 'quantity', (random() * 5 + 1)::INTEGER)
    )
FROM generate_series(1, 25000) i;

-- Create indexes for baseline performance
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_date ON orders(order_date);
CREATE INDEX idx_products_category ON products(category);
EOF
    
    # Load test data
    PGPASSWORD="TuningTest123!" psql -h $DB_ENDPOINT -U dbadmin -d postgres -f /tmp/create_test_data.sql
    
    success "Test data created successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Database Instance ID: ${DB_INSTANCE_ID}"
    echo "Database Endpoint: ${DB_ENDPOINT}"
    echo "Parameter Group: ${PARAMETER_GROUP_NAME}"
    echo "CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "VPC ID: ${VPC_ID}"
    echo "Security Group ID: ${SECURITY_GROUP_ID}"
    echo ""
    echo "Connection Details:"
    echo "Host: ${DB_ENDPOINT}"
    echo "Port: 5432"
    echo "Database: postgres"
    echo "Username: dbadmin"
    echo "Password: TuningTest123!"
    echo ""
    echo "Environment variables saved to: /tmp/perf-tuning-env.sh"
    echo "To clean up resources, run: ./destroy.sh"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Database Performance Tuning deployment..."
    
    check_prerequisites
    setup_environment
    create_networking
    create_monitoring_role
    create_parameter_group
    optimize_parameters
    create_rds_instance
    create_monitoring_dashboard
    create_monitoring_alarms
    create_test_data
    display_summary
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may need manual cleanup."' INT TERM

# Run main function
main "$@"