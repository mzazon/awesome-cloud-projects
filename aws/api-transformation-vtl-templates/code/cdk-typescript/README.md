# CDK TypeScript - Request/Response Transformation with VTL Templates

This directory contains a comprehensive CDK TypeScript implementation for the **Request/Response Transformation with VTL Templates and Custom Models** recipe. The application demonstrates advanced API Gateway transformation capabilities using Velocity Template Language (VTL) mapping templates, custom JSON Schema models, and comprehensive error handling.

## Architecture Overview

The CDK application creates the following AWS resources:

- **API Gateway REST API** - Main transformation endpoint with custom models
- **Lambda Function** - Data processor with transformation support
- **S3 Bucket** - Data storage for processed requests
- **CloudWatch Log Group** - API Gateway request/response logging
- **IAM Roles and Policies** - Secure access between services
- **Custom Gateway Responses** - Standardized error handling

## Key Features

### 🔄 Request/Response Transformation
- **VTL Mapping Templates** - Declarative data transformation without custom code
- **Field Renaming** - Transform client-friendly names to backend formats
- **Data Enrichment** - Add request context, metadata, and processing flags
- **Conditional Logic** - Handle optional fields and complex transformations

### 📋 Request Validation
- **JSON Schema Models** - Comprehensive input validation
- **Custom Error Responses** - User-friendly validation error messages
- **Multiple Response Formats** - Standardized success and error structures

### 🛠️ Advanced Features
- **Query Parameter Transformation** - Convert URL parameters to structured objects
- **Multiple Integration Types** - Lambda and S3 integration examples
- **CloudWatch Logging** - Detailed request/response tracing
- **CORS Support** - Cross-origin resource sharing configuration
- **Rate Limiting** - Built-in throttling and quota management

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured
2. **Node.js** version 18.0.0 or higher
3. **AWS CDK CLI** installed (`npm install -g aws-cdk`)
4. **TypeScript** installed (`npm install -g typescript`)
5. **Appropriate AWS permissions** for creating:
   - API Gateway resources
   - Lambda functions
   - S3 buckets
   - IAM roles and policies
   - CloudWatch log groups

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure AWS Environment

```bash
# Set your AWS region (optional - defaults to AWS CLI default)
export AWS_DEFAULT_REGION=us-east-1

# Verify AWS credentials
aws sts get-caller-identity
```

### 3. Bootstrap CDK (First Time Only)

```bash
cdk bootstrap
```

### 4. Deploy the Stack

```bash
# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# Deploy with approval prompts disabled
cdk deploy --require-approval never
```

### 5. Test the API

After deployment, the API Gateway endpoint URL will be displayed in the output. You can test the transformation capabilities:

```bash
# Test POST with valid data
curl -X POST "https://YOUR-API-ID.execute-api.us-east-1.amazonaws.com/staging/users" \
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
  }'

# Test GET with query parameters
curl -G "https://YOUR-API-ID.execute-api.us-east-1.amazonaws.com/staging/users" \
  -d "limit=5" \
  -d "offset=10" \
  -d "filter=email:example.com" \
  -d "sort=-createdAt"

# Test validation with invalid data
curl -X POST "https://YOUR-API-ID.execute-api.us-east-1.amazonaws.com/staging/users" \
  -H "Content-Type: application/json" \
  -d '{
    "firstName": "Jane",
    "lastName": "Smith",
    "email": "invalid-email"
  }'
```

## Project Structure

```
cdk-typescript/
├── app.ts                 # Main CDK application with stack definition
├── package.json          # Dependencies and scripts
├── tsconfig.json         # TypeScript configuration
├── cdk.json              # CDK configuration
├── README.md             # This documentation
└── cdk.out/              # Generated CloudFormation templates (after synth)
```

## Available Scripts

```bash
# Build TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm run test

# CDK commands
npm run cdk ls          # List stacks
npm run cdk synth       # Synthesize CloudFormation
npm run cdk deploy      # Deploy stack
npm run cdk destroy     # Destroy stack
npm run cdk diff        # Show differences
npm run bootstrap       # Bootstrap CDK
```

## Configuration Options

### Environment Variables

You can customize the deployment using environment variables:

```bash
# Custom AWS region
export AWS_DEFAULT_REGION=eu-west-1

# Custom account ID (optional)
export CDK_DEFAULT_ACCOUNT=123456789012

# Custom region (optional)
export CDK_DEFAULT_REGION=eu-west-1
```

### Stack Tags

The stack is automatically tagged with:
- `Project: RequestResponseTransformation`
- `Environment: Demo`
- `Purpose: API Gateway VTL Templates`

## Resource Details

### API Gateway Configuration

- **Endpoint Type**: Regional
- **Stage**: `staging`
- **Logging**: INFO level with data trace enabled
- **Throttling**: 100 requests/second, 200 burst
- **CORS**: Enabled for all origins and methods

### Lambda Function

- **Runtime**: Python 3.9
- **Memory**: 256 MB
- **Timeout**: 30 seconds
- **Environment Variables**:
  - `BUCKET_NAME`: S3 bucket for data storage
  - `LOG_LEVEL`: Logging level (INFO)

### S3 Bucket

- **Encryption**: S3 managed encryption
- **Versioning**: Disabled
- **Public Access**: Blocked
- **SSL**: Enforced

### VTL Templates

The application includes sophisticated VTL mapping templates:

#### Request Transformation
- Field renaming (`firstName` → `first_name`)
- Data enrichment (request context, metadata)
- Conditional processing (optional fields)
- Type conversion and validation

#### Response Transformation
- Standardized response format
- HATEOAS links for RESTful navigation
- Metadata injection
- Error handling and formatting

## Monitoring and Logging

### CloudWatch Logs

API Gateway logs are available in:
```
/aws/apigateway/{API-ID}
```

### CloudWatch Metrics

Monitor these key metrics:
- `4XXError` - Client errors
- `5XXError` - Server errors
- `Count` - Request count
- `Latency` - Response latency

### X-Ray Tracing

Enable X-Ray tracing for detailed request flow analysis:

```bash
# Enable tracing on the API Gateway stage
aws apigateway update-stage \
  --rest-api-id YOUR-API-ID \
  --stage-name staging \
  --patch-operations op=replace,path=/tracingConfig/tracingEnabled,value=true
```

## Customization

### Adding New Endpoints

1. Create a new resource in the `configureApiResources()` method
2. Define custom models for request/response validation
3. Create VTL mapping templates for transformation
4. Configure integration with backend services

### Modifying Transformations

1. Update VTL templates in the method configuration
2. Modify JSON Schema models for validation
3. Test transformations using API Gateway console
4. Deploy changes with `cdk deploy`

### Adding Authentication

```typescript
// Add API key authentication
const apiKey = api.addApiKey('ApiKey');
const plan = api.addUsagePlan('UsagePlan', {
  name: 'Easy',
  throttle: {
    rateLimit: 10,
    burstLimit: 2
  }
});
plan.addApiKey(apiKey);
```

## Troubleshooting

### Common Issues

1. **VTL Template Errors**
   - Check CloudWatch logs for template compilation errors
   - Validate JSON syntax in templates
   - Test templates in API Gateway console

2. **Validation Errors**
   - Verify JSON Schema model definitions
   - Check request body format
   - Review validation error messages

3. **Lambda Integration Issues**
   - Verify IAM permissions
   - Check Lambda function logs
   - Validate integration configuration

### Debug Commands

```bash
# View CloudFormation template
cdk synth

# Compare with deployed stack
cdk diff

# Check stack events
aws cloudformation describe-stack-events --stack-name RequestResponseTransformationStack

# View API Gateway logs
aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway/"
```

## Security Best Practices

### Implemented Security Features

- **IAM Roles**: Least privilege access
- **S3 Bucket**: Public access blocked, SSL enforced
- **API Gateway**: Request validation, rate limiting
- **Lambda**: Isolated execution environment

### Additional Security Recommendations

1. **API Authentication**: Add API keys or AWS Cognito
2. **WAF Integration**: Protect against common attacks
3. **VPC Endpoint**: Private API access
4. **Encryption**: Enable field-level encryption

## Cost Optimization

### Estimated Costs

- **API Gateway**: $3.50 per million requests
- **Lambda**: $0.20 per 1M requests (100ms duration)
- **S3**: $0.023 per GB storage
- **CloudWatch**: $0.50 per GB ingested

### Cost Reduction Tips

1. **Optimize Lambda**: Reduce memory and timeout
2. **S3 Lifecycle**: Implement automatic archiving
3. **CloudWatch**: Set log retention policies
4. **API Caching**: Enable response caching

## Cleanup

To remove all resources and avoid charges:

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
# Type 'y' when prompted

# Verify cleanup
aws cloudformation list-stacks --stack-status-filter DELETE_COMPLETE
```

## Support and Resources

### CDK Documentation
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/)
- [CDK TypeScript Reference](https://docs.aws.amazon.com/cdk/api/v2/typescript/)

### API Gateway Resources
- [VTL Template Reference](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-mapping-template-reference.html)
- [JSON Schema Validation](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-method-request-validation.html)

### Community
- [AWS CDK Examples](https://github.com/aws-samples/aws-cdk-examples)
- [CDK Workshop](https://cdkworkshop.com/)
- [AWS Developer Forums](https://forums.aws.amazon.com/forum.jspa?forumID=142)

---

**Note**: This implementation follows AWS CDK best practices and includes comprehensive error handling, security configurations, and monitoring capabilities. The VTL templates demonstrate advanced transformation patterns suitable for production environments.