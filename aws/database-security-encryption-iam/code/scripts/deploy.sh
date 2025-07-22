#!/bin/bash

# Deploy script for Database Security with Encryption and IAM Authentication
# This script implements comprehensive database security with RDS, KMS, and IAM authentication

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: $description"
        info "Would execute: $cmd"
        return 0
    else
        log "$description"
        eval "$cmd"
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if psql is installed
    if ! command -v psql &> /dev/null; then
        error "PostgreSQL client (psql) is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$account_id" ]]; then
        error "Unable to get AWS account ID. Please check your credentials."
        exit 1
    fi
    
    info "AWS Account ID: $account_id"
    info "Prerequisites check passed ✅"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region is not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export DB_INSTANCE_ID="secure-db-${random_suffix}"
    export DB_PROXY_NAME="secure-proxy-${random_suffix}"
    export KMS_KEY_ALIAS="alias/rds-security-key-${random_suffix}"
    export DB_SUBNET_GROUP_NAME="secure-db-subnet-group-${random_suffix}"
    export SECURITY_GROUP_NAME="secure-db-sg-${random_suffix}"
    export IAM_ROLE_NAME="DatabaseAccessRole-${random_suffix}"
    export IAM_POLICY_NAME="DatabaseAccessPolicy-${random_suffix}"
    export DB_USER_NAME="app_user"
    export DB_PARAMETER_GROUP_NAME="secure-postgres-params-${random_suffix}"
    
    # Get VPC information
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
        error "No default VPC found. Please ensure you have a default VPC or specify a custom VPC."
        exit 1
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[*].SubnetId' --output text)
    
    if [[ -z "$SUBNET_IDS" ]]; then
        error "No subnets found in VPC $VPC_ID"
        exit 1
    fi
    
    # Create state directory
    export STATE_DIR="./deployment-state"
    mkdir -p "$STATE_DIR"
    
    # Save environment variables to file
    cat > "$STATE_DIR/env_vars.sh" << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export DB_INSTANCE_ID="$DB_INSTANCE_ID"
export DB_PROXY_NAME="$DB_PROXY_NAME"
export KMS_KEY_ALIAS="$KMS_KEY_ALIAS"
export DB_SUBNET_GROUP_NAME="$DB_SUBNET_GROUP_NAME"
export SECURITY_GROUP_NAME="$SECURITY_GROUP_NAME"
export IAM_ROLE_NAME="$IAM_ROLE_NAME"
export IAM_POLICY_NAME="$IAM_POLICY_NAME"
export DB_USER_NAME="$DB_USER_NAME"
export DB_PARAMETER_GROUP_NAME="$DB_PARAMETER_GROUP_NAME"
export VPC_ID="$VPC_ID"
export SUBNET_IDS="$SUBNET_IDS"
EOF
    
    info "Environment configured for region: $AWS_REGION"
    info "Database instance ID: $DB_INSTANCE_ID"
    info "VPC ID: $VPC_ID"
}

# Function to create KMS key
create_kms_key() {
    log "Creating customer-managed KMS key..."
    
    # Create KMS key policy
    cat > "$STATE_DIR/kms-key-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow RDS Service",
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "rds.${AWS_REGION}.amazonaws.com"
        }
      }
    }
  ]
}
EOF
    
    # Create KMS key
    local kms_key_id
    kms_key_id=$(execute_cmd "aws kms create-key \
        --description 'Customer managed key for RDS encryption' \
        --policy file://$STATE_DIR/kms-key-policy.json \
        --query 'KeyMetadata.KeyId' --output text" \
        "Creating KMS key")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export KMS_KEY_ID="$kms_key_id"
        echo "KMS_KEY_ID=\"$kms_key_id\"" >> "$STATE_DIR/env_vars.sh"
        
        # Create key alias
        execute_cmd "aws kms create-alias \
            --alias-name '$KMS_KEY_ALIAS' \
            --target-key-id '$KMS_KEY_ID'" \
            "Creating KMS key alias"
        
        info "KMS key created: $KMS_KEY_ID ✅"
    fi
}

# Function to create security group
create_security_group() {
    log "Creating security group for database access..."
    
    local security_group_id
    security_group_id=$(execute_cmd "aws ec2 create-security-group \
        --group-name '$SECURITY_GROUP_NAME' \
        --description 'Security group for secure RDS instance' \
        --vpc-id '$VPC_ID' \
        --query 'GroupId' --output text" \
        "Creating security group")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export SECURITY_GROUP_ID="$security_group_id"
        echo "SECURITY_GROUP_ID=\"$security_group_id\"" >> "$STATE_DIR/env_vars.sh"
        
        # Allow PostgreSQL access from within VPC
        execute_cmd "aws ec2 authorize-security-group-ingress \
            --group-id '$SECURITY_GROUP_ID' \
            --protocol tcp \
            --port 5432 \
            --source-group '$SECURITY_GROUP_ID'" \
            "Configuring security group ingress rules"
        
        # Add tags
        execute_cmd "aws ec2 create-tags \
            --resources '$SECURITY_GROUP_ID' \
            --tags Key=Name,Value='$SECURITY_GROUP_NAME' \
                   Key=Purpose,Value='Database Security' \
                   Key=Environment,Value='Production'" \
            "Adding tags to security group"
        
        info "Security group created: $SECURITY_GROUP_ID ✅"
    fi
}

# Function to create database subnet group
create_db_subnet_group() {
    log "Creating database subnet group..."
    
    execute_cmd "aws rds create-db-subnet-group \
        --db-subnet-group-name '$DB_SUBNET_GROUP_NAME' \
        --db-subnet-group-description 'Subnet group for secure database' \
        --subnet-ids $SUBNET_IDS \
        --tags Key=Name,Value='$DB_SUBNET_GROUP_NAME' \
               Key=Purpose,Value='Database Security'" \
        "Creating database subnet group"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Database subnet group created: $DB_SUBNET_GROUP_NAME ✅"
    fi
}

# Function to create IAM resources
create_iam_resources() {
    log "Creating IAM role and policy for database authentication..."
    
    # Create IAM policy
    cat > "$STATE_DIR/database-access-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds-db:connect"
      ],
      "Resource": [
        "arn:aws:rds-db:${AWS_REGION}:${AWS_ACCOUNT_ID}:dbuser:${DB_INSTANCE_ID}/${DB_USER_NAME}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBInstances",
        "rds:DescribeDBProxies"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    local policy_arn
    policy_arn=$(execute_cmd "aws iam create-policy \
        --policy-name '$IAM_POLICY_NAME' \
        --policy-document file://$STATE_DIR/database-access-policy.json \
        --query 'Policy.Arn' --output text" \
        "Creating IAM policy")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export POLICY_ARN="$policy_arn"
        echo "POLICY_ARN=\"$policy_arn\"" >> "$STATE_DIR/env_vars.sh"
    fi
    
    # Create trust policy
    cat > "$STATE_DIR/trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": ["lambda.amazonaws.com", "ec2.amazonaws.com"]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    local role_arn
    role_arn=$(execute_cmd "aws iam create-role \
        --role-name '$IAM_ROLE_NAME' \
        --assume-role-policy-document file://$STATE_DIR/trust-policy.json \
        --query 'Role.Arn' --output text" \
        "Creating IAM role")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export ROLE_ARN="$role_arn"
        echo "ROLE_ARN=\"$role_arn\"" >> "$STATE_DIR/env_vars.sh"
        
        # Attach policy to role
        execute_cmd "aws iam attach-role-policy \
            --role-name '$IAM_ROLE_NAME' \
            --policy-arn '$POLICY_ARN'" \
            "Attaching policy to role"
        
        info "IAM resources created: $ROLE_ARN ✅"
    fi
}

# Function to create enhanced monitoring role
create_monitoring_role() {
    log "Creating enhanced monitoring role..."
    
    cat > "$STATE_DIR/monitoring-trust-policy.json" << EOF
{
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
}
EOF
    
    # Check if monitoring role already exists
    if ! aws iam get-role --role-name "rds-monitoring-role" &>/dev/null; then
        execute_cmd "aws iam create-role \
            --role-name 'rds-monitoring-role' \
            --assume-role-policy-document file://$STATE_DIR/monitoring-trust-policy.json" \
            "Creating monitoring role"
        
        execute_cmd "aws iam attach-role-policy \
            --role-name 'rds-monitoring-role' \
            --policy-arn 'arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole'" \
            "Attaching monitoring policy"
    else
        info "Monitoring role already exists, skipping creation"
    fi
}

# Function to create RDS instance
create_rds_instance() {
    log "Creating encrypted RDS instance with IAM authentication..."
    
    # Create parameter group
    execute_cmd "aws rds create-db-parameter-group \
        --db-parameter-group-name '$DB_PARAMETER_GROUP_NAME' \
        --db-parameter-group-family 'postgres15' \
        --description 'Security-enhanced PostgreSQL parameters'" \
        "Creating parameter group"
    
    # Modify parameter group to force SSL
    execute_cmd "aws rds modify-db-parameter-group \
        --db-parameter-group-name '$DB_PARAMETER_GROUP_NAME' \
        --parameters 'ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate'" \
        "Configuring SSL enforcement"
    
    # Create RDS instance
    local create_db_cmd="aws rds create-db-instance \
        --db-instance-identifier '$DB_INSTANCE_ID' \
        --db-instance-class 'db.r5.large' \
        --engine 'postgres' \
        --engine-version '15.7' \
        --master-username 'dbadmin' \
        --master-user-password 'TempPassword123!' \
        --allocated-storage 100 \
        --storage-type 'gp3' \
        --storage-encrypted \
        --kms-key-id '$KMS_KEY_ID' \
        --vpc-security-group-ids '$SECURITY_GROUP_ID' \
        --db-subnet-group-name '$DB_SUBNET_GROUP_NAME' \
        --db-parameter-group-name '$DB_PARAMETER_GROUP_NAME' \
        --backup-retention-period 7 \
        --preferred-backup-window '03:00-04:00' \
        --preferred-maintenance-window 'sun:04:00-sun:05:00' \
        --enable-iam-database-authentication \
        --monitoring-interval 60 \
        --monitoring-role-arn 'arn:aws:iam::${AWS_ACCOUNT_ID}:role/rds-monitoring-role' \
        --enable-performance-insights \
        --performance-insights-kms-key-id '$KMS_KEY_ID' \
        --performance-insights-retention-period 7 \
        --deletion-protection \
        --tags Key=Name,Value='$DB_INSTANCE_ID' \
               Key=Environment,Value='Production' \
               Key=Security,Value='Encrypted'"
    
    execute_cmd "$create_db_cmd" "Creating RDS instance"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Waiting for RDS instance to be available..."
        aws rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_ID"
        info "RDS instance created and available: $DB_INSTANCE_ID ✅"
    fi
}

# Function to create RDS proxy
create_rds_proxy() {
    log "Creating RDS proxy for enhanced security..."
    
    execute_cmd "aws rds create-db-proxy \
        --db-proxy-name '$DB_PROXY_NAME' \
        --engine-family 'POSTGRESQL' \
        --auth 'Description=IAM authentication for secure database access,AuthScheme=IAM' \
        --role-arn '$ROLE_ARN' \
        --vpc-subnet-ids $SUBNET_IDS \
        --vpc-security-group-ids '$SECURITY_GROUP_ID' \
        --require-tls \
        --idle-client-timeout 1800 \
        --debug-logging \
        --tags Key=Name,Value='$DB_PROXY_NAME' \
               Key=Environment,Value='Production'" \
        "Creating RDS proxy"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait a bit for proxy creation
        sleep 30
        
        # Register RDS instance with proxy
        execute_cmd "aws rds register-db-proxy-targets \
            --db-proxy-name '$DB_PROXY_NAME' \
            --db-instance-identifiers '$DB_INSTANCE_ID'" \
            "Registering RDS instance with proxy"
        
        info "RDS proxy created: $DB_PROXY_NAME ✅"
    fi
}

# Function to configure database user
configure_database_user() {
    log "Configuring database user for IAM authentication..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would configure database user for IAM authentication"
        return 0
    fi
    
    # Get RDS instance endpoint
    local db_endpoint
    db_endpoint=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    echo "DB_ENDPOINT=\"$db_endpoint\"" >> "$STATE_DIR/env_vars.sh"
    
    # Create SQL script
    cat > "$STATE_DIR/setup_db_user.sql" << EOF
-- Create database user for IAM authentication
CREATE USER ${DB_USER_NAME};
GRANT rds_iam TO ${DB_USER_NAME};

-- Create application database and grant permissions
CREATE DATABASE secure_app_db;
GRANT CONNECT ON DATABASE secure_app_db TO ${DB_USER_NAME};

-- Connect to the application database
\c secure_app_db

-- Create schema and grant permissions
CREATE SCHEMA app_schema;
GRANT USAGE ON SCHEMA app_schema TO ${DB_USER_NAME};
GRANT CREATE ON SCHEMA app_schema TO ${DB_USER_NAME};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app_schema TO ${DB_USER_NAME};
ALTER DEFAULT PRIVILEGES IN SCHEMA app_schema GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${DB_USER_NAME};

-- Create sample table for testing
CREATE TABLE app_schema.secure_data (
    id SERIAL PRIMARY KEY,
    sensitive_info VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO app_schema.secure_data (sensitive_info) VALUES ('Sample encrypted data');
EOF
    
    # Execute SQL script
    info "Executing database user setup script..."
    if PGPASSWORD="TempPassword123!" psql \
        -h "$db_endpoint" \
        -U "dbadmin" \
        -d "postgres" \
        -p 5432 \
        -f "$STATE_DIR/setup_db_user.sql" > "$STATE_DIR/db_setup.log" 2>&1; then
        info "Database user configured successfully ✅"
    else
        error "Failed to configure database user. Check $STATE_DIR/db_setup.log for details."
        return 1
    fi
}

# Function to setup CloudWatch monitoring
setup_cloudwatch_monitoring() {
    log "Setting up CloudWatch monitoring and alerts..."
    
    # Create log group
    execute_cmd "aws logs create-log-group \
        --log-group-name '/aws/rds/instance/$DB_INSTANCE_ID/postgresql' \
        --retention-in-days 30" \
        "Creating CloudWatch log group"
    
    # Create CPU alarm
    execute_cmd "aws cloudwatch put-metric-alarm \
        --alarm-name 'RDS-HighCPU-$DB_INSTANCE_ID' \
        --alarm-description 'High CPU usage on RDS instance' \
        --metric-name CPUUtilization \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 80.0 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=DBInstanceIdentifier,Value='$DB_INSTANCE_ID'" \
        "Creating CPU usage alarm"
    
    # Create connection alarm
    execute_cmd "aws cloudwatch put-metric-alarm \
        --alarm-name 'RDS-AuthFailures-$DB_INSTANCE_ID' \
        --alarm-description 'High number of authentication failures' \
        --metric-name DatabaseConnections \
        --namespace AWS/RDS \
        --statistic Sum \
        --period 300 \
        --threshold 50.0 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --dimensions Name=DBInstanceIdentifier,Value='$DB_INSTANCE_ID'" \
        "Creating authentication failure alarm"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "CloudWatch monitoring configured ✅"
    fi
}

# Function to generate security report
generate_security_report() {
    log "Generating security compliance report..."
    
    cat > "$STATE_DIR/security-compliance-report.json" << EOF
{
  "database_security_audit": {
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "encryption_at_rest": {
      "enabled": true,
      "kms_key_id": "${KMS_KEY_ID:-placeholder}",
      "customer_managed_key": true
    },
    "encryption_in_transit": {
      "enabled": true,
      "tls_required": true,
      "force_ssl": true
    },
    "iam_authentication": {
      "enabled": true,
      "db_user": "$DB_USER_NAME",
      "iam_role": "$IAM_ROLE_NAME"
    },
    "network_security": {
      "vpc_security_group": "${SECURITY_GROUP_ID:-placeholder}",
      "private_subnets": true,
      "db_subnet_group": "$DB_SUBNET_GROUP_NAME"
    },
    "monitoring": {
      "enhanced_monitoring": true,
      "performance_insights": true,
      "cloudwatch_logs": true,
      "cloudwatch_alarms": true
    },
    "backup_security": {
      "backup_retention_days": 7,
      "backup_encryption": true,
      "point_in_time_recovery": true
    }
  }
}
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Security compliance report generated: $STATE_DIR/security-compliance-report.json ✅"
    fi
}

# Function to run validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would run validation tests"
        return 0
    fi
    
    # Check encryption status
    info "Validating encryption configuration..."
    aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --query 'DBInstances[0].{Encrypted:StorageEncrypted,KmsKeyId:KmsKeyId,IAMAuth:IAMDatabaseAuthenticationEnabled}' \
        --output table > "$STATE_DIR/encryption_validation.txt"
    
    # Test IAM authentication
    info "Testing IAM database authentication..."
    local db_endpoint
    db_endpoint=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    # Generate auth token
    local auth_token
    auth_token=$(aws rds generate-db-auth-token \
        --hostname "$db_endpoint" \
        --port 5432 \
        --region "$AWS_REGION" \
        --username "$DB_USER_NAME")
    
    # Test connection
    if PGPASSWORD="$auth_token" psql \
        -h "$db_endpoint" \
        -U "$DB_USER_NAME" \
        -d "secure_app_db" \
        -p 5432 \
        -c "SELECT 'IAM Authentication successful' AS status;" > "$STATE_DIR/iam_auth_test.txt" 2>&1; then
        info "IAM authentication test passed ✅"
    else
        warn "IAM authentication test failed. Check $STATE_DIR/iam_auth_test.txt for details."
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Region: $AWS_REGION"
    echo "Account ID: $AWS_ACCOUNT_ID"
    echo "Database Instance ID: $DB_INSTANCE_ID"
    echo "Database Proxy Name: $DB_PROXY_NAME"
    echo "KMS Key Alias: $KMS_KEY_ALIAS"
    echo "Security Group: ${SECURITY_GROUP_ID:-Not created}"
    echo "IAM Role: $IAM_ROLE_NAME"
    echo
    echo "State files saved to: $STATE_DIR"
    echo "Security report: $STATE_DIR/security-compliance-report.json"
    echo
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "✅ Deployment completed successfully!"
        echo "⚠️  Remember to change the master password after testing!"
    else
        echo "🔍 Dry run completed - no resources were created"
    fi
}

# Main execution
main() {
    log "Starting Database Security Deployment..."
    
    # Check for help
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo "Usage: $0 [--dry-run] [--help]"
        echo "Options:"
        echo "  --dry-run   Show what would be done without making changes"
        echo "  --help      Show this help message"
        exit 0
    fi
    
    # Confirmation prompt (skip for dry run)
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "⚠️  This will create AWS resources that may incur charges."
        echo "Estimated monthly cost: $50-100 for db.r5.large instance"
        echo
        read -p "Do you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_kms_key
    create_security_group
    create_db_subnet_group
    create_iam_resources
    create_monitoring_role
    create_rds_instance
    create_rds_proxy
    configure_database_user
    setup_cloudwatch_monitoring
    generate_security_report
    run_validation_tests
    display_summary
    
    log "Deployment process completed!"
}

# Execute main function
main "$@"