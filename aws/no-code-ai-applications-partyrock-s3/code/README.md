# Infrastructure as Code for Creating No-Code AI Applications with PartyRock and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Creating No-Code AI Applications with PartyRock and S3".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Appropriate AWS permissions for S3, CloudFront, and IAM operations
- Social media account (Apple, Amazon, or Google) for PartyRock authentication
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

### Required AWS Permissions

Your AWS user/role needs the following permissions:
- `s3:*` for bucket operations
- `cloudfront:*` for CDN distribution
- `iam:PassRole` for service roles
- `sts:GetCallerIdentity` for account information

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name partyrock-s3-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketNameSuffix,ParameterValue=$(date +%s)

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name partyrock-s3-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name partyrock-s3-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
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
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the S3 website URL and CloudFront distribution URL
```

## Post-Deployment Steps

After deploying the infrastructure, complete these manual steps:

1. **Create PartyRock Application**:
   - Visit [https://partyrock.aws/](https://partyrock.aws/)
   - Sign in with your preferred social account
   - Create a new AI application (e.g., business name generator)
   - Configure widgets and test functionality
   - Make the application public and copy the URL

2. **Update Website Content**:
   - Replace `YOUR_PARTYROCK_APP_URL` in the uploaded HTML with your actual PartyRock application URL
   - Re-upload the updated HTML file to your S3 bucket

3. **Access Your Application**:
   - Use the S3 website URL for direct access
   - Use the CloudFront URL for global CDN access with HTTPS

## Configuration Options

### CloudFormation Parameters

- `BucketNameSuffix`: Suffix for unique bucket naming (default: timestamp)
- `EnableVersioning`: Enable S3 bucket versioning (default: true)
- `CacheTTL`: CloudFront cache TTL in seconds (default: 86400)

### CDK Configuration

Customize the deployment by modifying the stack configuration:

```typescript
// In CDK TypeScript
const config = {
  bucketName: `partyrock-app-${Date.now()}`,
  enableVersioning: true,
  cacheTtl: Duration.days(1)
};
```

### Terraform Variables

Configure deployment through `terraform.tfvars`:

```hcl
bucket_name_suffix = "unique-suffix"
enable_versioning = true
cache_ttl = 86400
aws_region = "us-east-1"
```

## Monitoring and Observability

The deployed infrastructure includes:

- CloudFront access logs (optional, can be enabled)
- S3 access logging (optional)
- CloudWatch metrics for CloudFront distribution
- S3 bucket metrics

To enable additional monitoring:

```bash
# Enable CloudFront logging (update distribution)
aws cloudfront update-distribution \
    --id DISTRIBUTION_ID \
    --distribution-config file://updated-config.json

# Enable S3 access logging
aws s3api put-bucket-logging \
    --bucket YOUR_BUCKET_NAME \
    --bucket-logging-status file://logging-config.json
```

## Security Considerations

This implementation follows AWS security best practices:

- S3 bucket uses server-side encryption (AES-256)
- CloudFront enforces HTTPS redirects
- Bucket policy restricts access to website content only
- No direct S3 bucket access from internet (via CloudFront)

### Enhanced Security Options

For production deployments, consider:

1. **Custom Domain with SSL**:
   ```bash
   # Request ACM certificate
   aws acm request-certificate \
       --domain-name yourdomain.com \
       --validation-method DNS
   ```

2. **WAF Integration**:
   ```bash
   # Create WAF Web ACL for CloudFront
   aws wafv2 create-web-acl \
       --scope CLOUDFRONT \
       --name partyrock-waf
   ```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack and all resources
aws cloudformation delete-stack --stack-name partyrock-s3-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name partyrock-s3-stack
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy

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

1. **CloudFront Distribution Takes Time to Deploy**:
   - CloudFront distributions can take 10-15 minutes to deploy globally
   - Use `aws cloudfront wait distribution-deployed` to monitor progress

2. **S3 Bucket Name Already Exists**:
   - S3 bucket names must be globally unique
   - Modify the bucket name suffix or use a different naming pattern

3. **Permission Denied Errors**:
   - Ensure your AWS credentials have sufficient permissions
   - Check IAM policies for S3 and CloudFront access

4. **Website Not Loading**:
   - Verify bucket policy allows public read access
   - Check that index.html exists in the bucket root
   - Ensure CloudFront distribution is deployed

### Debug Commands

```bash
# Check S3 bucket contents
aws s3 ls s3://YOUR_BUCKET_NAME

# Verify CloudFront distribution status
aws cloudfront get-distribution --id DISTRIBUTION_ID

# Test website accessibility
curl -I https://YOUR_CLOUDFRONT_DOMAIN

# Check bucket policy
aws s3api get-bucket-policy --bucket YOUR_BUCKET_NAME
```

## Cost Optimization

This solution uses several AWS services with different pricing models:

- **S3**: Pay for storage used (~$0.023/GB/month)
- **CloudFront**: Pay for data transfer (~$0.085/GB)
- **PartyRock**: Free tier available with daily usage limits

### Cost Monitoring

```bash
# Enable cost allocation tags
aws s3api put-bucket-tagging \
    --bucket YOUR_BUCKET_NAME \
    --tagging 'TagSet=[{Key=Project,Value=PartyRock},{Key=Environment,Value=Demo}]'

# Set up billing alerts
aws budgets create-budget \
    --account-id YOUR_ACCOUNT_ID \
    --budget file://budget-config.json
```

## Extensions and Customizations

### Adding Custom Domain

1. Purchase/configure domain in Route 53
2. Request SSL certificate via ACM
3. Update CloudFront distribution with custom domain
4. Create Route 53 alias record

### Implementing CI/CD

```bash
# Example GitHub Actions workflow
# .github/workflows/deploy.yml
name: Deploy PartyRock App
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy with CDK
        run: |
          cd cdk-typescript
          npm install
          cdk deploy --require-approval never
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../no-code-ai-applications-partyrock-s3.md)
2. Review AWS documentation for [S3 static websites](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
3. Consult [CloudFront documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/)
4. Visit [PartyRock documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/partyrock.html)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Update documentation accordingly
3. Follow AWS best practices
4. Ensure backward compatibility when possible