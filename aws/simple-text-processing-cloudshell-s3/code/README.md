# Infrastructure as Code for Simple Text Processing with CloudShell and S3

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Text Processing with CloudShell and S3". The recipe demonstrates how to use AWS CloudShell's built-in Linux tools to process text files stored in S3, providing a consistent, cloud-based environment for text analysis.

## Recipe Overview

The solution creates an S3 bucket with organized folder structure (input/ and output/) for storing raw and processed text data. While AWS CloudShell doesn't require infrastructure provisioning (it's a managed service), this IaC provides the foundational S3 storage infrastructure needed for the text processing workflow.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐
│   Data Analyst  │───▶│  AWS CloudShell │
│                 │    │ (Linux Environment)│
└─────────────────┘    └─────────┬───────┘
                                 │
                                 ▼
                       ┌─────────────────┐
                       │   S3 Bucket     │
                       │ ┌─────────────┐ │
                       │ │   input/    │ │
                       │ │   output/   │ │
                       │ └─────────────┘ │
                       └─────────────────┘
```

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements

- AWS CLI installed and configured with appropriate credentials
- AWS account with permissions for:
  - S3 bucket creation and management
  - CloudShell access (AWSCloudShellFullAccess policy recommended)
- Basic familiarity with chosen deployment tool

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI version 2.0 or later
- IAM permissions: `cloudformation:*`, `s3:*`

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI: `npm install -g aws-cdk`
- TypeScript: `npm install -g typescript`

#### CDK Python
- Python 3.8 or later
- AWS CDK CLI: `pip install aws-cdk-lib`
- Virtual environment recommended

#### Terraform
- Terraform 1.0 or later
- AWS provider familiarity

#### Bash Scripts
- bash 4.0 or later
- Standard Unix tools (grep, awk, sed)

## Infrastructure Components

The infrastructure includes:

1. **S3 Bucket**: Primary storage for text files with versioning enabled
2. **Bucket Folders**: Organized structure with `input/` and `output/` prefixes
3. **Bucket Policy**: Appropriate access controls for data processing workflow
4. **Lifecycle Rules**: Cost optimization for temporary processing files
5. **Sample Data**: Optional sample CSV file for demonstration

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name text-processing-infrastructure \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=my-text-processing-bucket-$(date +%s) \
    --capabilities CAPABILITY_IAM

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name text-processing-infrastructure

# Get bucket name from outputs
aws cloudformation describe-stacks \
    --stack-name text-processing-infrastructure \
    --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# The bucket name will be displayed in the output
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply

# Get the bucket name
terraform output bucket_name
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output the created bucket name
```

## Using the Infrastructure

Once deployed, you can use the infrastructure with AWS CloudShell:

1. **Access CloudShell**: Open AWS CloudShell from the AWS Management Console

2. **Set Environment Variables**:
   ```bash
   # Use the bucket name from your deployment output
   export BUCKET_NAME="your-deployed-bucket-name"
   export AWS_REGION=$(aws configure get region)
   ```

3. **Upload Sample Data**:
   ```bash
   # Create sample data file
   cat << 'EOF' > sales_data.txt
   Date,Region,Product,Sales,Quantity
   2024-01-15,North,Laptop,1200,2
   2024-01-16,South,Mouse,25,5
   2024-01-17,East,Keyboard,75,3
   EOF
   
   # Upload to input folder
   aws s3 cp sales_data.txt s3://${BUCKET_NAME}/input/
   ```

4. **Process Data in CloudShell**:
   ```bash
   # Download file for processing
   aws s3 cp s3://${BUCKET_NAME}/input/sales_data.txt .
   
   # Perform text processing
   awk -F',' 'NR>1 {sales[$2]+=$4} END {for (region in sales) 
       print region "," sales[region]}' sales_data.txt > regional_summary.csv
   
   # Upload processed results
   aws s3 cp regional_summary.csv s3://${BUCKET_NAME}/output/
   ```

## Configuration Options

### Customizable Parameters

All implementations support these customization options:

- **BucketName**: Custom name for the S3 bucket (must be globally unique)
- **BucketPrefix**: Prefix for organized resource naming
- **EnableVersioning**: Enable/disable S3 versioning (default: enabled)
- **EnableLifecycle**: Enable/disable lifecycle rules for cost optimization
- **Environment**: Environment tag (dev, staging, prod)

### CloudFormation Parameters

```yaml
Parameters:
  BucketName:
    Type: String
    Description: Name for the S3 bucket
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
```

### Terraform Variables

```hcl
variable "bucket_name" {
  description = "Name for the S3 bucket"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
```

### CDK Configuration

Both CDK implementations support environment-specific configuration through context:

```bash
# Deploy with custom bucket name
cdk deploy -c bucketName=my-custom-bucket

# Deploy for production environment
cdk deploy -c environment=prod
```

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check bucket exists and has correct structure
aws s3 ls s3://your-bucket-name/

# Test bucket access
aws s3 cp README.md s3://your-bucket-name/test/
aws s3 rm s3://your-bucket-name/test/README.md
```

### Test Text Processing Workflow

```bash
# Create test data
echo "test,data,123" > test.csv

# Upload test file
aws s3 cp test.csv s3://your-bucket-name/input/

# Process in CloudShell
aws s3 cp s3://your-bucket-name/input/test.csv .
wc -l test.csv > test_result.txt

# Upload result
aws s3 cp test_result.txt s3://your-bucket-name/output/

# Verify result exists
aws s3 ls s3://your-bucket-name/output/
```

## Cost Optimization

The infrastructure includes several cost optimization features:

1. **S3 Intelligent Tiering**: Automatically moves data to cost-effective storage classes
2. **Lifecycle Rules**: Deletes temporary processing files after 7 days
3. **Minimal Infrastructure**: Only provisions essential S3 storage
4. **CloudShell Usage**: No additional compute costs (within AWS limits)

### Estimated Costs

- **S3 Storage**: $0.023 per GB per month (Standard storage)
- **S3 Requests**: $0.0004 per 1,000 PUT requests
- **CloudShell**: Included with AWS account (1GB persistent storage per region)
- **Data Transfer**: Free within same AWS region

For typical text processing workloads (< 1GB data), expect costs under $1/month.

## Monitoring & Observability

### CloudWatch Metrics

The infrastructure automatically provides:

- S3 bucket metrics (storage size, request counts)
- Access logging for audit trails
- CloudTrail integration for API call tracking

### Recommended Monitoring

```bash
# Monitor bucket size
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name BucketSizeBytes \
    --dimensions Name=BucketName,Value=your-bucket-name \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-02T00:00:00Z \
    --period 86400 \
    --statistics Average

# Check recent S3 access
aws s3api get-bucket-logging \
    --bucket your-bucket-name
```

## Security Best Practices

The infrastructure implements security best practices:

1. **Bucket Encryption**: AES-256 encryption at rest
2. **Access Logging**: Detailed access logs for audit
3. **Versioning**: Protection against accidental deletions
4. **Least Privilege**: Minimal required permissions
5. **No Public Access**: All buckets remain private

### Security Validation

```bash
# Verify bucket encryption
aws s3api get-bucket-encryption --bucket your-bucket-name

# Check public access block
aws s3api get-public-access-block --bucket your-bucket-name

# Verify versioning status
aws s3api get-bucket-versioning --bucket your-bucket-name
```

## Troubleshooting

### Common Issues

1. **Bucket Name Already Exists**
   ```bash
   # Solution: Use a unique suffix
   BUCKET_NAME="text-processing-$(date +%s)-$(whoami)"
   ```

2. **Insufficient Permissions**
   ```bash
   # Verify AWS credentials
   aws sts get-caller-identity
   
   # Check permissions
   aws iam simulate-principal-policy \
       --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
       --action-names s3:CreateBucket \
       --resource-arns "arn:aws:s3:::test-bucket"
   ```

3. **CloudShell Access Issues**
   ```bash
   # Verify CloudShell service availability in region
   aws cloudshell describe-environments
   
   # Check service limits
   aws service-quotas get-service-quota \
       --service-code cloudshell \
       --quota-code L-5B8A74DA
   ```

### Debug Commands

```bash
# CloudFormation troubleshooting
aws cloudformation describe-stack-events \
    --stack-name text-processing-infrastructure

# CDK troubleshooting
cdk doctor

# Terraform troubleshooting
terraform plan -detailed-exitcode
terraform show
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name text-processing-infrastructure

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name text-processing-infrastructure
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Follow prompts to confirm deletion
```

### Manual Cleanup

If automated cleanup fails:

```bash
# Empty bucket contents first
aws s3 rm s3://your-bucket-name --recursive

# Delete bucket versions if versioning was enabled  
aws s3api delete-objects \
    --bucket your-bucket-name \
    --delete "$(aws s3api list-object-versions \
    --bucket your-bucket-name \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"

# Delete bucket
aws s3 rb s3://your-bucket-name
```

## Advanced Usage

### Integration with Other AWS Services

The infrastructure supports integration with:

1. **AWS Lambda**: Trigger processing on file upload
2. **AWS Glue**: ETL jobs for larger datasets  
3. **Amazon EMR**: Big data processing
4. **Amazon QuickSight**: Data visualization
5. **AWS Step Functions**: Workflow orchestration

### Automation Examples

```bash
# Automated processing script
cat << 'EOF' > process_files.sh
#!/bin/bash
BUCKET_NAME=$1
for file in $(aws s3 ls s3://${BUCKET_NAME}/input/ --recursive | awk '{print $4}'); do
    aws s3 cp s3://${BUCKET_NAME}/${file} .
    # Process file with custom logic
    # Upload results
    aws s3 cp processed_$(basename ${file}) s3://${BUCKET_NAME}/output/
done
EOF

chmod +x process_files.sh
./process_files.sh your-bucket-name
```

## Support and Documentation

### Additional Resources

- [AWS CloudShell User Guide](https://docs.aws.amazon.com/cloudshell/latest/userguide/)
- [Amazon S3 User Guide](https://docs.aws.amazon.com/s3/latest/userguide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation
3. Validate AWS credentials and permissions
4. Review CloudFormation/CDK/Terraform logs for errors
5. Consult AWS support for service-specific issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow AWS best practices for security and cost optimization
3. Update documentation for any new features
4. Validate all deployment methods work correctly

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and customize according to your organization's security and compliance requirements before production use.