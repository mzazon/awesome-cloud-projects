# Infrastructure as Code for Content Delivery Networks with CloudFront

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Content Delivery Networks with CloudFront".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates an advanced CloudFront distribution with:

- **Multiple Origins**: S3 static content and custom API origins
- **Edge Functions**: CloudFront Functions and Lambda@Edge for content processing
- **Security**: AWS WAF integration with managed rule sets
- **Monitoring**: Real-time logs, CloudWatch dashboards, and metrics
- **Dynamic Configuration**: CloudFront KeyValueStore for runtime configuration
- **Access Control**: Origin Access Control (OAC) for S3 security

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - CloudFront distributions and functions
  - Lambda functions (including Lambda@Edge in us-east-1)
  - S3 buckets and policies
  - WAF Web ACLs
  - CloudWatch logs and dashboards
  - Kinesis Data Streams
  - IAM roles and policies
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.5+ (for Terraform implementation)
- Estimated cost: $50-100/month for testing environment

> **Note**: This recipe creates resources that may incur charges. Lambda@Edge functions have additional costs for execution time and requests.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name advanced-cloudfront-cdn \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-cdn-project

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name advanced-cloudfront-cdn \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name advanced-cloudfront-cdn \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_name=my-cdn-project"

# Apply the configuration
terraform apply -var="project_name=my-cdn-project"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment outputs
cat outputs.json
```

## Post-Deployment Testing

After deployment, test your CloudFront distribution:

```bash
# Get the CloudFront domain name from outputs
DISTRIBUTION_DOMAIN="your-distribution-domain.cloudfront.net"

# Test main content
curl -I https://${DISTRIBUTION_DOMAIN}/

# Test API routing
curl -I https://${DISTRIBUTION_DOMAIN}/api/ip

# Test security headers
curl -s -I https://${DISTRIBUTION_DOMAIN}/ | grep -E "X-Content-Type-Options|Strict-Transport-Security"

# Test cache behavior
curl -s -I https://${DISTRIBUTION_DOMAIN}/ | grep -i x-cache
```

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Unique identifier for resources (default: advanced-cdn)
- `Environment`: Deployment environment (default: dev)
- `PriceClass`: CloudFront price class (default: PriceClass_All)
- `EnableRealTimeLogs`: Enable real-time logging (default: true)

### CDK Context Variables

```json
{
  "project-name": "my-cdn-project",
  "environment": "production",
  "enable-waf": true,
  "enable-real-time-logs": true
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
project_name           = "my-cdn-project"
environment           = "production"
aws_region            = "us-east-1"
enable_waf            = true
enable_real_time_logs = true
price_class           = "PriceClass_All"

# Optional: Custom domain configuration
# custom_domain = "cdn.example.com"
# certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/..."
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

### CloudWatch Dashboard
Access your dashboard at: AWS Console → CloudWatch → Dashboards → `CloudFront-Advanced-CDN-{suffix}`

### Key Metrics
- Request count and traffic patterns
- Error rates (4xx/5xx)
- Cache hit ratios
- WAF blocked/allowed requests
- Lambda@Edge execution metrics

### Real-time Logs
Stream name: `cloudfront-realtime-logs-{suffix}`

### Sample Queries
```bash
# View WAF metrics
aws wafv2 get-sampled-requests \
    --web-acl-arn "your-webacl-arn" \
    --rule-metric-name "CommonRuleSetMetric" \
    --scope CLOUDFRONT \
    --time-window StartTime=2024-01-01T00:00:00,EndTime=2024-01-01T23:59:59 \
    --max-items 10

# Check cache hit rates
aws cloudwatch get-metric-statistics \
    --namespace AWS/CloudFront \
    --metric-name CacheHitRate \
    --dimensions Name=DistributionId,Value=your-distribution-id \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 3600 \
    --statistics Average
```

## Advanced Configuration

### Custom Lambda@Edge Functions

To deploy custom edge functions:

1. Update the Lambda function code in the appropriate directory
2. Redeploy using your chosen IaC method
3. Functions will automatically be versioned and associated with CloudFront

### WAF Rule Customization

Modify WAF rules by updating the Web ACL configuration in your chosen IaC implementation:

- Add custom rate limiting rules
- Configure geo-blocking
- Add IP allow/deny lists
- Customize managed rule set exclusions

### KeyValueStore Updates

Update dynamic configuration:

```bash
# Add new configuration
aws cloudfront put-key \
    --kvs-arn "your-kvs-arn" \
    --key "new_feature_flag" \
    --value "true"

# Update existing configuration
aws cloudfront put-key \
    --kvs-arn "your-kvs-arn" \
    --key "maintenance_mode" \
    --value "true"
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name advanced-cloudfront-cdn

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name advanced-cloudfront-cdn \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy --force

# Verify cleanup
cdk list
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="project_name=my-cdn-project"

# Verify cleanup
terraform state list
```

### Using Bash Scripts
```bash
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

> **Warning**: CloudFront distributions can take 15-45 minutes to fully deploy or delete. Be patient during these operations.

## Troubleshooting

### Common Issues

1. **Distribution Deployment Timeout**
   - CloudFront distributions can take 15-45 minutes to deploy
   - Use `aws cloudfront wait distribution-deployed` to monitor

2. **Lambda@Edge Function Errors**
   - Functions must be created in us-east-1 region
   - Ensure proper IAM permissions for edge execution
   - Check CloudWatch logs in multiple regions

3. **S3 Access Denied**
   - Verify Origin Access Control (OAC) configuration
   - Ensure S3 bucket policy allows CloudFront access
   - Check bucket exists and has content

4. **WAF Association Errors**
   - Ensure WAF Web ACL is in CLOUDFRONT scope
   - Verify IAM permissions for WAF operations
   - Check Web ACL is in us-east-1 region

### Debug Commands

```bash
# Check distribution status
aws cloudfront get-distribution --id YOUR_DISTRIBUTION_ID

# Test edge function execution
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda"

# Verify WAF configuration
aws wafv2 get-web-acl --scope CLOUDFRONT --id YOUR_WEBACL_ID

# Check S3 bucket policy
aws s3api get-bucket-policy --bucket YOUR_BUCKET_NAME
```

## Cost Optimization

### Recommendations

1. **Use appropriate price class** for your geographic coverage needs
2. **Monitor cache hit ratios** and optimize cache policies
3. **Review Lambda@Edge execution** costs and optimize function runtime
4. **Use CloudFront Functions** instead of Lambda@Edge for simple operations
5. **Enable compression** to reduce data transfer costs

### Cost Monitoring

```bash
# Get cost and usage data
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Security Considerations

- All traffic is encrypted in transit with TLS 1.2+
- S3 origins use Origin Access Control (OAC) for secure access
- WAF provides application-layer protection
- Lambda@Edge functions include comprehensive security headers
- Real-time monitoring enables rapid incident response

## Support

- For infrastructure code issues, refer to the original recipe documentation
- For AWS service issues, consult the [AWS CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- For Terraform issues, see [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- For CDK issues, refer to [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)

## Additional Resources

- [CloudFront Functions vs Lambda@Edge](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/edge-functions-choosing.html)
- [AWS WAF with CloudFront](https://docs.aws.amazon.com/waf/latest/developerguide/cloudfront-features.html)
- [CloudFront Security Best Practices](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/SecurityBestPractices.html)
- [Origin Access Control Documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)