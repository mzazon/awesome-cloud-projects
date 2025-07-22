#!/bin/bash

# Aurora Global Database Deployment Script
# This script deploys a multi-master Aurora Global Database with write forwarding
# across three regions: us-east-1, eu-west-1, and ap-southeast-1

set -e
set -o pipefail

# Color codes for output
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_cli() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "AWS CLI is properly configured"
}

# Function to check MySQL client
check_mysql_client() {
    if ! command_exists mysql; then
        warn "MySQL client is not installed. Database operations will be skipped."
        warn "Install MySQL client to test database connectivity and operations."
        return 1
    fi
    return 0
}

# Function to check required permissions
check_permissions() {
    log "Checking AWS permissions..."
    
    # Test basic RDS permissions
    if ! aws rds describe-db-clusters --region us-east-1 >/dev/null 2>&1; then
        error "Insufficient permissions for RDS operations"
        exit 1
    fi
    
    # Test CloudWatch permissions
    if ! aws cloudwatch list-dashboards --region us-east-1 >/dev/null 2>&1; then
        error "Insufficient permissions for CloudWatch operations"
        exit 1
    fi
    
    log "AWS permissions verified"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set regions
    export PRIMARY_REGION="us-east-1"
    export SECONDARY_REGION_1="eu-west-1"
    export SECONDARY_REGION_2="ap-southeast-1"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set global database identifiers
    export GLOBAL_DB_IDENTIFIER="global-ecommerce-db-${random_suffix}"
    export PRIMARY_CLUSTER_ID="primary-cluster-${random_suffix}"
    export SECONDARY_CLUSTER_1_ID="secondary-eu-${random_suffix}"
    export SECONDARY_CLUSTER_2_ID="secondary-asia-${random_suffix}"
    
    # Database configuration
    export DB_ENGINE="aurora-mysql"
    export ENGINE_VERSION="8.0.mysql_aurora.3.02.0"
    export DB_INSTANCE_CLASS="db.r5.large"
    export MASTER_USERNAME="globaladmin"
    
    # Generate secure password
    export MASTER_PASSWORD=$(aws secretsmanager get-random-password \
        --exclude-characters '"@/\' --password-length 16 \
        --require-each-included-type --output text \
        --query RandomPassword 2>/dev/null || openssl rand -base64 16)
    
    # Save configuration to file for cleanup script
    cat > ./.deployment-config << EOF
GLOBAL_DB_IDENTIFIER=${GLOBAL_DB_IDENTIFIER}
PRIMARY_CLUSTER_ID=${PRIMARY_CLUSTER_ID}
SECONDARY_CLUSTER_1_ID=${SECONDARY_CLUSTER_1_ID}
SECONDARY_CLUSTER_2_ID=${SECONDARY_CLUSTER_2_ID}
PRIMARY_REGION=${PRIMARY_REGION}
SECONDARY_REGION_1=${SECONDARY_REGION_1}
SECONDARY_REGION_2=${SECONDARY_REGION_2}
MASTER_USERNAME=${MASTER_USERNAME}
MASTER_PASSWORD=${MASTER_PASSWORD}
EOF
    
    log "Environment configured:"
    info "Global DB ID: ${GLOBAL_DB_IDENTIFIER}"
    info "Primary Region: ${PRIMARY_REGION}"
    info "Secondary Regions: ${SECONDARY_REGION_1}, ${SECONDARY_REGION_2}"
    info "Master Username: ${MASTER_USERNAME}"
}

# Function to create global database
create_global_database() {
    log "Creating Aurora Global Database..."
    
    if aws rds describe-global-clusters \
        --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
        --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        warn "Global database ${GLOBAL_DB_IDENTIFIER} already exists"
        return 0
    fi
    
    aws rds create-global-cluster \
        --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
        --engine "${DB_ENGINE}" \
        --engine-version "${ENGINE_VERSION}" \
        --region "${PRIMARY_REGION}"
    
    log "Waiting for global database to become available..."
    aws rds wait global-cluster-available \
        --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
        --region "${PRIMARY_REGION}"
    
    log "✅ Global database ${GLOBAL_DB_IDENTIFIER} created successfully"
}

# Function to create primary cluster
create_primary_cluster() {
    log "Creating primary Aurora cluster..."
    
    if aws rds describe-db-clusters \
        --db-cluster-identifier "${PRIMARY_CLUSTER_ID}" \
        --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        warn "Primary cluster ${PRIMARY_CLUSTER_ID} already exists"
        return 0
    fi
    
    aws rds create-db-cluster \
        --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
        --db-cluster-identifier "${PRIMARY_CLUSTER_ID}" \
        --engine "${DB_ENGINE}" \
        --engine-version "${ENGINE_VERSION}" \
        --master-username "${MASTER_USERNAME}" \
        --master-user-password "${MASTER_PASSWORD}" \
        --backup-retention-period 7 \
        --preferred-backup-window "07:00-09:00" \
        --preferred-maintenance-window "sun:09:00-sun:11:00" \
        --region "${PRIMARY_REGION}"
    
    log "Waiting for primary cluster to become available..."
    aws rds wait db-cluster-available \
        --db-cluster-identifier "${PRIMARY_CLUSTER_ID}" \
        --region "${PRIMARY_REGION}"
    
    log "✅ Primary cluster ${PRIMARY_CLUSTER_ID} created successfully"
}

# Function to create cluster instances
create_cluster_instances() {
    local cluster_id=$1
    local region=$2
    local cluster_type=$3
    
    log "Creating database instances for ${cluster_type} cluster..."
    
    # Create writer instance
    if ! aws rds describe-db-instances \
        --db-instance-identifier "${cluster_id}-writer" \
        --region "${region}" >/dev/null 2>&1; then
        
        aws rds create-db-instance \
            --db-cluster-identifier "${cluster_id}" \
            --db-instance-identifier "${cluster_id}-writer" \
            --db-instance-class "${DB_INSTANCE_CLASS}" \
            --engine "${DB_ENGINE}" \
            --engine-version "${ENGINE_VERSION}" \
            --region "${region}"
    else
        warn "Writer instance for ${cluster_id} already exists"
    fi
    
    # Create reader instance
    if ! aws rds describe-db-instances \
        --db-instance-identifier "${cluster_id}-reader" \
        --region "${region}" >/dev/null 2>&1; then
        
        aws rds create-db-instance \
            --db-cluster-identifier "${cluster_id}" \
            --db-instance-identifier "${cluster_id}-reader" \
            --db-instance-class "${DB_INSTANCE_CLASS}" \
            --engine "${DB_ENGINE}" \
            --engine-version "${ENGINE_VERSION}" \
            --region "${region}"
    else
        warn "Reader instance for ${cluster_id} already exists"
    fi
    
    log "Waiting for instances to become available..."
    aws rds wait db-instance-available \
        --db-instance-identifier "${cluster_id}-writer" \
        --region "${region}"
    
    aws rds wait db-instance-available \
        --db-instance-identifier "${cluster_id}-reader" \
        --region "${region}"
    
    log "✅ ${cluster_type} cluster instances created successfully"
}

# Function to create secondary cluster
create_secondary_cluster() {
    local cluster_id=$1
    local region=$2
    local cluster_name=$3
    
    log "Creating ${cluster_name} secondary cluster..."
    
    if aws rds describe-db-clusters \
        --db-cluster-identifier "${cluster_id}" \
        --region "${region}" >/dev/null 2>&1; then
        warn "Secondary cluster ${cluster_id} already exists"
        return 0
    fi
    
    aws rds create-db-cluster \
        --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
        --db-cluster-identifier "${cluster_id}" \
        --engine "${DB_ENGINE}" \
        --engine-version "${ENGINE_VERSION}" \
        --enable-global-write-forwarding \
        --region "${region}"
    
    log "Waiting for ${cluster_name} secondary cluster to become available..."
    aws rds wait db-cluster-available \
        --db-cluster-identifier "${cluster_id}" \
        --region "${region}"
    
    log "✅ ${cluster_name} secondary cluster created successfully"
}

# Function to get database endpoints
get_database_endpoints() {
    log "Retrieving database endpoints..."
    
    PRIMARY_WRITER_ENDPOINT=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${PRIMARY_CLUSTER_ID}" \
        --query 'DBClusters[0].Endpoint' \
        --output text --region "${PRIMARY_REGION}")
    
    PRIMARY_READER_ENDPOINT=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${PRIMARY_CLUSTER_ID}" \
        --query 'DBClusters[0].ReaderEndpoint' \
        --output text --region "${PRIMARY_REGION}")
    
    SECONDARY_1_WRITER_ENDPOINT=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${SECONDARY_CLUSTER_1_ID}" \
        --query 'DBClusters[0].Endpoint' \
        --output text --region "${SECONDARY_REGION_1}")
    
    SECONDARY_2_WRITER_ENDPOINT=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${SECONDARY_CLUSTER_2_ID}" \
        --query 'DBClusters[0].Endpoint' \
        --output text --region "${SECONDARY_REGION_2}")
    
    # Save endpoints to configuration file
    cat >> ./.deployment-config << EOF
PRIMARY_WRITER_ENDPOINT=${PRIMARY_WRITER_ENDPOINT}
PRIMARY_READER_ENDPOINT=${PRIMARY_READER_ENDPOINT}
SECONDARY_1_WRITER_ENDPOINT=${SECONDARY_1_WRITER_ENDPOINT}
SECONDARY_2_WRITER_ENDPOINT=${SECONDARY_2_WRITER_ENDPOINT}
EOF
    
    log "Database endpoints retrieved:"
    info "Primary Writer: ${PRIMARY_WRITER_ENDPOINT}"
    info "Primary Reader: ${PRIMARY_READER_ENDPOINT}"
    info "EU Writer (with forwarding): ${SECONDARY_1_WRITER_ENDPOINT}"
    info "Asia Writer (with forwarding): ${SECONDARY_2_WRITER_ENDPOINT}"
}

# Function to configure database schema
configure_database_schema() {
    log "Configuring database schema and test data..."
    
    if ! check_mysql_client; then
        warn "Skipping database schema configuration - MySQL client not available"
        return 0
    fi
    
    # Wait for endpoints to be responsive
    log "Waiting for database to be ready for connections..."
    sleep 60
    
    # Create database schema with retry logic
    local retry_count=0
    local max_retries=5
    
    while [ $retry_count -lt $max_retries ]; do
        if mysql -h "${PRIMARY_WRITER_ENDPOINT}" \
            -u "${MASTER_USERNAME}" -p"${MASTER_PASSWORD}" \
            --connect-timeout=30 \
            --execute "
            CREATE DATABASE IF NOT EXISTS ecommerce;
            USE ecommerce;
            CREATE TABLE IF NOT EXISTS products (
                id INT PRIMARY KEY AUTO_INCREMENT,
                name VARCHAR(255) NOT NULL,
                price DECIMAL(10,2) NOT NULL,
                region VARCHAR(50) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            );
            INSERT IGNORE INTO products (name, price, region) VALUES
            ('Global Widget', 29.99, 'us-east-1'),
            ('International Gadget', 49.99, 'us-east-1');" 2>/dev/null; then
            
            log "✅ Database schema and test data created successfully"
            break
        else
            retry_count=$((retry_count + 1))
            warn "Database connection failed, retrying in 30 seconds... (${retry_count}/${max_retries})"
            sleep 30
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Failed to configure database schema after ${max_retries} attempts"
        return 1
    fi
}

# Function to test write forwarding
test_write_forwarding() {
    log "Testing write forwarding functionality..."
    
    if ! check_mysql_client; then
        warn "Skipping write forwarding test - MySQL client not available"
        return 0
    fi
    
    # Test write forwarding from European cluster
    if mysql -h "${SECONDARY_1_WRITER_ENDPOINT}" \
        -u "${MASTER_USERNAME}" -p"${MASTER_PASSWORD}" \
        --connect-timeout=30 \
        --execute "
        USE ecommerce;
        SET SESSION aurora_replica_read_consistency = 'session';
        INSERT INTO products (name, price, region) 
        VALUES ('European Product', 39.99, 'eu-west-1');" 2>/dev/null; then
        
        log "✅ Write forwarding test from EU region successful"
    else
        warn "Write forwarding test from EU region failed"
    fi
    
    # Test write forwarding from Asian cluster
    if mysql -h "${SECONDARY_2_WRITER_ENDPOINT}" \
        -u "${MASTER_USERNAME}" -p"${MASTER_PASSWORD}" \
        --connect-timeout=30 \
        --execute "
        USE ecommerce;
        SET SESSION aurora_replica_read_consistency = 'session';
        INSERT INTO products (name, price, region) 
        VALUES ('Asian Product', 59.99, 'ap-southeast-1');" 2>/dev/null; then
        
        log "✅ Write forwarding test from Asia region successful"
    else
        warn "Write forwarding test from Asia region failed"
    fi
}

# Function to enable enhanced monitoring
enable_enhanced_monitoring() {
    log "Enabling enhanced monitoring and Performance Insights..."
    
    # Enable Performance Insights for primary cluster writer
    aws rds modify-db-instance \
        --db-instance-identifier "${PRIMARY_CLUSTER_ID}-writer" \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --region "${PRIMARY_REGION}" >/dev/null 2>&1 || warn "Failed to enable Performance Insights for primary cluster"
    
    # Enable Performance Insights for secondary clusters
    aws rds modify-db-instance \
        --db-instance-identifier "${SECONDARY_CLUSTER_1_ID}-writer" \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --region "${SECONDARY_REGION_1}" >/dev/null 2>&1 || warn "Failed to enable Performance Insights for EU cluster"
    
    aws rds modify-db-instance \
        --db-instance-identifier "${SECONDARY_CLUSTER_2_ID}-writer" \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --region "${SECONDARY_REGION_2}" >/dev/null 2>&1 || warn "Failed to enable Performance Insights for Asia cluster"
    
    log "✅ Enhanced monitoring configuration completed"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating CloudWatch monitoring dashboard..."
    
    # Create dashboard JSON
    cat > ./global-db-dashboard.json << EOF
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
                    ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", "${PRIMARY_CLUSTER_ID}"],
                    ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", "${SECONDARY_CLUSTER_1_ID}"],
                    ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", "${SECONDARY_CLUSTER_2_ID}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${PRIMARY_REGION}",
                "title": "Global Database Connections"
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
                    ["AWS/RDS", "AuroraGlobalDBReplicationLag", "DBClusterIdentifier", "${SECONDARY_CLUSTER_1_ID}"],
                    ["AWS/RDS", "AuroraGlobalDBReplicationLag", "DBClusterIdentifier", "${SECONDARY_CLUSTER_2_ID}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${PRIMARY_REGION}",
                "title": "Global Database Replication Lag"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "${PRIMARY_CLUSTER_ID}"],
                    ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "${SECONDARY_CLUSTER_1_ID}"],
                    ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", "${SECONDARY_CLUSTER_2_ID}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${PRIMARY_REGION}",
                "title": "CPU Utilization Across All Clusters"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    local dashboard_name="Aurora-Global-Database-$(echo ${GLOBAL_DB_IDENTIFIER} | cut -d'-' -f4)"
    aws cloudwatch put-dashboard \
        --dashboard-name "${dashboard_name}" \
        --dashboard-body file://global-db-dashboard.json \
        --region "${PRIMARY_REGION}"
    
    # Save dashboard name to config
    echo "DASHBOARD_NAME=${dashboard_name}" >> ./.deployment-config
    
    log "✅ Monitoring dashboard '${dashboard_name}' created successfully"
    
    # Clean up temporary file
    rm -f ./global-db-dashboard.json
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check global database status
    local global_status
    global_status=$(aws rds describe-global-clusters \
        --global-cluster-identifier "${GLOBAL_DB_IDENTIFIER}" \
        --query 'GlobalClusters[0].Status' \
        --output text --region "${PRIMARY_REGION}")
    
    if [ "${global_status}" != "available" ]; then
        error "Global database is not in available state: ${global_status}"
        return 1
    fi
    
    # Check write forwarding status
    local eu_write_forwarding
    local asia_write_forwarding
    
    eu_write_forwarding=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${SECONDARY_CLUSTER_1_ID}" \
        --query 'DBClusters[0].GlobalWriteForwardingStatus' \
        --output text --region "${SECONDARY_REGION_1}")
    
    asia_write_forwarding=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${SECONDARY_CLUSTER_2_ID}" \
        --query 'DBClusters[0].GlobalWriteForwardingStatus' \
        --output text --region "${SECONDARY_REGION_2}")
    
    if [ "${eu_write_forwarding}" != "enabled" ] || [ "${asia_write_forwarding}" != "enabled" ]; then
        error "Write forwarding is not enabled on all secondary clusters"
        return 1
    fi
    
    log "✅ Deployment validation completed successfully"
    return 0
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    info "Global Database: ${GLOBAL_DB_IDENTIFIER}"
    info "Primary Cluster: ${PRIMARY_CLUSTER_ID} (${PRIMARY_REGION})"
    info "Secondary Cluster 1: ${SECONDARY_CLUSTER_1_ID} (${SECONDARY_REGION_1})"
    info "Secondary Cluster 2: ${SECONDARY_CLUSTER_2_ID} (${SECONDARY_REGION_2})"
    echo ""
    info "Database Endpoints:"
    info "  Primary Writer: ${PRIMARY_WRITER_ENDPOINT}"
    info "  Primary Reader: ${PRIMARY_READER_ENDPOINT}"
    info "  EU Writer (with forwarding): ${SECONDARY_1_WRITER_ENDPOINT}"
    info "  Asia Writer (with forwarding): ${SECONDARY_2_WRITER_ENDPOINT}"
    echo ""
    info "Master Username: ${MASTER_USERNAME}"
    info "Master Password: [Stored in deployment config]"
    echo ""
    warn "IMPORTANT: Save the deployment configuration file (.deployment-config) for cleanup!"
    warn "Estimated monthly cost: $500-800 for all regions and instances"
}

# Main deployment function
main() {
    log "Starting Aurora Global Database deployment..."
    
    # Check prerequisites
    check_aws_cli
    check_permissions
    
    # Setup environment
    setup_environment
    
    # Create global database infrastructure
    create_global_database
    create_primary_cluster
    create_cluster_instances "${PRIMARY_CLUSTER_ID}" "${PRIMARY_REGION}" "primary"
    
    # Create secondary clusters
    create_secondary_cluster "${SECONDARY_CLUSTER_1_ID}" "${SECONDARY_REGION_1}" "European"
    create_cluster_instances "${SECONDARY_CLUSTER_1_ID}" "${SECONDARY_REGION_1}" "European secondary"
    
    create_secondary_cluster "${SECONDARY_CLUSTER_2_ID}" "${SECONDARY_REGION_2}" "Asian"
    create_cluster_instances "${SECONDARY_CLUSTER_2_ID}" "${SECONDARY_REGION_2}" "Asian secondary"
    
    # Configure database and monitoring
    get_database_endpoints
    configure_database_schema
    test_write_forwarding
    enable_enhanced_monitoring
    create_monitoring_dashboard
    
    # Validate and summarize
    if validate_deployment; then
        display_summary
        log "✅ Aurora Global Database deployment completed successfully!"
    else
        error "Deployment validation failed. Please check the logs and resolve any issues."
        exit 1
    fi
}

# Handle script interruption
trap 'error "Script interrupted. Please run destroy.sh to clean up resources."; exit 1' INT TERM

# Run main deployment
main "$@"