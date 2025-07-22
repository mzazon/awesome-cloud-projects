#!/bin/bash

# Deploy script for Serverless Analytics with Athena Federated Query
# This script implements the complete infrastructure deployment for the recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
PROGRESS_FILE="${SCRIPT_DIR}/.deploy_progress"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "${LOG_FILE}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "${LOG_FILE}"
}

# Progress tracking
save_progress() {
    echo "$1" > "${PROGRESS_FILE}"
}

get_progress() {
    if [[ -f "${PROGRESS_FILE}" ]]; then
        cat "${PROGRESS_FILE}"
    else
        echo "0"
    fi
}

# Cleanup function for script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Check ${LOG_FILE} for details."
        info "To resume from the last successful step, run this script again."
        info "To start fresh, delete ${PROGRESS_FILE} and run again."
    fi
}

trap cleanup_on_exit EXIT

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
    fi
    
    # Check required AWS permissions
    log "Verifying AWS permissions..."
    aws sts get-caller-identity > /dev/null || error "Cannot verify AWS identity"
    
    # Check if jq is available (helpful for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some output formatting may be limited."
    fi
    
    log "Prerequisites check completed successfully"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        warn "AWS region not configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "Using AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "Using AWS Region: ${AWS_REGION}"
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || openssl rand -hex 3)
    
    export SPILL_BUCKET_NAME="athena-federated-spill-${RANDOM_SUFFIX}"
    export RESULTS_BUCKET_NAME="athena-federated-results-${RANDOM_SUFFIX}"
    export VPC_NAME="athena-federated-vpc"
    export DB_INSTANCE_ID="athena-federated-mysql-${RANDOM_SUFFIX}"
    export DB_NAME="analytics_db"
    export TABLE_NAME="sample_orders"
    export DYNAMO_TABLE_NAME="Orders-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export SPILL_BUCKET_NAME=${SPILL_BUCKET_NAME}
export RESULTS_BUCKET_NAME=${RESULTS_BUCKET_NAME}
export VPC_NAME=${VPC_NAME}
export DB_INSTANCE_ID=${DB_INSTANCE_ID}
export DB_NAME=${DB_NAME}
export TABLE_NAME=${TABLE_NAME}
export DYNAMO_TABLE_NAME=${DYNAMO_TABLE_NAME}
EOF
    
    log "Environment variables initialized and saved to .env file"
}

# Create S3 buckets
create_s3_buckets() {
    if [[ $(get_progress) -ge 1 ]]; then
        log "S3 buckets already created, skipping..."
        return 0
    fi
    
    log "Creating S3 buckets..."
    
    # Create spill bucket
    if aws s3api head-bucket --bucket "${SPILL_BUCKET_NAME}" 2>/dev/null; then
        log "Spill bucket ${SPILL_BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${SPILL_BUCKET_NAME}" --region "${AWS_REGION}"
        log "Created spill bucket: ${SPILL_BUCKET_NAME}"
    fi
    
    # Create results bucket
    if aws s3api head-bucket --bucket "${RESULTS_BUCKET_NAME}" 2>/dev/null; then
        log "Results bucket ${RESULTS_BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${RESULTS_BUCKET_NAME}" --region "${AWS_REGION}"
        log "Created results bucket: ${RESULTS_BUCKET_NAME}"
    fi
    
    save_progress "1"
    log "S3 buckets created successfully"
}

# Create VPC and networking resources
create_vpc_resources() {
    if [[ $(get_progress) -ge 2 ]]; then
        log "VPC resources already created, skipping..."
        return 0
    fi
    
    log "Creating VPC and networking resources..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}}]" \
        --query 'Vpc.VpcId' --output text)
    
    log "Created VPC: ${VPC_ID}"
    
    # Create subnets
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --query 'Subnet.SubnetId' --output text)
    
    SUBNET_ID_2=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --query 'Subnet.SubnetId' --output text)
    
    log "Created subnets: ${SUBNET_ID}, ${SUBNET_ID_2}"
    
    # Create security group
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name athena-federated-sg \
        --description "Security group for Athena federated query" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' --output text)
    
    # Allow MySQL access within security group
    aws ec2 authorize-security-group-ingress \
        --group-id "${SECURITY_GROUP_ID}" \
        --protocol tcp \
        --port 3306 \
        --source-group "${SECURITY_GROUP_ID}"
    
    log "Created security group: ${SECURITY_GROUP_ID}"
    
    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name athena-federated-subnet-group \
        --db-subnet-group-description "Subnet group for Athena federated query" \
        --subnet-ids "${SUBNET_ID}" "${SUBNET_ID_2}"
    
    log "Created DB subnet group"
    
    # Save VPC resources to .env file
    cat >> "${SCRIPT_DIR}/.env" << EOF
export VPC_ID=${VPC_ID}
export SUBNET_ID=${SUBNET_ID}
export SUBNET_ID_2=${SUBNET_ID_2}
export SECURITY_GROUP_ID=${SECURITY_GROUP_ID}
EOF
    
    save_progress "2"
    log "VPC resources created successfully"
}

# Create RDS MySQL instance
create_rds_instance() {
    if [[ $(get_progress) -ge 3 ]]; then
        log "RDS instance already created, skipping..."
        return 0
    fi
    
    log "Creating RDS MySQL instance..."
    
    # Source the environment to get VPC resources
    source "${SCRIPT_DIR}/.env"
    
    # Create RDS instance
    aws rds create-db-instance \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username admin \
        --master-user-password "TempPassword123!" \
        --allocated-storage 20 \
        --db-name "${DB_NAME}" \
        --vpc-security-group-ids "${SECURITY_GROUP_ID}" \
        --db-subnet-group-name athena-federated-subnet-group \
        --no-publicly-accessible
    
    log "RDS instance creation initiated, waiting for availability..."
    
    # Wait for RDS instance to be available
    aws rds wait db-instance-available \
        --db-instance-identifier "${DB_INSTANCE_ID}"
    
    # Get RDS endpoint
    RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query 'DBInstances[0].Endpoint.Address' --output text)
    
    log "RDS MySQL instance created successfully: ${RDS_ENDPOINT}"
    
    # Save RDS endpoint to .env file
    echo "export RDS_ENDPOINT=${RDS_ENDPOINT}" >> "${SCRIPT_DIR}/.env"
    
    save_progress "3"
}

# Create sample data in RDS
create_rds_sample_data() {
    if [[ $(get_progress) -ge 4 ]]; then
        log "RDS sample data already created, skipping..."
        return 0
    fi
    
    log "Creating sample data in RDS..."
    
    # Source the environment
    source "${SCRIPT_DIR}/.env"
    
    # Create a temporary script for database initialization
    cat > "${SCRIPT_DIR}/init_db.sql" << EOF
CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
    order_id INT PRIMARY KEY,
    customer_id INT,
    product_name VARCHAR(255),
    quantity INT,
    price DECIMAL(10,2),
    order_date DATE
);

INSERT IGNORE INTO ${TABLE_NAME} VALUES
    (1, 101, 'Laptop', 1, 999.99, '2024-01-15'),
    (2, 102, 'Mouse', 2, 29.99, '2024-01-16'),
    (3, 103, 'Keyboard', 1, 79.99, '2024-01-17'),
    (4, 101, 'Monitor', 1, 299.99, '2024-01-18'),
    (5, 104, 'Headphones', 3, 149.99, '2024-01-19');
EOF
    
    # Install MySQL client using EC2 instance
    log "Setting up temporary EC2 instance for database initialization..."
    
    # Create a simple user data script
    cat > "${SCRIPT_DIR}/user_data.sh" << 'EOF'
#!/bin/bash
yum update -y
yum install -y mysql
EOF
    
    # Launch temporary EC2 instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ami-0c02fb55956c7d316 \
        --instance-type t3.micro \
        --security-group-ids "${SECURITY_GROUP_ID}" \
        --subnet-id "${SUBNET_ID}" \
        --user-data file://"${SCRIPT_DIR}/user_data.sh" \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=athena-federated-temp}]' \
        --query 'Instances[0].InstanceId' --output text)
    
    log "Temporary EC2 instance launched: ${INSTANCE_ID}"
    
    # Wait for instance to be running
    aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
    
    # Wait additional time for user data to complete
    log "Waiting for database client installation..."
    sleep 120
    
    # Connect to database and create sample data
    aws ssm send-command \
        --instance-ids "${INSTANCE_ID}" \
        --document-name "AWS-RunShellScript" \
        --parameters commands="mysql -h ${RDS_ENDPOINT} -u admin -p'TempPassword123!' ${DB_NAME} < /tmp/init_db.sql" \
        --comment "Initialize database with sample data" 2>/dev/null || true
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/user_data.sh"
    
    # Terminate temporary instance
    aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
    
    log "Database initialization completed and temporary instance terminated"
    
    # Save instance ID to .env for cleanup
    echo "export TEMP_INSTANCE_ID=${INSTANCE_ID}" >> "${SCRIPT_DIR}/.env"
    
    save_progress "4"
}

# Create DynamoDB table
create_dynamodb_table() {
    if [[ $(get_progress) -ge 5 ]]; then
        log "DynamoDB table already created, skipping..."
        return 0
    fi
    
    log "Creating DynamoDB table..."
    
    # Create DynamoDB table
    aws dynamodb create-table \
        --table-name "${DYNAMO_TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=order_id,AttributeType=S \
        --key-schema \
            AttributeName=order_id,KeyType=HASH \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5
    
    # Wait for table to be active
    aws dynamodb wait table-exists --table-name "${DYNAMO_TABLE_NAME}"
    
    log "DynamoDB table created, adding sample data..."
    
    # Add sample data
    aws dynamodb put-item \
        --table-name "${DYNAMO_TABLE_NAME}" \
        --item '{"order_id": {"S": "1001"}, "status": {"S": "shipped"}, "tracking_number": {"S": "TRK123456"}, "carrier": {"S": "FedEx"}}'
    
    aws dynamodb put-item \
        --table-name "${DYNAMO_TABLE_NAME}" \
        --item '{"order_id": {"S": "1002"}, "status": {"S": "processing"}, "tracking_number": {"S": "TRK789012"}, "carrier": {"S": "UPS"}}'
    
    aws dynamodb put-item \
        --table-name "${DYNAMO_TABLE_NAME}" \
        --item '{"order_id": {"S": "1003"}, "status": {"S": "delivered"}, "tracking_number": {"S": "TRK345678"}, "carrier": {"S": "USPS"}}'
    
    log "DynamoDB table created with sample data"
    
    save_progress "5"
}

# Deploy connectors
deploy_connectors() {
    if [[ $(get_progress) -ge 6 ]]; then
        log "Connectors already deployed, skipping..."
        return 0
    fi
    
    log "Deploying Athena data source connectors..."
    
    # Source the environment
    source "${SCRIPT_DIR}/.env"
    
    # Deploy MySQL connector
    log "Deploying MySQL connector..."
    aws serverlessrepo create-cloud-formation-stack \
        --application-id arn:aws:serverlessrepo:us-east-1:292517598671:applications/AthenaMySQLConnector \
        --stack-name athena-mysql-connector \
        --parameters \
            ParameterKey=LambdaFunctionName,ParameterValue=athena-mysql-connector \
            ParameterKey=DefaultConnectionString,ParameterValue="mysql://jdbc:mysql://${RDS_ENDPOINT}:3306/${DB_NAME}?user=admin&password=TempPassword123!" \
            ParameterKey=SpillBucket,ParameterValue="${SPILL_BUCKET_NAME}" \
            ParameterKey=LambdaMemory,ParameterValue=3008 \
            ParameterKey=LambdaTimeout,ParameterValue=900 \
            ParameterKey=SecurityGroupIds,ParameterValue="${SECURITY_GROUP_ID}" \
            ParameterKey=SubnetIds,ParameterValue="${SUBNET_ID},${SUBNET_ID_2}"
    
    # Deploy DynamoDB connector
    log "Deploying DynamoDB connector..."
    aws serverlessrepo create-cloud-formation-stack \
        --application-id arn:aws:serverlessrepo:us-east-1:292517598671:applications/AthenaDynamoDBConnector \
        --stack-name athena-dynamodb-connector \
        --parameters \
            ParameterKey=LambdaFunctionName,ParameterValue=athena-dynamodb-connector \
            ParameterKey=SpillBucket,ParameterValue="${SPILL_BUCKET_NAME}" \
            ParameterKey=LambdaMemory,ParameterValue=3008 \
            ParameterKey=LambdaTimeout,ParameterValue=900
    
    # Wait for both stacks to complete
    log "Waiting for connector stacks to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name athena-mysql-connector
    
    aws cloudformation wait stack-create-complete \
        --stack-name athena-dynamodb-connector
    
    log "Connectors deployed successfully"
    
    save_progress "6"
}

# Create data catalogs
create_data_catalogs() {
    if [[ $(get_progress) -ge 7 ]]; then
        log "Data catalogs already created, skipping..."
        return 0
    fi
    
    log "Creating Athena data catalogs..."
    
    # Create MySQL data catalog
    aws athena create-data-catalog \
        --name "mysql_catalog" \
        --description "MySQL data source for federated queries" \
        --type LAMBDA \
        --parameters "function=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:athena-mysql-connector"
    
    # Create DynamoDB data catalog
    aws athena create-data-catalog \
        --name "dynamodb_catalog" \
        --description "DynamoDB data source for federated queries" \
        --type LAMBDA \
        --parameters "function=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:athena-dynamodb-connector"
    
    log "Data catalogs created successfully"
    
    save_progress "7"
}

# Create Athena workgroup
create_athena_workgroup() {
    if [[ $(get_progress) -ge 8 ]]; then
        log "Athena workgroup already created, skipping..."
        return 0
    fi
    
    log "Creating Athena workgroup..."
    
    # Create workgroup
    aws athena create-work-group \
        --name "federated-analytics" \
        --description "Workgroup for federated query analytics" \
        --configuration "ResultConfiguration={OutputLocation=s3://${RESULTS_BUCKET_NAME}/},EnforceWorkGroupConfiguration=true"
    
    log "Athena workgroup created successfully"
    
    save_progress "8"
}

# Test federated queries
test_federated_queries() {
    if [[ $(get_progress) -ge 9 ]]; then
        log "Federated queries already tested, skipping..."
        return 0
    fi
    
    log "Testing federated queries..."
    
    # Test MySQL connection
    log "Testing MySQL connection..."
    TEST_MYSQL_QUERY=$(aws athena start-query-execution \
        --query-string "SHOW TABLES IN mysql_catalog.${DB_NAME}" \
        --work-group "federated-analytics" \
        --query 'QueryExecutionId' --output text)
    
    aws athena wait query-execution-completed \
        --query-execution-id "${TEST_MYSQL_QUERY}"
    
    MYSQL_STATUS=$(aws athena get-query-execution \
        --query-execution-id "${TEST_MYSQL_QUERY}" \
        --query 'QueryExecution.Status.State' --output text)
    
    if [[ "${MYSQL_STATUS}" == "SUCCEEDED" ]]; then
        log "MySQL connection test successful"
    else
        warn "MySQL connection test failed, status: ${MYSQL_STATUS}"
    fi
    
    # Test DynamoDB connection
    log "Testing DynamoDB connection..."
    TEST_DDB_QUERY=$(aws athena start-query-execution \
        --query-string "SELECT * FROM dynamodb_catalog.default.${DYNAMO_TABLE_NAME} LIMIT 5" \
        --work-group "federated-analytics" \
        --query 'QueryExecutionId' --output text)
    
    aws athena wait query-execution-completed \
        --query-execution-id "${TEST_DDB_QUERY}"
    
    DDB_STATUS=$(aws athena get-query-execution \
        --query-execution-id "${TEST_DDB_QUERY}" \
        --query 'QueryExecution.Status.State' --output text)
    
    if [[ "${DDB_STATUS}" == "SUCCEEDED" ]]; then
        log "DynamoDB connection test successful"
    else
        warn "DynamoDB connection test failed, status: ${DDB_STATUS}"
    fi
    
    save_progress "9"
}

# Main deployment function
main() {
    log "Starting Athena Federated Query deployment..."
    log "Log file: ${LOG_FILE}"
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    initialize_environment
    create_s3_buckets
    create_vpc_resources
    create_rds_instance
    create_rds_sample_data
    create_dynamodb_table
    deploy_connectors
    create_data_catalogs
    create_athena_workgroup
    test_federated_queries
    
    # Final success message
    log "🎉 Deployment completed successfully!"
    log ""
    log "Summary of deployed resources:"
    log "- S3 Buckets: ${SPILL_BUCKET_NAME}, ${RESULTS_BUCKET_NAME}"
    log "- RDS MySQL Instance: ${DB_INSTANCE_ID}"
    log "- DynamoDB Table: ${DYNAMO_TABLE_NAME}"
    log "- Lambda Connectors: athena-mysql-connector, athena-dynamodb-connector"
    log "- Athena Workgroup: federated-analytics"
    log "- Data Catalogs: mysql_catalog, dynamodb_catalog"
    log ""
    log "Next steps:"
    log "1. Open the AWS Athena console"
    log "2. Select the 'federated-analytics' workgroup"
    log "3. Try running federated queries across your data sources"
    log ""
    log "Example federated query:"
    log "SELECT * FROM mysql_catalog.${DB_NAME}.${TABLE_NAME} LIMIT 10;"
    log ""
    log "To clean up resources, run: ./destroy.sh"
    
    # Clean up progress file
    rm -f "${PROGRESS_FILE}"
    
    log "Deployment log saved to: ${LOG_FILE}"
}

# Check if running in dry-run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    log "DRY RUN MODE - No resources will be created"
    log "This would deploy the following components:"
    log "- S3 buckets for spill and results"
    log "- VPC with subnets and security groups"
    log "- RDS MySQL instance with sample data"
    log "- DynamoDB table with sample data"
    log "- Athena Lambda connectors"
    log "- Athena data catalogs and workgroup"
    log "Use './deploy.sh' to perform actual deployment"
    exit 0
fi

# Run main function
main "$@"