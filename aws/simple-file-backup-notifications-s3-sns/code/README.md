# Infrastructure as Code for Simple File Backup Notifications with S3 and SNS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple File Backup Notifications with S3 and SNS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- Valid email address for notifications
- Permissions required:
  - `s3:CreateBucket`, `s3:DeleteBucket`, `s3:PutBucketNotification`
  - `s3:PutBucketVersioning`, `s3:PutBucketEncryption`
  - `sns:CreateTopic`, `sns:DeleteTopic`, `sns:Subscribe`
  - `sns:SetTopicAttributes`, `sns:GetTopicAttributes`
  - `iam:PassRole` (for service integrations)

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI v2.0 or later

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform v1.0 or later
- AWS Provider v5.0 or later

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name simple-backup-notifications \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
        ParameterKey=BucketName,ParameterValue=my-backup-bucket-$(date +%s) \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name simple-backup-notifications

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name simple-backup-notifications \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure your email address
npm run cdk -- deploy --parameters NotificationEmail=your-email@example.com

# Or set environment variable
export NOTIFICATION_EMAIL=your-email@example.com
npm run cdk deploy
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure your email address
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
bucket_name_prefix = "backup-notifications"
aws_region = "us-east-1"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts and confirm email subscription
```

## Testing the Deployment

After deployment, test the notification system:

```bash
# Get the bucket name from outputs (adjust based on deployment method)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name simple-backup-notifications \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

# Create and upload a test file
echo "Test backup file created at $(date)" > test-backup.txt
aws s3 cp test-backup.txt s3://${BUCKET_NAME}/

# Check your email for the notification (may take 1-2 minutes)
```

## Cleanup

### Using CloudFormation

```bash
# Empty the S3 bucket first (required before deletion)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name simple-backup-notifications \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name simple-backup-notifications

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name simple-backup-notifications
```

### Using CDK

```bash
# From the respective CDK directory (cdk-typescript/ or cdk-python/)

# Empty the S3 bucket first
aws s3 rm s3://$(cdk list --json | jq -r '.[0]' | cut -d'-' -f3-) --recursive

# Destroy the stack
cdk destroy
```

### Using Terraform

```bash
cd terraform/

# Terraform will handle S3 bucket emptying automatically
terraform destroy
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Architecture Components

The infrastructure creates the following AWS resources:

- **S3 Bucket**: Secure storage for backup files with:
  - Versioning enabled for data protection
  - Server-side encryption (AES256)
  - Event notifications configured
- **SNS Topic**: Message distribution service for notifications
- **SNS Subscription**: Email endpoint for receiving alerts
- **IAM Policies**: Secure service-to-service communication
- **S3 Bucket Policy**: Allows SNS publishing from S3 events

## Customization

### Parameters/Variables

All implementations support these customization options:

- **NotificationEmail/notification_email**: Email address for notifications
- **BucketName/bucket_name_prefix**: Custom bucket name or prefix
- **AwsRegion/aws_region**: AWS region for deployment
- **EnableVersioning**: Toggle S3 bucket versioning (default: true)
- **EncryptionAlgorithm**: S3 encryption method (default: AES256)

### Event Filtering

To customize which S3 events trigger notifications, modify the event configuration:

- **S3 Event Types**: ObjectCreated:*, ObjectRemoved:*, etc.
- **Object Prefixes**: Filter by folder or file name patterns
- **Object Suffixes**: Filter by file extensions

### Advanced Configurations

- **Multiple Email Recipients**: Add additional SNS subscriptions
- **Cross-Region Notifications**: Deploy SNS topics in multiple regions
- **Custom Message Formatting**: Use SNS message attributes and filtering
- **Integration with Other Services**: Add Lambda functions, SQS queues, etc.

## Cost Considerations

This solution follows a pay-per-use model:

- **S3 Storage**: $0.023/GB/month (Standard storage class)
- **S3 Requests**: $0.0004 per 1,000 PUT requests
- **SNS Messages**: $0.50 per 1 million messages
- **Email Notifications**: $2.00 per 100,000 notifications

Estimated monthly cost for typical backup scenarios: $0.01-$0.50

## Security Features

The infrastructure implements security best practices:

- **Least Privilege IAM**: Minimal permissions for service integrations
- **Encryption at Rest**: S3 server-side encryption enabled
- **Account-Level Restrictions**: SNS policies restrict access to your account
- **Resource-Level Policies**: S3 bucket policies prevent unauthorized access
- **Email Confirmation**: SNS requires explicit subscription confirmation

## Troubleshooting

### Common Issues

1. **Email notifications not received**:
   - Check spam/junk folders
   - Confirm SNS subscription via email link
   - Verify SNS topic policy allows S3 publishing

2. **S3 bucket creation fails**:
   - Bucket names must be globally unique
   - Use the random suffix generation in scripts
   - Check AWS region availability

3. **Permission denied errors**:
   - Verify AWS CLI credentials have required permissions
   - Check IAM policies and role assignments
   - Ensure cross-service policies are correctly configured

### Validation Commands

```bash
# Check SNS topic exists and has subscription
aws sns list-topics --query 'Topics[?contains(TopicArn, `backup-alerts`)]'
aws sns list-subscriptions --query 'Subscriptions[?contains(TopicArn, `backup-alerts`)]'

# Verify S3 bucket configuration
aws s3api get-bucket-notification-configuration --bucket YOUR_BUCKET_NAME
aws s3api get-bucket-versioning --bucket YOUR_BUCKET_NAME
aws s3api get-bucket-encryption --bucket YOUR_BUCKET_NAME

# Test S3 to SNS connectivity
aws s3 cp test-file.txt s3://YOUR_BUCKET_NAME/
aws logs filter-log-events --log-group-name /aws/sns/YOUR_REGION/YOUR_ACCOUNT/YOUR_TOPIC
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for step-by-step guidance
2. **AWS Documentation**: 
   - [S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/notification-how-to.html)
   - [SNS Getting Started](https://docs.aws.amazon.com/sns/latest/dg/sns-getting-started.html)
3. **Community Support**: AWS forums and Stack Overflow
4. **AWS Support**: For production deployments, consider AWS Support plans

## Best Practices

- **Environment Separation**: Use different stacks/deployments for dev/staging/prod
- **Resource Tagging**: Add consistent tags for cost allocation and management
- **Monitoring**: Set up CloudWatch alarms for failed notifications
- **Backup Testing**: Regularly test the notification system with sample uploads
- **Documentation**: Keep deployment parameters and customizations documented

## Next Steps

Consider these enhancements for production use:

- **Multi-Region Deployment**: Deploy across multiple AWS regions for redundancy
- **Advanced Filtering**: Implement object-level filtering for specific backup types
- **Integration**: Connect with monitoring systems, ITSM tools, or chat platforms
- **Automation**: Integrate with CI/CD pipelines for infrastructure updates
- **Compliance**: Add logging and audit trails for regulatory requirements