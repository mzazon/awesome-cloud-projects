# Infrastructure as Code for Computer Vision Solutions with Rekognition

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Computer Vision Solutions with Rekognition".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a comprehensive computer vision solution using Amazon Rekognition that includes:

- **S3 Buckets**: Image storage and results storage
- **Amazon Rekognition**: Face detection, object recognition, text extraction, and content moderation
- **Rekognition Collections**: Face indexing and search capabilities
- **Lambda Functions**: Image processing automation
- **DynamoDB**: Analysis results storage
- **IAM Roles**: Secure service access with least privilege
- **API Gateway**: RESTful API endpoints for image analysis

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Rekognition (create collections, analyze images)
  - S3 (create buckets, read/write objects)
  - Lambda (create functions, manage execution roles)
  - DynamoDB (create tables, read/write items)
  - IAM (create roles and policies)
  - API Gateway (create APIs and deployments)
- For CDK: Node.js 18+ or Python 3.8+
- For Terraform: Terraform 1.0+

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name rekognition-computer-vision \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketNamePrefix,ParameterValue=my-cv-demo

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name rekognition-computer-vision \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name rekognition-computer-vision \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls --long

# Optional: View synthesized CloudFormation template
cdk synth
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure changes
terraform apply

# View outputs
terraform output

# Optional: Validate configuration
terraform validate
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# - Validate prerequisites
# - Create S3 buckets
# - Set up Rekognition collections
# - Deploy Lambda functions
# - Configure DynamoDB tables
# - Set up API Gateway endpoints
```

## Configuration Options

### CloudFormation Parameters

- `BucketNamePrefix`: Prefix for S3 bucket names (default: cv-demo)
- `CollectionName`: Name for Rekognition face collection (default: faces)
- `Environment`: Deployment environment (default: dev)
- `EnableContentModeration`: Enable automatic content moderation (default: true)

### CDK Configuration

Modify the configuration in the CDK app files:

```typescript
// CDK TypeScript - app.ts
const config = {
  bucketNamePrefix: 'my-cv-demo',
  collectionName: 'face-collection',
  environment: 'production',
  enableContentModeration: true
};
```

```python
# CDK Python - app.py
config = {
    "bucket_name_prefix": "my-cv-demo",
    "collection_name": "face-collection", 
    "environment": "production",
    "enable_content_moderation": True
}
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
bucket_name_prefix = "my-cv-demo"
collection_name = "face-collection"
environment = "production"
aws_region = "us-east-1"
enable_content_moderation = true
min_confidence_score = 75
```

## Testing the Deployment

After deployment, test the computer vision capabilities:

```bash
# Get the S3 bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name rekognition-computer-vision \
    --query 'Stacks[0].Outputs[?OutputKey==`ImageBucketName`].OutputValue' \
    --output text)

# Upload a test image
aws s3 cp test-image.jpg s3://${BUCKET_NAME}/images/

# Test face detection via API Gateway
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name rekognition-computer-vision \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

curl -X POST "${API_ENDPOINT}/analyze" \
    -H "Content-Type: application/json" \
    -d '{"bucket":"'${BUCKET_NAME}'","key":"images/test-image.jpg","analysisType":"faces"}'
```

## Monitoring and Logging

The infrastructure includes CloudWatch integration for monitoring:

- **Lambda Function Logs**: `/aws/lambda/rekognition-processor`
- **API Gateway Logs**: `/aws/apigateway/rekognition-api`
- **Custom Metrics**: Analysis success/failure rates
- **Cost Tracking**: Tagged resources for cost allocation

Access logs via AWS CLI:

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/rekognition"

# View recent API Gateway requests
aws logs filter-log-events \
    --log-group-name "/aws/apigateway/rekognition-api" \
    --start-time $(date -d "1 hour ago" +%s)000
```

## Security Considerations

The infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for all services
- **S3 Bucket Policies**: Restricted access with encryption
- **API Gateway**: Optional authentication and rate limiting
- **VPC Endpoints**: Private connectivity to AWS services (optional)
- **Encryption**: At-rest and in-transit encryption enabled

## Cost Management

Estimated monthly costs for moderate usage (1,000 images):

- **Rekognition**: $1-5 (based on analysis types)
- **S3**: $1-3 (storage and requests)
- **Lambda**: $0.20-1 (execution time)
- **DynamoDB**: $1-2 (on-demand pricing)
- **API Gateway**: $3.50 per million requests

Use AWS Cost Explorer and Budget alerts to monitor spending.

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name rekognition-computer-vision

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name rekognition-computer-vision \
    --query 'Stacks[0].StackStatus'

# Note: Some resources may need manual cleanup if they contain data
```

### Using CDK (AWS)

```bash
# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm destruction when prompted
# This will remove all resources created by the stack
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
# Review the destruction plan carefully
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# - Delete Rekognition collections
# - Empty and delete S3 buckets
# - Remove Lambda functions
# - Delete DynamoDB tables
# - Clean up IAM roles and policies
# - Remove API Gateway resources
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**:
   ```bash
   # Verify your AWS credentials and permissions
   aws sts get-caller-identity
   aws iam get-user
   ```

2. **Region-Specific Services**:
   ```bash
   # Ensure Rekognition is available in your region
   aws rekognition describe-collection --collection-id test-collection --region us-east-1
   ```

3. **Resource Limits**:
   ```bash
   # Check service quotas
   aws service-quotas get-service-quota \
       --service-code rekognition \
       --quota-code L-D4D9B1E8
   ```

4. **CDK Bootstrap Issues**:
   ```bash
   # Re-bootstrap CDK if needed
   cdk bootstrap --force
   ```

### Getting Help

- Review CloudFormation stack events for deployment issues
- Check Lambda function logs in CloudWatch
- Verify IAM permissions for service access
- Consult the [Amazon Rekognition documentation](https://docs.aws.amazon.com/rekognition/)

## Customization

### Adding Custom Analysis Types

Extend the Lambda function to support additional analysis:

```python
# Add to the Lambda function code
def analyze_celebrities(image_location):
    response = rekognition.recognize_celebrities(
        Image={'S3Object': image_location}
    )
    return response

def analyze_protective_equipment(image_location):
    response = rekognition.detect_protective_equipment(
        Image={'S3Object': image_location}
    )
    return response
```

### Integrating with Other Services

- **SNS**: Add notifications for analysis results
- **SQS**: Queue images for batch processing
- **Step Functions**: Orchestrate complex workflows
- **EventBridge**: Event-driven architecture patterns

## Performance Optimization

- Use Rekognition batch operations for high-volume processing
- Implement caching for frequently analyzed images
- Configure Lambda reserved concurrency for predictable performance
- Use S3 Transfer Acceleration for global image uploads

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult AWS documentation for specific services
4. Use AWS Support for production issues

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's policies and AWS terms of service.