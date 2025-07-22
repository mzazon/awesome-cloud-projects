# Infrastructure as Code for API Throttling and Rate Limiting

This directory contains Infrastructure as Code (IaC) implementations for the recipe "API Throttling and Rate Limiting".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- AWS account with permissions for:
  - API Gateway (create/manage REST APIs, usage plans, API keys)
  - Lambda (create/manage functions)
  - IAM (create/manage roles and policies)
  - CloudWatch (create/manage alarms and metrics)
- For CDK implementations: Node.js 18+ and Python 3.9+ respectively
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $5-15/month for API Gateway requests, Lambda executions, and CloudWatch metrics

## Architecture Overview

This implementation creates:
- REST API Gateway with throttling controls
- Lambda function backend
- Three usage plan tiers (Basic, Standard, Premium)
- Customer-specific API keys
- CloudWatch monitoring and alarms
- Stage-level and method-level throttling

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name api-throttling-demo \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=api-throttling-demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name api-throttling-demo \
    --query 'Stacks[0].StackStatus'

# Get API endpoint and keys
aws cloudformation describe-stacks \
    --stack-name api-throttling-demo \
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
cdk deploy

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
cdk deploy

# View outputs
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
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

# The script will output API endpoint and keys for testing
```

## Testing the Deployment

### Test API Key Authentication
```bash
# Get API endpoint from outputs
API_URL="<your-api-endpoint-from-outputs>"

# Test without API key (should return 403)
curl -X GET ${API_URL}

# Test with different tier keys
curl -X GET ${API_URL} -H "X-API-Key: <premium-key>"
curl -X GET ${API_URL} -H "X-API-Key: <standard-key>"
curl -X GET ${API_URL} -H "X-API-Key: <basic-key>"
```

### Load Testing Rate Limits
```bash
# Install Apache Bench for load testing
# Ubuntu/Debian: sudo apt-get install apache2-utils
# macOS: brew install apache-bench

# Test Basic tier rate limiting (100 RPS limit)
ab -n 1000 -c 10 -H "X-API-Key: <basic-key>" ${API_URL}

# Test Premium tier (2000 RPS limit)
ab -n 1000 -c 50 -H "X-API-Key: <premium-key>" ${API_URL}
```

### Monitor CloudWatch Metrics
```bash
# View API Gateway request count
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name Count \
    --dimensions Name=ApiName,Value=<api-name> Name=Stage,Value=prod \
    --statistics Sum \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300

# Check throttling events
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name ThrottleCount \
    --dimensions Name=ApiName,Value=<api-name> Name=Stage,Value=prod \
    --statistics Sum \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name api-throttling-demo

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name api-throttling-demo \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# From the CDK directory
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
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Usage Plan Configuration

Each implementation supports customizing the usage plan tiers through variables:

**Basic Tier (Default)**:
- Rate Limit: 100 requests/second
- Burst Limit: 200 requests
- Monthly Quota: 10,000 requests

**Standard Tier (Default)**:
- Rate Limit: 500 requests/second
- Burst Limit: 1,000 requests
- Monthly Quota: 100,000 requests

**Premium Tier (Default)**:
- Rate Limit: 2,000 requests/second
- Burst Limit: 5,000 requests
- Monthly Quota: 1,000,000 requests

### CloudWatch Alarm Thresholds

Customize monitoring thresholds by modifying:
- High throttling alarm threshold (default: 100 throttled requests in 5 minutes)
- High 4xx error alarm threshold (default: 50 errors in 5 minutes)
- Evaluation periods and alarm actions

### Regional Deployment

Change the AWS region by:
- **CloudFormation/CDK**: Modify your AWS CLI profile or CDK context
- **Terraform**: Update the `aws_region` variable
- **Bash Scripts**: Export `AWS_REGION` environment variable

## Usage Plan Tier Details

| Tier | Rate Limit (RPS) | Burst Limit | Monthly Quota | Use Case |
|------|------------------|-------------|---------------|----------|
| Basic | 100 | 200 | 10,000 | Free tier, light usage |
| Standard | 500 | 1,000 | 100,000 | Paid customers, moderate usage |
| Premium | 2,000 | 5,000 | 1,000,000 | Enterprise customers, high volume |

## Monitoring and Alerting

The implementation includes CloudWatch alarms for:

1. **High Throttling Events**: Triggers when throttling exceeds 100 events in 10 minutes
2. **High 4xx Error Rate**: Triggers when 4xx errors exceed 50 in 10 minutes

These alarms help identify:
- Customers hitting their usage limits
- Potential API abuse or unusual traffic patterns
- Need for usage plan adjustments

## Security Considerations

- API keys are required for all requests (enforced at method level)
- IAM roles follow least privilege principle
- Lambda function has minimal required permissions
- CloudWatch logs are retained for 14 days by default
- No sensitive data is logged in CloudWatch

## Troubleshooting

### Common Issues

1. **403 Forbidden Errors**:
   - Verify API key is included in `X-API-Key` header
   - Check that API key is associated with a usage plan
   - Ensure usage plan is associated with the API stage

2. **429 Too Many Requests**:
   - Client has exceeded their usage plan limits
   - Check CloudWatch metrics for throttling events
   - Consider upgrading client to higher tier usage plan

3. **500 Internal Server Error**:
   - Check Lambda function logs in CloudWatch
   - Verify Lambda function has proper IAM permissions
   - Check API Gateway integration configuration

### Debugging Commands

```bash
# Check API Gateway configuration
aws apigateway get-rest-apis
aws apigateway get-usage-plans

# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
aws logs filter-log-events --log-group-name "/aws/lambda/<function-name>"

# Check CloudWatch alarms
aws cloudwatch describe-alarms --state-value ALARM
```

## Best Practices

1. **Monitor Usage Patterns**: Regularly review CloudWatch metrics to optimize usage plan limits
2. **Secure API Keys**: Rotate API keys periodically and use secure distribution methods
3. **Cost Optimization**: Monitor API Gateway and Lambda costs, especially with high-volume usage
4. **Scaling**: Consider implementing custom authorizers for more complex authentication scenarios
5. **Regional Deployment**: Deploy in multiple regions for global applications with geo-specific rate limits

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check AWS service documentation:
   - [API Gateway Usage Plans](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-api-usage-plans.html)
   - [API Gateway Throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-request-throttling.html)
   - [Lambda Error Handling](https://docs.aws.amazon.com/lambda/latest/dg/python-exceptions.html)
3. Review CloudWatch logs for detailed error information
4. Validate IAM permissions for all services

## Extension Ideas

Consider enhancing this implementation with:
- AWS WAF integration for additional protection
- Amazon Cognito for user authentication
- Custom authorizers for advanced access control
- Multi-region deployment with Route 53 failover
- Integration with AWS X-Ray for distributed tracing