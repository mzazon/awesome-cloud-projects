# Terraform Infrastructure for Simple Timezone Converter

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless timezone converter API using AWS Lambda and API Gateway.

## Architecture Overview

The infrastructure creates:

- **AWS Lambda Function**: Python 3.12 function that handles timezone conversion using built-in `zoneinfo` module
- **API Gateway REST API**: RESTful endpoint that accepts POST requests with timezone conversion parameters
- **IAM Roles and Policies**: Least-privilege execution role for Lambda with CloudWatch Logs permissions
- **CloudWatch Log Groups**: Centralized logging for Lambda function and optionally API Gateway
- **Lambda Permissions**: Resource-based policy allowing API Gateway to invoke the Lambda function

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** version 1.5 or later
3. **AWS Account** with permissions to create:
   - Lambda functions
   - API Gateway REST APIs
   - IAM roles and policies
   - CloudWatch Log Groups
4. **AWS Region** configured (via `AWS_DEFAULT_REGION` environment variable or AWS CLI config)

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review and Customize Variables

Create a `terraform.tfvars` file to customize the deployment:

```hcl
# Basic configuration
environment    = "dev"
project_name   = "timezone-converter"
cost_center    = "engineering"

# Lambda configuration
lambda_runtime     = "python3.12"
lambda_timeout     = 30
lambda_memory_size = 128

# API Gateway configuration
api_gateway_stage_name = "prod"
api_gateway_endpoint_type = "REGIONAL"

# Monitoring configuration
log_retention_in_days = 14
enable_xray_tracing = false
enable_detailed_cloudwatch_metrics = false

# Security configuration
enable_cors = true
cors_allow_origins = ["*"]
```

### 3. Plan the Deployment

```bash
terraform plan
```

### 4. Deploy the Infrastructure

```bash
terraform apply
```

### 5. Test the API

After successful deployment, use the output `api_endpoint_url` to test:

```bash
# Test timezone conversion
curl -X POST https://your-api-id.execute-api.region.amazonaws.com/prod/convert \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2025-07-12T15:30:00",
    "from_timezone": "UTC",
    "to_timezone": "America/New_York"
  }'
```

## Configuration Variables

### Required Variables

No variables are strictly required as all have default values, but you may want to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | `"dev"` | Environment name (dev, staging, prod) |
| `project_name` | `"timezone-converter"` | Project name for resource naming |

### Lambda Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `lambda_runtime` | `"python3.12"` | Python runtime for Lambda function |
| `lambda_timeout` | `30` | Function timeout in seconds (1-900) |
| `lambda_memory_size` | `128` | Memory allocation in MB (128-10240) |
| `lambda_description` | `"Simple timezone converter API function"` | Function description |

### API Gateway Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `api_gateway_name` | `"timezone-converter-api"` | API Gateway name |
| `api_gateway_stage_name` | `"prod"` | Deployment stage name |
| `api_gateway_endpoint_type` | `"REGIONAL"` | Endpoint type (REGIONAL/EDGE/PRIVATE) |
| `api_throttle_rate_limit` | `100` | Requests per second limit |
| `api_throttle_burst_limit` | `200` | Burst request limit |

### Monitoring and Logging

| Variable | Default | Description |
|----------|---------|-------------|
| `log_retention_in_days` | `14` | CloudWatch log retention period |
| `enable_xray_tracing` | `false` | Enable AWS X-Ray tracing |
| `enable_detailed_cloudwatch_metrics` | `false` | Enable detailed API Gateway metrics |

### Security Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_cors` | `true` | Enable CORS headers |
| `cors_allow_origins` | `["*"]` | Allowed origins for CORS |
| `cors_allow_methods` | `["GET", "POST", "OPTIONS"]` | Allowed HTTP methods |

### Resource Naming

| Variable | Default | Description |
|----------|---------|-------------|
| `resource_suffix` | `""` | Custom suffix for resources (auto-generated if empty) |
| `cost_center` | `"engineering"` | Cost center tag for billing |

## Outputs

After deployment, Terraform provides these useful outputs:

### API Information
- `api_endpoint_url`: Complete URL for the timezone converter endpoint
- `api_base_url`: Base URL of the API Gateway
- `api_gateway_id`: API Gateway REST API ID
- `api_gateway_stage_name`: Deployment stage name

### Lambda Information
- `lambda_function_name`: Name of the Lambda function
- `lambda_function_arn`: ARN of the Lambda function
- `lambda_function_invoke_arn`: Invoke ARN for the function

### Testing Commands
- `curl_test_command`: Ready-to-use curl command for testing
- `lambda_test_command`: AWS CLI command to test Lambda directly

### Cost Information
- `estimated_monthly_cost`: Approximate monthly cost breakdown

## API Usage

### Endpoint

```
POST https://your-api-id.execute-api.region.amazonaws.com/prod/convert
```

### Request Format

```json
{
  "timestamp": "2025-07-12T15:30:00",
  "from_timezone": "UTC",
  "to_timezone": "America/New_York"
}
```

### Response Format

```json
{
  "original_timestamp": "2025-07-12T15:30:00",
  "original_timezone": "UTC",
  "converted_timestamp": "2025-07-12T11:30:00-04:00",
  "target_timezone": "America/New_York",
  "timezone_offset": "-0400",
  "timezone_name": "EDT"
}
```

### Supported Timezone Formats

- **IANA Timezone Database**: `America/New_York`, `Europe/London`, `Asia/Tokyo`
- **UTC**: `UTC` or `GMT`
- **Regional**: `US/Eastern`, `US/Pacific`, `Europe/Paris`

### Error Responses

The API returns appropriate HTTP status codes and error messages:

- `400 Bad Request`: Invalid timestamp format or timezone
- `500 Internal Server Error`: Unexpected server error

## Security Considerations

### IAM Permissions

The Lambda function uses least-privilege permissions:
- Basic execution role for Lambda
- CloudWatch Logs write permissions
- Optional X-Ray tracing permissions

### API Gateway Security

- CORS is configurable and enabled by default for web browser compatibility
- No authentication is configured by default (suitable for development)
- Throttling limits prevent abuse

### Production Recommendations

For production deployments:

1. **Enable API Authentication**:
   ```hcl
   # Add to terraform.tfvars for API key authentication
   # You'll need to create additional resources for API keys
   ```

2. **Restrict CORS Origins**:
   ```hcl
   cors_allow_origins = ["https://yourdomain.com"]
   ```

3. **Enable Detailed Monitoring**:
   ```hcl
   enable_detailed_cloudwatch_metrics = true
   enable_xray_tracing = true
   ```

4. **Increase Log Retention**:
   ```hcl
   log_retention_in_days = 90
   ```

## Cost Optimization

### AWS Free Tier Benefits

New AWS accounts receive:
- **Lambda**: 1M requests and 400,000 GB-seconds per month
- **API Gateway**: 1M API calls per month (first 12 months)
- **CloudWatch Logs**: 5GB ingestion and storage

### Estimated Costs (After Free Tier)

Based on 1 million requests per month:
- **Lambda**: ~$0.20 (requests) + ~$0.17 (compute)
- **API Gateway**: ~$3.50
- **CloudWatch Logs**: ~$0.50 (1GB logs)
- **Total**: ~$4.37/month

### Optimization Tips

1. **Right-size Lambda memory**: Monitor execution duration to optimize memory allocation
2. **Use provisioned concurrency sparingly**: Only for consistent low-latency requirements
3. **Monitor API Gateway caching**: Can reduce Lambda invocations significantly
4. **Set appropriate log retention**: Balance observability with storage costs

## Monitoring and Observability

### CloudWatch Metrics

**Lambda Metrics:**
- Duration: Function execution time
- Errors: Function errors and failures
- Throttles: Concurrency limit exceeded
- Invocations: Total function invocations

**API Gateway Metrics:**
- Count: Number of API calls
- Latency: Response time including Lambda execution
- 4XXError: Client-side errors
- 5XXError: Server-side errors

### CloudWatch Logs

**Lambda Logs:**
- Function execution logs
- Application-level logging
- Error stack traces
- Custom log messages

**API Gateway Logs (if enabled):**
- Request/response information
- Authentication details
- Performance metrics

### X-Ray Tracing (Optional)

When enabled, provides:
- End-to-end request tracing
- Performance bottleneck identification
- Service map visualization
- Error root cause analysis

## Troubleshooting

### Common Issues

1. **API Gateway 502 Bad Gateway**:
   - Check Lambda function logs in CloudWatch
   - Verify Lambda function permissions
   - Ensure function returns properly formatted response

2. **Lambda Timeout Errors**:
   - Increase `lambda_timeout` variable
   - Optimize function code performance
   - Check for external service dependencies

3. **CORS Errors in Browser**:
   - Verify `enable_cors = true`
   - Check `cors_allow_origins` includes your domain
   - Ensure OPTIONS method is working

4. **Permission Denied Errors**:
   - Verify IAM role has necessary permissions
   - Check Lambda resource-based policy
   - Ensure API Gateway has invoke permissions

### Debugging Steps

1. **Check Terraform State**:
   ```bash
   terraform show
   terraform state list
   ```

2. **Verify AWS Resources**:
   ```bash
   aws lambda get-function --function-name <function-name>
   aws apigateway get-rest-apis
   ```

3. **Test Lambda Directly**:
   ```bash
   aws lambda invoke \
     --function-name <function-name> \
     --payload '{"timestamp":"2025-07-12T15:30:00","to_timezone":"America/New_York"}' \
     response.json
   ```

4. **Check CloudWatch Logs**:
   ```bash
   aws logs tail /aws/lambda/<function-name> --follow
   ```

## Cleanup

To remove all resources created by this Terraform configuration:

```bash
terraform destroy
```

This will:
- Delete the Lambda function
- Remove the API Gateway and all its resources
- Delete IAM roles and policies
- Remove CloudWatch log groups
- Clean up all associated resources

**Note**: This action cannot be undone. Ensure you have backups of any important data or configurations.

## Advanced Configuration

### Custom Domain Names

To use a custom domain with your API:

1. **Register Domain in Route 53** or use external DNS
2. **Request SSL Certificate** via AWS Certificate Manager
3. **Add Custom Domain Configuration**:
   ```hcl
   # Add to main.tf
   resource "aws_api_gateway_domain_name" "custom_domain" {
     domain_name     = "api.yourdomain.com"
     certificate_arn = aws_acm_certificate.cert.arn
   }
   ```

### API Key Authentication

To add API key authentication:

```hcl
# Add API key resource
resource "aws_api_gateway_api_key" "api_key" {
  name = "${local.name_prefix}-api-key"
}

# Modify method to require API key
resource "aws_api_gateway_method" "convert_post" {
  # ... existing configuration ...
  api_key_required = true
}
```

### Environment-Specific Configurations

Use Terraform workspaces for multiple environments:

```bash
# Create development workspace
terraform workspace new dev
terraform apply -var="environment=dev"

# Create production workspace  
terraform workspace new prod
terraform apply -var="environment=prod"
```

## Support and Contributing

For issues with this infrastructure code:

1. Check the [AWS Lambda documentation](https://docs.aws.amazon.com/lambda/)
2. Review [API Gateway documentation](https://docs.aws.amazon.com/apigateway/)
3. Consult [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For recipe-specific questions, refer to the original recipe documentation in the parent directory.