# Infrastructure as Code for Backup Strategies with S3 and Glacier

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Backup Strategies with S3 and Glacier".

## Overview

This infrastructure deploys a comprehensive backup strategy using Amazon S3 with intelligent lifecycle transitions to Glacier storage classes, automated backup scheduling with Lambda functions, and event-driven notifications through EventBridge. The solution provides cost-effective data protection with multiple storage tiers, automated retention policies, and robust validation mechanisms.

## Architecture Components

- **S3 Bucket** with versioning, encryption, and lifecycle policies
- **Lambda Function** for backup orchestration and validation
- **EventBridge Rules** for scheduled backup execution
- **CloudWatch Alarms** and Dashboard for monitoring
- **SNS Topic** for backup notifications
- **IAM Roles** and Policies for secure access
- **Cross-Region Replication** for disaster recovery

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code with AWS provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 (CreateBucket, PutBucketPolicy, PutBucketVersioning, PutBucketEncryption)
  - Lambda (CreateFunction, UpdateFunctionCode, InvokeFunction)
  - IAM (CreateRole, AttachRolePolicy, CreatePolicy)
  - EventBridge (PutRule, PutTargets)
  - CloudWatch (PutMetricAlarm, PutDashboard)
  - SNS (CreateTopic, Subscribe, Publish)
- Basic understanding of backup strategies and S3 storage classes
- Email address for backup notifications

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2 with CloudFormation permissions

#### CDK TypeScript
- Node.js 18+ and npm
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- TypeScript: `npm install -g typescript`

#### CDK Python
- Python 3.8+ and pip
- AWS CDK v2 installed: `pip install aws-cdk-lib`
- Required Python packages (see requirements.txt)

#### Terraform
- Terraform 1.0+ installed
- AWS provider plugin (automatically downloaded)

#### Scripts
- Bash shell (Linux/macOS/WSL)
- jq for JSON processing: `sudo apt-get install jq` or `brew install jq`

### Cost Estimation
- **S3 Storage**: $5-15/month for testing (varies by data volume and retention)
- **Lambda**: $0.20/million requests + $0.0000166667/GB-second
- **EventBridge**: $1.00/million events
- **CloudWatch**: $0.30/alarm/month + dashboard costs
- **Cross-Region Transfer**: $0.02/GB (if using cross-region replication)

> **Note**: Costs vary significantly based on data volume, access patterns, and retention periods. Glacier storage is ~80% cheaper than S3 Standard but has retrieval fees.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name backup-strategy-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name backup-strategy-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name backup-strategy-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
backup_bucket_name = "backup-strategy-demo-$(openssl rand -hex 3)"
environment = "dev"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/validate.sh
```

## Configuration Options

### Environment Variables

All implementations support these environment variables:

- `NOTIFICATION_EMAIL`: Email address for backup notifications (required)
- `AWS_REGION`: AWS region for deployment (defaults to configured region)
- `BACKUP_BUCKET_NAME`: Custom S3 bucket name (optional, auto-generated if not provided)
- `ENVIRONMENT`: Environment tag (dev/staging/prod, defaults to "dev")

### Customizable Parameters

#### Lifecycle Policy Settings
```bash
# Modify these values in your chosen implementation:
STANDARD_IA_TRANSITION_DAYS=30      # Days before moving to Infrequent Access
GLACIER_TRANSITION_DAYS=90          # Days before moving to Glacier
DEEP_ARCHIVE_TRANSITION_DAYS=365    # Days before moving to Deep Archive
VERSION_EXPIRATION_DAYS=2555        # Days to keep old versions (7 years)
```

#### Backup Schedule
```bash
# EventBridge cron expressions (UTC timezone):
DAILY_BACKUP_SCHEDULE="cron(0 2 * * ? *)"     # 2 AM daily
WEEKLY_BACKUP_SCHEDULE="cron(0 1 ? * SUN *)"  # 1 AM every Sunday
```

#### Lambda Configuration
```bash
LAMBDA_TIMEOUT=300          # Function timeout in seconds
LAMBDA_MEMORY=256          # Function memory in MB
LAMBDA_RUNTIME=python3.9   # Python runtime version
```

## Deployment Validation

After deployment, validate the infrastructure:

### 1. Verify S3 Bucket Configuration
```bash
# Get bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name backup-strategy-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BackupBucketName`].OutputValue' \
    --output text)

# Check bucket settings
aws s3api get-bucket-versioning --bucket $BUCKET_NAME
aws s3api get-bucket-encryption --bucket $BUCKET_NAME
aws s3api get-bucket-lifecycle-configuration --bucket $BUCKET_NAME
```

### 2. Test Lambda Function
```bash
# Get function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name backup-strategy-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BackupFunctionName`].OutputValue' \
    --output text)

# Test function execution
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{"backup_type":"test","source_prefix":"validation/"}' \
    test-response.json

cat test-response.json
```

### 3. Verify EventBridge Rules
```bash
# List backup-related rules
aws events list-rules --name-prefix "backup-" \
    --query 'Rules[].{Name:Name,State:State,Schedule:ScheduleExpression}'
```

### 4. Check CloudWatch Monitoring
```bash
# List backup-related alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix "backup-" \
    --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}'
```

### 5. Test Notifications
```bash
# Trigger a test backup to verify SNS notifications
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{"backup_type":"notification_test"}' \
    notification-test.json

echo "Check your email for backup notification"
```

## Monitoring and Operations

### CloudWatch Metrics
The solution publishes custom metrics to the `BackupStrategy` namespace:
- `BackupSuccess`: Count of successful backups
- `BackupDuration`: Duration of backup operations in seconds

### Dashboard Access
Access the CloudWatch dashboard:
```bash
# Get dashboard URL
aws cloudwatch list-dashboards \
    --dashboard-name-prefix "backup-strategy" \
    --query 'DashboardEntries[0].DashboardName'
```

### Log Analysis
```bash
# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/backup-orchestrator"

# Get recent log events
LOG_GROUP="/aws/lambda/backup-orchestrator-$(echo $FUNCTION_NAME | cut -d'-' -f3-)"
aws logs describe-log-streams \
    --log-group-name $LOG_GROUP \
    --order-by LastEventTime \
    --descending \
    --max-items 1
```

## Testing Backup and Restore

### Upload Test Data
```bash
# Create test files
mkdir -p test-data
echo "Test business data - $(date)" > test-data/business-data.txt
echo "Test customer records - $(date)" > test-data/customer-records.txt

# Upload to backup bucket
aws s3 cp test-data/ s3://$BUCKET_NAME/test-data/ --recursive
```

### Validate Lifecycle Transitions
```bash
# Check object storage classes (may take time for transitions)
aws s3api list-objects-v2 --bucket $BUCKET_NAME \
    --query 'Contents[].{Key:Key,StorageClass:StorageClass,LastModified:LastModified}' \
    --output table
```

### Test Glacier Restore
```bash
# Find objects in Glacier (after lifecycle transition)
aws s3api list-objects-v2 --bucket $BUCKET_NAME \
    --query 'Contents[?StorageClass==`GLACIER`].Key' \
    --output text

# Initiate restore for testing (costs apply)
# aws s3api restore-object \
#     --bucket $BUCKET_NAME \
#     --key "test-data/business-data.txt" \
#     --restore-request Days=1,GlacierJobParameters='{Tier=Standard}'
```

## Troubleshooting

### Common Issues

#### 1. Email Subscription Not Confirmed
```bash
# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn $(aws cloudformation describe-stacks \
        --stack-name backup-strategy-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
        --output text)
```

#### 2. Lambda Function Timeouts
```bash
# Increase timeout in your IaC configuration
# CloudFormation: Update Timeout property
# CDK: function.addToRolePolicy() for additional permissions
# Terraform: Modify timeout in aws_lambda_function resource
```

#### 3. IAM Permission Issues
```bash
# Check Lambda execution role permissions
aws iam list-attached-role-policies \
    --role-name $(aws cloudformation describe-stacks \
        --stack-name backup-strategy-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`BackupRoleName`].OutputValue' \
        --output text)
```

#### 4. EventBridge Rules Not Triggering
```bash
# Verify rule targets
aws events list-targets-by-rule \
    --rule $(aws events list-rules --name-prefix "daily-backup" \
        --query 'Rules[0].Name' --output text)
```

### Debug Commands
```bash
# Enable Lambda function logging
aws logs create-log-group \
    --log-group-name "/aws/lambda/backup-orchestrator-debug"

# Test with verbose payload
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{"backup_type":"debug","source_prefix":"test/","debug":true}' \
    debug-response.json
```

## Security Considerations

### IAM Best Practices
- The Lambda execution role follows least privilege principle
- S3 bucket policies restrict public access
- Cross-region replication uses dedicated service role

### Encryption
- S3 bucket uses AES-256 server-side encryption
- SNS messages are encrypted in transit
- Lambda environment variables can be encrypted with KMS

### Network Security
- S3 bucket blocks all public access
- Lambda function runs in AWS managed VPC by default
- EventBridge rules are region-scoped

## Cleanup

### Using CloudFormation (AWS)
```bash
# Delete the stack (removes all resources)
aws cloudformation delete-stack --stack-name backup-strategy-stack

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name backup-strategy-stack \
    --query 'Stacks[0].StackStatus' 2>/dev/null || echo "Stack deleted"
```

### Using CDK (AWS)
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

### Manual Cleanup (if needed)
```bash
# Empty S3 bucket before deletion (if stack deletion fails)
aws s3 rm s3://$BUCKET_NAME --recursive

# Delete all object versions
aws s3api list-object-versions --bucket $BUCKET_NAME \
    --output json --query 'Versions[].{Key:Key,VersionId:VersionId}' | \
    jq -r '.[] | "--key \(.Key) --version-id \(.VersionId)"' | \
    xargs -I {} aws s3api delete-object --bucket $BUCKET_NAME {}

# Remove any lingering resources
aws s3api delete-bucket --bucket $BUCKET_NAME
```

## Cost Optimization

### Storage Cost Analysis
```bash
# Generate storage analytics report
aws s3api put-bucket-analytics-configuration \
    --bucket $BUCKET_NAME \
    --id backup-analytics \
    --analytics-configuration '{
        "Id": "backup-analytics",
        "StorageClassAnalysis": {
            "DataExport": {
                "OutputSchemaVersion": "V_1",
                "Destination": {
                    "S3BucketDestination": {
                        "Bucket": "arn:aws:s3:::'$BUCKET_NAME'",
                        "Prefix": "analytics/"
                    }
                }
            }
        }
    }'
```

### Lifecycle Policy Optimization
```bash
# Review current lifecycle configuration
aws s3api get-bucket-lifecycle-configuration --bucket $BUCKET_NAME \
    --query 'Rules[0].Transitions[].{Days:Days,StorageClass:StorageClass}'

# Analyze access patterns to optimize transition days
# Consider using S3 Intelligent-Tiering for automatic optimization
```

## Support and Documentation

### Additional Resources
- [AWS S3 Lifecycle Management](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS Backup Strategies](https://docs.aws.amazon.com/prescriptive-guidance/latest/backup-recovery/backup-recovery.html)
- [S3 Storage Classes Comparison](https://aws.amazon.com/s3/storage-classes/)

### Getting Help
For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS CloudFormation/CDK/Terraform documentation
3. Consult the original recipe documentation
4. Check AWS service status pages for regional issues

### Contributing
To improve this infrastructure code:
1. Test changes in a development environment
2. Follow AWS best practices for security and cost optimization
3. Update documentation for any new features
4. Validate against the original recipe requirements