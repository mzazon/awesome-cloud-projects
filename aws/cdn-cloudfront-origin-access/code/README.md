# Infrastructure as Code for CDN with CloudFront Origin Access Controls

This directory contains Infrastructure as Code (IaC) implementations for the recipe "CDN with CloudFront Origin Access Controls".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a secure, high-performance content delivery network with:

- CloudFront distribution with global edge locations
- S3 bucket for content storage with public access blocked
- Origin Access Control (OAC) for secure S3 access
- AWS WAF Web ACL for security protection
- CloudWatch monitoring and alarms
- Optimized cache behaviors for different content types

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- Permissions to create CloudFront distributions, S3 buckets, WAF web ACLs, and IAM policies
- Basic understanding of CDN concepts and web security
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform v1.5+ installed

### Required AWS Permissions

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudfront:*",
                "s3:*",
                "wafv2:*",
                "cloudwatch:*",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:PutRolePolicy",
                "iam:PassRole"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name cdn-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketNamePrefix,ParameterValue=my-cdn \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name cdn-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name cdn-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters bucketNamePrefix=my-cdn

# Get outputs
cdk outputs
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
cdk deploy --parameters bucket-name-prefix=my-cdn

# Get outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan deployment
terraform plan -var="bucket_name_prefix=my-cdn"

# Apply configuration
terraform apply -var="bucket_name_prefix=my-cdn"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
aws cloudfront list-distributions \
    --query 'DistributionList.Items[?Comment==`CDN Distribution`]'
```

## Configuration Parameters

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| BucketNamePrefix | Prefix for S3 bucket names | cdn-content | Yes |
| PriceClass | CloudFront price class | PriceClass_All | No |
| MinimumProtocolVersion | Minimum TLS version | TLSv1.2_2021 | No |
| LoggingEnabled | Enable CloudFront access logging | true | No |

### CDK/Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| bucket_name_prefix | Prefix for S3 bucket names | string | "cdn-content" |
| price_class | CloudFront price class | string | "PriceClass_All" |
| minimum_protocol_version | Minimum TLS version | string | "TLSv1.2_2021" |
| enable_logging | Enable access logging | bool | true |
| enable_waf | Enable WAF protection | bool | true |
| rate_limit | WAF rate limiting threshold | number | 2000 |

## Deployment Outputs

After successful deployment, you'll receive:

- **CloudFrontDistributionId**: The ID of the CloudFront distribution
- **CloudFrontDomainName**: The domain name for accessing your CDN
- **S3BucketName**: The name of the content S3 bucket
- **LogsBucketName**: The name of the logs S3 bucket
- **OriginAccessControlId**: The OAC ID for secure S3 access
- **WAFWebACLArn**: The ARN of the WAF Web ACL

## Testing Your Deployment

### 1. Upload Sample Content

```bash
# Set variables from outputs
BUCKET_NAME="your-content-bucket-name"
DISTRIBUTION_DOMAIN="your-cloudfront-domain.cloudfront.net"

# Create sample content
mkdir -p sample-content/{images,css,js}
echo "<h1>Hello CDN World!</h1>" > sample-content/index.html
echo "body { font-family: Arial; }" > sample-content/css/styles.css
echo "console.log('CDN working!');" > sample-content/js/app.js

# Upload to S3
aws s3 cp sample-content/ s3://${BUCKET_NAME}/ --recursive
```

### 2. Test CDN Performance

```bash
# Test main page
curl -s -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" \
    https://${DISTRIBUTION_DOMAIN}

# Test static assets
curl -s -o /dev/null -w "CSS Status: %{http_code}, Time: %{time_total}s\n" \
    https://${DISTRIBUTION_DOMAIN}/css/styles.css

# Test cache headers (second request should show cache hit)
curl -I https://${DISTRIBUTION_DOMAIN}/css/styles.css | grep X-Cache
```

### 3. Verify Security

```bash
# Test that direct S3 access is blocked
S3_URL="https://${BUCKET_NAME}.s3.amazonaws.com/index.html"
curl -s -o /dev/null -w "Direct S3 Status: %{http_code} (should be 403)\n" $S3_URL

# Test security headers
curl -I https://${DISTRIBUTION_DOMAIN} | grep -E "(X-Frame-Options|X-Content-Type-Options)"
```

## Monitoring and Optimization

### CloudWatch Metrics

Monitor these key metrics in the AWS Console:

- **Requests**: Total number of requests to your distribution
- **4xxErrorRate**: Client error rate (should be < 5%)
- **5xxErrorRate**: Server error rate (should be < 1%)
- **CacheHitRate**: Percentage of requests served from cache (target > 80%)
- **BytesDownloaded**: Amount of data transferred

### Performance Optimization

1. **Cache Behaviors**: Adjust TTL values based on content update frequency
2. **Compression**: Enable for text-based content (CSS, JS, HTML)
3. **Origin Shield**: Consider enabling for high-traffic scenarios
4. **Edge Locations**: Monitor geographic distribution of requests

### Security Best Practices

1. **WAF Rules**: Customize rules based on your application requirements
2. **SSL/TLS**: Use modern TLS versions and strong cipher suites
3. **HSTS**: Enable HTTP Strict Transport Security headers
4. **Content Security Policy**: Implement CSP headers for additional protection

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name cdn-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name cdn-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="bucket_name_prefix=my-cdn"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Distribution Deployment Takes Long**: CloudFront deployments typically take 5-15 minutes
2. **403 Forbidden Errors**: Check S3 bucket policy and OAC configuration
3. **Cache Not Working**: Verify cache behaviors and TTL settings
4. **WAF Blocking Legitimate Traffic**: Adjust rate limiting thresholds

### Debug Commands

```bash
# Check distribution status
aws cloudfront get-distribution --id YOUR_DISTRIBUTION_ID

# View WAF logs
aws logs describe-log-groups --log-group-name-prefix aws-waf-logs

# Monitor cache hit rates
aws cloudwatch get-metric-statistics \
    --namespace AWS/CloudFront \
    --metric-name CacheHitRate \
    --dimensions Name=DistributionId,Value=YOUR_DISTRIBUTION_ID \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 3600 \
    --statistics Average
```

## Cost Optimization

### Pricing Considerations

- **CloudFront Requests**: ~$0.0075 per 10,000 requests
- **Data Transfer**: ~$0.085 per GB (varies by region)
- **S3 Storage**: ~$0.023 per GB per month
- **WAF**: ~$1.00 per month + $0.60 per million requests

### Cost Optimization Tips

1. Use appropriate price class based on your user distribution
2. Optimize cache TTL to reduce origin requests
3. Enable compression to reduce data transfer costs
4. Monitor and adjust WAF rules to avoid unnecessary processing

## Advanced Configuration

### Custom Domain Setup

1. Request SSL certificate in AWS Certificate Manager
2. Add custom domain to CloudFront distribution
3. Update DNS records to point to CloudFront domain

### Multi-Origin Setup

1. Configure additional S3 buckets or custom origins
2. Set up origin groups for failover
3. Create cache behaviors for different content types

### Lambda@Edge Integration

1. Create Lambda functions for request/response manipulation
2. Associate functions with CloudFront behaviors
3. Monitor function performance and costs

## Support

For issues with this infrastructure code:

1. Check the [AWS CloudFront documentation](https://docs.aws.amazon.com/cloudfront/)
2. Review the [AWS WAF documentation](https://docs.aws.amazon.com/waf/)
3. Consult the original recipe documentation
4. Check AWS service health dashboard for known issues

## License

This infrastructure code is provided as-is for educational and development purposes.