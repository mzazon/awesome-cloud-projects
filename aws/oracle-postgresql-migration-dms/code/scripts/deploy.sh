#!/bin/bash

# Database Migration from Oracle to PostgreSQL - Deployment Script
# This script deploys AWS DMS infrastructure for Oracle to PostgreSQL migration

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_DIR}/deployment.log"

# Redirect all output to both console and log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log "Starting Oracle to PostgreSQL migration infrastructure deployment"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    # Check psql (PostgreSQL client)
    if ! command -v psql &> /dev/null; then
        warning "PostgreSQL client (psql) is not installed. Schema validation will be skipped"
    fi
    
    # Check curl for downloads
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Required for downloading AWS SCT"
        exit 1
    fi
    
    # Check Java for SCT
    if ! command -v java &> /dev/null; then
        warning "Java is not installed. AWS SCT installation will be skipped"
    else
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)
        if [[ "$JAVA_VERSION" -lt 8 ]]; then
            warning "Java 8 or later required for AWS SCT. Current version: $JAVA_VERSION"
        fi
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # AWS Configuration
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS_REGION not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export MIGRATION_PROJECT_NAME="oracle-to-postgresql-${RANDOM_SUFFIX}"
    export REPLICATION_INSTANCE_ID="dms-replication-${RANDOM_SUFFIX}"
    export AURORA_CLUSTER_ID="aurora-postgresql-${RANDOM_SUFFIX}"
    export DMS_SUBNET_GROUP_NAME="dms-subnet-group-${RANDOM_SUFFIX}"
    export VPC_NAME="${MIGRATION_PROJECT_NAME}-vpc"
    
    # Store environment variables for later use
    cat > "${PROJECT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
MIGRATION_PROJECT_NAME=${MIGRATION_PROJECT_NAME}
REPLICATION_INSTANCE_ID=${REPLICATION_INSTANCE_ID}
AURORA_CLUSTER_ID=${AURORA_CLUSTER_ID}
DMS_SUBNET_GROUP_NAME=${DMS_SUBNET_GROUP_NAME}
VPC_NAME=${VPC_NAME}
EOF
    
    success "Environment variables configured"
    log "Project: ${MIGRATION_PROJECT_NAME}"
    log "Region: ${AWS_REGION}"
}

# Create VPC and networking components
create_networking() {
    log "Creating VPC and networking components..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text)
    
    aws ec2 create-tags \
        --resources "${VPC_ID}" \
        --tags Key=Name,Value="${VPC_NAME}" \
               Key=Project,Value="${MIGRATION_PROJECT_NAME}"
    
    # Enable DNS support
    aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-support
    aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames
    
    # Create Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "${IGW_ID}" \
        --vpc-id "${VPC_ID}"
    
    aws ec2 create-tags \
        --resources "${IGW_ID}" \
        --tags Key=Name,Value="${VPC_NAME}-igw" \
               Key=Project,Value="${MIGRATION_PROJECT_NAME}"
    
    # Create subnets in different AZs
    SUBNET_1_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --query 'Subnet.SubnetId' --output text)
    
    SUBNET_2_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --query 'Subnet.SubnetId' --output text)
    
    # Tag subnets
    aws ec2 create-tags \
        --resources "${SUBNET_1_ID}" \
        --tags Key=Name,Value="${VPC_NAME}-subnet-1" \
               Key=Project,Value="${MIGRATION_PROJECT_NAME}"
    
    aws ec2 create-tags \
        --resources "${SUBNET_2_ID}" \
        --tags Key=Name,Value="${VPC_NAME}-subnet-2" \
               Key=Project,Value="${MIGRATION_PROJECT_NAME}"
    
    # Create route table and associate with subnets
    ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route \
        --route-table-id "${ROUTE_TABLE_ID}" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "${IGW_ID}"
    
    aws ec2 associate-route-table \
        --subnet-id "${SUBNET_1_ID}" \
        --route-table-id "${ROUTE_TABLE_ID}"
    
    aws ec2 associate-route-table \
        --subnet-id "${SUBNET_2_ID}" \
        --route-table-id "${ROUTE_TABLE_ID}"
    
    # Create security group
    VPC_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "${MIGRATION_PROJECT_NAME}-sg" \
        --description "Security group for DMS migration" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' --output text)
    
    # Add security group rules
    aws ec2 authorize-security-group-ingress \
        --group-id "${VPC_SECURITY_GROUP_ID}" \
        --protocol tcp \
        --port 5432 \
        --cidr 10.0.0.0/16
    
    aws ec2 authorize-security-group-ingress \
        --group-id "${VPC_SECURITY_GROUP_ID}" \
        --protocol tcp \
        --port 1521 \
        --cidr 10.0.0.0/16
    
    # Store networking info
    cat >> "${PROJECT_DIR}/.env" << EOF
VPC_ID=${VPC_ID}
IGW_ID=${IGW_ID}
SUBNET_1_ID=${SUBNET_1_ID}
SUBNET_2_ID=${SUBNET_2_ID}
ROUTE_TABLE_ID=${ROUTE_TABLE_ID}
VPC_SECURITY_GROUP_ID=${VPC_SECURITY_GROUP_ID}
EOF
    
    success "VPC and networking components created"
    log "VPC ID: ${VPC_ID}"
}

# Create subnet groups
create_subnet_groups() {
    log "Creating DB and DMS subnet groups..."
    
    # Create DB subnet group for Aurora
    aws rds create-db-subnet-group \
        --db-subnet-group-name "${AURORA_CLUSTER_ID}-subnet-group" \
        --db-subnet-group-description "Subnet group for Aurora PostgreSQL" \
        --subnet-ids "${SUBNET_1_ID}" "${SUBNET_2_ID}" \
        --tags Key=Name,Value="${AURORA_CLUSTER_ID}-subnet-group" \
               Key=Project,Value="${MIGRATION_PROJECT_NAME}"
    
    # Create DMS subnet group
    aws dms create-replication-subnet-group \
        --replication-subnet-group-identifier "${DMS_SUBNET_GROUP_NAME}" \
        --replication-subnet-group-description "DMS subnet group for migration" \
        --subnet-ids "${SUBNET_1_ID}" "${SUBNET_2_ID}" \
        --tags Key=Name,Value="${DMS_SUBNET_GROUP_NAME}" \
               Key=Project,Value="${MIGRATION_PROJECT_NAME}"
    
    success "Subnet groups created"
}

# Create IAM roles for DMS
create_iam_roles() {
    log "Creating IAM roles for DMS..."
    
    # Check if DMS VPC role exists
    if ! aws iam get-role --role-name dms-vpc-role &>/dev/null; then
        # Create DMS VPC role
        aws iam create-role \
            --role-name dms-vpc-role \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "dms.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' \
            --tags Key=Project,Value="${MIGRATION_PROJECT_NAME}"
        
        # Attach DMS VPC management policy
        aws iam attach-role-policy \
            --role-name dms-vpc-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole
        
        success "DMS VPC role created"
    else
        log "DMS VPC role already exists"
    fi
    
    # Check if DMS CloudWatch logs role exists
    if ! aws iam get-role --role-name dms-cloudwatch-logs-role &>/dev/null; then
        # Create DMS CloudWatch logs role
        aws iam create-role \
            --role-name dms-cloudwatch-logs-role \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "dms.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' \
            --tags Key=Project,Value="${MIGRATION_PROJECT_NAME}"
        
        # Attach CloudWatch logs policy
        aws iam attach-role-policy \
            --role-name dms-cloudwatch-logs-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole
        
        success "DMS CloudWatch logs role created"
    else
        log "DMS CloudWatch logs role already exists"
    fi
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
}

# Create Aurora PostgreSQL cluster
create_aurora_cluster() {
    log "Creating Aurora PostgreSQL cluster..."
    
    # Create Aurora PostgreSQL cluster
    aws rds create-db-cluster \
        --db-cluster-identifier "${AURORA_CLUSTER_ID}" \
        --engine aurora-postgresql \
        --engine-version 15.4 \
        --master-username dbadmin \
        --master-user-password 'TempPassword123!' \
        --db-subnet-group-name "${AURORA_CLUSTER_ID}-subnet-group" \
        --vpc-security-group-ids "${VPC_SECURITY_GROUP_ID}" \
        --backup-retention-period 7 \
        --preferred-backup-window "03:00-04:00" \
        --preferred-maintenance-window "sun:04:00-sun:05:00" \
        --port 5432 \
        --tags Key=Name,Value="${AURORA_CLUSTER_ID}" \
               Key=Project,Value="${MIGRATION_PROJECT_NAME}"
    
    # Create Aurora PostgreSQL instance
    aws rds create-db-instance \
        --db-instance-identifier "${AURORA_CLUSTER_ID}-instance-1" \
        --db-instance-class db.r6g.large \
        --engine aurora-postgresql \
        --db-cluster-identifier "${AURORA_CLUSTER_ID}" \
        --monitoring-interval 60 \
        --performance-insights-enabled \
        --performance-insights-retention-period 7 \
        --tags Key=Name,Value="${AURORA_CLUSTER_ID}-instance-1" \
               Key=Project,Value="${MIGRATION_PROJECT_NAME}"
    
    log "Waiting for Aurora cluster to be available..."
    aws rds wait db-cluster-available --db-cluster-identifier "${AURORA_CLUSTER_ID}"
    
    # Get Aurora endpoint
    AURORA_ENDPOINT=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${AURORA_CLUSTER_ID}" \
        --query 'DBClusters[0].Endpoint' --output text)
    
    echo "AURORA_ENDPOINT=${AURORA_ENDPOINT}" >> "${PROJECT_DIR}/.env"
    
    success "Aurora PostgreSQL cluster created and available"
    log "Aurora endpoint: ${AURORA_ENDPOINT}"
}

# Create DMS replication instance
create_dms_instance() {
    log "Creating DMS replication instance..."
    
    aws dms create-replication-instance \
        --replication-instance-identifier "${REPLICATION_INSTANCE_ID}" \
        --replication-instance-class dms.c5.large \
        --allocated-storage 100 \
        --auto-minor-version-upgrade \
        --multi-az \
        --engine-version 3.5.2 \
        --replication-subnet-group-identifier "${DMS_SUBNET_GROUP_NAME}" \
        --publicly-accessible false \
        --tags Key=Name,Value="${REPLICATION_INSTANCE_ID}" \
               Key=Project,Value="${MIGRATION_PROJECT_NAME}"
    
    log "Waiting for DMS replication instance to be available..."
    aws dms wait replication-instance-available \
        --replication-instance-identifier "${REPLICATION_INSTANCE_ID}"
    
    success "DMS replication instance created and available"
}

# Install AWS Schema Conversion Tool
install_sct() {
    log "Installing AWS Schema Conversion Tool..."
    
    if ! command -v java &> /dev/null; then
        warning "Java not found. Skipping AWS SCT installation"
        return 0
    fi
    
    local sct_dir="${PROJECT_DIR}/aws-sct"
    mkdir -p "${sct_dir}"
    
    if [[ ! -f "${sct_dir}/aws-schema-conversion-tool" ]]; then
        log "Downloading AWS SCT..."
        cd "${sct_dir}"
        
        curl -L -o aws-schema-conversion-tool.zip \
            "https://s3.amazonaws.com/publicsctdownload/AWS+SCT/1.0.668/aws-schema-conversion-tool-1.0.668.zip"
        
        unzip -q aws-schema-conversion-tool.zip
        chmod +x aws-schema-conversion-tool-*/aws-schema-conversion-tool
        
        # Create symlink
        ln -sf "$(pwd)/aws-schema-conversion-tool-*/aws-schema-conversion-tool" ./aws-sct
        
        rm aws-schema-conversion-tool.zip
        cd "${PROJECT_DIR}"
        
        success "AWS SCT installed successfully"
    else
        log "AWS SCT already installed"
    fi
    
    echo "SCT_PATH=${sct_dir}/aws-sct" >> "${PROJECT_DIR}/.env"
}

# Create configuration templates
create_configurations() {
    log "Creating configuration templates..."
    
    local config_dir="${PROJECT_DIR}/config"
    mkdir -p "${config_dir}"
    
    # Create SCT project configuration template
    cat > "${config_dir}/sct-project-config.json.template" << EOF
{
  "ProjectName": "${MIGRATION_PROJECT_NAME}",
  "SourceDatabaseEngine": "Oracle",
  "TargetDatabaseEngine": "PostgreSQL",
  "SourceConnection": {
    "ServerName": "your-oracle-server.example.com",
    "Port": 1521,
    "DatabaseName": "ORCL",
    "Username": "oracle_user",
    "Password": "oracle_password"
  },
  "TargetConnection": {
    "ServerName": "${AURORA_ENDPOINT:-placeholder}",
    "Port": 5432,
    "DatabaseName": "postgres",
    "Username": "dbadmin",
    "Password": "TempPassword123!"
  },
  "ConversionSettings": {
    "GenerateLogsReport": true,
    "OptimizeForAurora": true,
    "ConvertViews": true,
    "ConvertProcedures": true,
    "ConvertFunctions": true,
    "ConvertTriggers": true
  }
}
EOF
    
    # Create table mapping template
    cat > "${config_dir}/table-mapping.json.template" << EOF
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "1",
      "object-locator": {
        "schema-name": "HR",
        "table-name": "%"
      },
      "rule-action": "include",
      "filters": []
    },
    {
      "rule-type": "transformation",
      "rule-id": "2",
      "rule-name": "2",
      "rule-target": "schema",
      "object-locator": {
        "schema-name": "HR"
      },
      "rule-action": "rename",
      "value": "hr"
    },
    {
      "rule-type": "transformation",
      "rule-id": "3",
      "rule-name": "3",
      "rule-target": "table",
      "object-locator": {
        "schema-name": "HR",
        "table-name": "%"
      },
      "rule-action": "convert-lowercase"
    }
  ]
}
EOF
    
    # Create validation script template
    cat > "${config_dir}/validate-migration.sql.template" << 'EOF'
-- Connect to PostgreSQL and validate data
SELECT schemaname, tablename, n_tup_ins as row_count
FROM pg_stat_user_tables 
WHERE schemaname = 'hr'
ORDER BY tablename;

-- Check for any data type conversion issues
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'hr'
AND data_type IN ('text', 'varchar', 'character varying')
ORDER BY table_name, column_name;

-- Validate foreign key constraints
SELECT conname, conrelid::regclass AS table_name, 
       confrelid::regclass AS referenced_table
FROM pg_constraint
WHERE contype = 'f'
AND connamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'hr');
EOF
    
    success "Configuration templates created in ${config_dir}"
}

# Create helper scripts
create_helper_scripts() {
    log "Creating helper scripts..."
    
    local scripts_dir="${SCRIPT_DIR}"
    
    # Create endpoint creation script
    cat > "${scripts_dir}/create-endpoints.sh" << 'EOF'
#!/bin/bash
# Helper script to create DMS endpoints

source "$(dirname "$0")/../.env"

echo "Creating Oracle source endpoint..."
echo "Please update the Oracle connection details before running:"
echo "Server: your-oracle-server.example.com"
echo "Port: 1521"
echo "Database: ORCL"
echo "Username: oracle_user"
echo "Password: oracle_password"

echo ""
echo "Creating PostgreSQL target endpoint..."
aws dms create-endpoint \
    --endpoint-identifier postgresql-target-endpoint \
    --endpoint-type target \
    --engine-name postgres \
    --server-name "${AURORA_ENDPOINT}" \
    --port 5432 \
    --database-name postgres \
    --username dbadmin \
    --password 'TempPassword123!'

echo "✅ Endpoints creation template ready"
EOF
    
    chmod +x "${scripts_dir}/create-endpoints.sh"
    
    # Create migration task script
    cat > "${scripts_dir}/create-migration-task.sh" << 'EOF'
#!/bin/bash
# Helper script to create DMS migration task

source "$(dirname "$0")/../.env"

echo "Creating migration task..."
echo "Make sure Oracle and PostgreSQL endpoints are created first!"

# Use the table mapping configuration
aws dms create-replication-task \
    --replication-task-identifier "${MIGRATION_PROJECT_NAME}-task" \
    --source-endpoint-arn "$(aws dms describe-endpoints --endpoint-identifier oracle-source-endpoint --query 'Endpoints[0].EndpointArn' --output text)" \
    --target-endpoint-arn "$(aws dms describe-endpoints --endpoint-identifier postgresql-target-endpoint --query 'Endpoints[0].EndpointArn' --output text)" \
    --replication-instance-arn "$(aws dms describe-replication-instances --replication-instance-identifier ${REPLICATION_INSTANCE_ID} --query 'ReplicationInstances[0].ReplicationInstanceArn' --output text)" \
    --migration-type full-load-and-cdc \
    --table-mappings file://"$(dirname "$0")/../config/table-mapping.json.template"

echo "✅ Migration task created"
EOF
    
    chmod +x "${scripts_dir}/create-migration-task.sh"
    
    success "Helper scripts created"
}

# Create monitoring and alerts
create_monitoring() {
    log "Creating CloudWatch monitoring and alerts..."
    
    # Create SNS topic for alerts (optional)
    local sns_topic_arn=""
    if aws sns list-topics --query "Topics[?contains(TopicArn, 'dms-alerts')]" --output text | grep -q dms-alerts; then
        sns_topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'dms-alerts')].TopicArn" --output text | head -1)
        log "Using existing SNS topic: ${sns_topic_arn}"
    else
        log "SNS topic for alerts not found. Skipping alarm actions"
    fi
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${MIGRATION_PROJECT_NAME}-dashboard" \
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
                            [ "AWS/DMS", "CDCLatencySource", "ReplicationInstanceIdentifier", "'${REPLICATION_INSTANCE_ID}'" ],
                            [ ".", "CDCLatencyTarget", ".", "." ]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'${AWS_REGION}'",
                        "title": "DMS Replication Latency"
                    }
                }
            ]
        }'
    
    success "CloudWatch monitoring configured"
}

# Main deployment function
main() {
    log "=== Oracle to PostgreSQL Migration Infrastructure Deployment ==="
    log "Deployment started at $(date)"
    
    check_prerequisites
    setup_environment
    create_networking
    create_subnet_groups
    create_iam_roles
    create_aurora_cluster
    create_dms_instance
    install_sct
    create_configurations
    create_helper_scripts
    create_monitoring
    
    success "=== Deployment completed successfully! ==="
    log "Deployment finished at $(date)"
    
    echo ""
    echo "📋 NEXT STEPS:"
    echo "1. Update Oracle connection details in: ${PROJECT_DIR}/config/sct-project-config.json.template"
    echo "2. Run: ${SCRIPT_DIR}/create-endpoints.sh"
    echo "3. Test endpoint connections"
    echo "4. Run schema conversion with AWS SCT"
    echo "5. Create and start migration task"
    echo ""
    echo "📁 Configuration files location: ${PROJECT_DIR}/config/"
    echo "📄 Environment file: ${PROJECT_DIR}/.env"
    echo "📊 CloudWatch Dashboard: ${MIGRATION_PROJECT_NAME}-dashboard"
    echo ""
    echo "⚠️  Remember to:"
    echo "   - Update the Oracle endpoint configuration with your actual server details"
    echo "   - Change the default PostgreSQL password in production"
    echo "   - Review and test the migration in a non-production environment first"
    echo ""
    echo "💰 Estimated monthly cost: \$150-300 (Aurora + DMS instance)"
    echo "🧹 To clean up resources, run: ${SCRIPT_DIR}/destroy.sh"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Check ${LOG_FILE} for details."' ERR

# Run main function
main "$@"