#!/bin/bash

# Deploy script for AWS Systems Manager State Manager Configuration Management
# This script implements the infrastructure described in the recipe:
# "Configuration Management with Systems Manager"

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Starting cleanup..."
    
    # Remove temporary files
    rm -f state-manager-trust-policy.json
    rm -f state-manager-policy.json
    rm -f security-config-document.json
    rm -f remediation-document.json
    rm -f compliance-report.json
    rm -f dashboard-config.json
    
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_LOG="${SCRIPT_DIR}/deployment.log"
CONFIG_FILE="${SCRIPT_DIR}/../config/deployment.env"

# Start logging
exec > >(tee -a "${DEPLOYMENT_LOG}") 2>&1

log "Starting AWS Systems Manager State Manager deployment..."

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed for JSON processing
if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install it for JSON processing."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

success "Prerequisites check passed"

# Set environment variables
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    export AWS_REGION="us-east-1"
    warning "No region configured, using default: us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

# Set resource names
export ROLE_NAME="SSMStateManagerRole-${RANDOM_SUFFIX}"
export POLICY_NAME="SSMStateManagerPolicy-${RANDOM_SUFFIX}"
export ASSOCIATION_NAME="ConfigManagement-${RANDOM_SUFFIX}"
export SNS_TOPIC_NAME="config-drift-alerts-${RANDOM_SUFFIX}"
export CLOUDWATCH_LOG_GROUP="/aws/ssm/state-manager-${RANDOM_SUFFIX}"

success "Environment variables configured"

# Save configuration for cleanup
mkdir -p "${SCRIPT_DIR}/../config"
cat > "${CONFIG_FILE}" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
ROLE_NAME=${ROLE_NAME}
POLICY_NAME=${POLICY_NAME}
ASSOCIATION_NAME=${ASSOCIATION_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
CLOUDWATCH_LOG_GROUP=${CLOUDWATCH_LOG_GROUP}
EOF

# Step 1: Create CloudWatch log group
log "Creating CloudWatch log group..."
aws logs create-log-group \
    --log-group-name "${CLOUDWATCH_LOG_GROUP}" \
    --tags Key=Purpose,Value=StateManagerDemo \
           Key=Environment,Value=Demo \
           Key=CreatedBy,Value=DeployScript || true

success "CloudWatch log group created: ${CLOUDWATCH_LOG_GROUP}"

# Step 2: Create SNS topic
log "Creating SNS topic for notifications..."
export SNS_TOPIC_ARN=$(aws sns create-topic \
    --name "${SNS_TOPIC_NAME}" \
    --attributes DisplayName="Configuration Drift Alerts" \
    --query TopicArn --output text)

success "SNS topic created: ${SNS_TOPIC_ARN}"

# Update config with SNS ARN
echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> "${CONFIG_FILE}"

# Step 3: Create IAM role for State Manager
log "Creating IAM role for State Manager..."

# Create trust policy
cat > state-manager-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ssm.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create IAM role
aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document file://state-manager-trust-policy.json \
    --description "Role for Systems Manager State Manager operations" \
    --tags Key=Purpose,Value=StateManagerDemo \
           Key=Environment,Value=Demo \
           Key=CreatedBy,Value=DeployScript

# Get role ARN
export ROLE_ARN=$(aws iam get-role \
    --role-name "${ROLE_NAME}" \
    --query Role.Arn --output text)

success "IAM role created: ${ROLE_ARN}"

# Update config with role ARN
echo "ROLE_ARN=${ROLE_ARN}" >> "${CONFIG_FILE}"

# Step 4: Create and attach IAM policy
log "Creating IAM policy for State Manager..."

# Create custom policy
cat > state-manager-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:CreateAssociation",
                "ssm:DescribeAssociation*",
                "ssm:GetAutomationExecution",
                "ssm:ListAssociations",
                "ssm:ListDocuments",
                "ssm:SendCommand",
                "ssm:StartAutomationExecution",
                "ssm:DescribeInstanceInformation",
                "ssm:DescribeDocumentParameters",
                "ssm:ListCommandInvocations"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceAttribute",
                "ec2:DescribeImages",
                "ec2:DescribeSnapshots",
                "ec2:DescribeVolumes"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF

# Create and attach policy
aws iam create-policy \
    --policy-name "${POLICY_NAME}" \
    --policy-document file://state-manager-policy.json \
    --description "Policy for State Manager operations" \
    --tags Key=Purpose,Value=StateManagerDemo \
           Key=Environment,Value=Demo \
           Key=CreatedBy,Value=DeployScript

# Get policy ARN
export POLICY_ARN=$(aws iam list-policies \
    --scope Local \
    --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" \
    --output text)

# Attach policies to role
aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "${POLICY_ARN}"

aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

success "IAM policies attached to role"

# Update config with policy ARN
echo "POLICY_ARN=${POLICY_ARN}" >> "${CONFIG_FILE}"

# Step 5: Create custom security configuration document
log "Creating custom security configuration document..."

cat > security-config-document.json << 'EOF'
{
    "schemaVersion": "2.2",
    "description": "Configure security settings on Linux instances",
    "parameters": {
        "enableFirewall": {
            "type": "String",
            "description": "Enable firewall",
            "default": "true",
            "allowedValues": ["true", "false"]
        },
        "disableRootLogin": {
            "type": "String",
            "description": "Disable root SSH login",
            "default": "true",
            "allowedValues": ["true", "false"]
        }
    },
    "mainSteps": [
        {
            "action": "aws:runShellScript",
            "name": "configureFirewall",
            "precondition": {
                "StringEquals": ["platformType", "Linux"]
            },
            "inputs": {
                "runCommand": [
                    "#!/bin/bash",
                    "if [ '{{ enableFirewall }}' == 'true' ]; then",
                    "  if command -v ufw &> /dev/null; then",
                    "    ufw --force enable",
                    "    echo 'UFW firewall enabled'",
                    "  elif command -v firewall-cmd &> /dev/null; then",
                    "    systemctl enable firewalld",
                    "    systemctl start firewalld",
                    "    echo 'Firewalld enabled'",
                    "  fi",
                    "fi"
                ]
            }
        },
        {
            "action": "aws:runShellScript",
            "name": "configureSshSecurity",
            "precondition": {
                "StringEquals": ["platformType", "Linux"]
            },
            "inputs": {
                "runCommand": [
                    "#!/bin/bash",
                    "if [ '{{ disableRootLogin }}' == 'true' ]; then",
                    "  sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
                    "  if systemctl is-active --quiet sshd; then",
                    "    systemctl reload sshd",
                    "  fi",
                    "  echo 'Root SSH login disabled'",
                    "fi"
                ]
            }
        }
    ]
}
EOF

# Create the document
aws ssm create-document \
    --content file://security-config-document.json \
    --name "Custom-SecurityConfiguration-${RANDOM_SUFFIX}" \
    --document-type "Command" \
    --document-format JSON \
    --tags Key=Purpose,Value=StateManagerDemo \
           Key=Environment,Value=Demo \
           Key=CreatedBy,Value=DeployScript

export SECURITY_DOC_NAME="Custom-SecurityConfiguration-${RANDOM_SUFFIX}"

success "Custom security configuration document created: ${SECURITY_DOC_NAME}"

# Update config with document name
echo "SECURITY_DOC_NAME=${SECURITY_DOC_NAME}" >> "${CONFIG_FILE}"

# Step 6: Create automation document for remediation
log "Creating automated remediation document..."

cat > remediation-document.json << EOF
{
    "schemaVersion": "0.3",
    "description": "Automated remediation for configuration drift",
    "assumeRole": "{{ AutomationAssumeRole }}",
    "parameters": {
        "AutomationAssumeRole": {
            "type": "String",
            "description": "The ARN of the role for automation"
        },
        "InstanceId": {
            "type": "String",
            "description": "The ID of the non-compliant instance"
        },
        "AssociationId": {
            "type": "String",
            "description": "The ID of the failed association"
        }
    },
    "mainSteps": [
        {
            "name": "RerunAssociation",
            "action": "aws:executeAwsApi",
            "inputs": {
                "Service": "ssm",
                "Api": "StartAssociationsOnce",
                "AssociationIds": ["{{ AssociationId }}"]
            }
        },
        {
            "name": "WaitForCompletion",
            "action": "aws:waitForAwsResourceProperty",
            "inputs": {
                "Service": "ssm",
                "Api": "DescribeAssociationExecutions",
                "AssociationId": "{{ AssociationId }}",
                "PropertySelector": "$.AssociationExecutions[0].Status",
                "DesiredValues": ["Success"]
            },
            "timeoutSeconds": 300
        },
        {
            "name": "SendNotification",
            "action": "aws:executeAwsApi",
            "inputs": {
                "Service": "sns",
                "Api": "Publish",
                "TopicArn": "${SNS_TOPIC_ARN}",
                "Message": "Configuration drift remediation completed for instance {{ InstanceId }}"
            }
        }
    ]
}
EOF

# Create automation document
aws ssm create-document \
    --content file://remediation-document.json \
    --name "AutoRemediation-${RANDOM_SUFFIX}" \
    --document-type "Automation" \
    --document-format JSON \
    --tags Key=Purpose,Value=StateManagerDemo \
           Key=Environment,Value=Demo \
           Key=CreatedBy,Value=DeployScript

export REMEDIATION_DOC_NAME="AutoRemediation-${RANDOM_SUFFIX}"

success "Automated remediation document created: ${REMEDIATION_DOC_NAME}"

# Update config with remediation document name
echo "REMEDIATION_DOC_NAME=${REMEDIATION_DOC_NAME}" >> "${CONFIG_FILE}"

# Step 7: Create compliance report document
log "Creating compliance report document..."

cat > compliance-report.json << 'EOF'
{
    "schemaVersion": "0.3",
    "description": "Generate compliance report",
    "mainSteps": [
        {
            "name": "GenerateReport",
            "action": "aws:executeAwsApi",
            "inputs": {
                "Service": "ssm",
                "Api": "ListComplianceItems",
                "ResourceTypes": ["ManagedInstance"],
                "Filters": [
                    {
                        "Key": "ComplianceType",
                        "Values": ["Association"]
                    }
                ]
            }
        }
    ]
}
EOF

aws ssm create-document \
    --content file://compliance-report.json \
    --name "ComplianceReport-${RANDOM_SUFFIX}" \
    --document-type "Automation" \
    --document-format JSON \
    --tags Key=Purpose,Value=StateManagerDemo \
           Key=Environment,Value=Demo \
           Key=CreatedBy,Value=DeployScript

export COMPLIANCE_DOC_NAME="ComplianceReport-${RANDOM_SUFFIX}"

success "Compliance report document created: ${COMPLIANCE_DOC_NAME}"

# Update config with compliance document name
echo "COMPLIANCE_DOC_NAME=${COMPLIANCE_DOC_NAME}" >> "${CONFIG_FILE}"

# Step 8: Create CloudWatch dashboard
log "Creating CloudWatch dashboard..."

cat > dashboard-config.json << EOF
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
                    ["AWS/SSM", "AssociationExecutionsSucceeded", "AssociationName", "${ASSOCIATION_NAME}-Security"],
                    [".", "AssociationExecutionsFailed", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Association Execution Status"
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
                    ["AWS/SSM", "ComplianceByConfigRule", "RuleName", "${ASSOCIATION_NAME}-Security", "ComplianceType", "Association"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Compliance Status"
            }
        }
    ]
}
EOF

# Create dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "SSM-StateManager-${RANDOM_SUFFIX}" \
    --dashboard-body file://dashboard-config.json

export DASHBOARD_NAME="SSM-StateManager-${RANDOM_SUFFIX}"

success "CloudWatch dashboard created: ${DASHBOARD_NAME}"

# Update config with dashboard name
echo "DASHBOARD_NAME=${DASHBOARD_NAME}" >> "${CONFIG_FILE}"

# Step 9: Create CloudWatch alarms
log "Creating CloudWatch alarms for monitoring..."

# Create alarm for association failures
aws cloudwatch put-metric-alarm \
    --alarm-name "SSM-Association-Failures-${RANDOM_SUFFIX}" \
    --alarm-description "Monitor SSM association failures" \
    --metric-name "AssociationExecutionsFailed" \
    --namespace "AWS/SSM" \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 1 \
    --alarm-actions "${SNS_TOPIC_ARN}" \
    --dimensions Name=AssociationName,Value="${ASSOCIATION_NAME}-Security" \
    --tags Key=Purpose,Value=StateManagerDemo \
           Key=Environment,Value=Demo \
           Key=CreatedBy,Value=DeployScript

# Create alarm for compliance violations
aws cloudwatch put-metric-alarm \
    --alarm-name "SSM-Compliance-Violations-${RANDOM_SUFFIX}" \
    --alarm-description "Monitor compliance violations" \
    --metric-name "ComplianceByConfigRule" \
    --namespace "AWS/SSM" \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 1 \
    --alarm-actions "${SNS_TOPIC_ARN}" \
    --tags Key=Purpose,Value=StateManagerDemo \
           Key=Environment,Value=Demo \
           Key=CreatedBy,Value=DeployScript

success "CloudWatch alarms created for monitoring"

# Update config with alarm names
echo "ALARM_FAILURES=SSM-Association-Failures-${RANDOM_SUFFIX}" >> "${CONFIG_FILE}"
echo "ALARM_VIOLATIONS=SSM-Compliance-Violations-${RANDOM_SUFFIX}" >> "${CONFIG_FILE}"

# Step 10: Wait for role propagation
log "Waiting for IAM role propagation..."
sleep 30

# Step 11: Check for EC2 instances with appropriate tags
log "Checking for target EC2 instances..."

INSTANCE_COUNT=$(aws ec2 describe-instances \
    --filters "Name=tag:Environment,Values=Demo" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text | wc -w)

if [ "$INSTANCE_COUNT" -eq 0 ]; then
    warning "No EC2 instances found with Environment=Demo tag."
    warning "You can create associations manually or tag existing instances."
    warning "Example: aws ec2 create-tags --resources i-1234567890abcdef0 --tags Key=Environment,Value=Demo"
else
    success "Found ${INSTANCE_COUNT} target instances"
    
    # Create associations if instances exist
    log "Creating State Manager associations..."
    
    # Check if S3 bucket exists for output
    S3_BUCKET="aws-ssm-${AWS_REGION}-${AWS_ACCOUNT_ID}"
    if aws s3api head-bucket --bucket "${S3_BUCKET}" 2>/dev/null; then
        OUTPUT_LOCATION="S3Location={OutputS3Region=${AWS_REGION},OutputS3BucketName=${S3_BUCKET}}"
    else
        warning "S3 bucket ${S3_BUCKET} not found. Creating associations without S3 output."
        OUTPUT_LOCATION=""
    fi
    
    # Create association for SSM Agent updates
    if [ -n "$OUTPUT_LOCATION" ]; then
        export AGENT_ASSOCIATION_ID=$(aws ssm create-association \
            --name "AWS-UpdateSSMAgent" \
            --targets Key=tag:Environment,Values=Demo \
            --schedule-expression "rate(7 days)" \
            --association-name "${ASSOCIATION_NAME}-SSMAgent" \
            --output-location $OUTPUT_LOCATION \
            --query AssociationDescription.AssociationId --output text)
    else
        export AGENT_ASSOCIATION_ID=$(aws ssm create-association \
            --name "AWS-UpdateSSMAgent" \
            --targets Key=tag:Environment,Values=Demo \
            --schedule-expression "rate(7 days)" \
            --association-name "${ASSOCIATION_NAME}-SSMAgent" \
            --query AssociationDescription.AssociationId --output text)
    fi
    
    success "SSM Agent update association created: ${AGENT_ASSOCIATION_ID}"
    
    # Create association for security configuration
    if [ -n "$OUTPUT_LOCATION" ]; then
        export SECURITY_ASSOCIATION_ID=$(aws ssm create-association \
            --name "${SECURITY_DOC_NAME}" \
            --targets Key=tag:Environment,Values=Demo \
            --schedule-expression "rate(1 day)" \
            --association-name "${ASSOCIATION_NAME}-Security" \
            --parameters enableFirewall=true,disableRootLogin=true \
            --compliance-severity CRITICAL \
            --output-location $OUTPUT_LOCATION \
            --query AssociationDescription.AssociationId --output text)
    else
        export SECURITY_ASSOCIATION_ID=$(aws ssm create-association \
            --name "${SECURITY_DOC_NAME}" \
            --targets Key=tag:Environment,Values=Demo \
            --schedule-expression "rate(1 day)" \
            --association-name "${ASSOCIATION_NAME}-Security" \
            --parameters enableFirewall=true,disableRootLogin=true \
            --compliance-severity CRITICAL \
            --query AssociationDescription.AssociationId --output text)
    fi
    
    success "Security configuration association created: ${SECURITY_ASSOCIATION_ID}"
    
    # Update config with association IDs
    echo "AGENT_ASSOCIATION_ID=${AGENT_ASSOCIATION_ID}" >> "${CONFIG_FILE}"
    echo "SECURITY_ASSOCIATION_ID=${SECURITY_ASSOCIATION_ID}" >> "${CONFIG_FILE}"
fi

# Clean up temporary files
log "Cleaning up temporary files..."
rm -f state-manager-trust-policy.json
rm -f state-manager-policy.json
rm -f security-config-document.json
rm -f remediation-document.json
rm -f compliance-report.json
rm -f dashboard-config.json

success "Temporary files cleaned up"

# Final summary
echo ""
echo "=================================================================================="
echo "                    AWS Systems Manager State Manager Deployment"
echo "=================================================================================="
echo ""
echo "✅ Deployment completed successfully!"
echo ""
echo "📋 Resources Created:"
echo "   • IAM Role: ${ROLE_NAME}"
echo "   • IAM Policy: ${POLICY_NAME}"
echo "   • SNS Topic: ${SNS_TOPIC_NAME}"
echo "   • CloudWatch Log Group: ${CLOUDWATCH_LOG_GROUP}"
echo "   • Security Document: ${SECURITY_DOC_NAME}"
echo "   • Remediation Document: ${REMEDIATION_DOC_NAME}"
echo "   • Compliance Document: ${COMPLIANCE_DOC_NAME}"
echo "   • CloudWatch Dashboard: ${DASHBOARD_NAME}"
echo "   • CloudWatch Alarms: 2 monitoring alarms"
echo ""
echo "🔧 Configuration saved to: ${CONFIG_FILE}"
echo "📊 View dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
echo ""
echo "⚠️  Next Steps:"
echo "   1. Tag EC2 instances with 'Environment=Demo' to include them in State Manager"
echo "   2. Confirm SNS subscription in your email"
echo "   3. Monitor associations in Systems Manager console"
echo "   4. Review compliance reports in the dashboard"
echo ""
echo "🧹 To clean up resources, run: ./destroy.sh"
echo ""
echo "=================================================================================="

log "Deployment completed successfully!"