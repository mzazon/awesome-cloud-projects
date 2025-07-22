# Infrastructure as Code for Serving Static Content with S3 and CloudFront

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serving Static Content with S3 and CloudFront".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a serverless static website hosting architecture using:

- **Amazon S3**: Cost-effective storage for website files
- **Amazon CloudFront**: Global CDN for low-latency content delivery
- **AWS Certificate Manager**: Free SSL/TLS certificates for HTTPS
- **Route 53**: DNS management for custom domains (optional)
- **Origin Access Control**: Secure access between CloudFront and S3

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions to create:
  - S3 buckets and policies
  - CloudFront distributions
  - ACM certificates
  - Route 53 records (if using custom domain)
  - IAM policies and roles
- Domain name registered (optional, for custom domain setup)
- Website files ready for upload (HTML, CSS, JavaScript, images)

### Estimated Costs

For a typical small website:
- S3 storage: ~$0.023/GB/month
- CloudFront data transfer: ~$0.085/GB
- Route 53 hosted zone: $0.50/month (if using custom domain)
- ACM certificates: Free

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name static-website-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DomainName,ParameterValue=example.com \
                 ParameterKey=CreateCustomDomain,ParameterValue=true \
    --capabilities CAPABILITY_IAM

# Upload website files after stack creation
aws s3 sync website/ s3://your-bucket-name/ --delete

# Check stack status
aws cloudformation describe-stacks \
    --stack-name static-website-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters domainName=example.com \
           --parameters createCustomDomain=true

# Upload website files
aws s3 sync ../website/ s3://$(cdk list --json | jq -r '.[0].outputs.BucketName')/ --delete
```

### Using CDK Python

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
cdk deploy --parameters domain-name=example.com \
           --parameters create-custom-domain=true

# Upload website files
aws s3 sync ../website/ s3://$(cdk list --json | jq -r '.[0].outputs.BucketName')/ --delete
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="domain_name=example.com" \
               -var="create_custom_domain=true"

# Apply the configuration
terraform apply -var="domain_name=example.com" \
                -var="create_custom_domain=true"

# Upload website files
aws s3 sync ../website/ s3://$(terraform output -raw bucket_name)/ --delete
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow prompts for domain configuration
# Script will automatically upload sample website files
```

## Configuration Options

### Domain Setup

All implementations support both CloudFront-only and custom domain configurations:

**CloudFront-only (no custom domain):**
- Set `CreateCustomDomain=false` (CloudFormation)
- Set `createCustomDomain=false` (CDK)
- Set `create_custom_domain=false` (Terraform)
- Answer "n" when prompted (Bash scripts)

**Custom domain:**
- Ensure your domain is registered in Route 53 or update DNS manually
- Provide your domain name as a parameter
- Certificate validation will be automatic if using Route 53

### Security Features

- **Origin Access Control**: Prevents direct S3 access
- **HTTPS Redirect**: All HTTP traffic redirected to HTTPS
- **TLS 1.2+**: Modern encryption standards enforced
- **Secure Headers**: CloudFront security headers enabled
- **Least Privilege**: IAM policies follow principle of least privilege

### Performance Optimizations

- **Gzip Compression**: Automatic compression for text-based files
- **Edge Caching**: Global CDN with 400+ edge locations
- **Cache Optimization**: Optimized TTL settings for different file types
- **Cost Class**: PriceClass_100 for cost optimization (North America and Europe)

## Post-Deployment Steps

1. **Upload Website Content**:
   ```bash
   # Upload your website files with proper content types
   aws s3 sync website/ s3://your-bucket-name/ \
       --delete \
       --content-type-by-extension
   ```

2. **Test Access**:
   ```bash
   # Test CloudFront URL
   curl -I https://your-cloudfront-domain.cloudfront.net
   
   # Test custom domain (if configured)
   curl -I https://your-domain.com
   ```

3. **Verify SSL Certificate**:
   ```bash
   # Check certificate details
   openssl s_client -connect your-domain.com:443 -servername your-domain.com
   ```

## Content Updates

To update your website content:

```bash
# Upload new or modified files
aws s3 sync website/ s3://your-bucket-name/ --delete

# Optional: Invalidate CloudFront cache for immediate updates
aws cloudfront create-invalidation \
    --distribution-id YOUR_DISTRIBUTION_ID \
    --paths "/*"
```

> **Note**: CloudFront invalidations incur charges after the first 1,000 paths per month.

## Monitoring and Logging

### CloudFront Access Logs

Access logs are automatically configured and stored in a separate S3 bucket:

```bash
# View recent access logs
aws s3 ls s3://your-logs-bucket-name/ --recursive --human-readable
```

### CloudWatch Metrics

Monitor key metrics in the AWS Console:
- **Requests**: Number of requests to your distribution
- **Bytes Downloaded**: Data transfer volume
- **Error Rate**: 4xx and 5xx error percentages
- **Cache Hit Rate**: Percentage of requests served from cache

## Troubleshooting

### Common Issues

1. **403 Forbidden Errors**:
   - Verify bucket policy allows CloudFront access
   - Check Origin Access Control configuration
   - Ensure S3 bucket is not publicly accessible

2. **Domain Not Resolving**:
   - Verify DNS propagation (can take up to 48 hours)
   - Check Route 53 hosted zone configuration
   - Confirm certificate validation completed

3. **SSL Certificate Issues**:
   - Ensure certificate is in us-east-1 region
   - Verify domain ownership validation
   - Check certificate status in ACM console

4. **Slow Content Updates**:
   - CloudFront caches content based on TTL settings
   - Use cache invalidation for immediate updates
   - Consider versioning strategy for frequent updates

### Useful Commands

```bash
# Check CloudFront distribution status
aws cloudfront list-distributions \
    --query 'DistributionList.Items[0].{ID:Id,Status:Status,Domain:DomainName}'

# View certificate status
aws acm list-certificates --region us-east-1 \
    --query 'CertificateSummaryList[0].{Arn:CertificateArn,Status:Status}'

# Test cache headers
curl -I https://your-domain.com/index.html | grep -E "(Cache|X-Cache)"
```

## Cleanup

### Using CloudFormation

```bash
# Empty S3 buckets first (required before stack deletion)
aws s3 rm s3://your-bucket-name/ --recursive
aws s3 rm s3://your-logs-bucket-name/ --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name static-website-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name static-website-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Empty S3 buckets first
aws s3 rm s3://$(cdk list --json | jq -r '.[0].outputs.BucketName')/ --recursive
aws s3 rm s3://$(cdk list --json | jq -r '.[0].outputs.LogsBucketName')/ --recursive

# Destroy the stack
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
cd terraform/

# Empty S3 buckets first
aws s3 rm s3://$(terraform output -raw bucket_name)/ --recursive
aws s3 rm s3://$(terraform output -raw logs_bucket_name)/ --recursive

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run destruction script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Variables and Parameters

Each implementation provides customizable variables:

- `domain_name` / `DomainName`: Your custom domain (optional)
- `create_custom_domain` / `CreateCustomDomain`: Enable custom domain setup
- `price_class` / `PriceClass`: CloudFront price class (100, 200, or All)
- `bucket_prefix` / `BucketPrefix`: S3 bucket name prefix
- `enable_logging` / `EnableLogging`: Enable CloudFront access logging

### Advanced Customizations

1. **Custom Error Pages**: Modify error page configurations
2. **Additional Domains**: Add multiple domain aliases
3. **Cache Behaviors**: Configure different caching rules
4. **Security Headers**: Add custom security headers
5. **Compression**: Configure additional compression settings

### Example Custom Configurations

```bash
# Terraform with custom settings
terraform apply \
    -var="domain_name=www.example.com" \
    -var="create_custom_domain=true" \
    -var="price_class=PriceClass_All" \
    -var="enable_logging=true"

# CloudFormation with parameters file
aws cloudformation create-stack \
    --stack-name static-website-stack \
    --template-body file://cloudformation.yaml \
    --parameters file://parameters.json \
    --capabilities CAPABILITY_IAM
```

## Best Practices

### Security

- Keep S3 buckets private (never enable public access)
- Use Origin Access Control instead of Origin Access Identity
- Enable CloudFront security headers
- Regularly review and update IAM policies
- Monitor access logs for suspicious activity

### Performance

- Optimize images and assets before uploading
- Use appropriate cache headers for different content types
- Consider using CloudFront Functions for edge customization
- Implement proper compression for text-based files
- Monitor cache hit rates and optimize accordingly

### Cost Management

- Choose appropriate CloudFront price class for your audience
- Monitor data transfer costs in CloudWatch
- Use S3 lifecycle policies for log management
- Consider Reserved Capacity for predictable traffic

### Operational Excellence

- Implement Infrastructure as Code for consistency
- Use version control for website content
- Set up monitoring and alerting
- Document deployment and rollback procedures
- Regular backup verification

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for step-by-step guidance
2. **AWS Documentation**: Check AWS service documentation for detailed configuration options
3. **Provider Documentation**: Consult CloudFormation, CDK, or Terraform documentation
4. **Community Forums**: AWS forums and Stack Overflow for community support

## Additional Resources

- [AWS Static Website Hosting Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)