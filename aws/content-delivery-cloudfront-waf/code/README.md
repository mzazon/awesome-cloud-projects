# Infrastructure as Code for Secure Content Delivery with CloudFront WAF

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Content Delivery with CloudFront WAF".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for CloudFront, WAF, S3, and CloudWatch
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Basic understanding of web application security concepts
- Estimated cost: $0.50-$2.00 per month for WAF rules and CloudFront requests (varies by traffic volume)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name secure-content-delivery-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketNamePrefix,ParameterValue=secure-content \
    --capabilities CAPABILITY_IAM

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name secure-content-delivery-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name secure-content-delivery-stack \
    --query "Stacks[0].Outputs"
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done before)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using Terraform
```bash
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

# The script will output the CloudFront distribution URL and other important information
```

## Architecture Overview

This infrastructure deploys:

- **S3 Bucket**: Stores static content with secure access policies
- **Origin Access Control (OAC)**: Ensures S3 can only be accessed through CloudFront
- **AWS WAF Web ACL**: Provides multi-layered security protection including:
  - AWS Managed Rules for common threats (OWASP Top 10, known bad inputs)
  - Rate-based rules for DDoS protection (2000 requests per 5-minute window)
  - Geographic restrictions (configurable)
- **CloudFront Distribution**: Global content delivery with edge security
- **CloudWatch Integration**: Monitoring and logging for security events

## Security Features

- **HTTPS Enforcement**: All HTTP requests are redirected to HTTPS
- **Origin Protection**: Direct S3 access is blocked via bucket policies
- **DDoS Protection**: Rate-based rules automatically block excessive requests
- **Common Threat Protection**: AWS Managed Rules protect against OWASP Top 10
- **Geographic Controls**: Optional country-based access restrictions
- **Security Monitoring**: CloudWatch metrics for all security events

## Configuration Options

Each implementation supports customization through variables/parameters:

- **Bucket Name Prefix**: Customize the S3 bucket naming
- **Rate Limit**: Adjust the rate-based rule threshold (default: 2000 requests/5min)
- **Geographic Restrictions**: Configure allowed/blocked countries
- **Cache Behavior**: Customize CloudFront caching policies
- **WAF Rules**: Enable/disable specific managed rule groups

## Testing the Deployment

After deployment, test the security features:

```bash
# Get the CloudFront domain name from outputs
DOMAIN_NAME="your-cloudfront-domain.cloudfront.net"

# Test HTTPS access (should work)
curl -I https://${DOMAIN_NAME}/index.html

# Test HTTP redirect (should redirect to HTTPS)
curl -I http://${DOMAIN_NAME}/index.html

# Verify direct S3 access is blocked
curl -I https://your-bucket-name.s3.amazonaws.com/index.html
# This should return 403 Forbidden
```

## Monitoring and Logs

Access security metrics and logs through:

- **CloudWatch Metrics**: WAF and CloudFront request metrics
- **WAF Logs**: Detailed request inspection results
- **CloudFront Logs**: Access patterns and geographic distribution
- **Security Dashboard**: Real-time security event monitoring

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name secure-content-delivery-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name secure-content-delivery-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Cost Optimization

To minimize costs:

- **WAF Rules**: Start with essential managed rules and add more as needed
- **CloudFront Price Class**: Use PriceClass_100 for cost-effective global delivery
- **S3 Storage Class**: Consider Intelligent Tiering for varying access patterns
- **Monitoring**: Set up CloudWatch billing alerts for usage tracking

## Troubleshooting

### Common Issues

1. **403 Forbidden Errors**: Verify Origin Access Control configuration
2. **WAF Blocking Legitimate Traffic**: Review rate limits and managed rule exclusions
3. **Deployment Failures**: Check IAM permissions and resource quotas
4. **Slow Propagation**: CloudFront changes can take 15-20 minutes to propagate

### Support Resources

- [AWS CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [AWS WAF Best Practices](https://docs.aws.amazon.com/waf/latest/developerguide/waf-best-practices.html)
- [CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)

## Customization

Refer to the variable definitions in each implementation to customize the deployment for your environment. Key customization areas include:

- WAF rule configurations and thresholds
- CloudFront cache behaviors and TTL settings
- S3 bucket policies and access controls
- Geographic restriction policies
- Monitoring and alerting configurations

## Support

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation. For specific implementation issues, consult the relevant tool documentation (CloudFormation, CDK, or Terraform).