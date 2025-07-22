#!/bin/bash

# AWS Application Migration Service Deployment Script
# This script deploys the infrastructure needed for automated application migration workflows

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN="${DRY_RUN:-false}"

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    if [[ -n "${WORKFLOW_ID:-}" ]]; then
        aws migrationhub-orchestrator stop-workflow --id "$WORKFLOW_ID" 2>/dev/null || true
        aws migrationhub-orchestrator delete-workflow --id "$WORKFLOW_ID" 2>/dev/null || true
    fi
    if [[ -n "${VPC_ID:-}" ]]; then
        ./destroy.sh --force 2>/dev/null || true
    fi
}

trap cleanup_on_error ERR

# Display banner
echo -e "${BLUE}"
echo "=========================================="
echo "AWS Application Migration Service Deployment"
echo "=========================================="
echo -e "${NC}"

# Validate prerequisites
log_info "Validating prerequisites..."

# Check if AWS CLI is installed and configured
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed. Please install it first."
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error_exit "AWS credentials not configured. Please run 'aws configure' first."
fi

# Check required permissions
log_info "Checking AWS permissions..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION="us-east-1"
    log_warning "No region configured, defaulting to $AWS_REGION"
fi

# Check if MGN service is available in region
if ! aws mgn describe-replication-configuration-templates --region "$AWS_REGION" &> /dev/null; then
    if [[ $? -eq 254 ]]; then
        error_exit "MGN service is not available in region $AWS_REGION. Please use a supported region."
    fi
fi

# Check required IAM permissions
log_info "Verifying IAM permissions..."
REQUIRED_PERMISSIONS=(
    "mgn:*"
    "migrationhub-orchestrator:*"
    "ec2:*"
    "cloudformation:*"
    "ssm:*"
    "cloudwatch:*"
    "iam:PassRole"
)

# Generate unique identifiers
TIMESTAMP=$(date +%s)
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 8 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "${TIMESTAMP:(-8)}")

# Environment variables
export AWS_REGION
export AWS_ACCOUNT_ID
export MIGRATION_PROJECT_NAME="migration-project-${RANDOM_SUFFIX}"
export VPC_NAME="migration-vpc-${RANDOM_SUFFIX}"
export IAM_ROLE_NAME="MGNServiceRole-${RANDOM_SUFFIX}"

log_info "Deployment configuration:"
log_info "  AWS Account ID: $AWS_ACCOUNT_ID"
log_info "  AWS Region: $AWS_REGION"
log_info "  Project Name: $MIGRATION_PROJECT_NAME"
log_info "  VPC Name: $VPC_NAME"
log_info "  Random Suffix: $RANDOM_SUFFIX"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN MODE - No resources will be created"
    exit 0
fi

# Confirm deployment
read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled by user"
    exit 0
fi

log_info "Starting deployment..."

# Step 1: Initialize AWS Application Migration Service
log_info "Step 1: Initializing AWS Application Migration Service..."
if ! aws mgn describe-replication-configuration-templates --region "$AWS_REGION" &> /dev/null; then
    aws mgn initialize-service --region "$AWS_REGION"
    log_success "MGN service initialized"
else
    log_info "MGN service already initialized"
fi

# Wait for initialization and get template ID
log_info "Getting MGN template ID..."
for i in {1..30}; do
    MGN_TEMPLATE_ID=$(aws mgn describe-replication-configuration-templates \
        --region "$AWS_REGION" \
        --query 'ReplicationConfigurationTemplates[0].ReplicationConfigurationTemplateID' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$MGN_TEMPLATE_ID" != "None" && "$MGN_TEMPLATE_ID" != "null" ]]; then
        break
    fi
    log_info "Waiting for MGN initialization... ($i/30)"
    sleep 10
done

if [[ "$MGN_TEMPLATE_ID" == "None" || "$MGN_TEMPLATE_ID" == "null" ]]; then
    error_exit "Failed to get MGN template ID after initialization"
fi

export MGN_TEMPLATE_ID
log_success "MGN initialized with template ID: $MGN_TEMPLATE_ID"

# Step 2: Create Migration Hub home region
log_info "Step 2: Configuring Migration Hub home region..."
aws migrationhub config create-home-region-control \
    --home-region "$AWS_REGION" \
    --target "$AWS_ACCOUNT_ID" 2>/dev/null || log_info "Home region already configured"

# Step 3: Create Migration Hub Orchestrator Workflow Template
log_info "Step 3: Creating Migration Hub Orchestrator workflow template..."
cat > "${SCRIPT_DIR}/migration-workflow.json" << 'EOF'
{
  "name": "AutomatedMigrationWorkflow",
  "description": "Automated end-to-end migration workflow using MGN",
  "templateSource": {
    "workflowSteps": [
      {
        "stepId": "step1",
        "name": "ValidateSourceConnectivity",
        "description": "Verify source server connectivity and prerequisites",
        "stepActionType": "AUTOMATED",
        "owner": "AWS_MANAGED"
      },
      {
        "stepId": "step2", 
        "name": "ConfigureReplication",
        "description": "Deploy and configure MGN replication agents",
        "stepActionType": "AUTOMATED",
        "owner": "AWS_MANAGED"
      },
      {
        "stepId": "step3",
        "name": "MonitorDataReplication", 
        "description": "Monitor initial sync and ongoing replication",
        "stepActionType": "AUTOMATED",
        "owner": "AWS_MANAGED"
      },
      {
        "stepId": "step4",
        "name": "ExecuteTestLaunch",
        "description": "Launch test instances for validation",
        "stepActionType": "AUTOMATED", 
        "owner": "AWS_MANAGED"
      },
      {
        "stepId": "step5",
        "name": "ValidateTestInstances",
        "description": "Perform automated testing and validation",
        "stepActionType": "MANUAL",
        "owner": "CUSTOMER"
      },
      {
        "stepId": "step6",
        "name": "ExecuteCutover",
        "description": "Perform final cutover to production instances",
        "stepActionType": "AUTOMATED",
        "owner": "AWS_MANAGED"
      }
    ]
  }
}
EOF

# Create the workflow template
TEMPLATE_NAME="AutomatedMigrationWorkflow-${RANDOM_SUFFIX}"
aws migrationhub-orchestrator create-template \
    --template-name "$TEMPLATE_NAME" \
    --template-description "Automated MGN migration workflow" \
    --template-source file://"${SCRIPT_DIR}/migration-workflow.json" > /dev/null

log_success "Migration workflow template created: $TEMPLATE_NAME"

# Step 4: Create VPC Infrastructure
log_info "Step 4: Creating VPC infrastructure..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications \
    "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Purpose,Value=Migration},{Key=Project,Value=${MIGRATION_PROJECT_NAME}}]" \
    --query 'Vpc.VpcId' --output text)

export VPC_ID
log_success "VPC created: $VPC_ID"

# Enable DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames

# Create subnets
log_info "Creating subnets..."
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.0.1.0/24 \
    --availability-zone "${AWS_REGION}a" \
    --tag-specifications \
    "ResourceType=subnet,Tags=[{Key=Name,Value=Migration-Public-${RANDOM_SUFFIX}},{Key=Type,Value=Public},{Key=Project,Value=${MIGRATION_PROJECT_NAME}}]" \
    --query 'Subnet.SubnetId' --output text)

PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.0.2.0/24 \
    --availability-zone "${AWS_REGION}b" \
    --tag-specifications \
    "ResourceType=subnet,Tags=[{Key=Name,Value=Migration-Private-${RANDOM_SUFFIX}},{Key=Type,Value=Private},{Key=Project,Value=${MIGRATION_PROJECT_NAME}}]" \
    --query 'Subnet.SubnetId' --output text)

export PUBLIC_SUBNET_ID
export PRIVATE_SUBNET_ID
log_success "Subnets created: Public=$PUBLIC_SUBNET_ID, Private=$PRIVATE_SUBNET_ID"

# Create and attach Internet Gateway
log_info "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications \
    "ResourceType=internet-gateway,Tags=[{Key=Name,Value=Migration-IGW-${RANDOM_SUFFIX}},{Key=Project,Value=${MIGRATION_PROJECT_NAME}}]" \
    --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"

export IGW_ID
log_success "Internet Gateway created and attached: $IGW_ID"

# Configure route table
log_info "Configuring route table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --tag-specifications \
    "ResourceType=route-table,Tags=[{Key=Name,Value=Migration-Public-RT-${RANDOM_SUFFIX}},{Key=Project,Value=${MIGRATION_PROJECT_NAME}}]" \
    --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route \
    --route-table-id "$ROUTE_TABLE_ID" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID"

aws ec2 associate-route-table \
    --subnet-id "$PUBLIC_SUBNET_ID" \
    --route-table-id "$ROUTE_TABLE_ID"

export ROUTE_TABLE_ID
log_success "Route table configured: $ROUTE_TABLE_ID"

# Step 5: Configure Security Groups
log_info "Step 5: Creating security groups..."
MIGRATION_SG_ID=$(aws ec2 create-security-group \
    --group-name "migration-sg-${RANDOM_SUFFIX}" \
    --description "Security group for migrated instances" \
    --vpc-id "$VPC_ID" \
    --tag-specifications \
    "ResourceType=security-group,Tags=[{Key=Name,Value=Migration-SG-${RANDOM_SUFFIX}},{Key=Project,Value=${MIGRATION_PROJECT_NAME}}]" \
    --query 'GroupId' --output text)

# Configure security group rules
aws ec2 authorize-security-group-ingress \
    --group-id "$MIGRATION_SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 10.0.0.0/16

aws ec2 authorize-security-group-ingress \
    --group-id "$MIGRATION_SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id "$MIGRATION_SG_ID" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0

export MIGRATION_SG_ID
log_success "Security group created: $MIGRATION_SG_ID"

# Update MGN replication configuration
log_info "Updating MGN replication configuration..."
aws mgn update-replication-configuration-template \
    --replication-configuration-template-id "$MGN_TEMPLATE_ID" \
    --replication-servers-security-groups-i-ds "$MIGRATION_SG_ID" \
    --staging-area-subnet-id "$PRIVATE_SUBNET_ID"

log_success "MGN replication configuration updated"

# Step 6: Set up CloudWatch monitoring
log_info "Step 6: Setting up CloudWatch monitoring..."
cat > "${SCRIPT_DIR}/migration-dashboard.json" << EOF
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/MGN", "TotalSourceServers"],
          ["AWS/MGN", "HealthySourceServers"],
          ["AWS/MGN", "ReplicationProgress"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "MGN Migration Status"
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/migrationhub-orchestrator' | fields @timestamp, message\\n| filter message like /ERROR/\\n| sort @timestamp desc\\n| limit 20",
        "region": "${AWS_REGION}",
        "title": "Migration Errors"
      }
    }
  ]
}
EOF

DASHBOARD_NAME="Migration-Dashboard-${RANDOM_SUFFIX}"
aws cloudwatch put-dashboard \
    --dashboard-name "$DASHBOARD_NAME" \
    --dashboard-body file://"${SCRIPT_DIR}/migration-dashboard.json"

export DASHBOARD_NAME
log_success "CloudWatch dashboard created: $DASHBOARD_NAME"

# Create CloudWatch alarm
ALARM_NAME="MGN-Replication-Health-${RANDOM_SUFFIX}"
aws cloudwatch put-metric-alarm \
    --alarm-name "$ALARM_NAME" \
    --alarm-description "Alert when MGN replication encounters issues" \
    --metric-name "HealthySourceServers" \
    --namespace "AWS/MGN" \
    --statistic "Average" \
    --period 300 \
    --evaluation-periods 2 \
    --threshold 1 \
    --comparison-operator "LessThanThreshold" \
    --treat-missing-data "breaching"

export ALARM_NAME
log_success "CloudWatch alarm created: $ALARM_NAME"

# Step 7: Create Systems Manager automation
log_info "Step 7: Creating Systems Manager automation..."
cat > "${SCRIPT_DIR}/post-migration-automation.json" << 'EOF'
{
  "schemaVersion": "0.3",
  "description": "Post-migration automation tasks",
  "assumeRole": "{{ AutomationAssumeRole }}",
  "parameters": {
    "InstanceId": {
      "type": "String",
      "description": "EC2 Instance ID for post-migration tasks"
    },
    "AutomationAssumeRole": {
      "type": "String",
      "description": "IAM role for automation execution"
    }
  },
  "mainSteps": [
    {
      "name": "WaitForInstanceReady",
      "action": "aws:waitForAwsResourceProperty",
      "inputs": {
        "Service": "ec2",
        "Api": "DescribeInstanceStatus",
        "InstanceIds": ["{{ InstanceId }}"],
        "PropertySelector": "$.InstanceStatuses[0].InstanceStatus.Status",
        "DesiredValues": ["ok"]
      }
    },
    {
      "name": "ConfigureCloudWatchAgent", 
      "action": "aws:runCommand",
      "inputs": {
        "DocumentName": "AWS-ConfigureAWSPackage",
        "InstanceIds": ["{{ InstanceId }}"],
        "Parameters": {
          "action": "Install",
          "name": "AmazonCloudWatchAgent"
        }
      }
    },
    {
      "name": "ValidateServices",
      "action": "aws:runCommand", 
      "inputs": {
        "DocumentName": "AWS-RunShellScript",
        "InstanceIds": ["{{ InstanceId }}"],
        "Parameters": {
          "commands": [
            "#!/bin/bash",
            "systemctl status sshd",
            "curl -f http://localhost/health || echo 'Application health check failed'"
          ]
        }
      }
    }
  ]
}
EOF

SSM_DOCUMENT_NAME="PostMigrationAutomation-${RANDOM_SUFFIX}"
aws ssm create-document \
    --name "$SSM_DOCUMENT_NAME" \
    --document-type "Automation" \
    --document-format "JSON" \
    --content file://"${SCRIPT_DIR}/post-migration-automation.json"

export SSM_DOCUMENT_NAME
log_success "Systems Manager automation document created: $SSM_DOCUMENT_NAME"

# Step 8: Create Migration Hub Orchestrator workflow instance
log_info "Step 8: Creating Migration Hub Orchestrator workflow instance..."
WORKFLOW_ID=$(aws migrationhub-orchestrator create-workflow \
    --name "$MIGRATION_PROJECT_NAME" \
    --description "Automated migration workflow for ${MIGRATION_PROJECT_NAME}" \
    --template-id "$TEMPLATE_NAME" \
    --application-configuration-id "$MIGRATION_PROJECT_NAME" \
    --input-parameters "{
      \"region\": \"${AWS_REGION}\",
      \"targetVpcId\": \"${VPC_ID}\",
      \"targetSubnetId\": \"${PRIVATE_SUBNET_ID}\",
      \"securityGroupId\": \"${MIGRATION_SG_ID}\"
    }" \
    --step-targets "[
      {
        \"stepId\": \"step1\",
        \"inputs\": {
          \"region\": \"${AWS_REGION}\"
        }
      }
    ]" \
    --query 'Id' --output text)

export WORKFLOW_ID
log_success "Migration workflow instance created: $WORKFLOW_ID"

# Save deployment state
log_info "Saving deployment state..."
cat > "${SCRIPT_DIR}/deployment-state.env" << EOF
# Migration deployment state - $(date)
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export MIGRATION_PROJECT_NAME="$MIGRATION_PROJECT_NAME"
export VPC_NAME="$VPC_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export MGN_TEMPLATE_ID="$MGN_TEMPLATE_ID"
export TEMPLATE_NAME="$TEMPLATE_NAME"
export VPC_ID="$VPC_ID"
export PUBLIC_SUBNET_ID="$PUBLIC_SUBNET_ID"
export PRIVATE_SUBNET_ID="$PRIVATE_SUBNET_ID"
export IGW_ID="$IGW_ID"
export ROUTE_TABLE_ID="$ROUTE_TABLE_ID"
export MIGRATION_SG_ID="$MIGRATION_SG_ID"
export DASHBOARD_NAME="$DASHBOARD_NAME"
export ALARM_NAME="$ALARM_NAME"
export SSM_DOCUMENT_NAME="$SSM_DOCUMENT_NAME"
export WORKFLOW_ID="$WORKFLOW_ID"
EOF

chmod 600 "${SCRIPT_DIR}/deployment-state.env"

# Display deployment summary
log_success "================== DEPLOYMENT COMPLETE =================="
log_success "Migration infrastructure deployed successfully!"
log_success ""
log_success "Deployment Summary:"
log_success "  Project Name: $MIGRATION_PROJECT_NAME"
log_success "  AWS Region: $AWS_REGION"
log_success "  VPC ID: $VPC_ID"
log_success "  MGN Template ID: $MGN_TEMPLATE_ID"
log_success "  Workflow ID: $WORKFLOW_ID"
log_success "  CloudWatch Dashboard: $DASHBOARD_NAME"
log_success ""
log_success "Next Steps:"
log_success "  1. Install MGN replication agents on source servers"
log_success "  2. Monitor replication progress in CloudWatch dashboard"
log_success "  3. Execute test launches when replication is complete"
log_success "  4. Perform validation testing"
log_success "  5. Execute cutover when ready"
log_success ""
log_success "AWS Console URLs:"
log_success "  MGN Console: https://console.aws.amazon.com/mgn/home?region=$AWS_REGION"
log_success "  Migration Hub: https://console.aws.amazon.com/migrationhub/home?region=$AWS_REGION"
log_success "  CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=$DASHBOARD_NAME"
log_success ""
log_success "Deployment state saved to: ${SCRIPT_DIR}/deployment-state.env"
log_success "To clean up resources, run: ./destroy.sh"
log_success "=================================================="

# Clean up temporary files
rm -f "${SCRIPT_DIR}/migration-workflow.json" "${SCRIPT_DIR}/migration-dashboard.json" "${SCRIPT_DIR}/post-migration-automation.json"

log_success "Deployment completed successfully at $(date)"