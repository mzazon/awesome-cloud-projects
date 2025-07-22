# Infrastructure as Code for Automated Data Archiving with S3 Glacier

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Data Archiving with S3 Glacier".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - S3 lifecycle policy configuration
  - SNS topic creation and subscription
  - IAM role and policy management
- For CDK implementations:
  - Node.js 14.x or later (for TypeScript)
  - Python 3.7+ (for Python)
  - AWS CDK CLI installed (`npm install -g aws-cdk`)
- For Terraform:
  - Terraform 1.0+ installed
  - AWS provider configured
- Basic understanding of S3 storage classes and lifecycle policies

## Architecture Overview

This solution implements automated data archiving using:

- **S3 Bucket**: Primary storage for your data
- **S3 Lifecycle Policies**: Automated transition rules for archiving
- **SNS Topic**: Notifications for restore operations
- **IAM Roles**: Secure access permissions

The solution automatically transitions data:
- From S3 Standard to S3 Glacier Flexible Retrieval after 90 days
- From S3 Glacier Flexible Retrieval to S3 Glacier Deep Archive after 365 days

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name s3-glacier-archiving \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=my-archive-bucket \
                 ParameterKey=NotificationEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name s3-glacier-archiving \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to the CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=admin@example.com

# View outputs
cdk output
```

### Using CDK Python (AWS)

```bash
# Navigate to the CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=admin@example.com

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="notification_email=admin@example.com"

# Apply the configuration
terraform apply -var="notification_email=admin@example.com"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="admin@example.com"
export BUCKET_NAME="my-unique-archive-bucket"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
aws s3 ls
aws sns list-topics
```

## Configuration Options

### CloudFormation Parameters

- `BucketName`: Name for the S3 bucket (must be globally unique)
- `NotificationEmail`: Email address for SNS notifications
- `GlacierTransitionDays`: Days after which objects transition to Glacier (default: 90)
- `DeepArchiveTransitionDays`: Days after which objects transition to Deep Archive (default: 365)
- `ObjectPrefix`: Prefix for objects to be archived (default: "data/")

### CDK Parameters

Both TypeScript and Python implementations support these context variables:

```bash
# Set via command line
cdk deploy --context bucketName=my-archive-bucket \
           --context notificationEmail=admin@example.com \
           --context glacierTransitionDays=90 \
           --context deepArchiveTransitionDays=365

# Or set in cdk.json
```

### Terraform Variables

```bash
# Set via command line
terraform apply \
    -var="bucket_name=my-archive-bucket" \
    -var="notification_email=admin@example.com" \
    -var="glacier_transition_days=90" \
    -var="deep_archive_transition_days=365"

# Or create terraform.tfvars file
cat > terraform.tfvars << EOF
bucket_name = "my-archive-bucket"
notification_email = "admin@example.com"
glacier_transition_days = 90
deep_archive_transition_days = 365
EOF
```

## Post-Deployment Steps

After successful deployment:

1. **Confirm SNS subscription**: Check your email and confirm the SNS subscription
2. **Upload test data**: Upload sample files to test the lifecycle policy
3. **Monitor transitions**: Use CloudWatch or AWS CLI to monitor object transitions
4. **Test restore functionality**: Practice restoring archived objects

### Testing Object Upload

```bash
# Create test file
echo "This is a test file for archiving" > test-file.txt

# Upload to your bucket (replace with your actual bucket name)
aws s3 cp test-file.txt s3://your-bucket-name/data/

# Verify upload
aws s3 ls s3://your-bucket-name/data/
```

### Monitoring Lifecycle Transitions

```bash
# Check object storage class
aws s3api head-object \
    --bucket your-bucket-name \
    --key data/test-file.txt

# View lifecycle configuration
aws s3api get-bucket-lifecycle-configuration \
    --bucket your-bucket-name
```

## Cost Optimization

This solution provides significant cost savings:

- **S3 Standard to Glacier Flexible Retrieval**: ~68% cost reduction
- **S3 Glacier Flexible Retrieval to Deep Archive**: ~95% cost reduction compared to S3 Standard
- **Total potential savings**: Up to 95% on long-term storage costs

### Cost Monitoring

```bash
# Enable cost allocation tags (if using Terraform or CDK)
aws s3api put-bucket-tagging \
    --bucket your-bucket-name \
    --tagging 'TagSet=[{Key=Project,Value=DataArchiving},{Key=Environment,Value=Production}]'
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name s3-glacier-archiving

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name s3-glacier-archiving \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# TypeScript
cd cdk-typescript/
cdk destroy

# Python
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="notification_email=admin@example.com"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup
aws s3 ls
aws sns list-topics
```

## Troubleshooting

### Common Issues

1. **Bucket name already exists**: S3 bucket names must be globally unique
   - Solution: Use a unique suffix or change the bucket name

2. **Insufficient permissions**: Ensure your AWS credentials have required permissions
   - Solution: Attach necessary IAM policies or use administrator access

3. **SNS subscription not confirmed**: Email notifications won't work
   - Solution: Check email spam folder and confirm subscription

4. **Lifecycle policy not working**: Objects aren't transitioning
   - Solution: Verify object age and policy configuration; transitions aren't immediate

### Debugging Commands

```bash
# Check bucket lifecycle configuration
aws s3api get-bucket-lifecycle-configuration --bucket your-bucket-name

# Check object storage class
aws s3api head-object --bucket your-bucket-name --key data/your-file.txt

# List SNS topics
aws sns list-topics

# Check SNS subscriptions
aws sns list-subscriptions-by-topic --topic-arn your-topic-arn
```

## Security Considerations

This implementation follows AWS security best practices:

- **Least privilege IAM**: Roles have minimal required permissions
- **Encryption**: S3 objects are encrypted at rest (SSE-S3)
- **Access logging**: S3 access logging can be enabled
- **Versioning**: S3 versioning can be enabled for data protection

### Additional Security Enhancements

```bash
# Enable S3 bucket versioning
aws s3api put-bucket-versioning \
    --bucket your-bucket-name \
    --versioning-configuration Status=Enabled

# Enable S3 access logging
aws s3api put-bucket-logging \
    --bucket your-bucket-name \
    --bucket-logging-status file://logging-config.json
```

## Customization

### Modifying Transition Periods

To change when objects transition between storage classes:

1. **CloudFormation**: Update the Parameters section
2. **CDK**: Modify the transition rules in the construct
3. **Terraform**: Update the variables.tf file
4. **Bash scripts**: Modify the lifecycle policy JSON

### Adding Additional Storage Classes

Consider adding S3 Intelligent-Tiering or S3 Glacier Instant Retrieval:

```json
{
    "Days": 30,
    "StorageClass": "INTELLIGENT_TIERING"
}
```

### Multiple Archive Policies

Create different lifecycle rules for different prefixes:

```json
{
    "Rules": [
        {
            "ID": "LogArchive",
            "Status": "Enabled",
            "Filter": {"Prefix": "logs/"},
            "Transitions": [{"Days": 30, "StorageClass": "GLACIER"}]
        },
        {
            "ID": "BackupArchive",
            "Status": "Enabled",
            "Filter": {"Prefix": "backups/"},
            "Transitions": [{"Days": 180, "StorageClass": "DEEP_ARCHIVE"}]
        }
    ]
}
```

## Support

For issues with this infrastructure code:

1. **Recipe documentation**: Refer to the original recipe markdown file
2. **AWS documentation**: Check the [S3 Lifecycle Management guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
3. **Provider documentation**: Consult CloudFormation, CDK, or Terraform documentation
4. **Community support**: AWS forums and Stack Overflow

## Additional Resources

- [AWS S3 Storage Classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
- [S3 Lifecycle Configuration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/how-to-set-lifecycle-configuration-intro.html)
- [S3 Glacier Retrieval Options](https://docs.aws.amazon.com/AmazonS3/latest/userguide/restoring-objects.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)