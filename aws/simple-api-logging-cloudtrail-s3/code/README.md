# Infrastructure as Code for Simple API Logging with CloudTrail and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple API Logging with CloudTrail and S3". This solution implements AWS CloudTrail to automatically capture and log all API calls across your AWS account, storing the audit logs in a secure S3 bucket with proper access controls and CloudWatch integration for real-time monitoring.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- AWS account with administrative permissions for CloudTrail, S3, CloudWatch, and IAM services
- For CDK implementations: Node.js (v18+) and AWS CDK CLI installed
- For Terraform: Terraform CLI (v1.0+) installed
- Basic understanding of AWS services and security best practices
- Appropriate IAM permissions for resource creation

## Architecture Overview

This implementation creates:
- AWS CloudTrail trail with multi-region support
- S3 bucket with encryption, versioning, and proper bucket policies
- CloudWatch Log Group with configurable retention
- IAM role for CloudTrail to CloudWatch Logs integration
- CloudWatch alarm for root account usage monitoring
- SNS topic for security notifications

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name simple-api-logging-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=LogRetentionDays,ParameterValue=30 \
    --capabilities CAPABILITY_IAM

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name simple-api-logging-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name simple-api-logging-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Review changes
cdk diff

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Review changes
cdk diff

# Deploy the stack
cdk deploy

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
aws cloudtrail describe-trails --query 'trailList[?Name==`api-logging-trail-*`]'
```

## Configuration Options

### CloudFormation Parameters

- `LogRetentionDays`: CloudWatch Logs retention period (default: 30 days)
- `EnableRootAccountAlarm`: Enable CloudWatch alarm for root account usage (default: true)
- `S3BucketPrefix`: Custom prefix for S3 bucket name (optional)

### CDK Configuration

Both CDK implementations support environment variables:

```bash
export LOG_RETENTION_DAYS=30
export ENABLE_ROOT_ALARM=true
export CUSTOM_BUCKET_PREFIX=my-org
```

### Terraform Variables

```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
log_retention_days = 30
enable_root_account_alarm = true
custom_bucket_prefix = "my-org"
EOF
```

## Validation

After deployment, verify the solution is working:

```bash
# Check CloudTrail status
aws cloudtrail get-trail-status --name $(aws cloudtrail describe-trails --query 'trailList[0].Name' --output text)

# Verify S3 bucket exists and has proper configuration
BUCKET_NAME=$(aws cloudtrail describe-trails --query 'trailList[0].S3BucketName' --output text)
aws s3api get-bucket-encryption --bucket $BUCKET_NAME
aws s3api get-bucket-versioning --bucket $BUCKET_NAME

# Check CloudWatch Log Group
aws logs describe-log-groups --log-group-name-prefix "/aws/cloudtrail/"

# Test alarm configuration
aws cloudwatch describe-alarms --alarm-names "CloudTrail-RootAccountUsage-*"
```

## Monitoring and Alerting

The solution includes built-in monitoring:

- **CloudWatch Logs**: Real-time API event streaming
- **Root Account Alarm**: Triggers on root account usage
- **SNS Notifications**: Configurable alerting endpoint
- **Log Retention**: Automatic cleanup based on retention policy

To receive notifications, subscribe to the SNS topic:

```bash
# Get SNS topic ARN from outputs
TOPIC_ARN=$(terraform output -raw sns_topic_arn)  # For Terraform
# or from CloudFormation/CDK outputs

# Subscribe email to receive alerts
aws sns subscribe \
    --topic-arn $TOPIC_ARN \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Custom roles with minimal required permissions
- **Encryption**: S3 server-side encryption enabled
- **Access Control**: Bucket policies with source ARN conditions
- **Log File Validation**: CloudTrail integrity verification enabled
- **Multi-Region**: Trail captures events across all AWS regions
- **Public Access Block**: S3 bucket secured against public access

## Cost Optimization

To optimize costs:

1. **Adjust Log Retention**: Modify CloudWatch Logs retention period
2. **S3 Lifecycle Policies**: Implement automated archiving to cheaper storage classes
3. **Event Filtering**: Configure data events only for critical resources
4. **Regional Considerations**: Use single-region trail if multi-region isn't required

```bash
# Example: Set S3 lifecycle policy for log archiving
aws s3api put-bucket-lifecycle-configuration \
    --bucket $BUCKET_NAME \
    --lifecycle-configuration file://lifecycle-policy.json
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name simple-api-logging-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name simple-api-logging-stack
```

### Using CDK (AWS)

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure your AWS credentials have sufficient permissions
2. **Bucket Name Conflicts**: S3 bucket names must be globally unique
3. **CloudTrail Delays**: Log delivery may take 5-10 minutes initially
4. **CDK Bootstrap**: First-time CDK users need to run `cdk bootstrap`

### Verification Commands

```bash
# Check CloudTrail events
aws cloudtrail lookup-events --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S.000Z)

# Verify S3 log delivery
aws s3 ls s3://$BUCKET_NAME/AWSLogs/ --recursive

# Check CloudWatch Logs
aws logs describe-log-streams --log-group-name "/aws/cloudtrail/api-logging-trail-*"
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation in `../simple-api-logging-cloudtrail-s3.md`
2. Consult AWS CloudTrail documentation: https://docs.aws.amazon.com/cloudtrail/
3. Check AWS CloudFormation/CDK/Terraform provider documentation
4. Verify IAM permissions and service quotas

## Customization

Each implementation can be customized for your environment:

- **Naming Conventions**: Modify resource prefixes and naming patterns
- **Security Policies**: Adjust IAM policies and S3 bucket policies
- **Monitoring Rules**: Add custom CloudWatch metric filters
- **Retention Policies**: Configure appropriate log retention periods
- **Notification Endpoints**: Integrate with existing alerting systems

Refer to the variable definitions in each implementation to understand available customization options.