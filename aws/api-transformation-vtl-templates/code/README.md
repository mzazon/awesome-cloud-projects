# Infrastructure as Code for Request/Response Transformation with VTL Templates and Custom Models

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Transforming API Requests with VTL Templates".

## Overview

This recipe demonstrates sophisticated API Gateway transformation capabilities using Velocity Template Language (VTL) mapping templates, custom JSON Schema models for validation, and comprehensive error handling. The infrastructure creates an API Gateway with advanced request/response transformation, Lambda backend integration, and S3 storage for data operations.

## Architecture Components

- **API Gateway REST API** with custom models and validators
- **Lambda Function** for data processing with transformation support
- **S3 Bucket** for data storage operations
- **IAM Roles** with least privilege permissions
- **CloudWatch Logs** for monitoring and debugging
- **VTL Mapping Templates** for request/response transformation

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - API Gateway (create, update, deploy)
  - Lambda (create, update, invoke permissions)
  - S3 (create buckets, put/get objects)
  - IAM (create roles, attach policies)
  - CloudWatch (create log groups, put log events)
- For CDK implementations: Node.js 18+ or Python 3.9+
- For Terraform: Terraform 1.0+ installed

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name vtl-transformation-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=staging

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name vtl-transformation-stack \
    --query 'Stacks[0].StackStatus'

# Get API endpoint
aws cloudformation describe-stacks \
    --stack-name vtl-transformation-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm install

# Deploy the stack
cdk deploy

# Get outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
cd cdk-python/
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# Get stack outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/
terraform init

# Plan the deployment
terraform plan -var="environment=staging"

# Apply the configuration
terraform apply -var="environment=staging"

# Get outputs
terraform output api_endpoint
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# The script will output the API endpoint URL
```

## Testing the Deployment

After deployment, test the API transformation capabilities:

### Test Request Transformation

```bash
# Replace with your API endpoint
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com/staging"

# Test POST with valid data
curl -X POST "${API_ENDPOINT}/users" \
    -H "Content-Type: application/json" \
    -d '{
        "firstName": "John",
        "lastName": "Doe",
        "email": "john.doe@example.com",
        "phoneNumber": "+1234567890",
        "preferences": {
            "notifications": true,
            "theme": "dark",
            "language": "en"
        }
    }' | jq '.'
```

### Test Validation

```bash
# Test with invalid email
curl -X POST "${API_ENDPOINT}/users" \
    -H "Content-Type: application/json" \
    -d '{
        "firstName": "Jane",
        "lastName": "Smith",
        "email": "invalid-email"
    }' | jq '.'
```

### Test Query Parameter Transformation

```bash
# Test GET with query parameters
curl -G "${API_ENDPOINT}/users" \
    -d "limit=5" \
    -d "offset=10" \
    -d "filter=email:example.com" \
    -d "sort=-createdAt" | jq '.'
```

## Configuration Options

### CloudFormation Parameters

- `Environment`: Deployment environment (default: staging)
- `ApiName`: Custom API name (default: auto-generated)
- `LambdaMemorySize`: Lambda memory allocation (default: 256)
- `LogRetentionDays`: CloudWatch log retention (default: 7)

### CDK Context Variables

Configure in `cdk.json`:

```json
{
  "context": {
    "@aws-cdk/core:enableStackNameDuplicates": true,
    "environment": "staging",
    "api-name": "custom-transformation-api",
    "lambda-memory": 256
  }
}
```

### Terraform Variables

Available in `variables.tf`:

- `environment`: Deployment environment
- `api_name`: Custom API Gateway name
- `lambda_memory_size`: Lambda function memory size
- `log_retention_days`: CloudWatch log retention period

## Architecture Details

### Request Transformation Flow

1. **Client Request** → API Gateway receives JSON request
2. **Model Validation** → JSON Schema validates request structure
3. **VTL Transformation** → Request mapped to backend format
4. **Lambda Processing** → Transformed data processed by Lambda
5. **Response Transformation** → Lambda response transformed to API format
6. **Client Response** → Standardized JSON response returned

### Key Features

- **Advanced VTL Templates**: Complex request/response transformations
- **JSON Schema Validation**: Comprehensive input validation
- **Error Handling**: Custom gateway responses and error templates
- **Multi-Integration Support**: Lambda, S3, and HTTP integrations
- **Monitoring**: CloudWatch logs and metrics integration
- **HATEOAS Support**: Hypermedia links in responses

## Monitoring and Logging

### CloudWatch Logs

Monitor transformation execution:

```bash
# View API Gateway logs
aws logs tail /aws/apigateway/your-api-id --follow

# View Lambda function logs
aws logs tail /aws/lambda/your-function-name --follow
```

### CloudWatch Metrics

Key metrics to monitor:

- API Gateway: `Count`, `Latency`, `4XXError`, `5XXError`
- Lambda: `Invocations`, `Duration`, `Errors`
- Request validation failures and transformation errors

## Troubleshooting

### Common Issues

1. **VTL Template Errors**
   - Check CloudWatch logs for template parsing errors
   - Verify VTL syntax and variable references
   - Test templates using API Gateway test feature

2. **Validation Failures**
   - Verify JSON Schema model definitions
   - Check request payload against model requirements
   - Review validation error messages in responses

3. **Lambda Integration Issues**
   - Verify Lambda function permissions
   - Check IAM role policies
   - Review function logs for processing errors

### Debug Mode

Enable detailed logging by updating stage settings:

```bash
aws apigateway update-stage \
    --rest-api-id YOUR_API_ID \
    --stage-name staging \
    --patch-operations \
        'op=replace,path=/*/*/logging/loglevel,value=INFO' \
        'op=replace,path=/*/*/logging/dataTrace,value=true'
```

## Security Considerations

### IAM Permissions

The infrastructure implements least privilege access:

- Lambda execution role with minimal S3 and CloudWatch permissions
- API Gateway service role for Lambda invocation only
- No public S3 bucket access

### API Security

- Request validation prevents malformed data
- VTL templates sanitize input data
- Error responses don't expose sensitive information
- CloudWatch logs capture security-relevant events

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name vtl-transformation-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name vtl-transformation-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="environment=staging"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization Examples

### Adding New Transformation Templates

1. **Custom Request Mapping**:
   ```vtl
   {
       "custom_field": "$input.path('$.originalField')",
       "computed_value": #if($input.path('$.condition'))true#{else}false#end,
       "timestamp": "$context.requestTimeEpoch"
   }
   ```

2. **Advanced Response Transformation**:
   ```vtl
   {
       "result": {
           "id": "$input.path('$.id')",
           "name": "$util.escapeJavaScript($input.path('$.name'))",
           "links": {
               "self": "https://$context.domainName/$context.stage/resource/$input.path('$.id')"
           }
       }
   }
   ```

### Extending Validation Models

Add custom JSON Schema properties:

```json
{
    "customField": {
        "type": "string",
        "pattern": "^[A-Z]{2,3}$",
        "description": "Two or three uppercase letters"
    },
    "numericRange": {
        "type": "number",
        "minimum": 1,
        "maximum": 100
    }
}
```

## Performance Optimization

### VTL Template Optimization

- Minimize template complexity
- Use conditional logic efficiently
- Cache computed values in variables
- Avoid nested loops in templates

### Lambda Optimization

- Right-size memory allocation
- Use connection pooling for external services
- Implement proper error handling
- Monitor cold start metrics

## Cost Considerations

### Resource Costs

- API Gateway: Per request and data transfer
- Lambda: Per invocation and execution time
- S3: Storage and request costs
- CloudWatch: Log ingestion and storage

### Cost Optimization

- Use API Gateway caching for repeated requests
- Optimize Lambda memory for cost/performance balance
- Set appropriate CloudWatch log retention periods
- Monitor usage patterns and adjust resources accordingly

## Advanced Features

### Multi-Environment Support

The infrastructure supports multiple environments through parameters:

```bash
# Development environment
terraform apply -var="environment=dev"

# Production environment
terraform apply -var="environment=prod"
```

### Custom Domain Integration

Add custom domain support by extending the infrastructure:

```yaml
# CloudFormation example
CustomDomain:
  Type: AWS::ApiGateway::DomainName
  Properties:
    DomainName: !Ref CustomDomainName
    CertificateArn: !Ref SSLCertificateArn
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation
3. Verify IAM permissions and resource limits
4. Check CloudWatch logs for detailed error information
5. Use AWS support resources for service-specific issues

## Contributing

When modifying the infrastructure:

1. Test changes in a development environment
2. Update relevant documentation
3. Follow provider-specific best practices
4. Validate security configurations
5. Update variable definitions and outputs as needed