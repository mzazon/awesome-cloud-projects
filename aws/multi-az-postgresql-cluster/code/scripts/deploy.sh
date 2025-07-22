#!/bin/bash

#####################################################################
# AWS High-Availability PostgreSQL Cluster Deployment Script      #
# Recipe: Building High-Availability PostgreSQL Clusters with RDS  #
# Version: 1.1                                                     #
# Last Updated: 2025-07-12                                         #
#####################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for script interruption
cleanup() {
    log_warning "Script interrupted. Some resources may have been created."
    log_info "Run destroy.sh to clean up any created resources."
    exit 1
}

trap cleanup SIGINT SIGTERM

# Banner
show_banner() {
    echo "================================================================="
    echo "  AWS High-Availability PostgreSQL Cluster Deployment"
    echo "================================================================="
    echo ""
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required environment variables
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            error_exit "AWS_REGION is not set and no default region configured."
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Cost warning
show_cost_warning() {
    echo ""
    log_warning "COST WARNING: This deployment will create production-grade resources"
    log_warning "Estimated monthly cost: $200-500 depending on instance types"
    log_warning "Resources include:"
    log_warning "  - Multi-AZ RDS PostgreSQL instances (primary + standby)"
    log_warning "  - Read replicas (local + cross-region)"
    log_warning "  - RDS Proxy for connection pooling"
    log_warning "  - CloudWatch monitoring and SNS notifications"
    echo ""
    
    read -p "Do you want to continue with deployment? (yes/no): " confirm
    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Initialize environment variables
initialize_environment() {
    log_info "Initializing environment variables..."
    
    # Set AWS environment
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    # Core cluster configuration
    export CLUSTER_NAME="postgresql-ha-${random_suffix}"
    export DB_NAME="productiondb"
    export MASTER_USERNAME="dbadmin"
    
    # Generate secure password if not provided
    if [[ -z "${MASTER_PASSWORD:-}" ]]; then
        export MASTER_PASSWORD=$(aws secretsmanager get-random-password \
            --password-length 16 --exclude-characters '"@/\' \
            --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "SecurePassword123!")
    fi
    
    # Resource names
    export SUBNET_GROUP_NAME="postgresql-subnet-group-${random_suffix}"
    export PARAMETER_GROUP_NAME="postgresql-params-${random_suffix}"
    export SECURITY_GROUP_NAME="postgresql-sg-${random_suffix}"
    export SNS_TOPIC_NAME="postgresql-alerts-${random_suffix}"
    
    # Network configuration
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    
    if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
        error_exit "No default VPC found. Please create a VPC first."
    fi
    
    # Get subnet IDs across multiple AZs
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[0:3].SubnetId' --output text 2>/dev/null)
    
    if [[ -z "$SUBNET_IDS" ]]; then
        error_exit "No subnets found in VPC $VPC_ID"
    fi
    
    # Validate we have at least 2 subnets for Multi-AZ
    local subnet_count=$(echo $SUBNET_IDS | wc -w)
    if [[ $subnet_count -lt 2 ]]; then
        error_exit "At least 2 subnets required for Multi-AZ deployment. Found: $subnet_count"
    fi
    
    log_success "Environment initialized successfully"
    log_info "Cluster Name: $CLUSTER_NAME"
    log_info "VPC ID: $VPC_ID"
    log_info "Using $subnet_count subnets across AZs"
}

# Create RDS monitoring role
create_monitoring_role() {
    log_info "Creating RDS monitoring role..."
    
    local role_name="rds-monitoring-role"
    
    # Check if role already exists
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_info "RDS monitoring role already exists"
        return 0
    fi
    
    # Create the role
    aws iam create-role \
        --role-name "$role_name" \
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
        }' &> /dev/null
    
    # Attach the policy
    aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole" &> /dev/null
    
    # Wait for role to be ready
    sleep 10
    
    log_success "RDS monitoring role created"
}

# Create database subnet group
create_subnet_group() {
    log_info "Creating database subnet group..."
    
    aws rds create-db-subnet-group \
        --db-subnet-group-name "$SUBNET_GROUP_NAME" \
        --db-subnet-group-description "PostgreSQL HA subnet group" \
        --subnet-ids $SUBNET_IDS &> /dev/null
    
    log_success "Database subnet group created: $SUBNET_GROUP_NAME"
}

# Create security group
create_security_group() {
    log_info "Creating security group for PostgreSQL..."
    
    export SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "Security group for PostgreSQL HA cluster" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' --output text)
    
    # Allow PostgreSQL access from within VPC
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 5432 \
        --source-group "$SECURITY_GROUP_ID" &> /dev/null
    
    # Allow access from application subnets
    aws ec2 authorize-security-group-ingress \
        --group-id "$SECURITY_GROUP_ID" \
        --protocol tcp \
        --port 5432 \
        --cidr "10.0.0.0/16" &> /dev/null
    
    log_success "Security group created: $SECURITY_GROUP_ID"
}

# Create parameter group
create_parameter_group() {
    log_info "Creating custom parameter group..."
    
    aws rds create-db-parameter-group \
        --db-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --db-parameter-group-family "postgres15" \
        --description "Optimized PostgreSQL parameters for HA" &> /dev/null
    
    # Configure performance and logging parameters
    aws rds modify-db-parameter-group \
        --db-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --parameters "ParameterName=log_statement,ParameterValue=all,ApplyMethod=pending-reboot" \
                    "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=pending-reboot" \
                    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot" \
                    "ParameterName=track_activity_query_size,ParameterValue=2048,ApplyMethod=pending-reboot" \
                    "ParameterName=max_connections,ParameterValue=200,ApplyMethod=pending-reboot" &> /dev/null
    
    log_success "Parameter group created: $PARAMETER_GROUP_NAME"
}

# Create SNS topic
create_sns_topic() {
    log_info "Creating SNS topic for alerts..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query 'TopicArn' --output text)
    
    log_success "SNS topic created: $SNS_TOPIC_ARN"
    log_info "To receive email notifications, subscribe manually:"
    log_info "aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
}

# Create primary PostgreSQL instance
create_primary_instance() {
    log_info "Creating primary PostgreSQL instance with Multi-AZ..."
    
    aws rds create-db-instance \
        --db-instance-identifier "${CLUSTER_NAME}-primary" \
        --db-instance-class "db.r6g.large" \
        --engine "postgres" \
        --engine-version "15.4" \
        --master-username "$MASTER_USERNAME" \
        --master-user-password "$MASTER_PASSWORD" \
        --allocated-storage 200 \
        --storage-type "gp3" \
        --storage-encrypted \
        --multi-az \
        --db-subnet-group-name "$SUBNET_GROUP_NAME" \
        --vpc-security-group-ids "$SECURITY_GROUP_ID" \
        --db-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --backup-retention-period 35 \
        --preferred-backup-window "03:00-04:00" \
        --preferred-maintenance-window "sun:04:00-sun:05:00" \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --monitoring-interval 60 \
        --monitoring-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/rds-monitoring-role" \
        --enable-cloudwatch-logs-exports postgresql \
        --deletion-protection \
        --copy-tags-to-snapshot &> /dev/null
    
    log_success "Primary instance creation initiated"
    
    # Wait for instance to be available
    log_info "Waiting for primary instance to become available (this may take 10-15 minutes)..."
    aws rds wait db-instance-available --db-instance-identifier "${CLUSTER_NAME}-primary"
    
    log_success "Primary PostgreSQL instance is now available"
}

# Create read replica
create_read_replica() {
    log_info "Creating read replica..."
    
    aws rds create-db-instance-read-replica \
        --db-instance-identifier "${CLUSTER_NAME}-read-replica-1" \
        --source-db-instance-identifier "${CLUSTER_NAME}-primary" \
        --db-instance-class "db.r6g.large" \
        --publicly-accessible false \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --monitoring-interval 60 \
        --monitoring-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/rds-monitoring-role" &> /dev/null
    
    log_success "Read replica creation initiated"
    
    # Wait for replica to be available
    log_info "Waiting for read replica to become available..."
    aws rds wait db-instance-available --db-instance-identifier "${CLUSTER_NAME}-read-replica-1"
    
    log_success "Read replica is now available"
}

# Create cross-region read replica
create_cross_region_replica() {
    log_info "Creating cross-region disaster recovery replica..."
    
    aws rds create-db-instance-read-replica \
        --db-instance-identifier "${CLUSTER_NAME}-dr-replica" \
        --source-db-instance-identifier "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:db:${CLUSTER_NAME}-primary" \
        --db-instance-class "db.r6g.large" \
        --region us-west-2 \
        --publicly-accessible false \
        --enable-performance-insights \
        --performance-insights-retention-period 7 &> /dev/null
    
    log_success "Cross-region replica creation initiated"
    
    # Wait for cross-region replica
    log_info "Waiting for cross-region replica to become available..."
    aws rds wait db-instance-available \
        --db-instance-identifier "${CLUSTER_NAME}-dr-replica" \
        --region us-west-2
    
    log_success "Cross-region replica is now available"
}

# Setup backup replication
setup_backup_replication() {
    log_info "Enabling automated backup replication..."
    
    aws rds start-db-instance-automated-backups-replication \
        --source-db-instance-arn "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:db:${CLUSTER_NAME}-primary" \
        --backup-retention-period 35 \
        --region us-west-2 &> /dev/null
    
    log_success "Automated backup replication enabled"
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    log_info "Creating CloudWatch alarms..."
    
    # CPU utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CLUSTER_NAME}-cpu-high" \
        --alarm-description "PostgreSQL CPU utilization high" \
        --metric-name CPUUtilization \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=DBInstanceIdentifier,Value="${CLUSTER_NAME}-primary" &> /dev/null
    
    # Database connection alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CLUSTER_NAME}-connections-high" \
        --alarm-description "PostgreSQL connection count high" \
        --metric-name DatabaseConnections \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 150 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=DBInstanceIdentifier,Value="${CLUSTER_NAME}-primary" &> /dev/null
    
    # Read replica lag alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CLUSTER_NAME}-replica-lag-high" \
        --alarm-description "PostgreSQL read replica lag high" \
        --metric-name ReplicaLag \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 30 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=DBInstanceIdentifier,Value="${CLUSTER_NAME}-read-replica-1" &> /dev/null
    
    log_success "CloudWatch alarms created"
}

# Create manual snapshot
create_manual_snapshot() {
    log_info "Creating initial manual snapshot..."
    
    local snapshot_id="${CLUSTER_NAME}-initial-snapshot-$(date +%Y%m%d)"
    
    aws rds create-db-snapshot \
        --db-instance-identifier "${CLUSTER_NAME}-primary" \
        --db-snapshot-identifier "$snapshot_id" &> /dev/null
    
    log_success "Manual snapshot creation initiated: $snapshot_id"
    
    # Wait for snapshot to complete
    log_info "Waiting for snapshot to complete..."
    aws rds wait db-snapshot-completed --db-snapshot-identifier "$snapshot_id"
    
    log_success "Manual snapshot completed"
}

# Configure event notifications
configure_event_notifications() {
    log_info "Configuring event notifications..."
    
    aws rds create-event-subscription \
        --subscription-name "${CLUSTER_NAME}-events" \
        --sns-topic-arn "$SNS_TOPIC_ARN" \
        --source-type db-instance \
        --source-ids "${CLUSTER_NAME}-primary" "${CLUSTER_NAME}-read-replica-1" \
        --event-categories "availability" "backup" "configuration change" \
                           "creation" "deletion" "failover" "failure" \
                           "low storage" "maintenance" "notification" \
                           "recovery" "restoration" &> /dev/null
    
    log_success "Event notifications configured"
}

# Setup RDS Proxy
setup_rds_proxy() {
    log_info "Setting up RDS Proxy for connection pooling..."
    
    # Create IAM role for RDS Proxy
    local proxy_role="rds-proxy-role-$(echo $CLUSTER_NAME | cut -d'-' -f3)"
    
    aws iam create-role \
        --role-name "$proxy_role" \
        --assume-role-policy-document '{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "Service": "rds.amazonaws.com"
              },
              "Action": "sts:AssumeRole"
            }
          ]
        }' &> /dev/null
    
    # Attach policy
    aws iam attach-role-policy \
        --role-name "$proxy_role" \
        --policy-arn "arn:aws:iam::aws:policy/SecretsManagerReadWrite" &> /dev/null
    
    # Create secret for credentials
    local secret_arn=$(aws secretsmanager create-secret \
        --name "${CLUSTER_NAME}-credentials" \
        --description "PostgreSQL credentials for RDS Proxy" \
        --secret-string "{\"username\":\"${MASTER_USERNAME}\",\"password\":\"${MASTER_PASSWORD}\"}" \
        --query 'ARN' --output text)
    
    # Wait for role propagation
    sleep 30
    
    # Create RDS Proxy
    aws rds create-db-proxy \
        --db-proxy-name "${CLUSTER_NAME}-proxy" \
        --engine-family POSTGRESQL \
        --auth Description="PostgreSQL authentication",AuthScheme=SECRETS,SecretArn="$secret_arn" \
        --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/$proxy_role" \
        --vpc-subnet-ids $SUBNET_IDS \
        --vpc-security-group-ids "$SECURITY_GROUP_ID" \
        --require-tls \
        --idle-client-timeout 1800 \
        --max-connections-percent 100 \
        --max-idle-connections-percent 50 &> /dev/null
    
    log_success "RDS Proxy created for connection pooling"
}

# Display deployment summary
show_deployment_summary() {
    echo ""
    echo "================================================================="
    echo "  Deployment Summary"
    echo "================================================================="
    
    # Get endpoints
    local primary_endpoint=$(aws rds describe-db-instances \
        --db-instance-identifier "${CLUSTER_NAME}-primary" \
        --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null || echo "Not available")
    
    local read_endpoint=$(aws rds describe-db-instances \
        --db-instance-identifier "${CLUSTER_NAME}-read-replica-1" \
        --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null || echo "Not available")
    
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Primary Endpoint: $primary_endpoint"
    echo "Read Replica Endpoint: $read_endpoint"
    echo "Database Name: $DB_NAME"
    echo "Master Username: $MASTER_USERNAME"
    echo "Master Password: $MASTER_PASSWORD"
    echo ""
    echo "Connection String:"
    echo "psql -h $primary_endpoint -U $MASTER_USERNAME -d $DB_NAME"
    echo ""
    echo "SNS Topic ARN: $SNS_TOPIC_ARN"
    echo ""
    echo "Next Steps:"
    echo "1. Subscribe to SNS topic for notifications"
    echo "2. Configure application connection strings"
    echo "3. Test failover capabilities"
    echo "4. Monitor CloudWatch dashboards"
    echo ""
    echo "Important: Save the master password securely!"
    echo "================================================================="
}

# Save deployment information
save_deployment_info() {
    local info_file="postgresql-ha-deployment.txt"
    
    cat > "$info_file" << EOF
PostgreSQL HA Cluster Deployment Information
Generated: $(date)

Cluster Name: $CLUSTER_NAME
AWS Region: $AWS_REGION
VPC ID: $VPC_ID

Database Configuration:
- Database Name: $DB_NAME
- Master Username: $MASTER_USERNAME
- Master Password: $MASTER_PASSWORD

Resource Names:
- Subnet Group: $SUBNET_GROUP_NAME
- Parameter Group: $PARAMETER_GROUP_NAME
- Security Group: $SECURITY_GROUP_ID
- SNS Topic: $SNS_TOPIC_ARN

Connection Information:
- Primary Instance: ${CLUSTER_NAME}-primary
- Read Replica: ${CLUSTER_NAME}-read-replica-1
- Cross-Region Replica: ${CLUSTER_NAME}-dr-replica (us-west-2)
- RDS Proxy: ${CLUSTER_NAME}-proxy

CloudWatch Alarms:
- ${CLUSTER_NAME}-cpu-high
- ${CLUSTER_NAME}-connections-high
- ${CLUSTER_NAME}-replica-lag-high

Event Subscription: ${CLUSTER_NAME}-events

IMPORTANT: Keep this file secure as it contains sensitive information!
EOF

    log_success "Deployment information saved to $info_file"
}

# Main deployment function
main() {
    show_banner
    check_prerequisites
    show_cost_warning
    
    log_info "Starting PostgreSQL HA cluster deployment..."
    
    # Core setup
    initialize_environment
    create_monitoring_role
    create_subnet_group
    create_security_group
    create_parameter_group
    create_sns_topic
    
    # Database instances
    create_primary_instance
    create_read_replica
    create_cross_region_replica
    
    # Additional features
    setup_backup_replication
    create_cloudwatch_alarms
    create_manual_snapshot
    configure_event_notifications
    setup_rds_proxy
    
    # Finalization
    show_deployment_summary
    save_deployment_info
    
    log_success "PostgreSQL HA cluster deployment completed successfully!"
    log_info "Total deployment time: Approximately 20-30 minutes"
    log_warning "Remember to clean up resources using destroy.sh when no longer needed"
}

# Run main function
main "$@"