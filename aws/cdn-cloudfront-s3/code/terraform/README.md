# CloudFront and S3 CDN - Terraform Implementation

This Terraform configuration deploys a complete CloudFront Content Delivery Network (CDN) with S3 origin, implementing security best practices and performance optimization.

## Architecture Overview

The infrastructure includes:
- **S3 Bucket**: Secure content storage with encryption and versioning
- **CloudFront Distribution**: Global CDN with multiple cache behaviors
- **Origin Access Control (OAC)**: Secure S3 access prevention
- **Security Headers**: Comprehensive response headers policy
- **CloudWatch Monitoring**: Alarms and dashboard for performance tracking
- **Sample Content**: Test files demonstrating different cache behaviors

## Features

### Security
- Origin Access Control (OAC) preventing direct S3 access
- Security headers (CSP, HSTS, X-Frame-Options, etc.)
- TLS 1.2+ enforcement with HTTPS redirect
- S3 bucket encryption and public access blocking

### Performance
- Multiple cache behaviors for different content types
- Compression enabled for optimal bandwidth usage
- Regional edge locations (configurable price class)
- HTTP/2 support with IPv6 enabled

### Monitoring
- CloudWatch alarms for error rates and latency
- Performance dashboard with key metrics
- Access logging to dedicated S3 bucket

## Prerequisites

1. **AWS CLI** installed and configured
2. **Terraform** >= 1.0 installed
3. **AWS Account** with appropriate permissions:
   - CloudFront full access
   - S3 full access
   - CloudWatch full access
   - IAM permissions for bucket policies

## Quick Start

1. **Clone and navigate to the directory**:
   ```bash
   cd aws/content-delivery-networks-cloudfront-s3/code/terraform/
   ```

2. **Copy and customize variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your preferred settings
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan the deployment**:
   ```bash
   terraform plan
   ```

5. **Apply the configuration**:
   ```bash
   terraform apply
   ```

6. **Test the deployment**:
   ```bash
   # Get the CloudFront domain name
   terraform output cloudfront_domain_name
   
   # Test the distribution
   curl -I https://$(terraform output -raw cloudfront_domain_name)
   ```

## Configuration Variables

### Required Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for resources | `us-east-1` |
| `environment` | Environment name | `dev` |
| `project_name` | Project name for resource naming | `cdn-content` |

### CloudFront Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `cloudfront_price_class` | Price class for edge locations | `PriceClass_100` |
| `cloudfront_default_ttl` | Default cache TTL in seconds | `86400` |
| `cloudfront_max_ttl` | Maximum cache TTL in seconds | `31536000` |
| `cloudfront_min_ttl` | Minimum cache TTL in seconds | `0` |

### Feature Toggles
| Variable | Description | Default |
|----------|-------------|---------|
| `enable_cloudfront_logging` | Enable CloudFront access logging | `true` |
| `enable_cloudwatch_monitoring` | Enable CloudWatch monitoring | `true` |
| `enable_ipv6` | Enable IPv6 support | `true` |
| `enable_compression` | Enable automatic compression | `true` |

### Monitoring Configuration
| Variable | Description | Default |
|----------|-------------|---------|
| `error_rate_threshold` | Error rate alarm threshold (%) | `5.0` |
| `origin_latency_threshold` | Origin latency alarm threshold (ms) | `1000` |

## Cache Behaviors

The distribution includes optimized cache behaviors for different content types:

1. **Default Behavior** (HTML pages): 24-hour TTL
2. **CSS Files** (`*.css`): 30-day TTL
3. **JavaScript Files** (`*.js`): 30-day TTL
4. **Images** (`/images/*`): 30-day TTL
5. **API Endpoints** (`/api/*`): 1-hour TTL with query string forwarding

## Security Configuration

### Origin Access Control
- Uses modern OAC instead of legacy OAI
- Prevents direct S3 bucket access
- Supports all S3 features including SSE-KMS

### Security Headers
- **Content Security Policy**: Restrictive CSP for XSS protection
- **Strict Transport Security**: HSTS with 1-year max-age
- **X-Frame-Options**: Prevents clickjacking
- **X-Content-Type-Options**: Prevents MIME type sniffing
- **Referrer Policy**: Controls referrer information

### S3 Security
- Public access blocked at bucket level
- Server-side encryption enabled
- Versioning enabled for content recovery
- Bucket policy restricts access to CloudFront only

## Monitoring and Alerting

### CloudWatch Alarms
- **High Error Rate**: Triggers when 4xx errors exceed threshold
- **High Origin Latency**: Triggers when origin response time is high

### CloudWatch Dashboard
- Request volume and bytes downloaded
- Error rates (4xx and 5xx)
- Cache hit rate and origin latency
- Performance metrics over time

## Cost Optimization

### Price Classes
- **PriceClass_100**: US and Europe only (lowest cost)
- **PriceClass_200**: US, Europe, and Asia
- **PriceClass_All**: Global coverage (highest cost)

### Caching Strategy
- Long TTLs for static assets reduce origin requests
- Compression enabled reduces bandwidth costs
- Edge locations cache content close to users

## Testing

### Test URLs
After deployment, test different cache behaviors:

```bash
# Get the CloudFront domain
DOMAIN=$(terraform output -raw cloudfront_domain_name)

# Test main page (24-hour cache)
curl -I https://$DOMAIN/

# Test CSS file (30-day cache)
curl -I https://$DOMAIN/styles.css

# Test API endpoint (1-hour cache)
curl -I https://$DOMAIN/api/response.json
```

### Cache Invalidation
Invalidate cached content when needed:

```bash
# Invalidate all content
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"

# Invalidate specific files
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/index.html" "/styles.css"
```

## Outputs

The configuration provides comprehensive outputs for integration and verification:

- **CloudFront**: Distribution ID, domain name, ARN, status
- **S3 Buckets**: Bucket names, ARNs, domain names
- **Security**: OAC and security headers policy IDs
- **Monitoring**: Alarm ARNs and dashboard URL
- **Testing**: URLs for testing different cache behaviors

## Customization

### Adding Custom Domains
To use a custom domain with SSL certificate:

1. Add Route 53 hosted zone and SSL certificate
2. Update the CloudFront distribution viewer certificate configuration
3. Add CNAME record pointing to CloudFront domain

### Additional Cache Behaviors
Add more cache behaviors by extending the `ordered_cache_behavior` blocks in `main.tf`:

```hcl
ordered_cache_behavior {
  path_pattern     = "/fonts/*"
  target_origin_id = "S3-${aws_s3_bucket.content_bucket.id}"
  # ... additional configuration
}
```

### WAF Integration
Add AWS WAF for additional security:

```hcl
resource "aws_wafv2_web_acl" "cdn_waf" {
  # WAF configuration
}

# Add web_acl_id to CloudFront distribution
resource "aws_cloudfront_distribution" "cdn_distribution" {
  web_acl_id = aws_wafv2_web_acl.cdn_waf.arn
  # ... rest of configuration
}
```

## Cleanup

To remove all resources:

```bash
# Destroy all resources
terraform destroy

# Clean up state files
rm -f terraform.tfstate*
rm -rf .terraform/
```

## Troubleshooting

### Common Issues

1. **Distribution not accessible**: Wait 10-15 minutes for deployment
2. **403 Forbidden errors**: Check OAC and S3 bucket policy
3. **Cache not working**: Verify cache behaviors and TTL settings
4. **High costs**: Consider lower price class or review cache hit rates

### Debug Commands

```bash
# Check distribution status
aws cloudfront get-distribution \
  --id $(terraform output -raw cloudfront_distribution_id)

# Check S3 bucket policy
aws s3api get-bucket-policy \
  --bucket $(terraform output -raw content_bucket_id)

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=DistributionId,Value=$(terraform output -raw cloudfront_distribution_id) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --statistics Sum
```

## Best Practices

1. **Use OAC**: Always use Origin Access Control instead of OAI
2. **Monitor Performance**: Set up CloudWatch alarms for key metrics
3. **Optimize Caching**: Use appropriate TTLs for different content types
4. **Security Headers**: Implement comprehensive security headers
5. **Cost Management**: Choose appropriate price class for your user base
6. **Regular Updates**: Keep Terraform and AWS provider versions current

## Support

For issues with this Terraform configuration:
1. Check the [AWS CloudFront documentation](https://docs.aws.amazon.com/cloudfront/)
2. Review the [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
3. Consult the original recipe documentation for implementation details

## License

This configuration is provided as-is for educational and demonstration purposes.