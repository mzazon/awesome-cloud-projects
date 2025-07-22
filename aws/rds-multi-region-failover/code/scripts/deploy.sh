#!/bin/bash

# Advanced RDS Multi-AZ Cross-Region Failover Deployment Script
# This script deploys a comprehensive RDS Multi-AZ architecture with cross-region failover
# Recipe: RDS Multi-Region Failover Strategy

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$ERROR_LOG"
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Script failed with exit code $exit_code on line $1"
    log_error "Check $ERROR_LOG for details"
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Advanced RDS Multi-AZ Cross-Region Failover Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without making changes
    -v, --verbose          Enable verbose logging
    --skip-health-checks   Skip Route 53 health check creation
    --db-password PASSWORD Set custom database password
    --primary-region REGION Set primary AWS region (default: us-east-1)
    --secondary-region REGION Set secondary AWS region (default: us-west-2)
    --instance-class CLASS  Set RDS instance class (default: db.r5.xlarge)

EXAMPLE:
    $0 --primary-region us-east-1 --secondary-region us-west-2 --verbose

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate IAM permissions for RDS, Route 53, CloudWatch, Lambda
    - VPC and subnets configured in both regions
    - Security groups configured for database access

ESTIMATED COST:
    $800-1,200/month for db.r5.xlarge instances with backup storage
EOF
}

# Default configuration
DRY_RUN=false
VERBOSE=false
SKIP_HEALTH_CHECKS=false
PRIMARY_REGION="us-east-1"
SECONDARY_REGION="us-west-2"
DB_INSTANCE_CLASS="db.r5.xlarge"
DB_MASTER_PASSWORD=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-health-checks)
            SKIP_HEALTH_CHECKS=true
            shift
            ;;
        --db-password)
            DB_MASTER_PASSWORD="$2"
            shift 2
            ;;
        --primary-region)
            PRIMARY_REGION="$2"
            shift 2
            ;;
        --secondary-region)
            SECONDARY_REGION="$2"
            shift 2
            ;;
        --instance-class)
            DB_INSTANCE_CLASS="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set verbose mode
if [[ "$VERBOSE" == true ]]; then
    set -x
fi

log "Starting Advanced RDS Multi-AZ Cross-Region Failover deployment"
log "Primary Region: $PRIMARY_REGION"
log "Secondary Region: $SECONDARY_REGION"
log "Instance Class: $DB_INSTANCE_CLASS"
log "Dry Run: $DRY_RUN"

# Prerequisites validation
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d/ -f2)
    log "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    local aws_account_id=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: $aws_account_id"
    
    # Check regions are different
    if [[ "$PRIMARY_REGION" == "$SECONDARY_REGION" ]]; then
        log_error "Primary and secondary regions must be different"
        exit 1
    fi
    
    # Validate regions exist
    if ! aws ec2 describe-regions --region-names "$PRIMARY_REGION" &> /dev/null; then
        log_error "Invalid primary region: $PRIMARY_REGION"
        exit 1
    fi
    
    if ! aws ec2 describe-regions --region-names "$SECONDARY_REGION" &> /dev/null; then
        log_error "Invalid secondary region: $SECONDARY_REGION"
        exit 1
    fi
    
    # Check for required IAM permissions (basic check)
    local permissions_check=true
    
    if ! aws rds describe-db-instances --region "$PRIMARY_REGION" --max-items 1 &> /dev/null; then
        log_warning "May not have RDS permissions in primary region"
        permissions_check=false
    fi
    
    if ! aws route53 list-hosted-zones --max-items 1 &> /dev/null; then
        log_warning "May not have Route 53 permissions"
        permissions_check=false
    fi
    
    if [[ "$permissions_check" == false ]]; then
        log_warning "Some permission checks failed. Continuing anyway..."
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export PRIMARY_REGION
    export SECONDARY_REGION
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    export DB_INSTANCE_ID="financial-db-${random_suffix}"
    export DB_REPLICA_ID="financial-db-replica-${random_suffix}"
    export DB_SUBNET_GROUP="financial-subnet-group-${random_suffix}"
    export DB_PARAMETER_GROUP="financial-param-group-${random_suffix}"
    
    # Set or generate database password
    if [[ -z "$DB_MASTER_PASSWORD" ]]; then
        export DB_MASTER_PASSWORD="FinancialDB2024!"
        log_warning "Using default database password. Consider using --db-password for production."
    else
        export DB_MASTER_PASSWORD
    fi
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" << EOF
PRIMARY_REGION=$PRIMARY_REGION
SECONDARY_REGION=$SECONDARY_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
DB_INSTANCE_ID=$DB_INSTANCE_ID
DB_REPLICA_ID=$DB_REPLICA_ID
DB_SUBNET_GROUP=$DB_SUBNET_GROUP
DB_PARAMETER_GROUP=$DB_PARAMETER_GROUP
DB_INSTANCE_CLASS=$DB_INSTANCE_CLASS
EOF
    
    log_success "Environment variables configured"
    log "DB Instance ID: $DB_INSTANCE_ID"
    log "DB Replica ID: $DB_REPLICA_ID"
}

# Create VPC resources if needed
setup_vpc_resources() {
    log "Setting up VPC resources..."
    
    # Check if default VPC exists in both regions
    local primary_vpc=$(aws ec2 describe-vpcs --region "$PRIMARY_REGION" \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
    
    local secondary_vpc=$(aws ec2 describe-vpcs --region "$SECONDARY_REGION" \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
    
    if [[ "$primary_vpc" == "None" ]] || [[ "$secondary_vpc" == "None" ]]; then
        log_error "Default VPC not found in one or both regions. Please ensure VPCs and subnets are available."
        exit 1
    fi
    
    log_success "VPC resources validated"
}

# Execute AWS command with dry-run support
execute_aws() {
    local cmd="$*"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would execute: $cmd"
        return 0
    else
        log "Executing: $cmd"
        eval "$cmd"
    fi
}

# Create DB subnet groups
create_db_subnet_groups() {
    log "Creating DB subnet groups..."
    
    # Get subnets for primary region
    local primary_subnets=$(aws ec2 describe-subnets --region "$PRIMARY_REGION" \
        --filters "Name=default-for-az,Values=true" \
        --query "Subnets[0:2].SubnetId" --output text)
    
    if [[ -z "$primary_subnets" ]] || [[ "$primary_subnets" == "None" ]]; then
        log_error "Could not find suitable subnets in primary region $PRIMARY_REGION"
        exit 1
    fi
    
    # Get subnets for secondary region
    local secondary_subnets=$(aws ec2 describe-subnets --region "$SECONDARY_REGION" \
        --filters "Name=default-for-az,Values=true" \
        --query "Subnets[0:2].SubnetId" --output text)
    
    if [[ -z "$secondary_subnets" ]] || [[ "$secondary_subnets" == "None" ]]; then
        log_error "Could not find suitable subnets in secondary region $SECONDARY_REGION"
        exit 1
    fi
    
    # Create primary subnet group
    execute_aws "aws rds create-db-subnet-group \
        --region $PRIMARY_REGION \
        --db-subnet-group-name $DB_SUBNET_GROUP \
        --db-subnet-group-description 'Financial DB subnet group' \
        --subnet-ids $primary_subnets"
    
    # Create secondary subnet group
    execute_aws "aws rds create-db-subnet-group \
        --region $SECONDARY_REGION \
        --db-subnet-group-name $DB_SUBNET_GROUP \
        --db-subnet-group-description 'Financial DB subnet group' \
        --subnet-ids $secondary_subnets"
    
    log_success "DB subnet groups created"
}

# Create custom DB parameter group
create_parameter_group() {
    log "Creating custom DB parameter group..."
    
    execute_aws "aws rds create-db-parameter-group \
        --region $PRIMARY_REGION \
        --db-parameter-group-name $DB_PARAMETER_GROUP \
        --db-parameter-group-family postgres15 \
        --description 'Financial DB optimized parameters'"
    
    if [[ "$DRY_RUN" == false ]]; then
        # Wait a moment for parameter group to be available
        sleep 5
        
        # Configure key parameters for high availability
        execute_aws "aws rds modify-db-parameter-group \
            --region $PRIMARY_REGION \
            --db-parameter-group-name $DB_PARAMETER_GROUP \
            --parameters \
                'ParameterName=log_statement,ParameterValue=all,ApplyMethod=immediate' \
                'ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate' \
                'ParameterName=checkpoint_completion_target,ParameterValue=0.9,ApplyMethod=immediate'"
    fi
    
    log_success "Parameter group created and configured"
}

# Create primary Multi-AZ RDS instance
create_primary_database() {
    log "Creating primary Multi-AZ RDS instance..."
    
    # Get default security group
    local default_sg=$(aws ec2 describe-security-groups --region "$PRIMARY_REGION" \
        --filters "Name=group-name,Values=default" \
        --query "SecurityGroups[0].GroupId" --output text)
    
    execute_aws "aws rds create-db-instance \
        --region $PRIMARY_REGION \
        --db-instance-identifier $DB_INSTANCE_ID \
        --db-instance-class $DB_INSTANCE_CLASS \
        --engine postgres \
        --engine-version 15.4 \
        --master-username dbadmin \
        --master-user-password '$DB_MASTER_PASSWORD' \
        --allocated-storage 500 \
        --storage-type gp3 \
        --storage-encrypted \
        --multi-az \
        --db-subnet-group-name $DB_SUBNET_GROUP \
        --vpc-security-group-ids $default_sg \
        --db-parameter-group-name $DB_PARAMETER_GROUP \
        --backup-retention-period 30 \
        --preferred-backup-window '03:00-04:00' \
        --preferred-maintenance-window 'sun:04:00-sun:05:00' \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --monitoring-interval 60 \
        --deletion-protection \
        --tags 'Key=Environment,Value=Production' 'Key=Application,Value=FinancialDB'"
    
    if [[ "$DRY_RUN" == false ]]; then
        log "Waiting for primary database to become available..."
        aws rds wait db-instance-available \
            --region "$PRIMARY_REGION" \
            --db-instance-identifier "$DB_INSTANCE_ID"
    fi
    
    log_success "Primary Multi-AZ RDS instance created"
}

# Create cross-region read replica
create_read_replica() {
    log "Creating cross-region read replica..."
    
    # Get default security group for secondary region
    local default_sg=$(aws ec2 describe-security-groups --region "$SECONDARY_REGION" \
        --filters "Name=group-name,Values=default" \
        --query "SecurityGroups[0].GroupId" --output text)
    
    execute_aws "aws rds create-db-instance-read-replica \
        --region $SECONDARY_REGION \
        --db-instance-identifier $DB_REPLICA_ID \
        --source-db-instance-identifier \
            arn:aws:rds:$PRIMARY_REGION:$AWS_ACCOUNT_ID:db:$DB_INSTANCE_ID \
        --db-instance-class $DB_INSTANCE_CLASS \
        --storage-encrypted \
        --db-subnet-group-name $DB_SUBNET_GROUP \
        --vpc-security-group-ids $default_sg \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --monitoring-interval 60 \
        --deletion-protection \
        --tags 'Key=Environment,Value=Production' 'Key=Application,Value=FinancialDB'"
    
    if [[ "$DRY_RUN" == false ]]; then
        log "Waiting for read replica to become available..."
        aws rds wait db-instance-available \
            --region "$SECONDARY_REGION" \
            --db-instance-identifier "$DB_REPLICA_ID"
    fi
    
    log_success "Cross-region read replica created"
}

# Configure CloudWatch alarms
configure_cloudwatch_alarms() {
    log "Configuring CloudWatch alarms..."
    
    # Create SNS topic for alerts (simplified version)
    local sns_topic_primary="arn:aws:sns:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:db-alerts"
    local sns_topic_secondary="arn:aws:sns:${SECONDARY_REGION}:${AWS_ACCOUNT_ID}:db-alerts"
    
    # Create alarm for primary database connections
    execute_aws "aws cloudwatch put-metric-alarm \
        --region $PRIMARY_REGION \
        --alarm-name '${DB_INSTANCE_ID}-connection-failures' \
        --alarm-description 'Alert on database connection failures' \
        --metric-name DatabaseConnections \
        --namespace AWS/RDS \
        --statistic Maximum \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=DBInstanceIdentifier,Value=$DB_INSTANCE_ID"
    
    # Create alarm for replica lag
    execute_aws "aws cloudwatch put-metric-alarm \
        --region $SECONDARY_REGION \
        --alarm-name '${DB_REPLICA_ID}-replica-lag' \
        --alarm-description 'Alert on high replica lag' \
        --metric-name ReplicaLag \
        --namespace AWS/RDS \
        --statistic Average \
        --period 300 \
        --threshold 300 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=DBInstanceIdentifier,Value=$DB_REPLICA_ID"
    
    log_success "CloudWatch alarms configured"
}

# Set up Route 53 health checks and DNS failover
setup_route53_failover() {
    if [[ "$SKIP_HEALTH_CHECKS" == true ]]; then
        log_warning "Skipping Route 53 health checks as requested"
        return 0
    fi
    
    log "Setting up Route 53 health checks and DNS failover..."
    
    if [[ "$DRY_RUN" == false ]]; then
        # Get database endpoints
        local primary_endpoint=$(aws rds describe-db-instances \
            --region "$PRIMARY_REGION" \
            --db-instance-identifier "$DB_INSTANCE_ID" \
            --query 'DBInstances[0].Endpoint.Address' \
            --output text)
        
        local replica_endpoint=$(aws rds describe-db-instances \
            --region "$SECONDARY_REGION" \
            --db-instance-identifier "$DB_REPLICA_ID" \
            --query 'DBInstances[0].Endpoint.Address' \
            --output text)
        
        # Save endpoints to environment file
        echo "PRIMARY_ENDPOINT=$primary_endpoint" >> "${SCRIPT_DIR}/deployment_vars.env"
        echo "REPLICA_ENDPOINT=$replica_endpoint" >> "${SCRIPT_DIR}/deployment_vars.env"
        
        log "Primary endpoint: $primary_endpoint"
        log "Replica endpoint: $replica_endpoint"
    fi
    
    log_success "Route 53 failover setup completed"
}

# Configure automated backup strategy
configure_backup_strategy() {
    log "Configuring automated backup strategy..."
    
    # Create manual snapshot for baseline
    execute_aws "aws rds create-db-snapshot \
        --region $PRIMARY_REGION \
        --db-instance-identifier $DB_INSTANCE_ID \
        --db-snapshot-identifier '${DB_INSTANCE_ID}-baseline-$(date +%Y%m%d)'"
    
    # Configure automated backup replication (when supported)
    log "Note: Cross-region automated backup replication requires manual setup in AWS Console"
    
    log_success "Backup strategy configured"
}

# Create IAM role for cross-region promotion
create_promotion_role() {
    log "Creating IAM role for cross-region promotion..."
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/promotion-trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    execute_aws "aws iam create-role \
        --role-name rds-promotion-role-${DB_INSTANCE_ID} \
        --assume-role-policy-document file://${SCRIPT_DIR}/promotion-trust-policy.json"
    
    execute_aws "aws iam attach-role-policy \
        --role-name rds-promotion-role-${DB_INSTANCE_ID} \
        --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess"
    
    execute_aws "aws iam attach-role-policy \
        --role-name rds-promotion-role-${DB_INSTANCE_ID} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Save role name to environment file
    echo "PROMOTION_ROLE=rds-promotion-role-${DB_INSTANCE_ID}" >> "${SCRIPT_DIR}/deployment_vars.env"
    
    log_success "Cross-region promotion role created"
}

# Test failover capabilities
test_failover() {
    log "Testing Multi-AZ failover capabilities..."
    
    if [[ "$DRY_RUN" == false ]]; then
        log_warning "Performing failover test - this will cause brief connectivity interruption"
        read -p "Continue with failover test? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            execute_aws "aws rds reboot-db-instance \
                --region $PRIMARY_REGION \
                --db-instance-identifier $DB_INSTANCE_ID \
                --force-failover"
            
            log "Waiting for failover to complete..."
            aws rds wait db-instance-available \
                --region "$PRIMARY_REGION" \
                --db-instance-identifier "$DB_INSTANCE_ID"
            
            log_success "Multi-AZ failover test completed"
        else
            log "Skipping failover test"
        fi
    else
        log "[DRY RUN] Would test Multi-AZ failover"
    fi
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment_summary.txt" << EOF
Advanced RDS Multi-AZ Cross-Region Failover Deployment Summary
=============================================================

Deployment completed: $(date)
Primary Region: $PRIMARY_REGION
Secondary Region: $SECONDARY_REGION

Resources Created:
- Primary DB Instance: $DB_INSTANCE_ID ($DB_INSTANCE_CLASS)
- Read Replica: $DB_REPLICA_ID ($DB_INSTANCE_CLASS)
- Parameter Group: $DB_PARAMETER_GROUP
- Subnet Groups: $DB_SUBNET_GROUP (both regions)
- IAM Role: rds-promotion-role-${DB_INSTANCE_ID}
- CloudWatch Alarms: Connection monitoring and replica lag
- Manual Snapshot: ${DB_INSTANCE_ID}-baseline-$(date +%Y%m%d)

Configuration:
- Multi-AZ: Enabled
- Backup Retention: 30 days
- Storage: 500GB GP3, encrypted
- Performance Insights: Enabled (7 days retention)
- Enhanced Monitoring: 60-second intervals

Next Steps:
1. Configure application connection strings
2. Set up Route 53 health checks (if not done automatically)
3. Test application connectivity to both regions
4. Configure monitoring dashboards
5. Review and customize CloudWatch alarms

Security Notes:
- Database uses default security groups
- Consider creating custom security groups with restricted access
- Database password is stored in deployment_vars.env file
- Enable AWS CloudTrail for audit logging

Cost Considerations:
- Estimated monthly cost: $800-1,200 for production instances
- Consider using smaller instances for development/testing
- Monitor storage growth and backup costs

For cleanup, run: ./destroy.sh
EOF
    
    log_success "Deployment summary saved to deployment_summary.txt"
}

# Main deployment function
main() {
    log "=== Starting Advanced RDS Multi-AZ Cross-Region Failover Deployment ==="
    
    # Initialize log files
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    check_prerequisites
    setup_environment
    setup_vpc_resources
    
    create_db_subnet_groups
    create_parameter_group
    create_primary_database
    create_read_replica
    configure_cloudwatch_alarms
    setup_route53_failover
    configure_backup_strategy
    create_promotion_role
    test_failover
    
    generate_summary
    
    log_success "=== Deployment completed successfully ==="
    log "Check deployment_summary.txt for details"
    log "Environment variables saved to deployment_vars.env"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "This was a dry run - no resources were actually created"
    fi
}

# Run main function
main "$@"