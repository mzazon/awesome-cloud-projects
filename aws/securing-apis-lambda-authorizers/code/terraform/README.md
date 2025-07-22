# Serverless API Patterns with Lambda Authorizers - Terraform Implementation

This Terraform configuration deploys a comprehensive serverless API security solution using AWS API Gateway with custom Lambda authorizers, demonstrating both TOKEN and REQUEST authorization patterns.

## Architecture Overview

The infrastructure creates:
- **API Gateway REST API** with multiple endpoints and security patterns
- **Lambda Authorizers** for token-based and request-based authentication
- **Business Logic Functions** for protected and public API endpoints
- **IAM Roles and Policies** following least privilege principles
- **CloudWatch Log Groups** for monitoring and debugging

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for creating API Gateway, Lambda, IAM, and CloudWatch resources
- Basic understanding of serverless architecture and API security

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd aws/serverless-api-patterns-lambda-authorizers-api-gateway/code/terraform/
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your desired configuration
   ```

3. **Initialize and Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Test the API**:
   ```bash
   # Get the API URL from outputs
   terraform output api_gateway_url
   
   # Test public endpoint
   curl -s "$(terraform output -raw api_gateway_url)/public" | jq .
   
   # Test protected endpoint with token
   curl -s -H "Authorization: Bearer user-token" \
        "$(terraform output -raw api_gateway_url)/protected" | jq .
   ```

## Configuration Variables

### Required Variables
- `aws_region`: AWS region for deployment (default: us-east-1)
- `environment`: Environment name (dev/staging/prod)

### Security Variables (Sensitive)
- `valid_tokens`: Map of valid bearer tokens with user attributes
- `valid_api_keys`: List of valid API keys for request authorization
- `custom_auth_values`: List of valid custom authentication header values

### Optional Variables
- `api_name`: Name prefix for API Gateway (default: secure-api)
- `authorizer_cache_ttl`: Cache TTL for authorizers in seconds (default: 300)
- `lambda_timeout`: Lambda function timeout in seconds (default: 30)
- `enable_cloudwatch_logs`: Enable API Gateway logging (default: true)

## API Endpoints

| Endpoint | Method | Authorization | Description |
|----------|---------|---------------|-------------|
| `/public` | GET | None | Public endpoint without authentication |
| `/protected` | GET | Bearer Token | Protected endpoint requiring valid token |
| `/protected/admin` | GET | API Key/Custom Header | Admin endpoint with request-based auth |

## Authentication Methods

### Token-Based Authorization
- **Header**: `Authorization: Bearer <token>`
- **Valid Tokens**: admin-token, user-token (configurable)
- **Cache**: 5-minute TTL for performance optimization
- **Use Case**: Standard JWT/OAuth token validation

### Request-Based Authorization
- **API Key**: `?api_key=secret-api-key-123`
- **Custom Header**: `X-Custom-Auth: custom-auth-value`
- **IP Validation**: Automatic approval for internal networks (10.x, 172.x, 192.168.x)
- **Use Case**: Complex authorization scenarios with multiple validation criteria

## Testing Commands

The Terraform outputs provide ready-to-use curl commands for testing:

```bash
# Get all test commands
terraform output test_commands

# Test public endpoint
curl -s "$(terraform output -raw api_gateway_url)/public"

# Test with valid user token
curl -s -H "Authorization: Bearer user-token" \
     "$(terraform output -raw api_gateway_url)/protected"

# Test with admin token
curl -s -H "Authorization: Bearer admin-token" \
     "$(terraform output -raw api_gateway_url)/protected"

# Test admin endpoint with API key
curl -s "$(terraform output -raw api_gateway_url)/protected/admin?api_key=secret-api-key-123"

# Test admin endpoint with custom header
curl -s -H "X-Custom-Auth: custom-auth-value" \
     "$(terraform output -raw api_gateway_url)/protected/admin"

# Test unauthorized access (should fail)
curl -s "$(terraform output -raw api_gateway_url)/protected"
```

## Monitoring and Debugging

### CloudWatch Log Groups
- `/aws/lambda/token-authorizer-*`: Token authorizer logs
- `/aws/lambda/request-authorizer-*`: Request authorizer logs  
- `/aws/lambda/protected-api-*`: Protected function logs
- `/aws/lambda/public-api-*`: Public function logs
- `API-Gateway-Execution-Logs_*/prod`: API Gateway access logs

### Useful CloudWatch Queries
```bash
# View recent authorizer logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/token-authorizer-*" \
    --start-time $(date -d '1 hour ago' +%s)000

# Monitor API Gateway errors
aws logs filter-log-events \
    --log-group-name "API-Gateway-Execution-Logs_*" \
    --filter-pattern "ERROR"
```

## Security Best Practices

### Production Considerations
1. **Token Validation**: Replace simplified token validation with proper JWT verification
2. **Secrets Management**: Store tokens and API keys in AWS Secrets Manager
3. **Rate Limiting**: Implement per-user rate limiting with DynamoDB
4. **HTTPS Only**: Ensure all API communication uses HTTPS
5. **Audit Logging**: Enable detailed CloudTrail logging for API access

### IAM Security
- Lambda functions use least privilege execution roles
- API Gateway uses dedicated authorizer invocation role
- No hardcoded credentials in function code
- Resource-based policies scope permissions appropriately

## Cost Optimization

### Authorizer Caching
- 5-minute cache TTL reduces Lambda invocations
- Cache key based on identity source (token/headers)
- Balance security freshness with performance

### Expected Costs (10,000 requests/month)
- API Gateway: ~$0.035
- Lambda Invocations: ~$0.002
- CloudWatch Logs: ~$0.50
- **Total**: ~$0.54/month

## Customization Examples

### Adding New Authorization Patterns
```hcl
# Add database-backed authorization
resource "aws_lambda_function" "database_authorizer" {
  # Function that validates against DynamoDB user table
}

# Add SAML/OIDC integration
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  type = "COGNITO_USER_POOLS"
  # Integration with Amazon Cognito
}
```

### Environment-Specific Configuration
```hcl
# Different cache TTL by environment
locals {
  cache_ttl = var.environment == "prod" ? 300 : 60
}
```

## Troubleshooting

### Common Issues

1. **Authorizer Returns 500 Error**
   - Check Lambda function logs for exceptions
   - Verify policy document format in authorizer response
   - Ensure proper IAM permissions for Lambda execution

2. **Caching Issues**
   - Verify identity source configuration matches cache expectations
   - Check if authorizer context is being passed correctly
   - Consider cache TTL settings for your use case

3. **Permission Denied**
   - Verify API Gateway has permission to invoke Lambda functions
   - Check IAM role trust relationships
   - Ensure resource ARNs match in permissions

### Debug Mode
```bash
# Enable Terraform debug logging
export TF_LOG=DEBUG
terraform apply

# View detailed API Gateway logs
aws logs tail "API-Gateway-Execution-Logs_*" --follow
```

## Cleanup

```bash
terraform destroy
```

This will remove all created resources. The command will prompt for confirmation before deletion.

## Advanced Extensions

1. **JWT Integration**: Implement proper JWT token validation with signature verification
2. **Database Integration**: Add DynamoDB for user permissions and API quotas
3. **Multi-Factor Auth**: Implement step-up authentication for sensitive operations
4. **External Identity Providers**: Integrate with OAuth/OIDC providers
5. **Rate Limiting**: Add per-user rate limiting and abuse prevention

## Support and Documentation

- [AWS API Gateway Lambda Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-lambda-authorizer.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Serverless Application Lens](https://docs.aws.amazon.com/wellarchitected/latest/serverless-applications-lens/)

For issues with this Terraform configuration, check the AWS CloudWatch logs and Terraform state for detailed error information.