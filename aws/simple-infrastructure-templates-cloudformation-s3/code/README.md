# Infrastructure as Code for Simple Infrastructure Templates with CloudFormation and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Infrastructure Templates with CloudFormation and S3".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for CloudFormation, S3, and IAM operations
- Implementation-specific tools (see individual sections below)

### Common AWS Permissions Required

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:*",
                "s3:*",
                "iam:PassRole"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### Using CloudFormation (AWS)

**Prerequisites:**
- AWS CLI v2 installed and configured

**Deployment:**
```bash
# Set environment variables
export BUCKET_NAME="my-infrastructure-bucket-$(date +%s)"
export STACK_NAME="simple-s3-infrastructure"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=${BUCKET_NAME} \
    --capabilities CAPABILITY_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name ${STACK_NAME}

# View outputs
aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

**Prerequisites:**
- Node.js 18+ and npm installed
- AWS CDK CLI: `npm install -g aws-cdk`

**Deployment:**
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using CDK Python (AWS)

**Prerequisites:**
- Python 3.8+ and pip installed
- AWS CDK CLI: `npm install -g aws-cdk`

**Deployment:**
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform

**Prerequisites:**
- Terraform 1.0+ installed
- AWS CLI configured

**Deployment:**
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

**Prerequisites:**
- AWS CLI v2 installed and configured
- Bash shell environment

**Deployment:**
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for bucket name or generate one automatically
```

## Configuration Options

### Environment Variables

Set these environment variables to customize the deployment:

```bash
# Required for some implementations
export BUCKET_NAME="your-unique-bucket-name"
export STACK_NAME="your-stack-name"
export AWS_REGION="us-east-1"

# Optional: Add custom tags
export ENVIRONMENT="development"
export PROJECT="infrastructure-templates"
```

### CloudFormation Parameters

- `BucketName`: Name for the S3 bucket (must be globally unique)
- `Environment`: Environment tag (default: Development)
- `EnableVersioning`: Enable S3 versioning (default: true)

### Terraform Variables

Customize deployment by creating a `terraform.tfvars` file:

```hcl
bucket_name = "my-custom-bucket-name"
environment = "production"
enable_versioning = true
tags = {
  Project = "Infrastructure Templates"
  Owner   = "DevOps Team"
}
```

### CDK Context

Customize CDK deployments using `cdk.json` context:

```json
{
  "context": {
    "bucketName": "my-custom-bucket",
    "environment": "production",
    "enableVersioning": true
  }
}
```

## Validation and Testing

After deployment, validate your infrastructure:

### Check S3 Bucket Configuration

```bash
# Verify bucket exists
aws s3api head-bucket --bucket ${BUCKET_NAME}

# Check encryption settings
aws s3api get-bucket-encryption --bucket ${BUCKET_NAME}

# Verify versioning is enabled
aws s3api get-bucket-versioning --bucket ${BUCKET_NAME}

# Check public access block
aws s3api get-public-access-block --bucket ${BUCKET_NAME}
```

### Test Basic Functionality

```bash
# Upload test file
echo "Hello Infrastructure as Code!" > test-file.txt
aws s3 cp test-file.txt s3://${BUCKET_NAME}/

# List bucket contents
aws s3 ls s3://${BUCKET_NAME}/

# Download test file
aws s3 cp s3://${BUCKET_NAME}/test-file.txt downloaded-file.txt

# Clean up test files
aws s3 rm s3://${BUCKET_NAME}/test-file.txt
rm test-file.txt downloaded-file.txt
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Empty the bucket first (required before deletion)
aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name ${STACK_NAME}

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ${STACK_NAME}
```

### Using CDK (AWS)

```bash
# From the CDK directory (cdk-typescript/ or cdk-python/)
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Empty bucket contents first
terraform apply -auto-approve -var="force_destroy_bucket=true"

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow the prompts to confirm deletion
```

## Troubleshooting

### Common Issues

1. **Bucket Name Already Exists**
   - S3 bucket names must be globally unique
   - Use the random suffix approach from the recipe
   - Error: `BucketAlreadyExists`

2. **Permission Denied**
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM policies for CloudFormation, S3, and IAM operations
   - Error: `AccessDenied` or `UnauthorizedOperation`

3. **Stack Already Exists**
   - Choose a different stack name
   - Or delete the existing stack first
   - Error: `AlreadyExistsException`

### Debug Commands

```bash
# Check AWS credentials
aws sts get-caller-identity

# View CloudFormation stack events
aws cloudformation describe-stack-events \
    --stack-name ${STACK_NAME}

# Check Terraform state
terraform show

# CDK diff to see changes
cdk diff
```

## Security Considerations

This infrastructure implements several security best practices:

- **Encryption at Rest**: AES-256 server-side encryption enabled
- **Versioning**: Object versioning enabled for data protection
- **Public Access Block**: All public access blocked by default
- **Least Privilege**: IAM permissions follow principle of least privilege

### Additional Security Enhancements

Consider implementing these additional security measures:

```bash
# Enable CloudTrail for API logging
# Enable S3 access logging
# Configure bucket notifications for security monitoring
# Implement bucket policies for additional access control
```

## Cost Optimization

- S3 storage costs are minimal for this demo (~$0.02-0.10/month)
- CloudFormation has no additional charges
- Consider implementing S3 lifecycle policies for long-term cost optimization

## Customization

### Adding Additional Resources

To extend this infrastructure:

1. **CloudWatch Alarms**: Monitor bucket metrics
2. **S3 Lifecycle Policies**: Automate data archival
3. **Lambda Functions**: Process S3 events
4. **CloudTrail**: Log S3 API calls

### Environment-Specific Deployments

Deploy to multiple environments using parameters:

```bash
# Development
export ENVIRONMENT="dev"
export BUCKET_NAME="my-app-${ENVIRONMENT}-bucket-$(date +%s)"

# Staging
export ENVIRONMENT="staging"
export BUCKET_NAME="my-app-${ENVIRONMENT}-bucket-$(date +%s)"

# Production
export ENVIRONMENT="prod"
export BUCKET_NAME="my-app-${ENVIRONMENT}-bucket-$(date +%s)"
```

## Support

### Documentation Links

- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult the AWS documentation links
4. Check AWS service status at [status.aws.amazon.com](https://status.aws.amazon.com)

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Validate all implementation types still work
3. Update documentation as needed
4. Follow Infrastructure as Code best practices