# Infrastructure as Code for API Security with WAF and Gateway

This directory contains Infrastructure as Code (IaC) implementations for the recipe "API Security with WAF and Gateway".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a secure API architecture using:
- AWS WAF Web ACL with rate limiting and geographic blocking rules
- API Gateway REST API with a test endpoint
- CloudWatch log group for WAF logging and monitoring
- CloudWatch metrics and alarms for security monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS WAF (Web ACL creation, rule management)
  - API Gateway (REST API creation and deployment)
  - CloudWatch (log group creation, metrics access)
  - IAM (for service-linked roles)
- One of the following tools depending on your deployment method:
  - CloudFormation (included with AWS CLI)
  - AWS CDK v2 (for TypeScript/Python implementations)
  - Terraform v1.0+ (for Terraform implementation)
  - Bash shell (for script-based deployment)

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name api-waf-security-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=api-security \
                 ParameterKey=Environment,ParameterValue=prod

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name api-waf-security-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name api-waf-security-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=api-security

# Get outputs
cdk ls --long
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters project-name=api-security

# Get outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_name=api-security"

# Apply configuration
terraform apply -var="project_name=api-security"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for configuration values
# Follow the on-screen instructions
```

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Prefix for resource names (default: "api-security")
- `Environment`: Environment name (default: "prod")
- `RateLimitThreshold`: Rate limit per IP (default: 1000)
- `BlockedCountries`: Countries to block (default: "CN,RU,KP")

### CDK Context Variables

- `projectName`: Project identifier for resource naming
- `environment`: Deployment environment
- `rateLimitThreshold`: WAF rate limiting threshold
- `enableGeoBlocking`: Enable/disable geographic blocking

### Terraform Variables

- `project_name`: Project identifier (required)
- `environment`: Environment name (default: "prod")
- `aws_region`: AWS region for deployment (default: current CLI region)
- `rate_limit_threshold`: Rate limiting threshold (default: 1000)
- `blocked_countries`: List of country codes to block (default: ["CN", "RU", "KP"])

## Testing the Deployment

After successful deployment, test the protected API:

```bash
# Get the API endpoint from outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name api-waf-security-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Test legitimate access
curl -X GET "${API_ENDPOINT}/test"

# Test rate limiting (run multiple times rapidly)
for i in {1..50}; do
  curl -s "${API_ENDPOINT}/test" > /dev/null &
done
wait

# Check WAF metrics in CloudWatch
aws cloudwatch get-metric-statistics \
    --namespace AWS/WAFV2 \
    --metric-name BlockedRequests \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Sum
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

### CloudWatch Metrics

- `AWS/WAFV2/AllowedRequests`: Number of allowed requests
- `AWS/WAFV2/BlockedRequests`: Number of blocked requests
- `AWS/ApiGateway/Count`: Total API requests
- `AWS/ApiGateway/Latency`: API response latency

### CloudWatch Logs

- WAF logs: `/aws/waf/api-security-acl-*`
- API Gateway execution logs: Available in CloudWatch Logs
- API Gateway access logs: Configured for detailed request tracking

### CloudWatch Alarms

- High rate of blocked requests (indicates potential attack)
- API Gateway error rate threshold
- Unusual geographic access patterns

## Security Features

### WAF Protection Rules

1. **Rate Limiting Rule**: Blocks IPs exceeding 1000 requests per 5 minutes
2. **Geographic Blocking Rule**: Blocks traffic from high-risk countries
3. **Custom Rule Capacity**: Additional capacity for custom rules

### API Gateway Security

- HTTPS-only endpoints
- Request/response logging
- Throttling configuration
- Method-level access control

### Monitoring and Alerting

- Real-time WAF event logging
- Security metrics dashboard
- Automated incident response triggers

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name api-waf-security-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name api-waf-security-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_name=api-security"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Adding Custom WAF Rules

To add additional WAF rules, modify the Web ACL configuration in your chosen IaC template:

#### CloudFormation Example
```yaml
Rules:
  - Name: CustomSQLInjectionRule
    Priority: 3
    Statement:
      SqliMatchStatement:
        FieldToMatch:
          Body: {}
        TextTransformations:
          - Priority: 0
            Type: URL_DECODE
```

#### Terraform Example
```hcl
rule {
  name     = "CustomSQLInjectionRule"
  priority = 3
  
  statement {
    sqli_match_statement {
      field_to_match {
        body {}
      }
      text_transformation {
        priority = 0
        type     = "URL_DECODE"
      }
    }
  }
}
```

### Modifying Rate Limits

Adjust the rate limiting threshold by changing the `Limit` parameter in the rate-based rule configuration.

### Custom Geographic Restrictions

Modify the `CountryCodes` array in the geographic blocking rule to customize which countries are blocked.

## Cost Optimization

- **WAF Costs**: $1.00/month per Web ACL + $0.60 per million requests + $1.00 per rule per month
- **API Gateway Costs**: $3.50 per million API calls (REST API)
- **CloudWatch Costs**: $0.50 per GB of log data ingested
- **Data Transfer**: Standard AWS data transfer rates apply

### Cost Saving Tips

1. Use CloudWatch log retention policies to manage storage costs
2. Implement request sampling in WAF for high-traffic APIs
3. Use API Gateway caching to reduce backend calls
4. Monitor and tune WAF rules to avoid unnecessary processing

## Troubleshooting

### Common Issues

1. **WAF Association Fails**: Ensure API Gateway stage is deployed before associating WAF
2. **Rate Limiting Too Aggressive**: Increase rate limit threshold or implement IP allowlists
3. **Geographic Blocking Issues**: Verify country codes are correct (ISO 3166-1 alpha-2)
4. **CloudWatch Logging Delays**: WAF logs may take 5-10 minutes to appear

### Debug Commands

```bash
# Check WAF Web ACL status
aws wafv2 get-web-acl --scope REGIONAL --id <web-acl-id> --name <web-acl-name>

# Verify API Gateway association
aws wafv2 list-resources-for-web-acl --web-acl-arn <web-acl-arn>

# Check recent WAF logs
aws logs filter-log-events \
    --log-group-name "/aws/waf/<web-acl-name>" \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check AWS WAF documentation: https://docs.aws.amazon.com/waf/
3. Review API Gateway documentation: https://docs.aws.amazon.com/apigateway/
4. Consult CloudWatch documentation: https://docs.aws.amazon.com/cloudwatch/

## License

This infrastructure code is provided under the same license as the parent recipe repository.