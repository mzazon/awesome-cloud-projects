# Infrastructure as Code for Computer Vision Applications with Rekognition

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Computer Vision Applications with Rekognition".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)  
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Rekognition (image and video analysis, face collections)
  - Amazon S3 (bucket creation and object management)
  - Amazon Kinesis Video Streams and Data Streams
  - IAM (role creation and policy attachment)
- Basic understanding of computer vision concepts
- Sample images and videos for testing
- Estimated cost: $15-25 USD for processing 1,000 images and 1 hour of video

## Quick Start

### Using CloudFormation (AWS)
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name computer-vision-rekognition-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=computer-vision-demo \
                 ParameterKey=Environment,ParameterValue=dev

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name computer-vision-rekognition-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name computer-vision-rekognition-stack \
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
cdk deploy --parameters projectName=computer-vision-demo

# View outputs
cdk output
```

### Using CDK Python (AWS)
```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=computer-vision-demo

# View outputs
cdk output
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_name=computer-vision-demo"

# Apply the configuration
terraform apply -var="project_name=computer-vision-demo"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for project name and environment
# Or set environment variables:
# export PROJECT_NAME=computer-vision-demo
# export ENVIRONMENT=dev
# ./scripts/deploy.sh
```

## Infrastructure Components

This recipe deploys the following AWS resources:

### Core Components
- **Amazon S3 Bucket**: Storage for images, videos, and analysis results
- **Amazon Rekognition Face Collection**: Database for facial recognition
- **IAM Role**: Service role for Rekognition video analysis operations

### Streaming Components (Optional)
- **Kinesis Video Stream**: Real-time video input for streaming analysis
- **Kinesis Data Stream**: Output stream for real-time analysis results
- **Rekognition Stream Processor**: Real-time face search processor

### Security & Access
- **IAM Policies**: Least privilege access for Rekognition operations
- **S3 Bucket Policies**: Secure access to storage resources
- **Encryption**: Server-side encryption for S3 objects

## Configuration Options

### Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| project_name | Project identifier used in resource naming | computer-vision-demo | Yes |
| environment | Environment designation (dev/staging/prod) | dev | No |
| face_collection_name | Name for the Rekognition face collection | auto-generated | No |
| enable_streaming | Whether to create streaming components | false | No |
| s3_bucket_name | Custom S3 bucket name | auto-generated | No |
| retention_hours | Video stream retention in hours | 24 | No |

### Environment Variables (Bash Scripts)

```bash
export PROJECT_NAME="computer-vision-demo"
export ENVIRONMENT="dev"
export AWS_REGION="us-east-1"
export ENABLE_STREAMING="true"
export RETENTION_HOURS="24"
```

## Post-Deployment Steps

After deploying the infrastructure, follow these steps to start using the computer vision application:

### 1. Upload Sample Content
```bash
# Get bucket name from outputs
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name computer-vision-rekognition-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

# Upload sample images
aws s3 cp sample-images/ s3://${S3_BUCKET}/images/ --recursive

# Upload sample videos
aws s3 cp sample-videos/ s3://${S3_BUCKET}/videos/ --recursive
```

### 2. Index Known Faces
```bash
# Get face collection name from outputs
FACE_COLLECTION=$(aws cloudformation describe-stacks \
    --stack-name computer-vision-rekognition-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`FaceCollectionName`].OutputValue' \
    --output text)

# Index a face in the collection
aws rekognition index-faces \
    --image "S3Object={Bucket=${S3_BUCKET},Name=images/known-person.jpg}" \
    --collection-id ${FACE_COLLECTION} \
    --external-image-id "employee_001" \
    --detection-attributes "ALL"
```

### 3. Run Image Analysis
```bash
# Analyze an image for labels and faces
aws rekognition detect-labels \
    --image "S3Object={Bucket=${S3_BUCKET},Name=images/sample.jpg}" \
    --max-labels 10 \
    --min-confidence 80

# Search for faces in the image
aws rekognition search-faces-by-image \
    --image "S3Object={Bucket=${S3_BUCKET},Name=images/sample.jpg}" \
    --collection-id ${FACE_COLLECTION} \
    --face-match-threshold 80
```

### 4. Start Video Analysis
```bash
# Get IAM role ARN from outputs
ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name computer-vision-rekognition-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`RekognitionRoleArn`].OutputValue' \
    --output text)

# Start video analysis job
aws rekognition start-label-detection \
    --video "S3Object={Bucket=${S3_BUCKET},Name=videos/sample-video.mp4}" \
    --notification-channel "RoleArn=${ROLE_ARN},SNSTopicArn=arn:aws:sns:region:account:topic"
```

## Monitoring and Logging

### CloudWatch Integration
- Rekognition API calls are automatically logged to CloudWatch
- Monitor processing times and error rates
- Set up alarms for failed analysis jobs

### Cost Monitoring
```bash
# Monitor Rekognition costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**
   ```bash
   # Verify IAM permissions
   aws iam simulate-principal-policy \
       --policy-source-arn arn:aws:iam::account:role/RekognitionRole \
       --action-names rekognition:DetectLabels \
       --resource-arns "*"
   ```

2. **Face Collection Errors**
   ```bash
   # Check if face collection exists
   aws rekognition describe-collection \
       --collection-id ${FACE_COLLECTION}
   
   # List faces in collection
   aws rekognition list-faces \
       --collection-id ${FACE_COLLECTION}
   ```

3. **S3 Access Issues**
   ```bash
   # Test S3 access
   aws s3 ls s3://${S3_BUCKET}/
   
   # Check bucket policy
   aws s3api get-bucket-policy \
       --bucket ${S3_BUCKET}
   ```

### Performance Optimization

- Use appropriate image sizes (max 15MB for analysis)
- Implement batch processing for large volumes
- Use confidence thresholds to filter results
- Consider Regional endpoints for better latency

## Security Best Practices

### Data Protection
- Enable S3 server-side encryption
- Use least privilege IAM policies
- Implement proper bucket policies
- Regular access review and auditing

### Privacy Compliance
- Understand local regulations (GDPR, CCPA, biometric laws)
- Implement data retention policies
- Consider face collection data as biometric information
- Obtain proper consent for facial recognition

### Example Privacy-Compliant Setup
```bash
# Set S3 lifecycle policy for automatic deletion
aws s3api put-bucket-lifecycle-configuration \
    --bucket ${S3_BUCKET} \
    --lifecycle-configuration file://lifecycle-policy.json

# Enable CloudTrail for audit logging
aws cloudtrail create-trail \
    --name rekognition-audit-trail \
    --s3-bucket-name audit-logs-bucket
```

## Cleanup

### Using CloudFormation (AWS)
```bash
# Empty S3 bucket first (required before stack deletion)
aws s3 rm s3://${S3_BUCKET} --recursive

# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name computer-vision-rekognition-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name computer-vision-rekognition-stack
```

### Using CDK (AWS)
```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cdk-python/

# Empty S3 bucket first
aws s3 rm s3://${S3_BUCKET} --recursive

# Destroy the CDK stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
# Navigate to Terraform directory
cd terraform/

# Empty S3 bucket first
aws s3 rm s3://${S3_BUCKET} --recursive

# Destroy infrastructure
terraform destroy -var="project_name=computer-vision-demo"

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will handle S3 cleanup and resource deletion
# Confirm when prompted for destructive actions
```

## Advanced Usage

### Custom Labels with Amazon Rekognition Custom Labels
```bash
# Create a custom model project
aws rekognition create-project \
    --project-name "retail-inventory-detection"

# Train custom model (requires training data)
# See AWS documentation for detailed training process
```

### Integration with Other AWS Services
```bash
# Connect to Amazon Kinesis for real-time processing
# Set up Lambda triggers for automated responses
# Integrate with Amazon QuickSight for analytics dashboards
```

## Cost Optimization

### Pricing Considerations
- **Image Analysis**: $1.00 per 1,000 images (first 1M images/month)
- **Video Analysis**: $0.10 per minute of video processed
- **Face Storage**: $0.0001 per face/month stored in collections
- **Streaming Analysis**: Additional charges for Kinesis streams

### Cost-Saving Tips
- Use appropriate confidence thresholds to reduce processing
- Implement intelligent pre-filtering of content
- Archive old analysis results to cheaper storage tiers
- Monitor usage patterns and adjust retention policies

## Support and Resources

- [Amazon Rekognition Developer Guide](https://docs.aws.amazon.com/rekognition/latest/dg/)
- [AWS Computer Vision Blog](https://aws.amazon.com/blogs/machine-learning/category/artificial-intelligence/computer-vision/)
- [Rekognition API Reference](https://docs.aws.amazon.com/rekognition/latest/APIReference/)
- [AWS Well-Architected Machine Learning Lens](https://docs.aws.amazon.com/wellarchitected/latest/machine-learning-lens/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support channels.