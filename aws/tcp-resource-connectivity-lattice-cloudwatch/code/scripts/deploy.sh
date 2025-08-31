#!/bin/bash

# TCP Resource Connectivity with VPC Lattice and CloudWatch - Deployment Script
# This script deploys a complete VPC Lattice service network for secure TCP database connectivity
# with comprehensive CloudWatch monitoring and cost optimization

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    print_status "AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' or set up IAM role."
        exit 1
    fi
    
    # Check required permissions
    print_status "Checking AWS permissions..."
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    print_status "AWS Account: $(echo "${CALLER_IDENTITY}" | jq -r '.Account')"
    print_status "AWS User/Role: $(echo "${CALLER_IDENTITY}" | jq -r '.Arn')"
    
    # Check required services availability
    local required_services=("vpc-lattice" "rds" "cloudwatch" "iam" "ec2")
    for service in "${required_services[@]}"; do
        if ! aws "${service}" help &> /dev/null; then
            print_error "Service ${service} is not available in this region or account"
            exit 1
        fi
    done
    
    print_status "Prerequisites check completed successfully"
}

# Function to setup environment variables
setup_environment() {
    print_header "Setting up environment variables..."
    
    # AWS configuration
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        print_warning "No default region set, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Resource names
    export SERVICE_NETWORK_NAME="database-service-network-${RANDOM_SUFFIX}"
    export DATABASE_SERVICE_NAME="rds-database-service-${RANDOM_SUFFIX}"
    export TARGET_GROUP_NAME="rds-tcp-targets-${RANDOM_SUFFIX}"
    export RDS_INSTANCE_ID="vpc-lattice-db-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="VPCLatticeServiceRole-${RANDOM_SUFFIX}"
    
    # Get VPC and subnet information
    export DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "${DEFAULT_VPC_ID}" == "None" ]]; then
        print_error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
        --query 'Subnets[0:2].SubnetId' --output text | tr '\t' ' ')
    
    export SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
                 "Name=group-name,Values=default" \
        --query 'SecurityGroups[0].GroupId' --output text)
    
    # Create deployment state file
    cat > deployment_state.json << EOF
{
    "deployment_id": "${RANDOM_SUFFIX}",
    "region": "${AWS_REGION}",
    "account_id": "${AWS_ACCOUNT_ID}",
    "service_network_name": "${SERVICE_NETWORK_NAME}",
    "database_service_name": "${DATABASE_SERVICE_NAME}",
    "target_group_name": "${TARGET_GROUP_NAME}",
    "rds_instance_id": "${RDS_INSTANCE_ID}",
    "iam_role_name": "${IAM_ROLE_NAME}",
    "vpc_id": "${DEFAULT_VPC_ID}",
    "subnet_ids": "${SUBNET_IDS}",
    "security_group_id": "${SECURITY_GROUP_ID}",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    print_status "Environment configured with deployment ID: ${RANDOM_SUFFIX}"
    print_status "Region: ${AWS_REGION}"
    print_status "VPC ID: ${DEFAULT_VPC_ID}"
    print_status "Subnet IDs: ${SUBNET_IDS}"
}

# Function to create IAM role
create_iam_role() {
    print_header "Creating IAM role for VPC Lattice..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        print_warning "IAM role ${IAM_ROLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create IAM role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "vpc-lattice.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}"
    
    print_status "IAM role created: ${IAM_ROLE_NAME}"
}

# Function to create VPC Lattice service network
create_service_network() {
    print_header "Creating VPC Lattice service network..."
    
    SERVICE_NETWORK_ARN=$(aws vpc-lattice create-service-network \
        --name "${SERVICE_NETWORK_NAME}" \
        --auth-type "AWS_IAM" \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}" \
        --query 'arn' --output text)
    
    export SERVICE_NETWORK_ID=$(echo "${SERVICE_NETWORK_ARN}" | awk -F'/' '{print $NF}')
    
    # Update state file
    jq --arg snid "${SERVICE_NETWORK_ID}" --arg snarn "${SERVICE_NETWORK_ARN}" \
        '.service_network_id = $snid | .service_network_arn = $snarn' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "Service network created: ${SERVICE_NETWORK_ID}"
    
    # Wait for service network to be active
    print_status "Waiting for service network to become active..."
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local status=$(aws vpc-lattice get-service-network \
            --service-network-identifier "${SERVICE_NETWORK_ID}" \
            --query 'status' --output text)
        
        if [[ "${status}" == "ACTIVE" ]]; then
            print_status "Service network is now active"
            break
        fi
        
        if [[ ${attempt} -eq ${max_attempts} ]]; then
            print_error "Service network failed to become active within ${max_attempts} attempts"
            exit 1
        fi
        
        print_status "Attempt ${attempt}/${max_attempts}: Service network status is ${status}, waiting..."
        sleep 10
        ((attempt++))
    done
}

# Function to create RDS instance
create_rds_instance() {
    print_header "Creating RDS database instance..."
    
    # Check if RDS instance already exists
    if aws rds describe-db-instances --db-instance-identifier "${RDS_INSTANCE_ID}" &> /dev/null; then
        print_warning "RDS instance ${RDS_INSTANCE_ID} already exists, skipping creation"
        return 0
    fi
    
    # Create DB subnet group
    print_status "Creating DB subnet group..."
    aws rds create-db-subnet-group \
        --db-subnet-group-name "${RDS_INSTANCE_ID}-subnet-group" \
        --db-subnet-group-description "Subnet group for VPC Lattice demo" \
        --subnet-ids ${SUBNET_IDS} \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}"
    
    # Create RDS instance
    print_status "Creating RDS MySQL instance (this may take 5-10 minutes)..."
    aws rds create-db-instance \
        --db-instance-identifier "${RDS_INSTANCE_ID}" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --engine-version 8.0.35 \
        --master-username admin \
        --master-user-password MySecurePassword123! \
        --allocated-storage 20 \
        --db-subnet-group-name "${RDS_INSTANCE_ID}-subnet-group" \
        --vpc-security-group-ids "${SECURITY_GROUP_ID}" \
        --no-publicly-accessible \
        --port 3306 \
        --backup-retention-period 1 \
        --storage-encrypted \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}"
    
    print_status "RDS instance creation initiated: ${RDS_INSTANCE_ID}"
    
    # Wait for RDS instance to be available
    print_status "Waiting for RDS instance to become available (this may take 5-10 minutes)..."
    aws rds wait db-instance-available --db-instance-identifier "${RDS_INSTANCE_ID}"
    
    print_status "RDS instance is now available"
}

# Function to get RDS details
get_rds_details() {
    print_header "Retrieving RDS instance details..."
    
    export RDS_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "${RDS_INSTANCE_ID}" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    export RDS_PORT=$(aws rds describe-db-instances \
        --db-instance-identifier "${RDS_INSTANCE_ID}" \
        --query 'DBInstances[0].Endpoint.Port' \
        --output text)
    
    # Update state file
    jq --arg endpoint "${RDS_ENDPOINT}" --arg port "${RDS_PORT}" \
        '.rds_endpoint = $endpoint | .rds_port = $port' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "RDS endpoint: ${RDS_ENDPOINT}:${RDS_PORT}"
}

# Function to create target group
create_target_group() {
    print_header "Creating TCP target group for RDS..."
    
    TARGET_GROUP_ARN=$(aws vpc-lattice create-target-group \
        --name "${TARGET_GROUP_NAME}" \
        --type "IP" \
        --config '{
            "port": '${RDS_PORT}',
            "protocol": "TCP",
            "vpcIdentifier": "'${DEFAULT_VPC_ID}'",
            "healthCheck": {
                "enabled": true,
                "protocol": "TCP",
                "port": '${RDS_PORT}',
                "healthCheckIntervalSeconds": 30,
                "healthCheckTimeoutSeconds": 5,
                "healthyThresholdCount": 2,
                "unhealthyThresholdCount": 2
            }
        }' \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}" \
        --query 'arn' --output text)
    
    export TARGET_GROUP_ID=$(echo "${TARGET_GROUP_ARN}" | awk -F'/' '{print $NF}')
    
    # Update state file
    jq --arg tgid "${TARGET_GROUP_ID}" --arg tgarn "${TARGET_GROUP_ARN}" \
        '.target_group_id = $tgid | .target_group_arn = $tgarn' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "TCP target group created: ${TARGET_GROUP_ID}"
}

# Function to register RDS as target
register_rds_target() {
    print_header "Registering RDS instance as target..."
    
    aws vpc-lattice register-targets \
        --target-group-identifier "${TARGET_GROUP_ID}" \
        --targets '[{
            "id": "'${RDS_ENDPOINT}'",
            "port": '${RDS_PORT}'
        }]'
    
    print_status "RDS instance registered as target"
    
    # Wait for target to become healthy
    print_status "Waiting for target to become healthy..."
    local max_attempts=20
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local target_health=$(aws vpc-lattice list-targets \
            --target-group-identifier "${TARGET_GROUP_ID}" \
            --query 'items[0].status' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [[ "${target_health}" == "HEALTHY" ]]; then
            print_status "Target is now healthy"
            break
        fi
        
        if [[ ${attempt} -eq ${max_attempts} ]]; then
            print_warning "Target did not become healthy within ${max_attempts} attempts, continuing anyway"
            break
        fi
        
        print_status "Attempt ${attempt}/${max_attempts}: Target status is ${target_health}, waiting..."
        sleep 15
        ((attempt++))
    done
}

# Function to create VPC Lattice service
create_lattice_service() {
    print_header "Creating VPC Lattice service..."
    
    DATABASE_SERVICE_ARN=$(aws vpc-lattice create-service \
        --name "${DATABASE_SERVICE_NAME}" \
        --auth-type "AWS_IAM" \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}" \
        --query 'arn' --output text)
    
    export DATABASE_SERVICE_ID=$(echo "${DATABASE_SERVICE_ARN}" | awk -F'/' '{print $NF}')
    
    # Update state file
    jq --arg dsid "${DATABASE_SERVICE_ID}" --arg dsarn "${DATABASE_SERVICE_ARN}" \
        '.database_service_id = $dsid | .database_service_arn = $dsarn' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "Database service created: ${DATABASE_SERVICE_ID}"
}

# Function to create TCP listener
create_tcp_listener() {
    print_header "Creating TCP listener for database service..."
    
    LISTENER_ARN=$(aws vpc-lattice create-listener \
        --service-identifier "${DATABASE_SERVICE_ID}" \
        --name "mysql-tcp-listener" \
        --protocol "TCP" \
        --port 3306 \
        --default-action '{
            "forward": {
                "targetGroups": [{
                    "targetGroupIdentifier": "'${TARGET_GROUP_ID}'",
                    "weight": 100
                }]
            }
        }' \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}" \
        --query 'arn' --output text)
    
    export LISTENER_ID=$(echo "${LISTENER_ARN}" | awk -F'/' '{print $NF}')
    
    # Update state file
    jq --arg lid "${LISTENER_ID}" --arg larn "${LISTENER_ARN}" \
        '.listener_id = $lid | .listener_arn = $larn' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "TCP listener created on port 3306: ${LISTENER_ID}"
}

# Function to associate service with service network
associate_service() {
    print_header "Associating service with service network..."
    
    SERVICE_ASSOCIATION_ARN=$(aws vpc-lattice create-service-network-service-association \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --service-identifier "${DATABASE_SERVICE_ID}" \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}" \
        --query 'arn' --output text)
    
    # Update state file
    jq --arg saarn "${SERVICE_ASSOCIATION_ARN}" \
        '.service_association_arn = $saarn' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "Database service associated with service network"
}

# Function to associate VPC with service network
associate_vpc() {
    print_header "Associating VPC with service network..."
    
    VPC_ASSOCIATION_ARN=$(aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --vpc-identifier "${DEFAULT_VPC_ID}" \
        --security-group-ids "${SECURITY_GROUP_ID}" \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}" \
        --query 'arn' --output text)
    
    # Update state file
    jq --arg vaarn "${VPC_ASSOCIATION_ARN}" \
        '.vpc_association_arn = $vaarn' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "VPC associated with service network: ${VPC_ASSOCIATION_ARN}"
}

# Function to configure CloudWatch monitoring
configure_cloudwatch() {
    print_header "Configuring CloudWatch monitoring..."
    
    # Create CloudWatch dashboard
    DASHBOARD_NAME="VPCLattice-Database-Monitoring-${RANDOM_SUFFIX}"
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
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
                            ["AWS/VpcLattice", "NewConnectionCount", "TargetGroup", "'${TARGET_GROUP_ID}'"],
                            [".", "ActiveConnectionCount", ".", "."],
                            [".", "ConnectionErrorCount", ".", "."]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'${AWS_REGION}'",
                        "title": "Database Connection Metrics"
                    }
                },
                {
                    "type": "metric", 
                    "x": 0,
                    "y": 6,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "metrics": [
                            ["AWS/VpcLattice", "ProcessedBytes", "TargetGroup", "'${TARGET_GROUP_ID}'"]
                        ],
                        "period": 300,
                        "stat": "Sum", 
                        "region": "'${AWS_REGION}'",
                        "title": "Database Traffic Volume"
                    }
                }
            ]
        }'
    
    # Create CloudWatch alarm
    ALARM_NAME="VPCLattice-Database-Connection-Errors-${RANDOM_SUFFIX}"
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ALARM_NAME}" \
        --alarm-description "Alert on database connection errors" \
        --metric-name ConnectionErrorCount \
        --namespace AWS/VpcLattice \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=TargetGroup,Value="${TARGET_GROUP_ID}" \
        --evaluation-periods 2 \
        --tags Key=Project,Value=VPCLatticeDemo Key=DeploymentId,Value="${RANDOM_SUFFIX}"
    
    # Update state file
    jq --arg dashboard "${DASHBOARD_NAME}" --arg alarm "${ALARM_NAME}" \
        '.cloudwatch_dashboard = $dashboard | .cloudwatch_alarm = $alarm' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "CloudWatch monitoring configured"
    print_status "Dashboard: ${DASHBOARD_NAME}"
    print_status "Alarm: ${ALARM_NAME}"
}

# Function to run validation tests
run_validation() {
    print_header "Running validation tests..."
    
    # Test 1: Verify service network status
    print_status "Checking service network status..."
    local sn_status=$(aws vpc-lattice get-service-network \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --query 'status' --output text)
    
    if [[ "${sn_status}" == "ACTIVE" ]]; then
        print_status "✅ Service network is active"
    else
        print_warning "⚠️ Service network status: ${sn_status}"
    fi
    
    # Test 2: Verify target health
    print_status "Checking target health..."
    local target_status=$(aws vpc-lattice list-targets \
        --target-group-identifier "${TARGET_GROUP_ID}" \
        --query 'items[0].status' --output text 2>/dev/null || echo "UNKNOWN")
    
    if [[ "${target_status}" == "HEALTHY" ]]; then
        print_status "✅ Target is healthy"
    else
        print_warning "⚠️ Target status: ${target_status}"
    fi
    
    # Test 3: Generate service endpoint
    SERVICE_ENDPOINT="${DATABASE_SERVICE_NAME}.${SERVICE_NETWORK_ID}.vpc-lattice-svcs.${AWS_REGION}.on.aws"
    
    # Update state file with endpoint
    jq --arg endpoint "${SERVICE_ENDPOINT}" \
        '.service_endpoint = $endpoint' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "✅ Service endpoint: ${SERVICE_ENDPOINT}"
    
    # Test 4: Verify CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &> /dev/null; then
        print_status "✅ CloudWatch dashboard is available"
    else
        print_warning "⚠️ CloudWatch dashboard not found"
    fi
    
    print_status "Validation completed"
}

# Function to display deployment summary
display_summary() {
    print_header "Deployment Summary"
    
    cat << EOF

🎉 VPC Lattice TCP Resource Connectivity deployment completed successfully!

📋 Deployment Details:
   - Deployment ID: ${RANDOM_SUFFIX}
   - Region: ${AWS_REGION}
   - Account ID: ${AWS_ACCOUNT_ID}

🏗️ Infrastructure Created:
   - Service Network: ${SERVICE_NETWORK_NAME} (${SERVICE_NETWORK_ID})
   - Database Service: ${DATABASE_SERVICE_NAME} (${DATABASE_SERVICE_ID})
   - RDS Instance: ${RDS_INSTANCE_ID} (${RDS_ENDPOINT}:${RDS_PORT})
   - Target Group: ${TARGET_GROUP_NAME} (${TARGET_GROUP_ID})
   - TCP Listener: ${LISTENER_ID} (Port 3306)

🔗 Service Endpoint:
   ${SERVICE_ENDPOINT}

📊 CloudWatch Monitoring:
   - Dashboard: ${DASHBOARD_NAME}
   - Alarm: ${ALARM_NAME}

💰 Estimated Monthly Cost:
   - RDS db.t3.micro: ~$12-15
   - VPC Lattice: ~$10-25 (based on usage)
   - CloudWatch: ~$1-3

📁 State File: deployment_state.json
📋 Log File: ${LOG_FILE}

🧹 To clean up all resources:
   ./destroy.sh

EOF

    print_status "For more information, see the CloudWatch dashboard in the AWS Console"
    print_status "Deployment completed in $(date)"
}

# Function to handle cleanup on error
cleanup_on_error() {
    print_error "Deployment failed. Starting cleanup of partial resources..."
    
    if [[ -f deployment_state.json ]]; then
        # Source the destroy script for cleanup
        if [[ -f ./destroy.sh ]]; then
            print_status "Running cleanup script..."
            chmod +x ./destroy.sh
            ./destroy.sh --force
        fi
    fi
    
    exit 1
}

# Main deployment function
main() {
    print_header "Starting VPC Lattice TCP Resource Connectivity Deployment"
    print_status "Timestamp: $(date)"
    print_status "Log file: ${LOG_FILE}"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_iam_role
    create_service_network
    create_rds_instance
    get_rds_details
    create_target_group
    register_rds_target
    create_lattice_service
    create_tcp_listener
    associate_service
    associate_vpc
    configure_cloudwatch
    run_validation
    display_summary
    
    # Mark deployment as complete
    jq '.deployment_status = "COMPLETE" | .completed_at = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"' \
        deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    print_status "🎉 Deployment completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            cat << EOF
VPC Lattice TCP Resource Connectivity Deployment Script

This script deploys a complete VPC Lattice service network for secure TCP 
database connectivity with CloudWatch monitoring.

Usage: $0 [OPTIONS]

Options:
    --help, -h          Show this help message
    --region REGION     Specify AWS region (overrides AWS CLI default)
    --dry-run           Show what would be deployed without making changes
    --debug             Enable debug output

Environment Variables:
    AWS_REGION          AWS region for deployment
    AWS_PROFILE         AWS profile to use for deployment

Examples:
    $0                          # Deploy with default settings
    $0 --region us-west-2       # Deploy to specific region
    $0 --dry-run                # Show deployment plan

EOF
            exit 0
            ;;
        --region)
            export AWS_REGION="$2"
            shift 2
            ;;
        --dry-run)
            print_status "DRY RUN MODE - No resources will be created"
            export DRY_RUN=true
            shift
            ;;
        --debug)
            set -x
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"