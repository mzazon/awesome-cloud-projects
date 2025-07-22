# Terraform Infrastructure for Secure Static Website

This Terraform configuration creates a complete secure static website hosting solution on AWS using Certificate Manager, CloudFront, and S3.

## Architecture Overview

The infrastructure includes:

- **S3 Bucket**: Stores static website content with versioning enabled
- **CloudFront Distribution**: Global CDN with SSL/TLS termination
- **ACM Certificate**: Free, auto-renewing SSL certificate
- **Origin Access Control**: Secures S3 bucket access through CloudFront only
- **Route 53 DNS**: Maps custom domain to CloudFront distribution
- **Security Features**: HTTPS redirect, secure headers, blocked direct S3 access

## Prerequisites

1. **AWS Account**: With appropriate permissions for the following services:
   - S3 (bucket creation and management)
   - CloudFront (distribution creation and management)
   - Certificate Manager (certificate creation and validation)
   - Route 53 (DNS record management)
   - IAM (for resource policies)

2. **Domain Requirements**:
   - Registered domain name
   - Route 53 hosted zone for the domain (or ability to create DNS validation records)

3. **Tools**:
   - Terraform >= 1.0
   - AWS CLI configured with appropriate credentials
   - Access to modify DNS records for domain validation

4. **Estimated Costs**:
   - ACM Certificate: Free
   - CloudFront: ~$0.50-$2.00/month for typical traffic
   - S3 Storage: ~$0.02/GB/month
   - Route 53: ~$0.50/month per hosted zone

## Quick Start

### 1. Configure Variables

Copy the example variables file and customize:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your domain information:

```hcl
domain_name = "yourdomain.com"
subdomain_name = "www"
aws_region = "us-east-1"
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 3. Verify Deployment

After deployment completes (may take 15-20 minutes for CloudFront):

```bash
# Test HTTPS connection
curl -I https://yourdomain.com

# Verify SSL certificate
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com < /dev/null 2>/dev/null | openssl x509 -text -noout | grep -A 2 "Subject:"

# Check CloudFront distribution status
aws cloudfront get-distribution --id $(terraform output -raw cloudfront_distribution_id)
```

## Configuration Options

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `domain_name` | Your registered domain name | `"example.com"` |

### Optional Variables

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `subdomain_name` | Subdomain prefix | `"www"` | Any valid subdomain |
| `aws_region` | AWS region for S3 bucket | `"us-east-1"` | Any AWS region |
| `bucket_name_prefix` | S3 bucket name prefix | `"static-website"` | Lowercase, hyphens only |
| `hosted_zone_id` | Route 53 hosted zone ID | `""` (auto-lookup) | Valid zone ID |
| `price_class` | CloudFront price class | `"PriceClass_100"` | `PriceClass_100`, `PriceClass_200`, `PriceClass_All` |
| `enable_versioning` | Enable S3 versioning | `true` | `true`, `false` |
| `enable_compression` | Enable gzip compression | `true` | `true`, `false` |
| `enable_ipv6` | Enable IPv6 support | `true` | `true`, `false` |

### Price Class Options

- **PriceClass_100**: North America and Europe (lowest cost)
- **PriceClass_200**: North America, Europe, Asia, Middle East, and Africa
- **PriceClass_All**: All edge locations globally (highest performance)

## Content Management

### Upload Website Content

After deployment, upload your website files:

```bash
# Upload all files from a local directory
aws s3 sync ./my-website/ s3://$(terraform output -raw s3_bucket_name)/ --delete

# Upload individual files
aws s3 cp index.html s3://$(terraform output -raw s3_bucket_name)/
aws s3 cp styles.css s3://$(terraform output -raw s3_bucket_name)/
```

### Invalidate CloudFront Cache

After uploading new content, invalidate the cache:

```bash
aws cloudfront create-invalidation \
    --distribution-id $(terraform output -raw cloudfront_distribution_id) \
    --paths "/*"
```

## Security Features

### Implemented Security Measures

1. **HTTPS Enforcement**: All HTTP traffic redirected to HTTPS
2. **Origin Access Control**: S3 bucket only accessible through CloudFront
3. **SSL/TLS Certificate**: Modern TLS protocols with automatic renewal
4. **Blocked Public Access**: S3 bucket public access completely blocked
5. **Secure Headers**: CloudFront configured with security best practices

### Security Best Practices

- Certificate uses DNS validation for automated renewal
- Minimum TLS version 1.2 enforced
- S3 bucket policy restricts access to CloudFront service principal
- Origin Access Control prevents direct S3 access

## Performance Optimization

### Built-in Optimizations

1. **Global CDN**: Content cached at AWS edge locations worldwide
2. **Compression**: Gzip compression enabled by default
3. **Caching**: Configurable TTL for optimal performance
4. **IPv6 Support**: Dual-stack support for modern networks

### Performance Tuning

```hcl
# Adjust cache TTL for better performance
cloudfront_cache_ttl = 3600  # 1 hour for dynamic content
cloudfront_cache_ttl = 86400 # 24 hours for static assets
```

## Monitoring and Maintenance

### CloudWatch Monitoring

Enable CloudWatch monitoring for:
- CloudFront request metrics
- S3 access metrics
- Certificate expiration monitoring

### Maintenance Tasks

1. **Content Updates**: Upload new files and invalidate cache
2. **Certificate Monitoring**: ACM handles renewal automatically
3. **Performance Review**: Monitor CloudFront metrics
4. **Cost Optimization**: Review usage and adjust price class if needed

## Troubleshooting

### Common Issues

1. **Certificate Validation Timeout**:
   - Verify DNS records are correctly configured
   - Check hosted zone ID is correct
   - Ensure domain ownership

2. **CloudFront Distribution Not Working**:
   - Wait 15-20 minutes for global propagation
   - Check distribution status in AWS console
   - Verify DNS records point to CloudFront domain

3. **S3 Access Denied**:
   - Ensure Origin Access Control is properly configured
   - Verify S3 bucket policy allows CloudFront access
   - Check that public access is blocked

### Debugging Commands

```bash
# Check certificate status
aws acm describe-certificate \
    --certificate-arn $(terraform output -raw certificate_arn) \
    --region us-east-1

# Check CloudFront distribution
aws cloudfront get-distribution \
    --id $(terraform output -raw cloudfront_distribution_id)

# Check DNS resolution
nslookup yourdomain.com
dig yourdomain.com

# Test HTTPS connection
curl -v https://yourdomain.com
```

## Cleanup

To destroy all created resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

**Warning**: This will permanently delete all resources including the S3 bucket and its contents.

## Advanced Configuration

### Custom Error Pages

Modify the error page template in `website_content/error.html` before deployment.

### Multiple Environments

Use Terraform workspaces for different environments:

```bash
# Create and switch to staging environment
terraform workspace new staging
terraform workspace select staging

# Deploy with environment-specific variables
terraform apply -var-file="staging.tfvars"
```

### Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Deploy Website
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v1
      - name: Terraform Apply
        run: |
          terraform init
          terraform apply -auto-approve
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## Support and Documentation

- [AWS Certificate Manager Documentation](https://docs.aws.amazon.com/acm/)
- [CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [S3 Static Website Hosting](https://docs.aws.amazon.com/s3/latest/userguide/WebsiteHosting.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License

This Terraform configuration is provided as-is for educational and production use. Customize according to your security and compliance requirements.