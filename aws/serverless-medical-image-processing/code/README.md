# Infrastructure as Code for Serverless Medical Image Processing with HealthImaging

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless Medical Image Processing with HealthImaging".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a serverless medical image processing pipeline that includes:

- AWS HealthImaging data store for HIPAA-compliant DICOM storage
- S3 buckets for input/output with encryption enabled
- Lambda functions for image processing and metadata extraction
- Step Functions state machine for workflow orchestration
- EventBridge rules for event-driven automation
- IAM roles with least privilege access

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - HealthImaging (medical-imaging:*)
  - Lambda (lambda:*)
  - Step Functions (states:*)
  - S3 (s3:*)
  - EventBridge (events:*)
  - IAM (iam:*)
  - CloudWatch Logs (logs:*)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Business Associate Addendum (BAA) signed with AWS for processing PHI

> **Warning**: This solution processes medical imaging data. Ensure HIPAA compliance requirements are met before deploying in production environments.

## Estimated Costs

- AWS HealthImaging: $0.07 per GB stored per month
- Lambda: $0.20 per 1M requests + compute time
- Step Functions: $0.025 per 1,000 state transitions
- S3 Standard: $0.023 per GB stored per month
- EventBridge: $1.00 per million events

**Testing estimate**: $5-10 for sample DICOM files and basic testing

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name medical-imaging-pipeline \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=DataStoreName,ParameterValue=my-medical-datastore \
                 ParameterKey=Environment,ParameterValue=dev

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name medical-imaging-pipeline \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name medical-imaging-pipeline \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters dataStoreName=my-medical-datastore

# View outputs
cdk list
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

# Deploy the stack
cdk deploy --parameters dataStoreName=my-medical-datastore

# View outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="datastore_name=my-medical-datastore"

# Apply configuration
terraform apply -var="datastore_name=my-medical-datastore"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow prompts for configuration
# Script will create all necessary resources
```

## Configuration Options

### CloudFormation Parameters

- `DataStoreName`: Name for the HealthImaging data store
- `Environment`: Environment tag (dev, staging, prod)
- `InputBucketName`: Custom name for input S3 bucket (optional)
- `OutputBucketName`: Custom name for output S3 bucket (optional)

### CDK Configuration

Both TypeScript and Python CDK implementations support:

- Environment-specific configurations
- Custom resource naming
- Configurable retention policies
- Optional CloudWatch dashboard

### Terraform Variables

- `datastore_name`: HealthImaging data store name
- `environment`: Environment designation
- `aws_region`: Target AWS region
- `enable_encryption`: Enable S3 bucket encryption (default: true)
- `lambda_timeout`: Lambda function timeout in seconds

## Testing the Deployment

1. **Upload a test DICOM file**:
   ```bash
   # Create a sample DICOM file for testing
   echo "Sample DICOM content" > test.dcm
   
   # Upload to input bucket (replace with actual bucket name)
   aws s3 cp test.dcm s3://your-input-bucket/test-data/test.dcm
   ```

2. **Monitor processing**:
   ```bash
   # Check Step Functions execution
   aws stepfunctions list-executions \
       --state-machine-arn <state-machine-arn> \
       --max-items 5
   
   # View CloudWatch Logs
   aws logs describe-log-groups --log-group-name-prefix /aws/lambda/
   ```

3. **Verify outputs**:
   ```bash
   # List processed files in output bucket
   aws s3 ls s3://your-output-bucket/ --recursive
   ```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name medical-imaging-pipeline

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name medical-imaging-pipeline \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
# From terraform directory
terraform destroy -var="datastore_name=my-medical-datastore"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Security Considerations

### HIPAA Compliance

- All S3 buckets use server-side encryption
- HealthImaging data stores are HIPAA-eligible
- IAM roles follow least privilege principle
- CloudWatch Logs encrypted by default
- VPC endpoints recommended for production

### Best Practices Implemented

- No hardcoded credentials
- Resource-based access policies
- Encryption at rest and in transit
- Audit logging enabled
- Multi-factor authentication recommended

## Monitoring and Observability

### CloudWatch Integration

- Lambda function metrics and logs
- Step Functions execution history
- S3 access logging
- EventBridge rule metrics
- Custom dashboards (CDK implementations)

### X-Ray Tracing

Enable distributed tracing for Lambda functions:

```bash
# Update Lambda function configuration
aws lambda update-function-configuration \
    --function-name <function-name> \
    --tracing-config Mode=Active
```

## Troubleshooting

### Common Issues

1. **HealthImaging Data Store Creation Fails**:
   - Verify HealthImaging service availability in your region
   - Check IAM permissions for medical-imaging service

2. **Lambda Function Timeouts**:
   - Increase timeout values in configuration
   - Monitor memory usage and adjust accordingly

3. **Step Functions Execution Failures**:
   - Check CloudWatch Logs for detailed error messages
   - Verify IAM role permissions

4. **S3 Event Notifications Not Triggering**:
   - Verify Lambda function permissions
   - Check S3 bucket event configuration

### Debug Commands

```bash
# Check HealthImaging data store status
aws medical-imaging get-datastore --datastore-id <datastore-id>

# List Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `medical`)]'

# View Step Functions executions
aws stepfunctions list-executions --state-machine-arn <arn>

# Check EventBridge rules
aws events list-rules --name-prefix medical-imaging
```

## Customization

### Adding Custom Lambda Functions

1. Create new Lambda function code in the appropriate directory
2. Update IAM policies to include necessary permissions
3. Add function to Step Functions state machine definition
4. Update EventBridge rules if needed

### Integrating with AI/ML Services

```bash
# Example: Add SageMaker endpoint integration
aws sagemaker create-endpoint-config \
    --endpoint-config-name medical-imaging-endpoint \
    --production-variants file://variants.json
```

### Multi-Region Deployment

For production workloads, consider:
- Cross-region replication for S3 buckets
- Multiple HealthImaging data stores
- Global Step Functions workflows

## Cost Optimization

### Recommendations

1. **S3 Intelligent Tiering**: Automatically move data to cost-effective storage classes
2. **Lambda Provisioned Concurrency**: For predictable workloads
3. **HealthImaging Lifecycle Policies**: Archive older image sets
4. **CloudWatch Log Retention**: Set appropriate retention periods

### Cost Monitoring

```bash
# Enable Cost Explorer API
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Extensions and Enhancements

### Suggested Improvements

1. **DICOM Viewer Integration**: Build web-based viewer using HealthImaging DICOMweb APIs
2. **AI/ML Pipeline**: Integrate Amazon SageMaker for medical image analysis
3. **Compliance Reporting**: Automated HIPAA compliance monitoring
4. **Multi-Tenant Architecture**: Support multiple healthcare organizations
5. **Real-time Analytics**: Stream processing with Amazon Kinesis

### Integration Patterns

```bash
# Example: Add Comprehend Medical integration
aws comprehendmedical detect-entities \
    --text "Patient presents with chest pain" \
    --language-code en
```

## Support and Resources

### AWS Documentation

- [AWS HealthImaging Developer Guide](https://docs.aws.amazon.com/healthimaging/latest/devguide/)
- [Step Functions Best Practices](https://docs.aws.amazon.com/step-functions/latest/dg/best-practices.html)
- [HIPAA on AWS](https://aws.amazon.com/compliance/hipaa-compliance/)

### Community Resources

- AWS Health and Life Sciences Blog
- AWS re:Invent sessions on medical imaging
- Healthcare AWS Reference Architectures

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS service documentation
3. Consult the original recipe documentation
4. Contact AWS Support for service-specific issues

---

**Note**: This infrastructure code is provided as a reference implementation. Review and customize according to your specific requirements, security policies, and compliance needs before deploying to production environments.