# Infrastructure as Code for Analyzing Video Streams with Rekognition and Kinesis

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Analyzing Video Streams with Rekognition and Kinesis".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)  
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive real-time video analytics platform that:

- Ingests video streams from multiple cameras using Kinesis Video Streams
- Processes video in real-time using Amazon Rekognition stream processors
- Detects faces, objects, and activities with configurable confidence thresholds
- Stores detection metadata in DynamoDB for fast queries
- Triggers real-time alerts via SNS for security events
- Provides REST API for querying analytics data
- Supports facial recognition against a known face collection

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- Appropriate AWS permissions for:
  - Amazon Rekognition (full access)
  - Kinesis Video Streams (full access)
  - Lambda (create/invoke functions)
  - DynamoDB (create/read/write tables)
  - SNS (publish to topics)
  - API Gateway (create/deploy APIs)
  - IAM (create roles and policies)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)

## Cost Considerations

**Estimated monthly cost for moderate usage:**
- Kinesis Video Streams: $50-100 per stream
- Rekognition Video processing: $100-300 depending on hours analyzed
- Lambda executions: $10-50
- DynamoDB: $20-100 depending on read/write volume
- Other services: $10-30

> **Warning**: Rekognition Video stream processing and Kinesis Video Streams incur significant charges. Monitor usage carefully and clean up resources promptly after testing.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name video-analytics-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=EmailAddress,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name video-analytics-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name video-analytics-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the application
cdk deploy VideoAnalyticsStack

# Get outputs
cdk output
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the application
cdk deploy VideoAnalyticsStack

# Get outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure email notifications
```

## Configuration Options

### CloudFormation Parameters

- `EmailAddress`: Email address for security alerts
- `ProjectName`: Prefix for resource names (default: video-analytics)
- `StreamRetentionHours`: Video retention period (default: 24)
- `FaceMatchThreshold`: Face recognition confidence threshold (default: 80.0)

### CDK Configuration

Edit the configuration in `cdk-typescript/lib/config.ts` or `cdk-python/config.py`:

```typescript
export const config = {
  projectName: 'video-analytics',
  emailAddress: 'your-email@example.com',
  streamRetentionHours: 24,
  faceMatchThreshold: 80.0,
  region: 'us-east-1'
};
```

### Terraform Variables

Create a `terraform.tfvars` file in the terraform directory:

```hcl
email_address = "your-email@example.com"
project_name = "video-analytics"
stream_retention_hours = 24
face_match_threshold = 80.0
```

## Post-Deployment Setup

### 1. Confirm SNS Email Subscription

After deployment, check your email for an SNS subscription confirmation and click the confirmation link.

### 2. Populate Face Collection (Optional)

To enable facial recognition, add reference images to the face collection:

```bash
# Get collection name from outputs
COLLECTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name video-analytics-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`FaceCollectionName`].OutputValue' \
    --output text)

# Add a face to the collection (replace with your image)
aws rekognition index-faces \
    --collection-id ${COLLECTION_NAME} \
    --image S3Object='{Bucket=your-bucket,Name=reference-image.jpg}' \
    --external-image-id "person-001"
```

### 3. Test Video Stream Ingestion

You can test the system using:

- AWS Kinesis Video Streams console to upload test videos
- GStreamer or other streaming tools
- Mobile applications with KVS Producer SDK
- IP cameras with RTMP support

### 4. Monitor Detection Results

Query the API endpoints to view detection results:

```bash
# Get API endpoint from outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name video-analytics-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Test the API
curl "${API_ENDPOINT}/stats"
```

## API Endpoints

The deployed solution provides the following REST API endpoints:

- `GET /detections?stream={streamName}&hours={hours}` - Get detection events
- `GET /faces?project={projectName}` - Get face detection events  
- `GET /stats` - Get analytics statistics

## Monitoring and Troubleshooting

### CloudWatch Dashboards

The deployment creates CloudWatch dashboards for monitoring:

- Kinesis Video Streams metrics
- Rekognition processing metrics
- Lambda function performance
- DynamoDB table metrics

### Common Issues

**Stream Processor Not Starting:**
- Verify IAM permissions for Rekognition service role
- Check that Kinesis Video Stream is active
- Ensure face collection exists

**No Detection Events:**
- Verify Lambda function is receiving data from Kinesis Data Stream
- Check CloudWatch logs for processing errors
- Validate DynamoDB table permissions

**High Costs:**
- Monitor Rekognition processing hours in billing dashboard
- Consider reducing stream retention period
- Implement automated shutoff for testing environments

## Security Considerations

### IAM Permissions

The solution implements least-privilege IAM roles:

- Rekognition service role with minimal required permissions
- Lambda execution roles with specific resource access
- API Gateway with appropriate authentication

### Data Privacy

- Face collections store mathematical feature vectors, not images
- Detection metadata includes bounding boxes but not image data
- Video streams can be encrypted in transit and at rest

### Network Security

- API Gateway can be configured with API keys or IAM authentication
- VPC endpoints available for private service communication
- Security groups restrict network access to required ports

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name video-analytics-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy VideoAnalyticsStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

> **Important**: Cleanup may take several minutes as stream processors must be stopped before deletion. The destroy scripts include appropriate wait conditions.

## Customization Ideas

### Enhanced Analytics

- Integrate with Amazon OpenSearch for advanced querying
- Add Amazon QuickSight dashboards for visualization
- Implement Amazon Kinesis Data Analytics for real-time insights

### Security Enhancements

- Add multi-factor authentication for API access
- Implement field-level encryption for sensitive data
- Add AWS WAF protection for API endpoints

### Scalability Improvements

- Use Amazon ECS or EKS for custom video processing
- Implement regional distribution with cross-region replication
- Add auto-scaling for Lambda concurrency

### Integration Options

- Connect to existing SIEM systems via webhooks
- Integrate with physical access control systems
- Add mobile push notifications via Amazon Pinpoint

## Development and Testing

### Local Development

For local testing of Lambda functions:

```bash
cd scripts/
# Install SAM CLI for local testing
sam local start-api

# Test individual functions
sam local invoke AnalyticsProcessor --event test-event.json
```

### CI/CD Integration

The IaC templates can be integrated with AWS CodePipeline, GitHub Actions, or other CI/CD systems for automated deployment and testing.

## Support and Resources

### Documentation Links

- [Amazon Rekognition Video Developer Guide](https://docs.aws.amazon.com/rekognition/latest/dg/video.html)
- [Kinesis Video Streams Developer Guide](https://docs.aws.amazon.com/kinesisvideostreams/latest/dg/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)

### Community Resources

- AWS Computer Vision Blog
- AWS Architecture Center
- AWS Solutions Library

### Getting Help

For issues with this infrastructure code:

1. Check CloudWatch logs for detailed error messages
2. Review AWS service quotas and limits
3. Consult the original recipe documentation
4. Reference AWS support documentation
5. Consider AWS Professional Services for complex implementations

---

**Note**: This infrastructure code is generated from the recipe "Analyzing Video Streams with Rekognition and Kinesis". For the complete implementation guide and step-by-step instructions, refer to the recipe documentation.