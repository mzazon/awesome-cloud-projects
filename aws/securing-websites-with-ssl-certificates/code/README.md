# Infrastructure as Code for Securing Websites with SSL Certificates

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Securing Websites with SSL Certificates".

## Overview

This solution implements a fully managed SSL/TLS certificate solution using AWS Certificate Manager (ACM) integrated with CloudFront and S3. The infrastructure provides automatic certificate provisioning, validation, and renewal while ensuring secure HTTPS connections for static websites with custom domains and global content delivery performance.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

The solution deploys:
- S3 bucket configured for static website hosting
- AWS Certificate Manager SSL/TLS certificate with DNS validation
- CloudFront distribution with Origin Access Control (OAC)
- Route 53 DNS records for custom domain
- Proper security policies and access controls

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- A registered domain name with DNS management access in Route 53
- Permissions for:
  - S3 (bucket creation, policy management)
  - CloudFront (distribution creation, OAC management)
  - Certificate Manager (certificate requests, validation)
  - Route 53 (DNS record management)
  - IAM (policy creation for service integration)

### Cost Estimate

- Certificate Manager certificates: **Free**
- CloudFront: $0.085 per GB data transfer + $0.0075 per 10,000 requests
- S3: $0.023 per GB storage + minimal request costs
- Route 53: $0.50 per hosted zone per month + $0.40 per million queries
- **Total estimated cost**: $0.50-$2.00 per month for typical usage

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name secure-static-website \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=DomainName,ParameterValue=example.com \
        ParameterKey=SubdomainName,ParameterValue=www.example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name secure-static-website \
    --query 'Stacks[0].StackStatus'

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name secure-static-website
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Set required environment variables
export DOMAIN_NAME=example.com
export SUBDOMAIN_NAME=www.example.com

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy SecureStaticWebsiteStack

# View outputs
cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set required environment variables
export DOMAIN_NAME=example.com
export SUBDOMAIN_NAME=www.example.com

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy SecureStaticWebsiteStack

# View outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
domain_name    = "example.com"
subdomain_name = "www.example.com"
environment    = "production"
EOF

# Plan the deployment
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

# Set required environment variables
export DOMAIN_NAME=example.com
export SUBDOMAIN_NAME=www.example.com

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output important information like:
# - S3 bucket name
# - CloudFront distribution ID
# - Certificate ARN
# - DNS validation records (if manual validation needed)
```

## Post-Deployment Steps

### DNS Validation

After deployment, you may need to complete DNS validation for the SSL certificate:

1. **Automatic Validation** (if using Route 53 for DNS):
   - The infrastructure automatically creates validation records
   - Certificate validation completes within 5-10 minutes

2. **Manual Validation** (if using external DNS provider):
   - Retrieve validation records from AWS Console or CLI
   - Add CNAME records to your DNS provider
   - Wait for validation to complete

### Content Upload

Upload your website content to the S3 bucket:

```bash
# Get bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name secure-static-website \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

# Upload website files
aws s3 sync ./website-content/ s3://${BUCKET_NAME}/

# Set proper content types
aws s3 cp s3://${BUCKET_NAME}/index.html s3://${BUCKET_NAME}/index.html \
    --content-type "text/html" --metadata-directive REPLACE
```

## Validation

### Verify SSL Certificate

```bash
# Check certificate status
CERT_ARN=$(aws cloudformation describe-stacks \
    --stack-name secure-static-website \
    --query 'Stacks[0].Outputs[?OutputKey==`CertificateArn`].OutputValue' \
    --output text)

aws acm describe-certificate \
    --certificate-arn ${CERT_ARN} \
    --region us-east-1 \
    --query 'Certificate.Status'
```

### Test HTTPS Access

```bash
# Test CloudFront domain
CLOUDFRONT_DOMAIN=$(aws cloudformation describe-stacks \
    --stack-name secure-static-website \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDomain`].OutputValue' \
    --output text)

curl -I https://${CLOUDFRONT_DOMAIN}

# Test custom domain (after DNS propagation)
curl -I https://example.com

# Verify HTTPS redirect
curl -I http://example.com
```

### Security Validation

```bash
# Check SSL/TLS configuration
nmap --script ssl-enum-ciphers -p 443 example.com

# Verify security headers
curl -I https://example.com | grep -i "strict-transport-security\|content-security-policy"

# Test certificate chain
openssl s_client -connect example.com:443 -servername example.com < /dev/null
```

## Customization

### Variables and Parameters

Each implementation supports customization through variables:

- **Domain Configuration**:
  - `domain_name`: Primary domain name
  - `subdomain_name`: Subdomain (typically www.domain.com)
  
- **Environment Settings**:
  - `environment`: Environment name (dev, staging, production)
  - `project_name`: Project identifier for resource naming
  
- **Security Configuration**:
  - `minimum_protocol_version`: Minimum TLS version (default: TLSv1.2_2021)
  - `ssl_support_method`: SSL support method (default: sni-only)
  
- **CloudFront Settings**:
  - `price_class`: Price class for CloudFront distribution
  - `default_ttl`: Default cache TTL in seconds
  - `max_ttl`: Maximum cache TTL in seconds

### Advanced Configuration

For production deployments, consider these enhancements:

1. **Multiple Environments**:
   ```bash
   # Deploy to different environments
   terraform workspace new staging
   terraform apply -var="environment=staging"
   ```

2. **Custom Security Headers**:
   ```bash
   # Modify CloudFront behavior to add security headers
   # Update terraform/main.tf or CloudFormation template
   ```

3. **WAF Integration**:
   ```bash
   # Add AWS WAF for additional security
   # Uncomment WAF resources in templates
   ```

## Monitoring and Maintenance

### CloudWatch Monitoring

```bash
# Monitor certificate expiration
aws logs create-log-group --log-group-name /aws/certificate-monitor

# Monitor CloudFront metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/CloudFront \
    --metric-name Requests \
    --dimensions Name=DistributionId,Value=${DISTRIBUTION_ID} \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

### Certificate Renewal

AWS Certificate Manager automatically renews certificates, but you can monitor the process:

```bash
# Check certificate renewal status
aws acm describe-certificate \
    --certificate-arn ${CERT_ARN} \
    --region us-east-1 \
    --query 'Certificate.[Status,RenewalEligibility]'
```

## Cleanup

### Using CloudFormation

```bash
# Empty S3 bucket first (CloudFormation cannot delete non-empty buckets)
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name secure-static-website \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text)

aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete the stack
aws cloudformation delete-stack --stack-name secure-static-website

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name secure-static-website
```

### Using CDK

```bash
# CDK TypeScript
cd cdk-typescript/
cdk destroy SecureStaticWebsiteStack

# CDK Python
cd cdk-python/
cdk destroy SecureStaticWebsiteStack
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Troubleshooting

### Common Issues

1. **Certificate Validation Timeout**:
   - Verify DNS records are correctly configured
   - Check domain ownership in Route 53
   - Ensure certificate is requested in us-east-1 region

2. **CloudFront Distribution Not Accessible**:
   - Wait for distribution deployment (15-20 minutes)
   - Verify Origin Access Control configuration
   - Check S3 bucket policy allows CloudFront access

3. **DNS Resolution Issues**:
   - Allow time for DNS propagation (up to 48 hours)
   - Verify Route 53 records are correctly configured
   - Check domain registrar's nameserver configuration

4. **S3 Access Denied Errors**:
   - Verify bucket policy allows CloudFront service principal
   - Check Origin Access Control is properly configured
   - Ensure S3 bucket is not publicly accessible

### Debug Commands

```bash
# Check CloudFront distribution status
aws cloudfront get-distribution --id ${DISTRIBUTION_ID}

# Verify S3 bucket policy
aws s3api get-bucket-policy --bucket ${BUCKET_NAME}

# Check Route 53 records
aws route53 list-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID}

# Test DNS resolution
dig example.com
nslookup example.com
```

## Security Best Practices

This implementation follows AWS security best practices:

- **Least Privilege Access**: S3 bucket is only accessible through CloudFront
- **Encryption in Transit**: All traffic uses HTTPS with modern TLS versions
- **Certificate Management**: Automatic certificate renewal prevents expiration
- **Content Security**: Origin Access Control prevents direct S3 access
- **DNS Security**: Route 53 provides DDoS protection and health checks

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation:
   - [AWS Certificate Manager User Guide](https://docs.aws.amazon.com/acm/latest/userguide/)
   - [CloudFront Developer Guide](https://docs.aws.amazon.com/cloudfront/latest/developerguide/)
   - [S3 Static Website Hosting](https://docs.aws.amazon.com/s3/latest/userguide/WebsiteHosting.html)
3. Verify AWS service quotas and limits
4. Contact AWS Support for service-specific issues

## License

This infrastructure code is provided under the same license as the recipe documentation.