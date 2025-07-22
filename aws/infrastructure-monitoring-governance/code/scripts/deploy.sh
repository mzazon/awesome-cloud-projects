#!/bin/bash

# Infrastructure Monitoring Deployment Script
# Deploys CloudTrail, Config, and Systems Manager monitoring solution
# Recipe: infrastructure-monitoring-cloudtrail-config-systems-manager

set -euo pipefail

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for failed deployments
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    if [[ -n "${MONITORING_BUCKET:-}" ]]; then
        aws s3 rm s3://${MONITORING_BUCKET} --recursive 2>/dev/null || true
        aws s3 rb s3://${MONITORING_BUCKET} 2>/dev/null || true
    fi
    if [[ -n "${CONFIG_ROLE:-}" ]]; then
        aws iam detach-role-policy --role-name ${CONFIG_ROLE} \
            --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole 2>/dev/null || true
        aws iam delete-role-policy --role-name ${CONFIG_ROLE} --policy-name ConfigS3Policy 2>/dev/null || true
        aws iam delete-role --role-name ${CONFIG_ROLE} 2>/dev/null || true
    fi
    if [[ -n "${SNS_TOPIC:-}" ]]; then
        aws sns delete-topic --topic-arn arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC} 2>/dev/null || true
    fi
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Banner
echo "============================================================"
echo "  AWS Infrastructure Monitoring Deployment Script"
echo "  CloudTrail + Config + Systems Manager"
echo "============================================================"
echo

# Prerequisites check
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI v2."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
    exit 1
fi

# Check required permissions
log "Validating AWS permissions..."
if ! aws iam list-roles --max-items 1 &> /dev/null; then
    error "Insufficient IAM permissions. This script requires administrative access."
    exit 1
fi

success "Prerequisites check passed"

# Environment setup
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [[ -z "${AWS_REGION}" ]]; then
    warning "No default region configured. Using us-east-1"
    export AWS_REGION="us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || \
    echo $(date +%s | tail -c 6))

export MONITORING_BUCKET="infrastructure-monitoring-${RANDOM_SUFFIX}"
export SNS_TOPIC="infrastructure-alerts-${RANDOM_SUFFIX}"
export CONFIG_ROLE="ConfigRole-${RANDOM_SUFFIX}"
export CLOUDTRAIL_NAME="InfrastructureTrail-${RANDOM_SUFFIX}"

log "Deployment configuration:"
log "  Region: ${AWS_REGION}"
log "  Account ID: ${AWS_ACCOUNT_ID}"
log "  S3 Bucket: ${MONITORING_BUCKET}"
log "  SNS Topic: ${SNS_TOPIC}"
log "  Config Role: ${CONFIG_ROLE}"
log "  CloudTrail: ${CLOUDTRAIL_NAME}"

# Confirmation prompt
echo
read -p "Do you want to proceed with the deployment? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user"
    exit 0
fi

# Step 1: Create S3 bucket for monitoring data
log "Step 1: Creating S3 bucket for monitoring data..."

if aws s3 ls s3://${MONITORING_BUCKET} &> /dev/null; then
    warning "Bucket ${MONITORING_BUCKET} already exists"
else
    aws s3 mb s3://${MONITORING_BUCKET} --region ${AWS_REGION}
    aws s3api put-bucket-versioning \
        --bucket ${MONITORING_BUCKET} \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket ${MONITORING_BUCKET} \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    success "S3 bucket created and configured: ${MONITORING_BUCKET}"
fi

# Step 2: Create IAM role for AWS Config
log "Step 2: Creating IAM role for AWS Config..."

if aws iam get-role --role-name ${CONFIG_ROLE} &> /dev/null; then
    warning "IAM role ${CONFIG_ROLE} already exists"
else
    # Create trust policy
    cat > /tmp/config-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "config.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    # Create the IAM role
    aws iam create-role \
        --role-name ${CONFIG_ROLE} \
        --assume-role-policy-document file:///tmp/config-trust-policy.json

    # Attach AWS managed policy
    aws iam attach-role-policy \
        --role-name ${CONFIG_ROLE} \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole

    # Create custom S3 policy
    cat > /tmp/config-s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketAcl",
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::${MONITORING_BUCKET}"
    },
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${MONITORING_BUCKET}/AWSLogs/${AWS_ACCOUNT_ID}/Config/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::${MONITORING_BUCKET}"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name ${CONFIG_ROLE} \
        --policy-name ConfigS3Policy \
        --policy-document file:///tmp/config-s3-policy.json

    success "Config IAM role created: ${CONFIG_ROLE}"
fi

# Step 3: Create SNS topic for notifications
log "Step 3: Creating SNS topic for notifications..."

if aws sns get-topic-attributes --topic-arn arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC} &> /dev/null; then
    warning "SNS topic ${SNS_TOPIC} already exists"
    SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
else
    aws sns create-topic --name ${SNS_TOPIC}
    SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
    
    success "SNS topic created: ${SNS_TOPIC}"
fi

# Prompt for email subscription
echo
read -p "Enter email address for notifications (press Enter to skip): " EMAIL_ADDRESS
if [[ -n "${EMAIL_ADDRESS}" ]]; then
    aws sns subscribe \
        --topic-arn ${SNS_TOPIC_ARN} \
        --protocol email \
        --notification-endpoint ${EMAIL_ADDRESS}
    warning "Please check your email and confirm the SNS subscription"
fi

# Step 4: Configure AWS Config
log "Step 4: Configuring AWS Config..."

# Wait for IAM role to be available
log "Waiting for IAM role to be ready..."
sleep 30

# Check if Config is already set up
if aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[?name==`default`]' --output text 2>/dev/null | grep -q default; then
    warning "AWS Config is already configured"
else
    # Create configuration recorder
    aws configservice put-configuration-recorder \
        --configuration-recorder name=default,roleARN=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CONFIG_ROLE} \
        --recording-group allSupported=true,includeGlobalResourceTypes=true

    # Create delivery channel
    aws configservice put-delivery-channel \
        --delivery-channel name=default,s3BucketName=${MONITORING_BUCKET},snsTopicARN=${SNS_TOPIC_ARN}

    # Start the configuration recorder
    aws configservice start-configuration-recorder \
        --configuration-recorder-name default

    success "AWS Config configured and recording"
fi

# Step 5: Set up CloudTrail
log "Step 5: Setting up CloudTrail..."

if aws cloudtrail describe-trails --trail-name-list ${CLOUDTRAIL_NAME} --query 'trailList[0].Name' --output text 2>/dev/null | grep -q ${CLOUDTRAIL_NAME}; then
    warning "CloudTrail ${CLOUDTRAIL_NAME} already exists"
else
    # Create CloudTrail bucket policy
    cat > /tmp/cloudtrail-bucket-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::${MONITORING_BUCKET}"
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${MONITORING_BUCKET}/AWSLogs/${AWS_ACCOUNT_ID}/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    }
  ]
}
EOF

    # Update bucket policy
    EXISTING_POLICY=$(aws s3api get-bucket-policy --bucket ${MONITORING_BUCKET} --query Policy --output text 2>/dev/null || echo '{}')
    if [[ "${EXISTING_POLICY}" == "{}" ]]; then
        aws s3api put-bucket-policy \
            --bucket ${MONITORING_BUCKET} \
            --policy file:///tmp/cloudtrail-bucket-policy.json
    else
        warning "Bucket policy already exists, skipping CloudTrail policy update"
    fi

    # Create CloudTrail
    aws cloudtrail create-trail \
        --name ${CLOUDTRAIL_NAME} \
        --s3-bucket-name ${MONITORING_BUCKET} \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation

    # Start logging
    aws cloudtrail start-logging --name ${CLOUDTRAIL_NAME}

    success "CloudTrail configured: ${CLOUDTRAIL_NAME}"
fi

# Step 6: Configure Systems Manager
log "Step 6: Configuring Systems Manager..."

# Create maintenance window
MAINTENANCE_WINDOW_ID=$(aws ssm create-maintenance-window \
    --name "InfrastructureMonitoring-${RANDOM_SUFFIX}" \
    --description "Automated infrastructure monitoring tasks" \
    --duration 4 \
    --cutoff 1 \
    --schedule "cron(0 02 ? * SUN *)" \
    --allow-unassociated-targets \
    --query 'WindowId' --output text 2>/dev/null || \
    aws ssm describe-maintenance-windows \
        --filters Key=Name,Values="InfrastructureMonitoring-${RANDOM_SUFFIX}" \
        --query 'WindowIdentities[0].WindowId' --output text 2>/dev/null)

if [[ "${MAINTENANCE_WINDOW_ID}" != "None" && -n "${MAINTENANCE_WINDOW_ID}" ]]; then
    success "Systems Manager maintenance window: ${MAINTENANCE_WINDOW_ID}"
else
    warning "Failed to create maintenance window"
fi

# Create OpsItem
aws ssm create-ops-item \
    --title "Infrastructure Monitoring Setup Complete - ${RANDOM_SUFFIX}" \
    --description "CloudTrail, Config, and Systems Manager monitoring has been configured" \
    --priority 3 \
    --source "User" \
    --ops-item-type "Infrastructure" \
    --tags Key=Project,Value=InfrastructureMonitoring || true

success "Systems Manager OpsItem created"

# Step 7: Create Config rules
log "Step 7: Creating Config compliance rules..."

# Wait for Config to be ready
log "Waiting for Config to initialize..."
sleep 60

# Array of Config rules to create
declare -a config_rules=(
    "s3-bucket-public-access-prohibited:S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
    "encrypted-volumes:ENCRYPTED_VOLUMES"
    "root-access-key-check:ROOT_ACCESS_KEY_CHECK"
    "iam-password-policy:IAM_PASSWORD_POLICY"
)

for rule in "${config_rules[@]}"; do
    rule_name="${rule%%:*}"
    source_identifier="${rule##*:}"
    
    if aws configservice describe-config-rules --config-rule-names ${rule_name} &> /dev/null; then
        warning "Config rule ${rule_name} already exists"
    else
        aws configservice put-config-rule \
            --config-rule ConfigRuleName=${rule_name},Source="{Owner=AWS,SourceIdentifier=${source_identifier}}" || true
        log "Created Config rule: ${rule_name}"
    fi
done

success "Config compliance rules created"

# Step 8: Create CloudWatch dashboard
log "Step 8: Creating CloudWatch dashboard..."

cat > /tmp/dashboard-body.json << EOF
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
          [ "AWS/Config", "ComplianceByConfigRule", "ConfigRuleName", "s3-bucket-public-access-prohibited" ],
          [ ".", ".", ".", "encrypted-volumes" ],
          [ ".", ".", ".", "root-access-key-check" ],
          [ ".", ".", ".", "iam-password-policy" ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "Config Rule Compliance"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/events/rule/config-rule-compliance-change'\n| fields @timestamp, detail.newEvaluationResult.evaluationResultIdentifier.evaluationResultQualifier.resourceId, detail.newEvaluationResult.complianceType\n| filter detail.newEvaluationResult.complianceType = \"NON_COMPLIANT\"\n| sort @timestamp desc\n| limit 20",
        "region": "${AWS_REGION}",
        "title": "Recent Non-Compliant Resources"
      }
    }
  ]
}
EOF

aws cloudwatch put-dashboard \
    --dashboard-name "InfrastructureMonitoring-${RANDOM_SUFFIX}" \
    --dashboard-body file:///tmp/dashboard-body.json

success "CloudWatch dashboard created: InfrastructureMonitoring-${RANDOM_SUFFIX}"

# Cleanup temporary files
log "Cleaning up temporary files..."
rm -f /tmp/config-trust-policy.json /tmp/config-s3-policy.json /tmp/cloudtrail-bucket-policy.json /tmp/dashboard-body.json

# Save configuration for cleanup script
log "Saving deployment configuration..."
cat > /tmp/infrastructure-monitoring-config.env << EOF
# Infrastructure Monitoring Deployment Configuration
# Generated on $(date)
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
MONITORING_BUCKET=${MONITORING_BUCKET}
SNS_TOPIC=${SNS_TOPIC}
CONFIG_ROLE=${CONFIG_ROLE}
CLOUDTRAIL_NAME=${CLOUDTRAIL_NAME}
SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
MAINTENANCE_WINDOW_ID=${MAINTENANCE_WINDOW_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF

# Display summary
echo
echo "============================================================"
echo "  🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉"
echo "============================================================"
echo
success "Infrastructure monitoring solution deployed successfully!"
echo
log "Resources created:"
log "  • S3 Bucket: ${MONITORING_BUCKET}"
log "  • SNS Topic: ${SNS_TOPIC}"
log "  • Config Role: ${CONFIG_ROLE}"
log "  • CloudTrail: ${CLOUDTRAIL_NAME}"
log "  • Maintenance Window: ${MAINTENANCE_WINDOW_ID}"
echo
log "Access points:"
log "  • CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=InfrastructureMonitoring-${RANDOM_SUFFIX}"
log "  • Config Console: https://console.aws.amazon.com/config/home?region=${AWS_REGION}"
log "  • CloudTrail Console: https://console.aws.amazon.com/cloudtrail/home?region=${AWS_REGION}"
log "  • Systems Manager: https://console.aws.amazon.com/systems-manager/home?region=${AWS_REGION}"
echo
warning "Configuration saved to: /tmp/infrastructure-monitoring-config.env"
warning "Save this file for cleanup purposes!"
echo
log "🔍 Monitor your infrastructure compliance and security events through the dashboard"
if [[ -n "${EMAIL_ADDRESS}" ]]; then
    warning "📧 Don't forget to confirm your email subscription for alerts!"
fi
echo
log "For cleanup, run: ./destroy.sh"