# Terraform Infrastructure for PartyRock AI Applications with S3 and CloudFront

This Terraform configuration deploys a complete infrastructure for hosting static websites that showcase Amazon PartyRock AI applications, with global content delivery through CloudFront CDN.

## Architecture Overview

The infrastructure creates:

- **S3 Bucket**: Static website hosting with versioning and encryption
- **CloudFront Distribution**: Global CDN for fast content delivery and HTTPS support
- **Security Configuration**: Public access policies and origin access control
- **Sample Website**: Pre-built HTML pages showcasing PartyRock integration

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- Valid AWS credentials configured

### AWS Permissions

Your AWS credentials must have permissions for:

- S3 bucket creation and management
- CloudFront distribution creation and management
- IAM policy creation (for bucket policies)

### PartyRock Account

- Social media account (Apple, Amazon, or Google) for PartyRock authentication
- Access to [Amazon PartyRock](https://partyrock.aws/) platform

## Quick Start

### 1. Initialize Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform (downloads providers and modules)
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# Basic Configuration
aws_region     = "us-east-1"
environment    = "dev"
project_name   = "my-partyrock-app"

# S3 Configuration
bucket_name_prefix = "my-partyrock-site"
enable_versioning  = true
enable_encryption  = true

# Website Configuration
partyrock_app_url     = "https://partyrock.aws/u/your-username/your-app-id"
upload_sample_website = true

# CloudFront Configuration
enable_cloudfront      = true
cloudfront_price_class = "PriceClass_100"
enable_compression     = true

# Security Configuration
enable_public_access = true

# Additional Tags
resource_tags = {
  Owner       = "your-name"
  Project     = "PartyRock AI Showcase"
  Environment = "development"
}
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Get Deployment Information

```bash
# View all outputs
terraform output

# Get specific information
terraform output website_url
terraform output s3_bucket_name
terraform output cloudfront_domain_name
```

## Configuration Options

### S3 Bucket Settings

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `bucket_name_prefix` | Prefix for S3 bucket name | `"partyrock-app"` | string |
| `enable_versioning` | Enable S3 bucket versioning | `true` | bool |
| `enable_encryption` | Enable S3 server-side encryption | `true` | bool |
| `encryption_algorithm` | Encryption algorithm (AES256 or aws:kms) | `"AES256"` | string |

### Website Configuration

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `index_document` | Index document filename | `"index.html"` | string |
| `error_document` | Error document filename | `"error.html"` | string |
| `upload_sample_website` | Upload sample HTML files | `true` | bool |
| `partyrock_app_url` | URL of your PartyRock application | `"YOUR_PARTYROCK_APP_URL"` | string |

### CloudFront Configuration

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `enable_cloudfront` | Create CloudFront distribution | `true` | bool |
| `cloudfront_price_class` | Distribution coverage | `"PriceClass_100"` | string |
| `cloudfront_default_ttl` | Default cache TTL (seconds) | `86400` | number |
| `enable_compression` | Enable gzip compression | `true` | bool |

### Price Classes

- **PriceClass_All**: All edge locations (highest cost, best performance)
- **PriceClass_200**: Most edge locations (balanced cost/performance)
- **PriceClass_100**: Cheapest edge locations only (lowest cost)

## PartyRock Integration

### Step 1: Create Your PartyRock Application

1. Visit [Amazon PartyRock](https://partyrock.aws/)
2. Sign in with your social media account
3. Click "Build your own app"
4. Create your AI application (e.g., business name generator)
5. Test and refine your application

### Step 2: Make Application Public

1. In your PartyRock application, click "Make public and Share"
2. Copy the public application URL
3. Update your `terraform.tfvars` file with the URL:

```hcl
partyrock_app_url = "https://partyrock.aws/u/username/app-id"
```

### Step 3: Update Your Website

```bash
# Apply the changes to update the website
terraform apply
```

## Website Customization

### Upload Custom Files

```bash
# Get bucket name from Terraform output
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Upload custom HTML file
aws s3 cp custom-page.html s3://$BUCKET_NAME/

# Upload entire directory
aws s3 sync ./website-content s3://$BUCKET_NAME/

# Set proper content types
aws s3 cp styles.css s3://$BUCKET_NAME/ --content-type "text/css"
aws s3 cp script.js s3://$BUCKET_NAME/ --content-type "application/javascript"
```

### Invalidate CloudFront Cache

```bash
# Get CloudFront distribution ID
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)

# Invalidate all cached content
aws cloudfront create-invalidation \
    --distribution-id $DISTRIBUTION_ID \
    --paths "/*"

# Invalidate specific files
aws cloudfront create-invalidation \
    --distribution-id $DISTRIBUTION_ID \
    --paths "/index.html" "/styles.css"
```

## Monitoring and Maintenance

### View Website Logs

CloudFront access logs can be enabled by adding:

```hcl
# In your terraform.tfvars
enable_logging = true
log_bucket     = "your-logs-bucket"
```

### Monitor Costs

```bash
# Check S3 storage usage
aws s3 ls s3://$(terraform output -raw s3_bucket_name) --summarize --human-readable --recursive

# View CloudFront metrics in AWS Console
# Navigate to CloudFront > Distributions > Your Distribution > Monitoring
```

### Update PartyRock URL

```bash
# Update the variable
echo 'partyrock_app_url = "https://partyrock.aws/u/username/new-app-id"' >> terraform.tfvars

# Apply changes
terraform apply
```

## Security Best Practices

### Implemented Security Features

- ✅ HTTPS redirect via CloudFront
- ✅ S3 bucket encryption at rest
- ✅ Origin Access Control for CloudFront
- ✅ Public access only to necessary objects
- ✅ Versioning enabled for data protection

### Optional Enhancements

#### Add AWS WAF Protection

```hcl
# Example WAF integration (requires separate WAF resource)
web_acl_id = aws_wafv2_web_acl.security.arn
```

#### Custom Domain with SSL

```hcl
# Add to terraform.tfvars
domain_name = "my-ai-app.example.com"
ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789:certificate/abc-123"
```

## Troubleshooting

### Common Issues

#### Bucket Name Already Exists
```bash
# The random suffix should prevent this, but if it occurs:
terraform apply -var="random_id_length=10"
```

#### CloudFront Deployment Taking Long
```bash
# CloudFront deployments typically take 10-15 minutes
# Check status with:
aws cloudfront get-distribution --id $(terraform output -raw cloudfront_distribution_id)
```

#### Website Not Loading
```bash
# Check S3 website configuration
aws s3api get-bucket-website --bucket $(terraform output -raw s3_bucket_name)

# Verify public access
aws s3api get-public-access-block --bucket $(terraform output -raw s3_bucket_name)
```

#### PartyRock App Not Loading
- Ensure your PartyRock application is public
- Verify the URL is correct and accessible
- Check for CORS issues in browser developer tools

### Debug Commands

```bash
# Terraform debugging
export TF_LOG=DEBUG
terraform plan

# AWS CLI debugging
aws s3 ls --debug

# Test website connectivity
curl -I $(terraform output -raw website_url)
```

## Cost Optimization

### Estimated Monthly Costs

- **S3 Storage**: ~$0.023 per GB
- **S3 Requests**: ~$0.0004 per 1,000 GET requests
- **CloudFront**: ~$0.0075 per 10,000 requests + $0.085 per GB transfer
- **Total**: $0.50-$2.00 per month for typical usage

### Cost Reduction Strategies

1. **Use PriceClass_100** for CloudFront (cheapest option)
2. **Enable compression** to reduce transfer costs
3. **Set appropriate TTL** values to reduce origin requests
4. **Clean up old S3 versions** if versioning is enabled

## Cleanup

### Destroy Infrastructure

```bash
# Remove all resources
terraform destroy

# Confirm deletion
terraform show
```

### Manual Cleanup (if needed)

```bash
# Empty S3 bucket (if destroy fails)
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive

# Force delete bucket
aws s3 rb s3://$(terraform output -raw s3_bucket_name) --force
```

## Advanced Usage

### Multiple Environments

```bash
# Create workspace for different environments
terraform workspace new production
terraform workspace new staging

# Deploy to specific environment
terraform workspace select production
terraform apply -var-file="production.tfvars"
```

### Backend Configuration

```hcl
# Configure remote state storage (add to versions.tf)
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "partyrock-app/terraform.tfstate"
    region = "us-east-1"
  }
}
```

## Support and Resources

### Documentation Links

- [Amazon PartyRock User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/partyrock.html)
- [S3 Static Website Hosting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteHosting.html)
- [CloudFront Distribution Guide](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Getting Help

- Check the [AWS PartyRock community](https://community.aws/)
- Review [Terraform AWS provider issues](https://github.com/hashicorp/terraform-provider-aws/issues)
- Consult [AWS support](https://aws.amazon.com/support/) for infrastructure issues

## License

This Terraform configuration is provided as-is for educational and development purposes. Please review AWS service pricing and terms before deploying to production environments.