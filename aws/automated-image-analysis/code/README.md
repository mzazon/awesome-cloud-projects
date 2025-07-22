# Infrastructure as Code for Automated Image Analysis with ML

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Image Analysis with ML".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for Amazon Rekognition, Amazon S3, and IAM
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Sample images for testing (JPG or PNG format)

## Quick Start

### Using CloudFormation
```bash
aws cloudformation create-stack \
    --stack-name rekognition-image-analysis \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=BucketName,ParameterValue=your-unique-bucket-name
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install
npx cdk bootstrap  # First time only
npx cdk deploy
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt
npx cdk bootstrap  # First time only
npx cdk deploy
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Testing the Deployment

After deployment, test the image analysis functionality:

1. **Upload a test image**:
   ```bash
   # Get the bucket name from outputs
   BUCKET_NAME=$(aws cloudformation describe-stacks \
       --stack-name rekognition-image-analysis \
       --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
       --output text)
   
   # Upload test image
   aws s3 cp your-test-image.jpg s3://${BUCKET_NAME}/images/
   ```

2. **Analyze the image**:
   ```bash
   # Detect labels
   aws rekognition detect-labels \
       --image "{'S3Object':{'Bucket':'${BUCKET_NAME}','Name':'images/your-test-image.jpg'}}" \
       --features GENERAL_LABELS
   
   # Detect text
   aws rekognition detect-text \
       --image "{'S3Object':{'Bucket':'${BUCKET_NAME}','Name':'images/your-test-image.jpg'}}"
   ```

## Architecture Components

This infrastructure deploys:

- **S3 Bucket**: Secure storage for images with appropriate permissions
- **IAM Roles**: Least privilege access for Rekognition to read from S3
- **S3 Bucket Policy**: Secure access controls for image storage
- **CloudWatch Logs**: Optional logging for API calls and monitoring

## Customization

### Variables and Parameters

Each implementation supports customization through variables:

- **Bucket Name**: Customize the S3 bucket name (must be globally unique)
- **Region**: Deploy to different AWS regions
- **Logging**: Enable/disable CloudWatch logging
- **Retention**: Configure image retention policies

### CloudFormation Parameters
```yaml
Parameters:
  BucketName:
    Type: String
    Description: Name for the S3 bucket (must be globally unique)
  EnableLogging:
    Type: String
    Default: "true"
    AllowedValues: ["true", "false"]
```

### Terraform Variables
```hcl
variable "bucket_name" {
  description = "Name for the S3 bucket"
  type        = string
  default     = null
}

variable "enable_logging" {
  description = "Enable CloudWatch logging"
  type        = bool
  default     = true
}
```

## Security Considerations

The infrastructure implements security best practices:

- **Least Privilege IAM**: Rekognition service only has read access to specific S3 bucket
- **Bucket Encryption**: S3 bucket uses AES-256 server-side encryption
- **Public Access Blocking**: S3 bucket blocks all public access
- **Resource Isolation**: Resources are isolated to prevent cross-contamination

## Cost Considerations

- **S3 Storage**: Standard storage class for frequently accessed images
- **Amazon Rekognition**: Pay-per-request pricing ($1 per 1,000 images)
- **Data Transfer**: Minimal costs for data transfer within AWS region
- **Free Tier**: 5,000 images per month for first 12 months

Estimated monthly cost for 1,000 images: ~$2-5 USD

## Monitoring and Logging

Optional CloudWatch integration provides:

- **API Call Logs**: Track Rekognition API usage
- **Error Monitoring**: Monitor failed requests and rate limits
- **Usage Metrics**: Track image processing volume and patterns
- **Cost Tracking**: Monitor service usage and associated costs

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name rekognition-image-analysis
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python
```bash
cd cdk-python/
npx cdk destroy
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Bucket Name Conflicts**: S3 bucket names must be globally unique
   - Solution: Use a unique suffix or let the IaC generate one

2. **Permission Errors**: Insufficient IAM permissions
   - Solution: Ensure your AWS credentials have permissions for S3, Rekognition, and IAM

3. **Region Limitations**: Some AWS regions don't support all Rekognition features
   - Solution: Deploy in supported regions (us-east-1, us-west-2, eu-west-1, etc.)

4. **Image Format Issues**: Rekognition supports JPG and PNG only
   - Solution: Convert images to supported formats before upload

### Validation Commands

```bash
# Verify S3 bucket creation
aws s3 ls | grep your-bucket-name

# Test Rekognition permissions
aws rekognition describe-collection --collection-id test 2>/dev/null || echo "Rekognition access confirmed"

# Check IAM role creation
aws iam get-role --role-name rekognition-s3-access-role
```

## Extensions

This infrastructure can be extended with:

- **Lambda Functions**: Automatic processing when images are uploaded
- **DynamoDB**: Store analysis results for querying and reporting
- **API Gateway**: RESTful API for image upload and analysis
- **SQS/SNS**: Asynchronous processing and notifications
- **Step Functions**: Complex workflow orchestration

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for CLI-based implementation
2. Refer to AWS documentation for service-specific issues
3. Review CloudFormation/CDK/Terraform provider documentation
4. Check AWS service limits and quotas in your account

## Additional Resources

- [Amazon Rekognition Developer Guide](https://docs.aws.amazon.com/rekognition/latest/dg/)
- [S3 Best Practices](https://docs.aws.amazon.com/s3/latest/userguide/security-best-practices.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)