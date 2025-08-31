# Infrastructure as Code for Visual Infrastructure Design with Application Composer and CloudFormation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Visual Infrastructure Design with Application Composer and CloudFormation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- One of the following based on your chosen deployment method:
  - For CloudFormation: AWS CLI v2.0+
  - For CDK TypeScript: Node.js 18+ and AWS CDK CLI v2.0+
  - For CDK Python: Python 3.9+ and AWS CDK CLI v2.0+
  - For Terraform: Terraform v1.0+ and AWS provider
  - For Bash scripts: AWS CLI and bash shell
- AWS permissions for S3, CloudFormation, and IAM operations
- Estimated cost: $0.50-2.00 per month for S3 storage and requests

## Architecture Overview

This recipe deploys a static website hosting solution using:
- S3 bucket configured for static website hosting
- Bucket policy for public read access
- Website configuration with index and error documents

## Quick Start

### Using CloudFormation (AWS)

```bash
# Create stack with default parameters
aws cloudformation create-stack \
    --stack-name visual-website-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketNameSuffix,ParameterValue=$(date +%s)

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name visual-website-stack

# Get website URL from outputs
aws cloudformation describe-stacks \
    --stack-name visual-website-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`WebsiteURL`].OutputValue' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters bucketNameSuffix=$(date +%s)

# Get website URL
cdk outputs --stack-name VisualWebsiteStack
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters bucketNameSuffix=$(date +%s)

# Get website URL
cdk outputs --stack-name VisualWebsiteStack
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="bucket_name_suffix=$(date +%s)"

# Apply configuration
terraform apply -var="bucket_name_suffix=$(date +%s)" -auto-approve

# Get website URL
terraform output website_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the website URL upon completion
```

## Uploading Website Content

After deploying the infrastructure, upload your website files:

```bash
# Set your bucket name (replace with actual bucket name from deployment)
export BUCKET_NAME="your-bucket-name-here"

# Create sample website files
cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Visual Infrastructure Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .success { color: #4CAF50; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 Success!</h1>
        <p class="success">This website was deployed using Infrastructure as Code!</p>
        <p>Your infrastructure design is now live and serving content.</p>
    </div>
</body>
</html>
EOF

cat > error.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Page Not Found</title></head>
<body><h1>404 - Page Not Found</h1></body>
</html>
EOF

# Upload files to S3
aws s3 cp index.html s3://${BUCKET_NAME}/
aws s3 cp error.html s3://${BUCKET_NAME}/

# Clean up local files
rm index.html error.html
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Empty S3 bucket first (CloudFormation cannot delete non-empty buckets)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name visual-website-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name visual-website-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name visual-website-stack
```

### Using CDK (AWS)

```bash
# Empty S3 bucket first
BUCKET_NAME=$(cdk outputs --stack-name VisualWebsiteStack | grep BucketName | cut -d' ' -f2)
aws s3 rm s3://${BUCKET_NAME} --recursive

# Destroy the stack
cdk destroy VisualWebsiteStack --force
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Empty S3 bucket first
BUCKET_NAME=$(terraform output -raw bucket_name)
aws s3 rm s3://${BUCKET_NAME} --recursive

# Destroy infrastructure
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# The script will handle bucket cleanup and resource deletion
```

## Customization

### Parameters and Variables

Each implementation supports customization through variables:

#### CloudFormation Parameters
- `BucketNameSuffix`: Unique suffix for bucket naming
- `IndexDocument`: Default index document (default: index.html)
- `ErrorDocument`: Default error document (default: error.html)

#### CDK Parameters
- `bucketNameSuffix`: Unique suffix for bucket naming
- `indexDocument`: Default index document
- `errorDocument`: Default error document

#### Terraform Variables
- `bucket_name_suffix`: Unique suffix for bucket naming
- `index_document`: Default index document
- `error_document`: Default error document
- `aws_region`: AWS region for deployment

### Environment-Specific Configurations

To deploy to different environments, customize the variables:

```bash
# Development environment
terraform apply -var="bucket_name_suffix=dev-$(date +%s)" -var="aws_region=us-east-1"

# Production environment
terraform apply -var="bucket_name_suffix=prod-$(date +%s)" -var="aws_region=us-west-2"
```

## Validation and Testing

After deployment, validate your infrastructure:

```bash
# Test website accessibility
WEBSITE_URL="your-website-url-here"
curl -I "${WEBSITE_URL}"

# Verify S3 website configuration
aws s3api get-bucket-website --bucket your-bucket-name

# Check CloudFormation stack status
aws cloudformation describe-stacks --stack-name visual-website-stack
```

## Security Considerations

This implementation includes:
- Public read access bucket policy for website hosting
- HTTPS redirect capability (when used with CloudFront)
- Minimal required permissions for S3 website hosting

For production use, consider:
- Adding CloudFront distribution for HTTPS and global distribution
- Implementing access logging
- Adding custom domain with SSL certificate
- Enabling S3 server access logging

## Troubleshooting

### Common Issues

1. **Bucket already exists**: Ensure bucket names are globally unique by using a proper suffix
2. **Access denied**: Verify AWS credentials and permissions
3. **Website not loading**: Check bucket policy and website configuration
4. **CDK bootstrap required**: Run `cdk bootstrap` if this is your first CDK deployment

### Debug Commands

```bash
# Check bucket policy
aws s3api get-bucket-policy --bucket your-bucket-name

# Verify website configuration
aws s3api get-bucket-website --bucket your-bucket-name

# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name visual-website-stack
```

## Cost Optimization

- S3 storage costs are minimal for small websites
- Consider S3 Intelligent Tiering for larger content
- Use CloudFront for global distribution and reduced S3 requests
- Monitor usage with AWS Cost Explorer

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS CloudFormation, CDK, or Terraform documentation
3. Verify AWS service limits and quotas
4. Review AWS CLI configuration and permissions

## Related Resources

- [AWS S3 Static Website Hosting Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [AWS Infrastructure Composer Documentation](https://docs.aws.amazon.com/infrastructure-composer/latest/dg/what-is-composer.html)
- [CloudFormation Template Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-reference.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/home.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)