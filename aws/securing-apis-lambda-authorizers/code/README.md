# Infrastructure as Code for Securing APIs with Lambda Authorizers and API Gateway

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Securing APIs with Lambda Authorizers and API Gateway".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for:
  - API Gateway (create APIs, authorizers, methods)
  - Lambda (create functions, manage permissions)
  - IAM (create roles, attach policies)
  - CloudWatch (create log groups)
- For CDK implementations:
  - Node.js (for TypeScript)
  - Python 3.8+ (for Python)
- For Terraform:
  - Terraform CLI v1.0+
- Estimated cost: $2-8 for testing resources

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name serverless-api-patterns \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ApiName,ParameterValue=my-secure-api
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npm run build
cdk bootstrap  # Only needed once per account/region
cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
cdk bootstrap  # Only needed once per account/region
cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply -auto-approve
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

The infrastructure creates:

- **API Gateway REST API** with multiple endpoints
- **Lambda Authorizers**:
  - Token-based authorizer for Bearer token validation
  - Request-based authorizer for complex authentication logic
- **Business Logic Functions**:
  - Protected API function requiring authorization
  - Public API function without authorization requirements
- **IAM Roles** with least-privilege permissions
- **CloudWatch Log Groups** for monitoring and debugging

## Endpoint Structure

| Endpoint | Authorization | Description |
|----------|--------------|-------------|
| `/public` | None | Public API without authentication |
| `/protected` | Token Authorizer | Requires Bearer token authentication |
| `/protected/admin` | Request Authorizer | Requires API key or custom header |

## Testing the Deployment

After deployment, test the API endpoints:

```bash
# Get API URL from outputs
API_URL=$(aws cloudformation describe-stacks \
    --stack-name serverless-api-patterns \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
    --output text)

# Test public endpoint
curl "$API_URL/public"

# Test protected endpoint with valid token
curl -H "Authorization: Bearer user-token" "$API_URL/protected"

# Test admin endpoint with API key
curl "$API_URL/protected/admin?api_key=secret-api-key-123"

# Test admin endpoint with custom header
curl -H "X-Custom-Auth: custom-auth-value" "$API_URL/protected/admin"
```

## Authentication Methods

### Token Authorizer
- Validates Bearer tokens in Authorization header
- Supports tokens: `user-token`, `admin-token`
- Cached for 5 minutes for performance

### Request Authorizer
- Validates API keys in query parameters: `?api_key=secret-api-key-123`
- Validates custom headers: `X-Custom-Auth: custom-auth-value`
- Supports IP-based authentication for internal networks
- Cached for 5 minutes for performance

## Customization

### Variables/Parameters

Each implementation supports customization through variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `api_name` | Name for the API Gateway | `secure-api` | No |
| `stage_name` | Deployment stage name | `prod` | No |
| `cache_ttl` | Authorizer cache TTL (seconds) | `300` | No |
| `log_retention_days` | CloudWatch log retention | `14` | No |

### CloudFormation Parameters
```bash
aws cloudformation create-stack \
    --stack-name serverless-api-patterns \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ApiName,ParameterValue=my-custom-api \
        ParameterKey=StageName,ParameterValue=dev \
        ParameterKey=CacheTTL,ParameterValue=600
```

### Terraform Variables
Create a `terraform.tfvars` file:
```hcl
api_name = "my-custom-api"
stage_name = "dev"
cache_ttl = 600
log_retention_days = 7
```

### CDK Context
Pass context values during deployment:
```bash
cdk deploy --context api_name=my-custom-api --context stage_name=dev
```

## Monitoring and Observability

The infrastructure includes:

- **CloudWatch Log Groups** for all Lambda functions
- **API Gateway Access Logs** for request monitoring
- **X-Ray Tracing** (optional) for distributed tracing
- **CloudWatch Metrics** for API performance monitoring

### Viewing Logs
```bash
# View authorizer logs
aws logs tail /aws/lambda/token-authorizer-* --follow

# View API access logs
aws logs tail API-Gateway-Execution-Logs_* --follow
```

## Security Considerations

- **IAM Roles**: Functions use least-privilege execution roles
- **Authorizer Caching**: Balances performance with security freshness
- **CORS Configuration**: Configured for web application integration
- **API Throttling**: Built-in API Gateway throttling protection
- **Input Validation**: Authorizers validate all input parameters

> **Warning**: The demo tokens and API keys are for testing only. In production, implement proper JWT validation with signature verification and integrate with real identity providers.

## Troubleshooting

### Common Issues

1. **403 Forbidden**: Check authorizer configuration and token format
2. **500 Internal Server Error**: Check Lambda function logs
3. **Missing Permissions**: Verify IAM roles and Lambda permissions

### Debug Commands
```bash
# Check API Gateway configuration
aws apigateway get-authorizers --rest-api-id <API_ID>

# Test authorizer directly
aws lambda invoke \
    --function-name <AUTHORIZER_FUNCTION> \
    --payload file://test-event.json \
    response.json

# Check function permissions
aws lambda get-policy --function-name <FUNCTION_NAME>
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name serverless-api-patterns
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Cost Optimization

- **Authorizer Caching**: Reduces Lambda invocations for repeated requests
- **CloudWatch Log Retention**: Set appropriate retention periods to control costs
- **API Gateway Caching**: Consider enabling response caching for frequently accessed endpoints
- **Reserved Concurrency**: Set Lambda reserved concurrency to control costs

## Production Considerations

1. **JWT Validation**: Implement proper JWT libraries (PyJWT, jose-python)
2. **External Identity Providers**: Integrate with OAuth/OIDC providers
3. **Database Integration**: Store user permissions in DynamoDB
4. **Rate Limiting**: Implement per-user rate limiting
5. **Monitoring**: Set up comprehensive CloudWatch alarms
6. **Security**: Enable AWS WAF for additional protection

## Extension Ideas

- Add DynamoDB tables for user management
- Implement rate limiting with DynamoDB or ElastiCache
- Add Step Functions for complex authorization workflows
- Integrate with Amazon Cognito for user management
- Add AWS WAF for additional security layers

## Support

For issues with this infrastructure code, refer to:
- [Original recipe documentation](../serverless-api-patterns-lambda-authorizers-api-gateway.md)
- [AWS API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)