# Infrastructure as Code for S3 Glacier Deep Archive for Long-term Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "S3 Glacier Deep Archive for Long-term Storage".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a comprehensive long-term archiving solution that includes:

- S3 bucket configured for archival storage
- Lifecycle policies for automatic transition to Glacier Deep Archive
- SNS topic for archive event notifications
- S3 event notifications for monitoring archive activities
- S3 inventory configuration for compliance tracking
- IAM roles and policies with least privilege access

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - SNS topic creation and subscription
  - IAM role and policy creation
  - CloudWatch Events (for event notifications)
- For CDK implementations: Node.js 18+ or Python 3.8+
- For Terraform: Terraform 1.0+

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name long-term-archive-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name long-term-archive-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name long-term-archive-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy \
    --parameters notificationEmail=your-email@example.com

# View deployed resources
npx cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy \
    --parameters notificationEmail=your-email@example.com

# View deployed resources
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="notification_email=your-email@example.com"

# Apply configuration
terraform apply \
    -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment summary
./scripts/deploy.sh --status
```

## Configuration Parameters

All implementations support the following customizable parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `notification_email` | Email address for SNS notifications | - | Yes |
| `bucket_name_prefix` | Prefix for S3 bucket name | `long-term-archive` | No |
| `transition_days_archives` | Days before archiving objects in archives/ folder | `90` | No |
| `transition_days_general` | Days before archiving general objects | `180` | No |
| `inventory_frequency` | S3 inventory report frequency | `Weekly` | No |
| `environment` | Environment tag for resources | `production` | No |

## Testing Your Deployment

After deployment, test the archiving system:

```bash
# Get bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name long-term-archive-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

# Upload test files
echo "Test archive document" > test-document.pdf
aws s3 cp test-document.pdf s3://${BUCKET_NAME}/archives/
aws s3 cp test-document.pdf s3://${BUCKET_NAME}/

# Verify lifecycle configuration
aws s3api get-bucket-lifecycle-configuration --bucket ${BUCKET_NAME}

# Check notification configuration
aws s3api get-bucket-notification-configuration --bucket ${BUCKET_NAME}

# Test direct archive upload
aws s3 cp test-document.pdf \
    s3://${BUCKET_NAME}/immediate-test/ \
    --storage-class DEEP_ARCHIVE

# Monitor SNS subscription (check your email)
```

## Monitoring and Operations

### View Archive Status

```bash
# Check object storage classes
aws s3api list-objects-v2 \
    --bucket ${BUCKET_NAME} \
    --query 'Contents[*].[Key,StorageClass,LastModified]' \
    --output table

# Monitor inventory reports
aws s3 ls s3://${BUCKET_NAME}/inventory-reports/
```

### Restore Archived Objects

```bash
# Initiate restore for specific object
aws s3api restore-object \
    --bucket ${BUCKET_NAME} \
    --key "path/to/archived-file.pdf" \
    --restore-request '{"Days":5,"GlacierJobParameters":{"Tier":"Standard"}}'

# Check restore status
aws s3api head-object \
    --bucket ${BUCKET_NAME} \
    --key "path/to/archived-file.pdf"
```

### Cost Monitoring

```bash
# Get storage metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name BucketSizeBytes \
    --dimensions Name=BucketName,Value=${BUCKET_NAME} Name=StorageType,Value=StandardStorage \
    --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 86400 \
    --statistics Average
```

## Cleanup

### Using CloudFormation

```bash
# Empty the S3 bucket first (required)
aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete the stack
aws cloudformation delete-stack \
    --stack-name long-term-archive-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name long-term-archive-stack
```

### Using CDK

```bash
# From the appropriate CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
npx cdk destroy  # or: cdk destroy (for Python)

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="notification_email=your-email@example.com"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Troubleshooting

### Common Issues

1. **SNS Subscription Not Confirmed**
   - Check your email for SNS confirmation message
   - Confirm subscription to receive notifications

2. **Lifecycle Policy Not Applied**
   - Verify bucket policy allows lifecycle management
   - Check CloudWatch Events for any error messages

3. **Restore Requests Failing**
   - Ensure objects are actually in DEEP_ARCHIVE storage class
   - Check that you have sufficient permissions for restore operations

4. **Inventory Reports Not Generated**
   - Inventory reports appear 24-48 hours after configuration
   - Check the destination prefix in your bucket

### Getting Help

```bash
# Check CloudFormation stack events for errors
aws cloudformation describe-stack-events \
    --stack-name long-term-archive-stack

# View CloudWatch logs for Lambda functions (if any)
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Check S3 bucket notifications
aws s3api get-bucket-notification-configuration --bucket ${BUCKET_NAME}
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: All roles and policies use minimum required permissions
- **Encryption**: S3 bucket uses server-side encryption by default
- **Access Logging**: S3 access logging can be enabled via parameters
- **Event Monitoring**: All archive activities are logged and can trigger notifications
- **Data Integrity**: S3 provides 99.999999999% (11 9's) durability

## Cost Optimization

- **Storage Classes**: Automatic transition to lowest-cost storage (Deep Archive)
- **Lifecycle Management**: Eliminates manual data management overhead
- **Inventory Reporting**: Tracks storage usage without retrieval costs
- **Bulk Retrieval**: Uses cost-effective bulk retrieval tier by default

## Compliance Features

- **Audit Trail**: Complete logging of all archive and retrieval operations
- **Retention Policies**: Automated enforcement of data retention requirements
- **Inventory Reports**: Regular reporting for compliance documentation
- **Event Notifications**: Real-time alerts for regulatory monitoring

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check AWS service documentation for specific services
3. Review CloudFormation/CDK/Terraform provider documentation
4. Verify your AWS permissions and account limits

## Next Steps

After successful deployment, consider:

1. Setting up additional lifecycle rules for different data types
2. Implementing data classification tags for automated archiving
3. Creating cost alerts for storage and retrieval operations
4. Integrating with existing backup and disaster recovery processes
5. Setting up cross-region replication for critical archived data