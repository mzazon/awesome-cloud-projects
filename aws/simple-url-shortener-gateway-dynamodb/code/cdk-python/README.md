# URL Shortener CDK Python Application

This directory contains the AWS CDK Python implementation for the Simple URL Shortener with API Gateway and DynamoDB recipe.

## Overview

This CDK application creates a serverless URL shortening service using:

- **AWS API Gateway**: REST API with CORS support and proper error handling
- **AWS Lambda Functions**: Two functions for URL creation and redirection
- **Amazon DynamoDB**: NoSQL database for storing URL mappings
- **AWS IAM**: Roles and policies following the principle of least privilege
- **Amazon CloudWatch**: Logging and monitoring for all components

## Architecture

The application implements a serverless architecture with the following components:

1. **API Gateway REST API** (`/prod` stage)
   - `POST /shorten` - Creates short URLs
   - `GET /{shortCode}` - Redirects to original URLs

2. **Lambda Functions**
   - `url-shortener-create` - Handles URL creation with validation
   - `url-shortener-redirect` - Handles URL redirection with error pages

3. **DynamoDB Table**
   - Table: `url-shortener-mappings`
   - Partition Key: `shortCode` (String)
   - Billing: On-demand (pay-per-request)

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI v2** installed and configured
2. **Python 3.8+** installed
3. **AWS CDK v2** installed globally:
   ```bash
   npm install -g aws-cdk
   ```
4. **AWS Account** with appropriate permissions for:
   - API Gateway
   - Lambda
   - DynamoDB
   - IAM
   - CloudWatch

## Installation

1. **Create a Python virtual environment**:
   ```bash
   python -m venv .venv
   ```

2. **Activate the virtual environment**:
   ```bash
   # On macOS/Linux
   source .venv/bin/activate
   
   # On Windows
   .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Deployment

1. **Bootstrap CDK** (only needed once per account/region):
   ```bash
   cdk bootstrap
   ```

2. **Synthesize CloudFormation template** (optional, for review):
   ```bash
   cdk synth
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

4. **Note the outputs**: The deployment will output important values including:
   - API Gateway URL
   - Example curl commands
   - Resource names

## Usage

After deployment, you can use the URL shortener as follows:

### Create a Short URL

```bash
# Replace <API_URL> with your actual API Gateway URL from deployment outputs
curl -X POST <API_URL>/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://aws.amazon.com/lambda/"}'
```

Response:
```json
{
  "shortCode": "aB3dEf",
  "shortUrl": "https://your-api-id.execute-api.region.amazonaws.com/prod/aB3dEf",
  "originalUrl": "https://aws.amazon.com/lambda/",
  "createdAt": "request-id",
  "message": "Short URL created successfully"
}
```

### Access a Short URL

Simply visit the short URL in your browser or use curl:

```bash
curl -I <API_URL>/aB3dEf
```

This will return a 302 redirect to the original URL.

## CDK Commands

- `cdk ls` - List all stacks in the app
- `cdk synth` - Emit the synthesized CloudFormation template
- `cdk deploy` - Deploy this stack to your default AWS account/region
- `cdk diff` - Compare deployed stack with current state
- `cdk destroy` - Remove the stack and all resources

## Project Structure

```
cdk-python/
├── app.py              # Main CDK application and stack definition
├── requirements.txt    # Python dependencies
├── setup.py           # Package setup configuration
├── cdk.json           # CDK configuration and feature flags
└── README.md          # This file
```

## Key Features

### Security
- **IAM Least Privilege**: Lambda functions have minimal required permissions
- **Input Validation**: Comprehensive URL validation and sanitization
- **CORS Support**: Proper CORS headers for web applications
- **Security Headers**: Anti-clickjacking and content-type protection

### Reliability
- **Error Handling**: Comprehensive error handling with meaningful messages
- **Logging**: Structured logging for debugging and monitoring
- **Retry Logic**: Collision handling for short code generation
- **Health Checks**: Built-in validation for all components

### Performance
- **On-Demand Billing**: DynamoDB scales automatically with usage
- **Regional API**: API Gateway configured for optimal performance
- **Caching Headers**: Proper cache directives for redirects
- **X-Ray Tracing**: Distributed tracing enabled for debugging

### Cost Optimization
- **Serverless Architecture**: Pay only for actual usage
- **Short Log Retention**: 1-week retention for development
- **Right-Sized Functions**: Optimized memory and timeout settings
- **On-Demand DynamoDB**: No provisioned capacity charges

## Customization

### Environment Variables
The Lambda functions use these environment variables (automatically configured):
- `TABLE_NAME`: DynamoDB table name
- `POWERTOOLS_SERVICE_NAME`: Service name for logging
- `LOG_LEVEL`: Logging level (INFO by default)

### Scaling Configuration
- **API Gateway**: 100 RPS limit, 200 burst capacity
- **Lambda**: 256MB memory, 10-second timeout
- **DynamoDB**: On-demand billing (automatic scaling)

### Monitoring
The application includes:
- CloudWatch log groups with 1-week retention
- X-Ray tracing for distributed debugging
- API Gateway access logs in JSON format
- Custom metrics for monitoring (can be extended)

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **Region Mismatch**: Verify CDK_DEFAULT_REGION matches your desired region
3. **Dependencies**: Ensure all Python packages are installed in the virtual environment

### Debugging

1. **Check CloudWatch Logs**:
   - `/aws/lambda/url-shortener-create`
   - `/aws/lambda/url-shortener-redirect`
   - `/aws/apigateway/url-shortener-api`

2. **Use X-Ray Tracing**: View distributed traces in the AWS X-Ray console

3. **Test Components Individually**: Use AWS CLI to test Lambda functions directly

## Cleanup

To remove all resources created by this stack:

```bash
cdk destroy
```

**Warning**: This will permanently delete the DynamoDB table and all stored URL mappings.

## Development

### Adding Features

1. **Analytics**: Add click tracking to the redirect function
2. **Custom Domains**: Configure Route 53 and ACM certificates
3. **Rate Limiting**: Implement API Gateway usage plans
4. **Authentication**: Add Cognito user pools or API keys

### Testing

1. **Unit Tests**: Add pytest tests for Lambda functions
2. **Integration Tests**: Test the full API workflow
3. **Load Testing**: Use artillery or similar tools

### Code Quality

1. **Type Hints**: The code includes comprehensive type hints
2. **Documentation**: All functions have docstrings
3. **Error Handling**: Comprehensive error handling with logging
4. **Security**: Input validation and secure headers

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues with this CDK application:

1. Check the troubleshooting section above
2. Review AWS CDK documentation: https://docs.aws.amazon.com/cdk/
3. Check AWS service documentation for specific issues
4. Review CloudWatch logs for detailed error information

## Contributing

1. Follow Python PEP 8 style guidelines
2. Add type hints for all functions
3. Include comprehensive error handling
4. Update documentation for any changes
5. Test changes thoroughly before deployment