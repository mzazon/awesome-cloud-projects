# Infrastructure as Code for WAF Rate Limiting for Web Application Protection

This directory contains Infrastructure as Code (IaC) implementations for the recipe "WAF Rate Limiting for Web Application Protection".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for WAF, CloudFront, and CloudWatch operations
- Basic understanding of web application security and HTTP protocols
- Terraform CLI (for Terraform implementation)
- Node.js and npm (for CDK TypeScript)
- Python 3.7+ and pip (for CDK Python)
- Estimated cost: $1-5 per month for WAF rules + CloudFront/ALB usage charges

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name waf-protection-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=RateLimitThreshold,ParameterValue=2000 \
    --capabilities CAPABILITY_IAM \
    --region us-east-1
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
cdk bootstrap  # if first time using CDK in account
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # if first time using CDK in account
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Options

Each implementation supports the following customizable parameters:

- **WAF Web ACL Name**: Name for the WAF Web Access Control List
- **Rate Limit Threshold**: Maximum requests per 5-minute window (default: 2000)
- **CloudWatch Log Group**: Log group for WAF logging (default: /aws/wafv2/security-logs)
- **Dashboard Name**: CloudWatch dashboard name for monitoring
- **Environment Tags**: Tags for resource organization and cost tracking

## Architecture Components

This infrastructure deploys:

1. **AWS WAF Web ACL**: Central security policy container
2. **Rate Limiting Rule**: DDoS protection with configurable thresholds
3. **IP Reputation Rule**: Managed rule for threat intelligence
4. **CloudWatch Log Group**: Security event logging
5. **CloudWatch Dashboard**: Real-time monitoring and metrics
6. **IAM Roles**: Appropriate permissions for WAF logging

## Security Features

- **Rate-based Protection**: Automatically blocks IPs exceeding request thresholds
- **Threat Intelligence**: Leverages AWS managed IP reputation lists
- **Comprehensive Logging**: Detailed request/response logging with field redaction
- **Real-time Monitoring**: CloudWatch dashboards for security visibility
- **Edge Protection**: CloudFront integration for global protection

## Monitoring and Alerting

The deployed infrastructure includes:

- CloudWatch metrics for allowed/blocked requests
- Detailed WAF logs with request analysis
- Real-time dashboard for security events
- Metric-based alerting capabilities

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack \
    --stack-name waf-protection-stack \
    --region us-east-1
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Customization

### Rate Limiting Adjustments

Modify the rate limit threshold based on your application's traffic patterns:

- **Low Traffic Sites**: 500-1000 requests per 5 minutes
- **Medium Traffic Sites**: 2000-5000 requests per 5 minutes
- **High Traffic Sites**: 10000+ requests per 5 minutes

### Additional Security Rules

Consider adding these managed rule groups:

- **AWS Core Rule Set**: OWASP Top 10 protection
- **Known Bad Inputs**: Protection against common attack patterns
- **SQL Injection**: Database attack protection
- **Cross-Site Scripting**: XSS attack protection

### Geographic Restrictions

Implement geo-blocking by adding geographic match conditions to restrict or allow traffic from specific countries or regions.

## Integration with CloudFront

To associate the WAF Web ACL with a CloudFront distribution:

1. Update your CloudFront distribution configuration
2. Set the `WebACLId` to the WAF Web ACL ARN
3. Deploy the distribution update

## Cost Optimization

- Monitor WAF request charges ($0.60 per million requests)
- Set up CloudWatch billing alerts
- Review log retention policies to manage storage costs
- Consider rule efficiency to minimize processing overhead

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure IAM roles have sufficient WAF and CloudWatch permissions
2. **Region Restrictions**: WAF for CloudFront must be deployed in us-east-1
3. **Rate Limit Too Low**: Monitor blocked requests to adjust thresholds appropriately
4. **Log Volume**: High traffic sites may generate significant log data

### Validation Commands

```bash
# Check WAF Web ACL status
aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1

# Monitor blocked requests
aws cloudwatch get-metric-statistics \
    --namespace AWS/WAFV2 \
    --metric-name BlockedRequests \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# Check WAF logs
aws logs describe-log-streams \
    --log-group-name "/aws/wafv2/security-logs"
```

## Support

For issues with this infrastructure code, refer to:

- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- Original recipe documentation in the parent directory

## License

This infrastructure code is provided as-is under the same license as the recipe collection.