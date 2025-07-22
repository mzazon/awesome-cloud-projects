# Infrastructure as Code for Secure File Sharing with S3 Presigned URLs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure File Sharing with S3 Presigned URLs".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- IAM user or role with S3 permissions (s3:GetObject, s3:PutObject, s3:CreateBucket, s3:DeleteBucket)
- Appropriate permissions for IAM policy creation and CloudTrail logging
- Basic understanding of S3 bucket policies and presigned URL concepts

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- IAM permissions to create stacks and resources

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI: `npm install -g aws-cdk`
- TypeScript: `npm install -g typescript`

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI: `npm install -g aws-cdk`
- pip package manager

#### Terraform
- Terraform 1.0 or later
- AWS provider configured

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name file-sharing-s3-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketNamePrefix,ParameterValue=file-sharing-demo \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name file-sharing-s3-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name file-sharing-s3-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View deployed resources
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View deployed resources
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will create:
# - S3 bucket with private access
# - Sample files for testing
# - IAM policies for presigned URL generation
# - CloudTrail logging for audit trails
```

## Generated Resources

The infrastructure creates the following AWS resources:

### Core Resources
- **S3 Bucket**: Private bucket for secure file storage with public access blocked
- **S3 Bucket Policy**: Enforces secure access patterns and audit requirements
- **CloudTrail**: Audit logging for all S3 access and presigned URL generation

### Security Components
- **IAM Role**: Service role for presigned URL generation with least privilege access
- **IAM Policy**: Specific permissions for S3 operations and CloudTrail logging
- **S3 Public Access Block**: Prevents accidental public access to bucket contents

### Sample Content
- **Sample Documents**: Test files in `/documents/` prefix for download testing
- **Upload Directory**: `/uploads/` prefix configured for secure file submission

## Configuration Options

### Environment Variables
```bash
# Required
export AWS_REGION="us-east-1"
export BUCKET_NAME_PREFIX="your-org-file-sharing"

# Optional
export PRESIGNED_URL_EXPIRY_HOURS="24"        # Default: 24 hours
export ENABLE_CLOUDTRAIL_LOGGING="true"       # Default: true
export ENABLE_S3_VERSIONING="false"           # Default: false
export S3_STORAGE_CLASS="STANDARD"            # Default: STANDARD
```

### Terraform Variables
```bash
# Create terraform.tfvars file
cat > terraform/terraform.tfvars << EOF
bucket_name_prefix = "your-org-file-sharing"
aws_region = "us-east-1"
enable_versioning = false
enable_cloudtrail = true
default_expiry_hours = 24
EOF
```

### CloudFormation Parameters
```bash
# Override default parameters during deployment
aws cloudformation create-stack \
    --stack-name file-sharing-s3-stack \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=BucketNamePrefix,ParameterValue=your-org-files \
        ParameterKey=EnableVersioning,ParameterValue=true \
        ParameterKey=DefaultExpiryHours,ParameterValue=48 \
    --capabilities CAPABILITY_IAM
```

## Usage Examples

### Generate Download Presigned URL
```bash
# Get bucket name from infrastructure outputs
BUCKET_NAME=$(terraform output -raw bucket_name)
# or from CloudFormation:
# BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name file-sharing-s3-stack --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)

# Generate presigned URL for downloads (valid for 1 hour)
aws s3 presign s3://${BUCKET_NAME}/documents/sample-document.txt --expires-in 3600
```

### Generate Upload Presigned URL
```bash
# Generate presigned URL for uploads (valid for 30 minutes)
aws s3 presign s3://${BUCKET_NAME}/uploads/new-file.pdf --expires-in 1800 --http-method PUT
```

### Batch URL Generation
```bash
# Use the included script for multiple files
./scripts/generate_presigned_urls.sh ${BUCKET_NAME} 24
```

## Security Considerations

### Default Security Features
- **Private Bucket**: All files are private by default, accessible only via presigned URLs
- **Public Access Block**: Prevents accidental public exposure of bucket contents
- **CloudTrail Logging**: Comprehensive audit trail for all access and operations
- **Time-Limited Access**: All presigned URLs automatically expire
- **Least Privilege IAM**: Minimal required permissions for URL generation

### Best Practices Implemented
- Upload URLs have shorter expiration times than download URLs
- Bucket versioning available as optional feature for data protection
- S3 server-side encryption enabled by default
- CloudTrail integration for compliance and monitoring
- IP-based access restrictions can be added via bucket policies

### Additional Security Options
```bash
# Enable S3 bucket notifications for uploaded files
aws s3api put-bucket-notification-configuration \
    --bucket ${BUCKET_NAME} \
    --notification-configuration file://bucket-notifications.json

# Add bucket policy for IP restrictions (example)
aws s3api put-bucket-policy \
    --bucket ${BUCKET_NAME} \
    --policy file://ip-restriction-policy.json
```

## Monitoring and Troubleshooting

### CloudWatch Metrics
The infrastructure automatically enables S3 request metrics and CloudTrail logging. Monitor:
- Presigned URL generation frequency
- File download/upload patterns
- Failed access attempts
- Storage usage trends

### Common Issues

1. **Access Denied Errors**
   ```bash
   # Check IAM permissions
   aws iam simulate-principal-policy \
       --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
       --action-names s3:GetObject s3:PutObject \
       --resource-arns arn:aws:s3:::${BUCKET_NAME}/*
   ```

2. **Expired URL Testing**
   ```bash
   # Generate short-lived URL for testing expiration
   SHORT_URL=$(aws s3 presign s3://${BUCKET_NAME}/documents/sample-document.txt --expires-in 10)
   echo "URL expires in 10 seconds: ${SHORT_URL}"
   ```

3. **CloudTrail Event Analysis**
   ```bash
   # Query recent S3 events
   aws logs filter-log-events \
       --log-group-name CloudTrail/S3DataEvents \
       --start-time $(date -d '1 hour ago' +%s)000 \
       --filter-pattern '{ $.eventSource = "s3.amazonaws.com" }'
   ```

## Cost Optimization

### Storage Costs
- Use S3 Intelligent-Tiering for automatically optimizing storage costs
- Implement lifecycle policies for uploaded files
- Monitor storage usage with S3 Storage Lens

### Request Costs
- Presigned URL generation is free (only S3 API calls are charged)
- Monitor GET/PUT request patterns through CloudWatch
- Consider CloudFront for frequently accessed files

## Cleanup

### Using CloudFormation
```bash
# Delete the stack and all resources
aws cloudformation delete-stack --stack-name file-sharing-s3-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name file-sharing-s3-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Clean up all resources
./scripts/destroy.sh

# The script will:
# - Empty the S3 bucket
# - Delete all created resources
# - Clean up CloudTrail logs
# - Remove IAM roles and policies
```

## Customization

### Adding Custom Bucket Policies
Create custom bucket policies for additional security requirements:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RestrictToSpecificIPs",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ],
      "Condition": {
        "IpAddressIfExists": {
          "aws:SourceIp": "203.0.113.0/24"
        }
      }
    }
  ]
}
```

### Integration with Lambda
Extend the solution with Lambda functions for:
- Automatic virus scanning of uploaded files
- Email notifications for file sharing events
- Custom business logic for URL generation
- Integration with external authentication systems

### Web Interface Integration
The infrastructure can be extended with:
- API Gateway for REST endpoints
- Lambda functions for business logic
- CloudFront for global content delivery
- Cognito for user authentication

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../file-sharing-solutions-s3-presigned-urls.md)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [AWS IAM Documentation](https://docs.aws.amazon.com/iam/)
- [Presigned URLs Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html)

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Refer to your organization's policies for production usage guidelines.