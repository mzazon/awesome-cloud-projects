# Infrastructure as Code for Content Delivery Networks with CloudFront S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Delivery Networks with CloudFront S3".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - CloudFront distributions and Origin Access Control
  - S3 bucket creation and policy management
  - CloudWatch alarms and dashboards
  - Route 53 (if using custom domains)
- For CDK implementations: Node.js 18+ or Python 3.8+
- For Terraform: Terraform v1.0+
- Estimated cost: $5-15 per month for testing (depends on data transfer and requests)

> **Note**: CloudFront charges are based on data transfer out and requests. Monitor usage during testing to avoid unexpected costs.

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name cloudfront-cdn-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name cloudfront-cdn-stack \
    --query 'Stacks[0].StackStatus'

# Get CloudFront distribution domain
aws cloudformation describe-stacks \
    --stack-name cloudfront-cdn-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDomain`].OutputValue' \
    --output text
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Deploy the infrastructure
cdk deploy

# Get outputs
cdk output
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Deploy the infrastructure
cdk deploy

# Get outputs
cdk output
```

### Using Terraform
```bash
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy the infrastructure
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output CloudFront domain and other key information
```

## Infrastructure Components

This implementation creates the following AWS resources:

### Core Components
- **S3 Bucket**: Origin bucket for content storage with public access blocked
- **S3 Logs Bucket**: Dedicated bucket for CloudFront access logs
- **CloudFront Distribution**: Global CDN with optimized cache behaviors
- **Origin Access Control (OAC)**: Secure access to S3 origin

### Cache Behaviors
- **Default Behavior**: HTML content with 24-hour default TTL
- **Static Assets (*.css, *.js, *.png, *.jpg)**: 30-day cache duration
- **API Content (api/**)**: 1-hour cache duration for dynamic content

### Security Features
- **Origin Access Control**: Prevents direct S3 access
- **HTTPS Redirect**: Forces secure connections
- **S3 Bucket Policy**: Restricts access to CloudFront only
- **TLS 1.2 Minimum**: Modern encryption standards

### Monitoring & Logging
- **CloudWatch Alarms**: High error rate and origin latency monitoring
- **CloudWatch Dashboard**: Performance metrics visualization
- **Access Logs**: Detailed request logging to S3

## Configuration Options

### Environment Variables
All implementations support these customization options:

```bash
# Optional: Set custom resource names
export CDN_ENVIRONMENT=dev
export CDN_PROJECT_NAME=my-project

# Optional: Configure cache settings
export DEFAULT_TTL=86400        # 24 hours
export STATIC_ASSET_TTL=2592000 # 30 days
export API_TTL=3600             # 1 hour

# Optional: Set CloudFront price class
export PRICE_CLASS=PriceClass_100  # US and Europe only
```

### Terraform Variables
```hcl
# terraform.tfvars
environment        = "dev"
project_name      = "my-cdn-project"
price_class       = "PriceClass_100"
default_ttl       = 86400
static_asset_ttl  = 2592000
api_ttl           = 3600
enable_logging    = true
enable_monitoring = true
```

### CloudFormation Parameters
```yaml
# parameters.json
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "dev"
  },
  {
    "ParameterKey": "ProjectName",
    "ParameterValue": "my-cdn-project"
  },
  {
    "ParameterKey": "PriceClass",
    "ParameterValue": "PriceClass_100"
  }
]
```

## Testing the Deployment

### Verify Distribution
```bash
# Get CloudFront domain (replace with your actual domain)
CLOUDFRONT_DOMAIN="d1234567890.cloudfront.net"

# Test content delivery
curl -I https://${CLOUDFRONT_DOMAIN}

# Test cache headers
curl -I https://${CLOUDFRONT_DOMAIN}/styles.css

# Verify Origin Access Control
curl -I https://your-bucket-name.s3.amazonaws.com/index.html  # Should fail
```

### Upload Test Content
```bash
# Get bucket name from outputs
BUCKET_NAME=$(terraform output -raw content_bucket_name)

# Upload test files
aws s3 cp test-files/ s3://${BUCKET_NAME}/ --recursive

# Test different content types
curl https://${CLOUDFRONT_DOMAIN}/index.html
curl https://${CLOUDFRONT_DOMAIN}/styles.css
curl https://${CLOUDFRONT_DOMAIN}/api/data.json
```

### Monitor Performance
```bash
# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/CloudFront \
    --metric-name Requests \
    --dimensions Name=DistributionId,Value=YOUR_DISTRIBUTION_ID \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 3600 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name cloudfront-cdn-stack

# Wait for completion
aws cloudformation wait stack-delete-complete --stack-name cloudfront-cdn-stack
```

### Using CDK
```bash
# Destroy the infrastructure
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

## Customization

### Adding Custom Domains
To use a custom domain with your CloudFront distribution:

1. **Certificate**: Request or import SSL certificate in AWS Certificate Manager (us-east-1)
2. **DNS**: Configure Route 53 or your DNS provider
3. **Distribution**: Update distribution configuration with custom domain

### Advanced Cache Behaviors
Add custom cache behaviors by modifying the IaC templates:

```yaml
# CloudFormation example
CacheBehaviors:
  - PathPattern: "/api/v1/*"
    TargetOriginId: !Ref S3Origin
    ViewerProtocolPolicy: redirect-to-https
    DefaultTTL: 300  # 5 minutes
    MaxTTL: 3600     # 1 hour
```

### WAF Integration
Add AWS WAF for additional security:

```yaml
# CloudFormation example
WebACLId: !Ref MyWebACL
```

### Lambda@Edge Functions
Add Lambda@Edge for request/response modification:

```yaml
# CloudFormation example
LambdaFunctionAssociations:
  - EventType: viewer-request
    LambdaFunctionARN: !Ref MyLambdaFunction
```

## Troubleshooting

### Common Issues

1. **Distribution Not Accessible**
   - Check distribution status (must be "Deployed")
   - Verify Origin Access Control configuration
   - Ensure S3 bucket policy allows CloudFront access

2. **Cache Not Working**
   - Verify cache behaviors are correctly configured
   - Check CloudWatch metrics for cache hit ratio
   - Review TTL settings for different content types

3. **Origin Access Denied**
   - Verify OAC is properly configured
   - Check S3 bucket policy includes correct distribution ARN
   - Ensure public access is blocked on S3 bucket

4. **High Costs**
   - Monitor CloudWatch metrics for usage patterns
   - Consider using Price Class 100 for cost optimization
   - Optimize cache TTLs to reduce origin requests

### Debugging Commands
```bash
# Check distribution status
aws cloudfront get-distribution --id YOUR_DISTRIBUTION_ID

# View cache statistics
aws cloudfront get-distribution-config --id YOUR_DISTRIBUTION_ID

# Check invalidation status
aws cloudfront list-invalidations --distribution-id YOUR_DISTRIBUTION_ID
```

## Security Considerations

### Best Practices Implemented
- **Origin Access Control**: Secure S3 access
- **HTTPS Enforcement**: Redirect HTTP to HTTPS
- **Minimum TLS Version**: TLS 1.2 or higher
- **Restricted S3 Access**: Block public access to origin bucket

### Additional Security Measures
- Consider enabling AWS WAF for application-layer protection
- Implement signed URLs for premium content
- Use CloudFront custom headers for origin validation
- Enable real-time logs for security monitoring

## Performance Optimization

### Cache Optimization
- **Static Assets**: Long cache duration (30 days)
- **Dynamic Content**: Short cache duration (1 hour)
- **API Responses**: Conditional caching based on headers

### Cost Optimization
- **Price Class**: Limited to US and Europe for cost control
- **Compression**: Enabled for text-based content
- **Origin Shield**: Consider for frequently accessed content

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS CloudFront documentation
3. Verify all prerequisites are met
4. Check CloudWatch logs and metrics
5. Refer to the original recipe documentation

## Additional Resources

- [AWS CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [CloudFront Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/best-practices.html)
- [Origin Access Control Guide](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [CloudFront Monitoring](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/monitoring-using-cloudwatch.html)