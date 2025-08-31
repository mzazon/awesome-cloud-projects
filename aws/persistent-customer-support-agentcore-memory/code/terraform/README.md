# Terraform Infrastructure for Customer Support Agent

This directory contains Terraform Infrastructure as Code (IaC) for deploying the **Persistent Customer Support Agent with Bedrock AgentCore Memory** solution on AWS.

## Architecture Overview

This infrastructure deploys:

- **Amazon Bedrock AgentCore Memory**: Persistent memory for maintaining customer conversation context
- **AWS Lambda**: Serverless function processing customer support requests
- **Amazon DynamoDB**: Database for storing customer metadata and preferences
- **Amazon API Gateway**: REST API endpoint for client interactions
- **Amazon CloudWatch**: Monitoring, logging, and alerting
- **AWS IAM**: Security roles and policies with least privilege access

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS Account**: With appropriate permissions for all services
2. **Terraform**: Version 1.6.0 or later
3. **AWS CLI**: Version 2.x configured with appropriate credentials
4. **Bedrock AgentCore Access**: Preview service access enabled in your AWS account
5. **Regional Support**: Deploy in a region that supports Bedrock AgentCore

### Supported AWS Regions

Bedrock AgentCore is currently available in:
- `us-east-1` (N. Virginia)
- `us-west-2` (Oregon)
- `eu-west-1` (Ireland)
- `eu-central-1` (Frankfurt)
- `ap-southeast-1` (Singapore)
- `ap-northeast-1` (Tokyo)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/persistent-customer-support-agentcore-memory/code/terraform/
```

### 2. Configure Variables

```bash
# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit variables for your environment
nano terraform.tfvars
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

### 6. Test the Deployment

```bash
# Get the API endpoint from outputs
API_ENDPOINT=$(terraform output -raw api_gateway_invoke_url)

# Test with curl
curl -X POST $API_ENDPOINT \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "customer-001",
    "message": "Hi, I need help with my analytics dashboard. It'\''s loading very slowly.",
    "metadata": {
      "userAgent": "Mozilla/5.0 (Chrome)",
      "sessionLocation": "dashboard"
    }
  }'
```

## Configuration Options

### Essential Variables

```hcl
# Basic configuration
aws_region = "us-east-1"
tags = {
  Environment = "development"
  Project     = "CustomerSupportAgent"
}

# Bedrock model selection
bedrock_model_id = "anthropic.claude-3-haiku-20240307-v1:0"

# DynamoDB configuration
dynamodb_billing_mode   = "PROVISIONED"
dynamodb_read_capacity  = 5
dynamodb_write_capacity = 5
```

### Production Considerations

```hcl
# Enhanced security
enable_vpc_endpoints = true
enable_waf          = true
enable_api_key_required = true

# Performance optimization
enable_api_caching        = true
lambda_reserved_concurrency = 50

# Monitoring and alerting
enable_monitoring        = true
alarm_notification_topic = "arn:aws:sns:region:account:alerts"
```

## File Structure

```
terraform/
├── main.tf                    # Main infrastructure resources
├── variables.tf               # Variable definitions with validation
├── outputs.tf                 # Output values for integration
├── versions.tf                # Provider requirements and versions
├── lambda_function.py.tpl     # Lambda function code template
├── terraform.tfvars.example   # Example variable configuration
└── README.md                  # This file
```

## Key Resources Created

### Core Infrastructure

| Resource Type | Purpose | Naming Pattern |
|---------------|---------|----------------|
| `aws_bedrockagent_memory` | Persistent conversation memory | `{memory_name_prefix}-{random_suffix}` |
| `aws_lambda_function` | Support agent processing | `{lambda_function_name_prefix}-{random_suffix}` |
| `aws_dynamodb_table` | Customer metadata storage | `{table_name_prefix}-{random_suffix}` |
| `aws_api_gateway_rest_api` | Client API endpoint | `{api_name_prefix}-{random_suffix}` |

### Supporting Infrastructure

| Resource Type | Purpose |
|---------------|---------|
| `aws_iam_role` | Lambda execution role with minimal permissions |
| `aws_cloudwatch_log_group` | Centralized logging for Lambda and API Gateway |
| `aws_cloudwatch_metric_alarm` | Monitoring and alerting for errors |
| `aws_sqs_queue` | Dead letter queue for failed Lambda invocations |

## Security Features

### IAM Policies

The infrastructure implements least privilege access:

```json
{
  "Bedrock AgentCore": [
    "bedrock-agentcore:CreateEvent",
    "bedrock-agentcore:RetrieveMemoryRecords"
  ],
  "Bedrock Runtime": [
    "bedrock:InvokeModel"
  ],
  "DynamoDB": [
    "dynamodb:GetItem",
    "dynamodb:PutItem",
    "dynamodb:UpdateItem"
  ]
}
```

### Data Protection

- **Encryption**: DynamoDB encryption at rest enabled by default
- **Network Security**: VPC endpoints available for enhanced isolation
- **API Security**: CORS configuration and optional WAF protection
- **Audit Trail**: CloudWatch logging for all API calls and Lambda executions

## Monitoring and Observability

### CloudWatch Alarms

- **Lambda Errors**: Alert on function failures
- **API Gateway 4XX**: Monitor client errors
- **API Gateway 5XX**: Monitor server errors
- **Lambda Duration**: Monitor performance issues

### Logging

- **Lambda Logs**: `/aws/lambda/{function-name}`
- **API Gateway Logs**: `/aws/apigateway/{api-name}`
- **Retention**: Configurable (default: 14 days)

### Cost Monitoring

```hcl
# Enable budget alerts
enable_budget_alerts = true
budget_limit        = 100  # USD per month
budget_alert_email  = "alerts@yourcompany.com"
```

## Customization Examples

### Multi-Environment Deployment

```bash
# Development environment
terraform workspace new development
terraform apply -var-file="environments/dev.tfvars"

# Production environment
terraform workspace new production
terraform apply -var-file="environments/prod.tfvars"
```

### Custom Memory Strategies

```hcl
# Enhanced memory configuration
enable_memory_summarization = true
enable_semantic_memory      = true
enable_user_preferences     = true
enable_custom_extraction    = true

custom_extraction_prompt = "Extract customer sentiment, technical issues, product preferences, and escalation indicators from support conversations."
```

### Performance Tuning

```hcl
# High-performance configuration
lambda_memory_size          = 1024
lambda_timeout             = 60
lambda_reserved_concurrency = 100

# DynamoDB auto-scaling (requires additional resources)
dynamodb_billing_mode = "PAY_PER_REQUEST"

# API Gateway optimization
enable_api_caching     = true
api_cache_cluster_size = "1.6"
```

## Cost Optimization

### Estimated Monthly Costs

| Service | Usage Pattern | Estimated Cost |
|---------|---------------|----------------|
| **API Gateway** | 1M requests | ~$3.50 |
| **Lambda** | 1M invocations, 512MB | ~$8.50 |
| **DynamoDB** | 5 RCU/WCU | ~$3.00 |
| **Bedrock AgentCore** | Memory operations | ~$5-15 |
| **Bedrock Models** | Claude-3-Haiku | ~$10-30 |
| **CloudWatch** | Logs and metrics | ~$2.00 |
| **Total** | Moderate usage | **$30-60/month** |

### Cost Reduction Strategies

1. **Right-size Resources**: Start with minimal capacity and scale based on usage
2. **Use PAY_PER_REQUEST**: For DynamoDB with unpredictable traffic
3. **Optimize Lambda**: Reduce memory size and timeout for simple operations
4. **Model Selection**: Use cost-effective Bedrock models for basic queries
5. **Log Retention**: Reduce CloudWatch log retention periods

## Troubleshooting

### Common Issues

#### Bedrock AgentCore Access
```bash
# Check if AgentCore is available in your region
aws bedrock-agentcore-control list-memories --region us-east-1

# Error: Service not available
# Solution: Contact AWS Support to enable preview access
```

#### Lambda Function Errors
```bash
# Check Lambda logs
aws logs tail /aws/lambda/support-agent-{suffix} --follow

# Common issues:
# - Missing environment variables
# - Insufficient IAM permissions
# - Bedrock model not available in region
```

#### API Gateway 403 Errors
```bash
# Check IAM policies and resource permissions
# Verify API Gateway has permission to invoke Lambda
aws lambda get-policy --function-name support-agent-{suffix}
```

### Debug Mode

Enable detailed logging:

```hcl
# In terraform.tfvars
lambda_log_retention_days = 7
api_log_retention_days   = 7

# Set Lambda environment variables for debugging
# (modify lambda_function.py.tpl)
```

## Cleanup

### Destroy Infrastructure

```bash
# Remove all resources
terraform destroy

# Remove Terraform state (if using local state)
rm -rf .terraform
rm terraform.tfstate*
```

### Selective Cleanup

```bash
# Remove specific resources
terraform destroy -target=aws_dynamodb_table_item.sample_customer_1
terraform destroy -target=aws_dynamodb_table_item.sample_customer_2
```

## Advanced Configuration

### VPC Integration

```hcl
# Deploy in private subnets
enable_vpc_endpoints = true
vpc_id              = "vpc-xxxxxxxxx"
subnet_ids          = ["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]
```

### Multi-Region Setup

```hcl
# Configure provider aliases for multi-region
provider "aws" {
  alias  = "primary"
  region = "us-east-1"
}

provider "aws" {
  alias  = "backup"
  region = "us-west-2"
}
```

### CI/CD Integration

```yaml
# .github/workflows/terraform.yml
name: Deploy Customer Support Agent
on:
  push:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Init
        run: terraform init
      - name: Terraform Plan
        run: terraform plan
      - name: Terraform Apply
        run: terraform apply -auto-approve
```

## Support and Contributing

### Getting Help

1. **Documentation**: [AWS Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock-agentcore/)
2. **Issues**: Create issues in the repository for bugs or feature requests
3. **AWS Support**: Contact AWS Support for service-specific issues

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This infrastructure code is provided under the same license as the parent repository. See LICENSE file for details.