# Infrastructure as Code for Custom Video Conferencing with Amazon Chime SDK

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Custom Video Conferencing with Amazon Chime SDK".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a complete video conferencing platform using:
- Amazon Chime SDK for real-time audio/video communications
- AWS Lambda for backend meeting and attendee management
- Amazon API Gateway for RESTful API endpoints
- Amazon DynamoDB for meeting metadata storage
- Amazon S3 for recording storage
- Amazon SNS for event notifications
- Amazon Cognito for authentication (optional)

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm (for CDK TypeScript and web client)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Appropriate AWS permissions for:
  - Chime SDK operations
  - Lambda function management
  - API Gateway configuration
  - DynamoDB table operations
  - S3 bucket management
  - IAM role creation
  - SNS topic management

## Cost Considerations

- Amazon Chime SDK charges per attendee-minute
- Lambda functions charge per invocation and duration
- DynamoDB charges for read/write capacity
- S3 charges for storage and requests
- API Gateway charges per API call
- Estimated development cost: $50-100/month

> **Note**: Review [Amazon Chime SDK pricing](https://aws.amazon.com/chime/chime-sdk/pricing/) before deploying to production.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name video-conferencing-chime-sdk \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=my-video-conf

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name video-conferencing-chime-sdk \
    --query 'Stacks[0].StackStatus'

# Get API endpoint
aws cloudformation describe-stacks \
    --stack-name video-conferencing-chime-sdk \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview changes
cdk diff

# Deploy the stack
cdk deploy

# Get outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review execution plan
terraform plan

# Apply configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the API endpoint and other important information
```

## Configuration Options

### CloudFormation Parameters

- `ProjectName`: Unique project name for resource naming (default: video-conferencing)
- `Environment`: Environment name (default: dev)
- `EnableRecording`: Enable meeting recording features (default: true)
- `EnableChatMessaging`: Enable chat messaging features (default: false)

### CDK Configuration

Edit the configuration in the respective CDK app files:

**TypeScript**: `cdk-typescript/app.ts`
**Python**: `cdk-python/app.py`

Available configuration options:
- Project name and environment
- DynamoDB table configuration
- Lambda function timeout and memory settings
- S3 bucket configuration
- API Gateway CORS settings

### Terraform Variables

Configure in `terraform/terraform.tfvars`:

```hcl
project_name = "my-video-conferencing"
environment = "dev"
aws_region = "us-east-1"
enable_recording = true
enable_chat_messaging = false
lambda_timeout = 30
lambda_memory_size = 256
```

## Testing the Deployment

After deployment, test the video conferencing solution:

1. **API Endpoints**: Use the provided API Gateway endpoint to test meeting creation
2. **Web Client**: Deploy the included web client to test full functionality
3. **Meeting Creation**: Create a test meeting via API
4. **Attendee Management**: Add participants to meetings
5. **Real-time Features**: Test audio/video capabilities

### Example API Tests

```bash
# Get API endpoint from deployment outputs
API_ENDPOINT="https://your-api-id.execute-api.region.amazonaws.com/prod"

# Create a meeting
curl -X POST "${API_ENDPOINT}/meetings" \
    -H "Content-Type: application/json" \
    -d '{
        "externalMeetingId": "test-meeting-123",
        "mediaRegion": "us-east-1"
    }'

# Create an attendee (replace MEETING_ID with actual meeting ID)
curl -X POST "${API_ENDPOINT}/meetings/MEETING_ID/attendees" \
    -H "Content-Type: application/json" \
    -d '{
        "externalUserId": "test-user-123"
    }'
```

## Web Client Deployment

A sample web client is included for testing:

```bash
# Navigate to web client directory (created during deployment)
cd web-client/

# Install dependencies
npm install

# Start development server
npm start

# Open browser to http://localhost:8080
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda function logs:
- `/aws/lambda/[project-name]-meeting-handler`
- `/aws/lambda/[project-name]-attendee-handler`

### API Gateway Monitoring

Check API Gateway metrics in CloudWatch:
- Request count and latency
- Error rates (4xx, 5xx)
- Integration errors

### Chime SDK Events

Monitor SNS notifications for Chime SDK events:
- Meeting start/end events
- Participant join/leave events
- Media quality metrics

### Common Issues

1. **CORS Errors**: Ensure API Gateway CORS is properly configured
2. **Authentication Failures**: Verify IAM permissions for Lambda functions
3. **Media Connection Issues**: Check regional media placement configuration
4. **Recording Failures**: Verify S3 bucket permissions and configuration

## Security Considerations

### Production Hardening

1. **Authentication**: Implement proper authentication using Amazon Cognito
2. **API Security**: Add API keys or OAuth protection to API Gateway
3. **Network Security**: Deploy Lambda functions in private subnets with VPC endpoints
4. **Data Encryption**: Enable encryption for DynamoDB and S3
5. **Meeting Access**: Implement meeting access controls and time-based restrictions

### IAM Permissions

The deployment follows least privilege principles:
- Lambda functions have minimal required permissions
- API Gateway has execution permissions only
- S3 buckets have restricted access policies

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name video-conferencing-chime-sdk

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name video-conferencing-chime-sdk
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
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for resource deletion confirmation
```

## Customization

### Adding Authentication

To add Cognito authentication:

1. Uncomment Cognito resources in the IaC templates
2. Update API Gateway to use Cognito authorizer
3. Modify Lambda functions to validate JWT tokens
4. Update web client to handle authentication flow

### Enabling Recording

To enable meeting recording:

1. Set `EnableRecording` parameter to `true`
2. Configure S3 bucket for recording storage
3. Set up recording processing Lambda functions
4. Configure SNS notifications for recording events

### Multi-Region Deployment

For global deployment:

1. Deploy infrastructure in multiple regions
2. Configure Route 53 for DNS-based routing
3. Implement region selection logic in clients
4. Set up cross-region DynamoDB replication

## Support

- **Recipe Documentation**: Refer to the original recipe for detailed implementation guidance
- **AWS Documentation**: [Amazon Chime SDK Developer Guide](https://docs.aws.amazon.com/chime-sdk/)
- **API Reference**: [Chime SDK API Reference](https://docs.aws.amazon.com/chime-sdk/latest/APIReference/)
- **JavaScript SDK**: [Chime SDK for JavaScript](https://aws.github.io/amazon-chime-sdk-js/)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any new parameters or outputs
3. Validate security configurations
4. Update cost estimates if adding new resources
5. Test cleanup procedures thoroughly

## License

This infrastructure code is provided as part of the AWS recipes collection. Refer to the repository license for usage terms.