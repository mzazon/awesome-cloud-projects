#!/bin/bash

# VMware Cloud on AWS Migration - Deployment Script
# This script deploys the infrastructure needed for VMware Cloud migration
# Version: 1.0

set -e  # Exit on any error

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
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing jq for JSON parsing..."
        # Try to install jq based on OS
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y jq
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq
        else
            error "Please install jq manually for JSON parsing"
            exit 1
        fi
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No AWS region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    # Set VMware Cloud on AWS specific variables
    export SDDC_NAME="vmware-migration-${RANDOM_SUFFIX}"
    export MANAGEMENT_SUBNET="10.0.0.0/16"
    export SDDC_REGION="${AWS_REGION}"
    
    success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "SDDC Name: $SDDC_NAME"
}

# Function to create VPC and networking components
create_vpc_networking() {
    log "Creating VPC and networking components..."
    
    # Create VPC for VMware Cloud on AWS connectivity
    export VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.1.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=vmware-migration-vpc},{Key=Project,Value=VMware-Migration}]" \
        --query Vpc.VpcId --output text)
    
    if [[ -z "$VPC_ID" ]]; then
        error "Failed to create VPC"
        exit 1
    fi
    
    # Wait for VPC to be available
    aws ec2 wait vpc-available --vpc-ids $VPC_ID
    
    # Create subnet for VMware Cloud connectivity
    export SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 10.1.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=vmware-migration-subnet},{Key=Project,Value=VMware-Migration}]" \
        --query Subnet.SubnetId --output text)
    
    if [[ -z "$SUBNET_ID" ]]; then
        error "Failed to create subnet"
        exit 1
    fi
    
    # Create internet gateway for VPC
    export IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=vmware-migration-igw},{Key=Project,Value=VMware-Migration}]" \
        --query InternetGateway.InternetGatewayId --output text)
    
    # Attach internet gateway to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id $IGW_ID \
        --vpc-id $VPC_ID
    
    # Create route table for public subnet
    export RT_ID=$(aws ec2 create-route-table \
        --vpc-id $VPC_ID \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=vmware-migration-rt},{Key=Project,Value=VMware-Migration}]" \
        --query RouteTable.RouteTableId --output text)
    
    # Add route to internet gateway
    aws ec2 create-route \
        --route-table-id $RT_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $IGW_ID
    
    # Associate route table with subnet
    aws ec2 associate-route-table \
        --route-table-id $RT_ID \
        --subnet-id $SUBNET_ID
    
    success "VPC and networking components created"
    log "VPC ID: $VPC_ID"
    log "Subnet ID: $SUBNET_ID"
    log "Internet Gateway ID: $IGW_ID"
    log "Route Table ID: $RT_ID"
}

# Function to setup AWS Application Migration Service
setup_migration_service() {
    log "Setting up AWS Application Migration Service..."
    
    # Initialize MGN service in the region
    if aws mgn initialize-service --region $AWS_REGION 2>/dev/null; then
        success "MGN service initialized"
    else
        warning "MGN service may already be initialized or initialization failed"
    fi
    
    # Create security group for MGN
    export MGN_SG_ID=$(aws ec2 create-security-group \
        --group-name vmware-mgn-sg \
        --description "Security group for AWS Application Migration Service" \
        --vpc-id $VPC_ID \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=vmware-mgn-sg},{Key=Project,Value=VMware-Migration}]" \
        --query GroupId --output text)
    
    # Configure MGN security group rules
    aws ec2 authorize-security-group-ingress \
        --group-id $MGN_SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=HTTPS},{Key=Project,Value=VMware-Migration}]"
    
    # Create replication configuration template
    aws mgn create-replication-configuration-template \
        --associate-default-security-group \
        --bandwidth-throttling 100 \
        --create-public-ip \
        --data-plane-routing PRIVATE_IP \
        --default-large-staging-disk-type GP3 \
        --ebs-encryption DEFAULT \
        --replication-server-instance-type m5.large \
        --replication-servers-security-groups-i-ds $MGN_SG_ID \
        --staging-area-subnet-id $SUBNET_ID \
        --staging-area-tags Environment=Migration,Project=VMware-Migration \
        --use-dedicated-replication-server false 2>/dev/null || warning "MGN template may already exist"
    
    success "AWS Application Migration Service configured"
}

# Function to create Direct Connect gateway
create_direct_connect_gateway() {
    log "Creating Direct Connect gateway..."
    
    # Create Direct Connect gateway for hybrid connectivity
    export DX_GATEWAY_ID=$(aws directconnect create-direct-connect-gateway \
        --name "vmware-migration-dx-gateway" \
        --amazon-side-asn 64512 \
        --query directConnectGateway.directConnectGatewayId --output text)
    
    if [[ -n "$DX_GATEWAY_ID" ]]; then
        success "Direct Connect gateway created: $DX_GATEWAY_ID"
    else
        warning "Direct Connect gateway creation failed or already exists"
    fi
}

# Function to create IAM roles and policies
create_iam_resources() {
    log "Creating IAM roles and policies..."
    
    # Create IAM role for VMware Cloud on AWS
    cat > /tmp/vmware-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::063048924651:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "$AWS_ACCOUNT_ID"
                }
            }
        }
    ]
}
EOF
    
    # Create the IAM role
    aws iam create-role \
        --role-name VMwareCloudOnAWS-ServiceRole \
        --assume-role-policy-document file:///tmp/vmware-trust-policy.json \
        --tags Key=Project,Value=VMware-Migration 2>/dev/null || warning "IAM role may already exist"
    
    # Attach required policies to the role
    aws iam attach-role-policy \
        --role-name VMwareCloudOnAWS-ServiceRole \
        --policy-arn arn:aws:iam::aws:policy/VMwareCloudOnAWSServiceRolePolicy 2>/dev/null || warning "Policy may already be attached"
    
    # Create Lambda execution role
    cat > /tmp/lambda-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    aws iam create-role \
        --role-name VMware-Lambda-ExecutionRole \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --tags Key=Project,Value=VMware-Migration 2>/dev/null || warning "Lambda role may already exist"
    
    aws iam attach-role-policy \
        --role-name VMware-Lambda-ExecutionRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || warning "Lambda policy may already be attached"
    
    # Clean up temp files
    rm -f /tmp/vmware-trust-policy.json /tmp/lambda-trust-policy.json
    
    success "IAM resources configured"
}

# Function to configure CloudWatch monitoring
configure_monitoring() {
    log "Configuring CloudWatch monitoring..."
    
    # Create CloudWatch log group for VMware operations
    aws logs create-log-group \
        --log-group-name "/aws/vmware/migration" \
        --retention-in-days 30 \
        --tags Project=VMware-Migration 2>/dev/null || warning "Log group may already exist"
    
    # Create SNS topic for VMware alerts
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name VMware-Migration-Alerts \
        --tags Key=Project,Value=VMware-Migration \
        --query TopicArn --output text)
    
    # Create CloudWatch alarm for SDDC health
    aws cloudwatch put-metric-alarm \
        --alarm-name "VMware-SDDC-HostHealth" \
        --alarm-description "Monitor VMware SDDC host health" \
        --metric-name "HostHealth" \
        --namespace "AWS/VMwareCloudOnAWS" \
        --statistic "Average" \
        --period 300 \
        --threshold 1 \
        --comparison-operator "LessThanThreshold" \
        --evaluation-periods 2 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --tags Key=Project,Value=VMware-Migration 2>/dev/null || warning "CloudWatch alarm may already exist"
    
    # Create CloudWatch dashboard for VMware operations
    aws cloudwatch put-dashboard \
        --dashboard-name "VMware-Migration-Dashboard" \
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
                            ["AWS/VMwareCloudOnAWS", "HostHealth"],
                            ["VMware/Migration", "MigrationProgress"],
                            ["AWS/ApplicationMigrationService", "ReplicationProgress"]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'$AWS_REGION'",
                        "title": "VMware Migration Status"
                    }
                }
            ]
        }' || warning "Dashboard may already exist"
    
    success "CloudWatch monitoring configured"
}

# Function to create HCX security group
create_hcx_security_group() {
    log "Creating HCX security group..."
    
    # Create security group for HCX traffic
    export HCX_SG_ID=$(aws ec2 create-security-group \
        --group-name vmware-hcx-sg \
        --description "Security group for VMware HCX traffic" \
        --vpc-id $VPC_ID \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=vmware-hcx-sg},{Key=Project,Value=VMware-Migration}]" \
        --query GroupId --output text)
    
    # Configure HCX security group rules
    aws ec2 authorize-security-group-ingress \
        --group-id $HCX_SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=HTTPS},{Key=Project,Value=VMware-Migration}]"
    
    aws ec2 authorize-security-group-ingress \
        --group-id $HCX_SG_ID \
        --protocol tcp \
        --port 9443 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=HCX-Console},{Key=Project,Value=VMware-Migration}]"
    
    aws ec2 authorize-security-group-ingress \
        --group-id $HCX_SG_ID \
        --protocol tcp \
        --port 8043 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=HCX-API},{Key=Project,Value=VMware-Migration}]"
    
    # Allow HCX mobility traffic
    aws ec2 authorize-security-group-ingress \
        --group-id $HCX_SG_ID \
        --protocol tcp \
        --port 902 \
        --cidr 192.168.0.0/16 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=HCX-Mobility},{Key=Project,Value=VMware-Migration}]"
    
    success "HCX security group configured: $HCX_SG_ID"
}

# Function to create S3 backup bucket
create_s3_backup() {
    log "Creating S3 backup bucket..."
    
    # Create S3 bucket for VMware backups
    export BACKUP_BUCKET="vmware-backup-${RANDOM_SUFFIX}-${AWS_ACCOUNT_ID}"
    
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket \
            --bucket $BACKUP_BUCKET \
            --region $AWS_REGION
    else
        aws s3api create-bucket \
            --bucket $BACKUP_BUCKET \
            --region $AWS_REGION \
            --create-bucket-configuration LocationConstraint=$AWS_REGION
    fi
    
    # Configure bucket versioning
    aws s3api put-bucket-versioning \
        --bucket $BACKUP_BUCKET \
        --versioning-configuration Status=Enabled
    
    # Set up lifecycle policy for cost optimization
    aws s3api put-bucket-lifecycle-configuration \
        --bucket $BACKUP_BUCKET \
        --lifecycle-configuration '{
            "Rules": [
                {
                    "ID": "VMwareBackupLifecycle",
                    "Status": "Enabled",
                    "Transitions": [
                        {
                            "Days": 30,
                            "StorageClass": "STANDARD_IA"
                        },
                        {
                            "Days": 90,
                            "StorageClass": "GLACIER"
                        }
                    ]
                }
            ]
        }'
    
    # Add bucket tagging
    aws s3api put-bucket-tagging \
        --bucket $BACKUP_BUCKET \
        --tagging 'TagSet=[{Key=Project,Value=VMware-Migration},{Key=Purpose,Value=Backup}]'
    
    success "S3 backup bucket configured: $BACKUP_BUCKET"
}

# Function to create migration tracking resources
create_migration_tracking() {
    log "Creating migration tracking resources..."
    
    # Create migration wave plan
    cat > /tmp/migration-waves.json << EOF
{
    "waves": [
        {
            "wave": 1,
            "description": "Test/Dev workloads",
            "priority": "Low",
            "vms": ["test-vm-01", "dev-vm-01"],
            "migration_type": "HCX_vMotion"
        },
        {
            "wave": 2,
            "description": "Non-critical production",
            "priority": "Medium", 
            "vms": ["web-server-01", "app-server-01"],
            "migration_type": "HCX_Bulk_Migration"
        },
        {
            "wave": 3,
            "description": "Critical production",
            "priority": "High",
            "vms": ["db-server-01", "core-app-01"],
            "migration_type": "HCX_RAV"
        }
    ]
}
EOF
    
    # Upload migration plan to S3
    aws s3 cp /tmp/migration-waves.json s3://$BACKUP_BUCKET/migration-plan/
    
    # Create DynamoDB table to track migration progress
    aws dynamodb create-table \
        --table-name VMwareMigrationTracking \
        --attribute-definitions \
            AttributeName=VMName,AttributeType=S \
            AttributeName=MigrationWave,AttributeType=S \
        --key-schema \
            AttributeName=VMName,KeyType=HASH \
            AttributeName=MigrationWave,KeyType=RANGE \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --tags Key=Project,Value=VMware-Migration Key=Purpose,Value=Tracking 2>/dev/null || warning "DynamoDB table may already exist"
    
    # Clean up temp file
    rm -f /tmp/migration-waves.json
    
    success "Migration tracking resources configured"
}

# Function to create cost optimization resources
create_cost_optimization() {
    log "Creating cost optimization and governance resources..."
    
    # Create budget for VMware Cloud on AWS
    aws budgets create-budget \
        --account-id $AWS_ACCOUNT_ID \
        --budget '{
            "BudgetName": "VMware-Cloud-Budget",
            "BudgetLimit": {
                "Amount": "15000",
                "Unit": "USD"
            },
            "TimeUnit": "MONTHLY",
            "BudgetType": "COST",
            "CostFilters": {
                "Service": ["VMware Cloud on AWS"]
            }
        }' \
        --notifications-with-subscribers '[
            {
                "Notification": {
                    "NotificationType": "ACTUAL",
                    "ComparisonOperator": "GREATER_THAN",
                    "Threshold": 80,
                    "ThresholdType": "PERCENTAGE"
                },
                "Subscribers": [
                    {
                        "SubscriptionType": "EMAIL",
                        "Address": "admin@company.com"
                    }
                ]
            }
        ]' 2>/dev/null || warning "Budget may already exist"
    
    # Create cost anomaly detection
    aws ce create-anomaly-detector \
        --anomaly-detector '{
            "DetectorName": "VMware-Cost-Anomaly-Detector",
            "MonitorType": "DIMENSIONAL",
            "DimensionKey": "SERVICE",
            "MatchOptions": ["EQUALS"],
            "MonitorSpecification": {
                "DimensionKey": "SERVICE",
                "MatchOptions": ["EQUALS"],
                "Values": ["VMware Cloud on AWS"]
            }
        }' 2>/dev/null || warning "Cost anomaly detector may already exist"
    
    success "Cost optimization configured"
}

# Function to create validation scripts
create_validation_scripts() {
    log "Creating validation scripts..."
    
    # Create test migration validation script
    cat > /tmp/test-migration-validation.sh << 'EOF'
#!/bin/bash

# Test migration validation script
echo "Testing VMware Cloud migration connectivity..."

# Test HCX connectivity
echo "Testing HCX connectivity..."

# Check if HCX services are reachable (placeholder - requires actual SDDC deployment)
echo "✅ HCX connectivity test prepared"

# Validate network segments
echo "Validating network segments..."

# Test DNS resolution (placeholder - requires actual SDDC deployment)
echo "✅ DNS resolution test prepared"

echo "Validation framework ready"
EOF
    
    chmod +x /tmp/test-migration-validation.sh
    
    # Upload validation script to S3
    aws s3 cp /tmp/test-migration-validation.sh s3://$BACKUP_BUCKET/scripts/
    
    # Create migration execution script
    cat > /tmp/execute-migration-wave.sh << 'EOF'
#!/bin/bash

# Migration execution script
WAVE_NUMBER=$1

if [ -z "$WAVE_NUMBER" ]; then
    echo "Usage: $0 <wave_number>"
    exit 1
fi

echo "Executing migration wave $WAVE_NUMBER..."

# Start migration wave
aws cloudwatch put-metric-data \
    --namespace "VMware/Migration" \
    --metric-data MetricName=CurrentWave,Value=$WAVE_NUMBER,Unit=Count

# Log migration start
aws logs put-log-events \
    --log-group-name "/aws/vmware/migration" \
    --log-stream-name "wave-$WAVE_NUMBER" \
    --log-events timestamp=$(date +%s000),message="Starting migration wave $WAVE_NUMBER" 2>/dev/null || true

echo "Migration wave $WAVE_NUMBER execution prepared"
EOF
    
    chmod +x /tmp/execute-migration-wave.sh
    
    # Upload execution script to S3
    aws s3 cp /tmp/execute-migration-wave.sh s3://$BACKUP_BUCKET/scripts/
    
    # Clean up temp files
    rm -f /tmp/test-migration-validation.sh /tmp/execute-migration-wave.sh
    
    success "Validation scripts created and uploaded"
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    # Create deployment state file
    cat > /tmp/vmware-deployment-state.json << EOF
{
    "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "vpc_id": "$VPC_ID",
    "subnet_id": "$SUBNET_ID",
    "igw_id": "$IGW_ID",
    "rt_id": "$RT_ID",
    "hcx_sg_id": "$HCX_SG_ID",
    "mgn_sg_id": "$MGN_SG_ID",
    "backup_bucket": "$BACKUP_BUCKET",
    "sns_topic_arn": "$SNS_TOPIC_ARN",
    "dx_gateway_id": "$DX_GATEWAY_ID",
    "sddc_name": "$SDDC_NAME"
}
EOF
    
    # Upload state file to S3
    aws s3 cp /tmp/vmware-deployment-state.json s3://$BACKUP_BUCKET/deployment-state/
    
    # Also save locally for destroy script
    mkdir -p ~/.aws-vmware-migration
    cp /tmp/vmware-deployment-state.json ~/.aws-vmware-migration/deployment-state.json
    
    # Clean up temp file
    rm -f /tmp/vmware-deployment-state.json
    
    success "Deployment state saved"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary:"
    echo "==================="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo "VPC ID: $VPC_ID"
    echo "Subnet ID: $SUBNET_ID"
    echo "HCX Security Group ID: $HCX_SG_ID"
    echo "Backup Bucket: $BACKUP_BUCKET"
    echo "SNS Topic ARN: $SNS_TOPIC_ARN"
    echo "SDDC Name: $SDDC_NAME"
    echo "==================="
    echo ""
    echo "Next Steps:"
    echo "1. Complete SDDC deployment through VMware Cloud Console (vmc.vmware.com)"
    echo "2. Configure HCX connectivity between on-premises and cloud"
    echo "3. Execute migration waves using scripts in S3 bucket"
    echo "4. Monitor progress through CloudWatch dashboard"
    echo ""
    echo "Important Notes:"
    echo "- SDDC deployment takes 2-4 hours through VMware Cloud Console"
    echo "- Monthly costs will be $8,000-15,000 for 3-host SDDC cluster"
    echo "- Use destroy.sh script to clean up resources when migration is complete"
}

# Main execution
main() {
    log "Starting VMware Cloud on AWS migration deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_vpc_networking
    setup_migration_service
    create_direct_connect_gateway
    create_iam_resources
    configure_monitoring
    create_hcx_security_group
    create_s3_backup
    create_migration_tracking
    create_cost_optimization
    create_validation_scripts
    save_deployment_state
    
    success "VMware Cloud on AWS migration infrastructure deployed successfully!"
    
    display_deployment_summary
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"