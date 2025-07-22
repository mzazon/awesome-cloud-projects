# Infrastructure as Code for Archiving Data with S3 Intelligent Tiering

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Archiving Data with S3 Intelligent Tiering".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - S3 bucket creation and configuration
  - IAM role creation and policy attachment
  - Lambda function deployment
  - CloudWatch dashboard creation
  - EventBridge rule management
  - S3 Storage Lens configuration
- For CDK: Node.js (TypeScript) or Python 3.7+ (Python)
- For Terraform: Terraform >= 1.0
- Estimated cost: $5-20/month depending on storage volume and monitoring frequency

> **Note**: S3 Intelligent-Tiering has monitoring charges of $0.0025 per 1,000 objects. Evaluate this cost against potential savings for your specific use case.

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete sustainable archiving infrastructure
aws cloudformation create-stack \
    --stack-name sustainable-archive-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=production

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name sustainable-archive-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy SustainableArchiveStack

# View outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy SustainableArchiveStack

# View outputs
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="environment_name=production" \
    -var="aws_region=us-east-1"

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts and monitor the deployment
```

## Architecture Components

This IaC deployment creates:

- **S3 Bucket**: Main archive bucket with versioning and sustainability tagging
- **Intelligent-Tiering Configuration**: Automatic cost optimization across all storage tiers
- **Lifecycle Policies**: Comprehensive data lifecycle management for sustainability
- **S3 Storage Lens**: Advanced analytics for storage optimization tracking
- **Lambda Function**: Sustainability monitoring with carbon footprint calculations
- **IAM Roles**: Least-privilege security for automated monitoring
- **CloudWatch Dashboard**: Executive-level sustainability reporting
- **EventBridge Rules**: Automated daily sustainability analysis

## Configuration Options

### Environment Variables (Bash Scripts)
```bash
export AWS_REGION="us-east-1"
export ENVIRONMENT_NAME="production"
export ENABLE_DEEP_ARCHIVE="true"
export MONITORING_FREQUENCY="daily"
```

### CloudFormation Parameters
- `EnvironmentName`: Environment identifier (default: production)
- `EnableDeepArchive`: Enable deep archive tiers (default: true)
- `MonitoringSchedule`: CloudWatch monitoring frequency (default: rate(1 day))
- `SustainabilityGoal`: Organization sustainability target (default: CarbonNeutral)

### CDK Context Variables
```json
{
  "environmentName": "production",
  "enableDeepArchive": true,
  "monitoringSchedule": "rate(1 day)",
  "sustainabilityGoal": "CarbonNeutral"
}
```

### Terraform Variables
```hcl
variable "environment_name" {
  description = "Environment identifier"
  type        = string
  default     = "production"
}

variable "enable_deep_archive" {
  description = "Enable deep archive access tiers"
  type        = bool
  default     = true
}

variable "monitoring_schedule" {
  description = "EventBridge schedule for monitoring"
  type        = string
  default     = "rate(1 day)"
}
```

## Post-Deployment Validation

After deployment, verify the solution is working correctly:

```bash
# Check bucket intelligent-tiering configuration
aws s3api list-bucket-intelligent-tiering-configurations \
    --bucket $(terraform output -raw archive_bucket_name)

# Verify Lambda function deployment
aws lambda get-function \
    --function-name $(terraform output -raw lambda_function_name)

# Test sustainability monitoring
aws lambda invoke \
    --function-name $(terraform output -raw lambda_function_name) \
    --payload '{}' \
    test-response.json

# View CloudWatch dashboard
echo "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=SustainableArchive"
```

## Monitoring and Maintenance

### CloudWatch Metrics
Monitor these key sustainability metrics:
- `SustainableArchive/TotalStorageGB`: Total storage usage
- `SustainableArchive/EstimatedMonthlyCarbonKg`: Environmental impact
- `SustainableArchive/CarbonReductionPercentage`: Optimization progress

### Storage Lens Reports
Access detailed analytics at:
```bash
aws s3control get-storage-lens-configuration \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --config-id SustainabilityMetrics
```

### Cost Optimization Tracking
Review monthly costs and optimization opportunities:
- S3 Intelligent-Tiering savings reports
- Storage class distribution analysis
- Carbon footprint reduction trends

## Cleanup

### Using CloudFormation
```bash
# Empty S3 buckets before stack deletion
aws s3 rm s3://$(aws cloudformation describe-stacks \
    --stack-name sustainable-archive-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ArchiveBucketName`].OutputValue' \
    --output text) --recursive

# Delete the stack
aws cloudformation delete-stack \
    --stack-name sustainable-archive-stack

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name sustainable-archive-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy SustainableArchiveStack

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Customization

### Adding Custom Storage Policies
Modify the lifecycle policies to match your data retention requirements:

```yaml
# CloudFormation example
LifecycleRule:
  Id: CustomRetentionPolicy
  Status: Enabled
  Transitions:
    - Days: 30
      StorageClass: GLACIER
    - Days: 365
      StorageClass: DEEP_ARCHIVE
```

### Extending Sustainability Monitoring
Add custom metrics to the Lambda function for additional sustainability tracking:

```python
# Custom carbon calculation for specific data types
def calculate_industry_specific_carbon(data_type, size_gb):
    # Industry-specific carbon calculations
    carbon_factors = {
        'financial': 0.000420,  # Higher compliance requirements
        'healthcare': 0.000380,  # HIPAA considerations
        'media': 0.000350       # Large file optimizations
    }
    return size_gb * carbon_factors.get(data_type, 0.000385)
```

### Multi-Region Deployment
For global sustainability optimization, deploy across multiple regions:

```bash
# Deploy to additional regions
export AWS_REGION="eu-west-1"
terraform apply -var="aws_region=eu-west-1"
```

## Troubleshooting

### Common Issues

1. **Intelligent-Tiering Not Activating**
   - Verify bucket has objects (minimum 1KB)
   - Check IAM permissions for S3 service
   - Wait 24-48 hours for initial transitions

2. **Lambda Function Errors**
   - Check CloudWatch Logs for detailed errors
   - Verify IAM role has required permissions
   - Ensure bucket exists and is accessible

3. **Storage Lens Configuration Failures**
   - Confirm account-level permissions
   - Verify analytics bucket permissions
   - Check region compatibility

### Support Resources

- [AWS S3 Intelligent-Tiering Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering.html)
- [AWS Storage Lens User Guide](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage_lens.html)
- [AWS Sustainability Best Practices](https://docs.aws.amazon.com/whitepapers/latest/architecture-sustainability-whitepaper/architecture-sustainability-whitepaper.html)

## Security Considerations

This implementation follows AWS security best practices:

- **Least Privilege IAM**: Lambda functions have minimal required permissions
- **Bucket Security**: Default encryption and versioning enabled
- **Access Logging**: CloudTrail integration for audit trails
- **Network Security**: VPC endpoints for private communication (if configured)

## Cost Optimization

Expected cost breakdown:
- S3 Intelligent-Tiering monitoring: $0.0025 per 1,000 objects/month
- Lambda execution: ~$0.20/month for daily monitoring
- CloudWatch metrics: ~$0.30/month for custom metrics
- Storage Lens: Free tier for basic metrics
- Potential savings: 20-80% on storage costs depending on access patterns

## Contributing

To extend this infrastructure:

1. Follow the original recipe's architecture patterns
2. Test changes in a development environment
3. Validate sustainability calculations
4. Update documentation and examples
5. Submit pull requests with detailed descriptions

For issues with this infrastructure code, refer to the original recipe documentation or AWS service documentation.