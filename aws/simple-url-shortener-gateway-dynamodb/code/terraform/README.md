# Infrastructure as Code for Simple URL Shortener with API Gateway and DynamoDB

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless URL shortener service on AWS using API Gateway, Lambda functions, and DynamoDB.

## Architecture Overview

The solution creates:
- **DynamoDB Table**: Stores URL mappings with on-demand billing
- **Lambda Functions**: Two functions for URL creation and redirection
- **API Gateway**: REST API with CORS support and throttling
- **IAM Roles**: Least-privilege permissions for Lambda execution
- **CloudWatch Logs**: Centralized logging with configurable retention

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - DynamoDB (CreateTable, DeleteTable)
  - Lambda (CreateFunction, DeleteFunction)
  - API Gateway (CreateRestApi, DeleteRestApi)
  - IAM (CreateRole, AttachRolePolicy)
  - CloudWatch Logs (CreateLogGroup)

## Quick Start

### 1. Initialize Terraform

```bash
# Navigate to the terraform directory
cd aws/simple-url-shortener-gateway-dynamodb/code/terraform/

# Initialize Terraform (downloads providers)
terraform init
```

### 2. Review and Customize Configuration

```bash
# Review the default configuration
terraform plan

# Optionally create a terraform.tfvars file for customization
cat > terraform.tfvars << EOF
project_name = "my-url-shortener"
environment  = "dev"
aws_region   = "us-east-1"

# Optional: Customize Lambda settings
lambda_timeout     = 15
lambda_memory_size = 256

# Optional: Enable enhanced monitoring
enable_xray_tracing      = true
enable_api_access_logging = true
log_retention_in_days    = 30

# Optional: API Gateway throttling
api_throttle_rate_limit  = 500
api_throttle_burst_limit = 1000
EOF
```

### 3. Deploy Infrastructure

```bash
# Plan the deployment
terraform plan -out=tfplan

# Apply the configuration
terraform apply tfplan
```

### 4. Test the Deployment

After deployment, Terraform will output the API Gateway URL. Test the service:

```bash
# Get the API URL from Terraform output
API_URL=$(terraform output -raw api_gateway_url)

# Create a short URL
curl -X POST $API_URL/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://aws.amazon.com/lambda/"}'

# Use the returned short code to test redirection
# curl -I $API_URL/{shortCode}
```

## Configuration Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Name prefix for all resources | `url-shortener` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `aws_region` | AWS region for deployment | Current provider region | No |
| `dynamodb_billing_mode` | DynamoDB billing mode | `PAY_PER_REQUEST` | No |
| `lambda_timeout` | Lambda function timeout (seconds) | `10` | No |
| `lambda_memory_size` | Lambda memory allocation (MB) | `128` | No |
| `api_gateway_stage_name` | API Gateway stage name | `prod` | No |
| `short_code_length` | Length of generated short codes | `6` | No |
| `enable_xray_tracing` | Enable AWS X-Ray tracing | `false` | No |
| `log_retention_in_days` | CloudWatch log retention | `14` | No |
| `enable_api_access_logging` | Enable API Gateway access logs | `true` | No |

## Outputs

After deployment, Terraform provides these outputs:

- `api_gateway_url`: Base URL for the API
- `create_short_url_endpoint`: Full endpoint for creating short URLs
- `dynamodb_table_name`: Name of the DynamoDB table
- `lambda_create_function_name`: Name of the URL creation function
- `lambda_redirect_function_name`: Name of the redirect function
- `usage_instructions`: Complete usage guide
- `cost_optimization_notes`: Cost estimates and optimization tips

## Usage Examples

### Creating Short URLs

```bash
# Basic URL shortening
curl -X POST https://your-api-id.execute-api.region.amazonaws.com/prod/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com/very-long-url"}'

# Response:
# {
#   "shortCode": "aB3xY9",
#   "shortUrl": "https://your-api-id.execute-api.region.amazonaws.com/prod/aB3xY9",
#   "originalUrl": "https://example.com/very-long-url",
#   "message": "Short URL created successfully"
# }
```

### Using Short URLs

```bash
# Access the short URL directly
curl -I https://your-api-id.execute-api.region.amazonaws.com/prod/aB3xY9

# Returns HTTP 302 redirect to original URL
```

### Error Handling

The service provides proper error responses:

```bash
# Missing URL
curl -X POST $API_URL/shorten -H "Content-Type: application/json" -d '{}'
# Returns: {"error": "URL is required", "statusCode": 400}

# Invalid URL format
curl -X POST $API_URL/shorten -H "Content-Type: application/json" -d '{"url": "not-a-url"}'
# Returns: {"error": "Invalid URL format", "statusCode": 400}

# Non-existent short code
curl -I $API_URL/invalid
# Returns: HTML 404 error page
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Each component creates dedicated log groups:

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/url-shortener"

# View API Gateway access logs (if enabled)
aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway"
```

### DynamoDB Monitoring

```bash
# Check table status
aws dynamodb describe-table --table-name $(terraform output -raw dynamodb_table_name)

# View table metrics in CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=$(terraform output -raw dynamodb_table_name) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Lambda Function Monitoring

```bash
# Check function configuration
aws lambda get-function --function-name $(terraform output -raw lambda_create_function_name)

# View recent invocations
aws logs filter-log-events \
  --log-group-name $(terraform output -raw cloudwatch_log_group_create_function) \
  --start-time $(date -d '1 hour ago' +%s)000
```

## Cost Optimization

### Estimated Monthly Costs

For 1,000 URL creations and 10,000 redirects per month:

- **DynamoDB**: ~$0.25 (PAY_PER_REQUEST mode)
- **Lambda**: ~$0.02 (likely within free tier)
- **API Gateway**: ~$3.50 (REST API requests)
- **CloudWatch Logs**: ~$0.50 (with 14-day retention)
- **Total**: ~$4.27/month

### Optimization Tips

1. **DynamoDB**: Use `PAY_PER_REQUEST` for variable workloads
2. **Lambda**: Keep memory allocation low (128MB) for this use case
3. **Logs**: Adjust retention period based on compliance needs
4. **API Gateway**: Consider usage plans and caching for high-traffic scenarios

## Security Considerations

### Current Security Features

- **IAM**: Least-privilege roles for Lambda functions
- **DynamoDB**: Server-side encryption with AWS managed keys
- **CORS**: Configured for web browser access
- **Input Validation**: URL format validation and sanitization
- **Logging**: Comprehensive audit trail in CloudWatch

### Production Hardening

For production deployments, consider adding:

```hcl
# Example additional security configurations

# API Gateway with API Keys
resource "aws_api_gateway_api_key" "shortener_key" {
  name = "${local.api_name}-key"
}

# Usage plan with rate limiting
resource "aws_api_gateway_usage_plan" "shortener_plan" {
  name = "${local.api_name}-usage-plan"
  
  api_stages {
    api_id = aws_api_gateway_rest_api.url_shortener_api.id
    stage  = aws_api_gateway_stage.url_shortener_stage.stage_name
  }
  
  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }
}

# Custom domain with SSL
resource "aws_api_gateway_domain_name" "shortener_domain" {
  domain_name     = "short.yourdomain.com"
  certificate_arn = aws_acm_certificate.cert.arn
}
```

## Cleanup

To remove all resources:

```bash
# Destroy all infrastructure
terraform destroy

# Optionally remove Terraform state
rm terraform.tfstate*
rm -rf .terraform/
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Verify AWS credentials
   aws sts get-caller-identity
   
   # Check required permissions
   aws iam simulate-principal-policy \
     --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
     --action-names dynamodb:CreateTable lambda:CreateFunction
   ```

2. **Lambda Deployment Failures**
   ```bash
   # Check function logs
   aws logs filter-log-events \
     --log-group-name /aws/lambda/function-name \
     --start-time $(date -d '1 hour ago' +%s)000
   ```

3. **API Gateway 502 Errors**
   ```bash
   # Verify Lambda permissions
   aws lambda get-policy --function-name function-name
   
   # Check integration configuration
   aws apigateway get-integration \
     --rest-api-id api-id \
     --resource-id resource-id \
     --http-method GET
   ```

### Support Resources

- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/)
- [DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Extension Ideas

Consider these enhancements for advanced use cases:

1. **Custom Domain**: Add Route 53 and ACM for branded URLs
2. **Analytics**: Track click counts and referrer information
3. **User Management**: Add Cognito for user-specific short URLs
4. **Expiration**: Implement TTL for temporary links
5. **QR Codes**: Generate QR codes for mobile sharing
6. **Bulk Operations**: Support batch URL creation
7. **Admin Dashboard**: Web interface for URL management

## Contributing

When modifying this infrastructure:

1. Always run `terraform plan` before applying changes
2. Update variable descriptions and validation rules
3. Test with different variable combinations
4. Update this README with new features or changes
5. Consider backward compatibility for existing deployments