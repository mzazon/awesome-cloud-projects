# Infrastructure as Code for Building Static Website Hosting with S3, CloudFront, and Route 53

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Static Website Hosting with S3, CloudFront, and Route 53".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with permissions for S3, CloudFront, Route 53, and Certificate Manager
- A registered domain name (can be registered through Route 53 or external registrar)
- Domain DNS hosted in Route 53 (or ability to create DNS validation records)
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Appropriate IAM permissions for resource creation

## Architecture Overview

This implementation creates:
- S3 bucket for hosting static website content (www subdomain)
- S3 bucket for root domain redirects
- CloudFront distribution with global edge caching
- SSL/TLS certificate through AWS Certificate Manager
- Route 53 DNS records for domain resolution
- Public read access policies for website content

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name static-website-hosting \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DomainName,ParameterValue=example.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name static-website-hosting \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name static-website-hosting \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Set your domain name
export DOMAIN_NAME=example.com

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters domainName=$DOMAIN_NAME

# View outputs
cdk ls
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set your domain name
export DOMAIN_NAME=example.com

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters domainName=$DOMAIN_NAME

# View outputs
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your domain
echo 'domain_name = "example.com"' > terraform.tfvars

# Plan deployment
terraform plan

# Apply changes
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set your domain name
export DOMAIN_NAME=example.com

# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for domain name if not set
```

## Post-Deployment Steps

### Certificate Validation (All Methods)

After deployment, you need to validate the SSL certificate:

1. **Get DNS validation records**:
   ```bash
   # For CloudFormation/CDK
   aws acm describe-certificate \
       --certificate-arn <certificate-arn> \
       --region us-east-1 \
       --query 'Certificate.DomainValidationOptions[*].[DomainName,ResourceRecord.Name,ResourceRecord.Value]' \
       --output table
   
   # For Terraform
   terraform output certificate_validation_records
   ```

2. **Add CNAME records to Route 53**:
   The validation records will be automatically added if your domain is hosted in Route 53. If using external DNS, manually add the CNAME records.

3. **Wait for certificate validation**:
   ```bash
   aws acm wait certificate-validated \
       --certificate-arn <certificate-arn> \
       --region us-east-1
   ```

### Upload Website Content

After infrastructure deployment, upload your website content:

```bash
# Upload sample content to S3
aws s3 sync ./website-content/ s3://www.example.com/

# Or upload individual files
aws s3 cp index.html s3://www.example.com/ --content-type "text/html"
aws s3 cp error.html s3://www.example.com/ --content-type "text/html"
```

### Invalidate CloudFront Cache

When updating website content:

```bash
# Get distribution ID from outputs
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)

# Invalidate cache
aws cloudfront create-invalidation \
    --distribution-id $DISTRIBUTION_ID \
    --paths "/*"
```

## Customization

### CloudFormation Parameters

- `DomainName`: Your root domain name (e.g., example.com)
- `CreateDnsRecords`: Whether to create Route 53 DNS records (default: true)
- `PriceClass`: CloudFront price class (default: PriceClass_100)

### CDK Parameters

- `domainName`: Your root domain name
- `createDnsRecords`: Whether to create Route 53 DNS records
- `priceClass`: CloudFront price class

### Terraform Variables

Edit `terraform.tfvars` or use `-var` flags:

```bash
# terraform.tfvars
domain_name = "example.com"
create_dns_records = true
cloudfront_price_class = "PriceClass_100"
aws_region = "us-east-1"
```

### Bash Script Variables

Edit the variables section in `scripts/deploy.sh`:

```bash
# Configuration
DOMAIN_NAME=${DOMAIN_NAME:-"example.com"}
CREATE_DNS_RECORDS=${CREATE_DNS_RECORDS:-"true"}
CLOUDFRONT_PRICE_CLASS=${CLOUDFRONT_PRICE_CLASS:-"PriceClass_100"}
```

## Monitoring and Maintenance

### CloudWatch Monitoring

The infrastructure includes CloudWatch monitoring for:
- CloudFront request metrics
- S3 bucket access logs
- Certificate expiration alerts

### Cost Optimization

- Use CloudFront price classes to control costs
- Enable S3 Intelligent Tiering for infrequently accessed content
- Monitor CloudFront usage patterns

### Security Best Practices

- SSL/TLS certificates automatically renew
- S3 bucket policies restrict to read-only access
- CloudFront enforces HTTPS redirects
- Security headers can be added via Lambda@Edge

## Troubleshooting

### Common Issues

1. **Certificate validation fails**:
   - Verify DNS records are correctly configured
   - Check Route 53 hosted zone configuration
   - Ensure certificate is requested in us-east-1

2. **CloudFront deployment takes time**:
   - Initial deployment can take 15-20 minutes
   - Updates may take 10-15 minutes to propagate

3. **DNS propagation delays**:
   - Allow up to 24 hours for full global propagation
   - Use `dig` or `nslookup` to verify DNS resolution

### Validation Commands

```bash
# Test website accessibility
curl -I https://www.example.com
curl -I https://example.com

# Check certificate
openssl s_client -connect www.example.com:443 -servername www.example.com

# Verify CloudFront distribution
aws cloudfront get-distribution --id <distribution-id>
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name static-website-hosting

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name static-website-hosting \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Clean up CDK assets (optional)
cdk destroy --force
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

### Manual Cleanup Steps

If automated cleanup fails:

1. **Disable CloudFront distribution** (required before deletion)
2. **Delete S3 bucket contents** before deleting buckets
3. **Remove Route 53 records** if created outside of stack
4. **Delete Certificate Manager certificate** (only after CloudFront deletion)

## Cost Estimation

### Monthly Cost Breakdown (approximate)

- **Route 53 Hosted Zone**: $0.50/month
- **CloudFront**: $0.085/GB for first 10TB + $0.0075/10,000 requests
- **S3 Storage**: $0.023/GB/month (Standard)
- **Certificate Manager**: Free with CloudFront
- **Data Transfer**: Varies by usage

**Typical small website**: $0.50-$2.00/month (plus domain registration ~$12/year)

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult AWS documentation for specific services
4. Review CloudFormation/CDK/Terraform logs for deployment errors

## Additional Resources

- [AWS CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [AWS S3 Static Website Hosting](https://docs.aws.amazon.com/s3/latest/userguide/WebsiteHosting.html)
- [AWS Route 53 Documentation](https://docs.aws.amazon.com/route53/)
- [AWS Certificate Manager Documentation](https://docs.aws.amazon.com/acm/)
- [CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)