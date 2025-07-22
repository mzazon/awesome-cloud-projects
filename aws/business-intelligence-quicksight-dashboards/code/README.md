# Infrastructure as Code for Business Intelligence Dashboards with QuickSight

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Business Intelligence Dashboards with QuickSight".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon QuickSight (admin access for account setup)
  - Amazon S3 (bucket creation and object management)
  - AWS IAM (role and policy management)
  - Amazon RDS (if using database data sources)
- QuickSight account setup (may require manual initial configuration)
- Basic understanding of business intelligence and data visualization concepts

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions

#### CDK TypeScript
- Node.js 18+ and npm
- AWS CDK CLI: `npm install -g aws-cdk`

#### CDK Python
- Python 3.8+ and pip
- AWS CDK CLI: `pip install aws-cdk-lib`

#### Terraform
- Terraform 1.0+ installed
- AWS Provider 5.0+ will be automatically downloaded

## Estimated Costs

- **QuickSight**: Standard Edition $9/month per user, Enterprise Edition $18/month per user plus $250/month account fee
- **S3 Storage**: ~$0.50/month for sample data
- **RDS**: ~$15-50/month depending on instance size (if used)
- **IAM Roles**: No additional cost

> **Note**: QuickSight offers a 30-day free trial with up to 4 users for testing purposes.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name quicksight-bi-dashboards \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=S3BucketName,ParameterValue=quicksight-data-$(date +%s) \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name quicksight-bi-dashboards

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name quicksight-bi-dashboards \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the interactive prompts for QuickSight setup
```

## Post-Deployment Setup

### QuickSight Account Configuration

After deploying the infrastructure, you'll need to complete QuickSight setup:

1. **Initial Account Setup**:
   ```bash
   # Visit QuickSight console for first-time setup
   echo "Visit: https://quicksight.aws.amazon.com"
   echo "Choose Standard or Enterprise edition"
   echo "Configure account name and notification email"
   ```

2. **Data Source Connection**:
   ```bash
   # The IAM role for QuickSight will be created automatically
   # S3 bucket with sample data will be available
   # Connect QuickSight to the S3 data source through the console
   ```

3. **User Management**:
   ```bash
   # Add users through QuickSight console
   # Assign appropriate roles (Admin, Author, Reader)
   # Configure sharing permissions
   ```

### Sample Data

The deployment creates sample sales data in S3:

```csv
date,region,product,sales_amount,quantity
2024-01-01,North,Widget A,1200,10
2024-01-01,South,Widget B,800,8
2024-01-02,North,Widget A,1400,12
...
```

## Configuration Options

### Variables and Parameters

All implementations support these customizable values:

- **Region**: AWS region for deployment (default: us-east-1)
- **S3 Bucket Name**: Name for the data storage bucket
- **QuickSight User Email**: Email for QuickSight user creation
- **Environment**: Environment tag for resources (dev/staging/prod)

### CloudFormation Parameters
```yaml
Parameters:
  S3BucketName:
    Type: String
    Description: Name for the S3 bucket storing dashboard data
  
  Environment:
    Type: String
    Default: dev
    AllowedValues: [dev, staging, prod]
```

### Terraform Variables
```hcl
variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket storing dashboard data"
  type        = string
}
```

## Validation and Testing

### Verify Deployment
```bash
# Check S3 bucket and sample data
aws s3 ls s3://your-bucket-name/

# Verify IAM role creation
aws iam get-role --role-name QuickSight-DataSource-Role

# Check QuickSight account status
aws quicksight describe-account-settings \
    --aws-account-id $(aws sts get-caller-identity --query Account --output text)
```

### Test Dashboard Functionality
```bash
# List QuickSight data sources
aws quicksight list-data-sources \
    --aws-account-id $(aws sts get-caller-identity --query Account --output text)

# List dashboards
aws quicksight list-dashboards \
    --aws-account-id $(aws sts get-caller-identity --query Account --output text)
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack (will remove all resources)
aws cloudformation delete-stack \
    --stack-name quicksight-bi-dashboards

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name quicksight-bi-dashboards
```

### Using CDK
```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
cdk destroy --force

# Deactivate virtual environment (Python only)
deactivate
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy -auto-approve

# Clean up state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (QuickSight Account)

> **Important**: QuickSight account deletion may need to be done manually through the AWS Console if you no longer need QuickSight services.

```bash
# Cancel QuickSight subscription (if needed)
echo "Visit: https://quicksight.aws.amazon.com/sn/admin"
echo "Go to Manage QuickSight > Account settings > Unsubscribe"
```

## Troubleshooting

### Common Issues

1. **QuickSight Account Not Set Up**:
   ```bash
   # Error: QuickSight account doesn't exist
   # Solution: Visit QuickSight console to set up account first
   echo "Visit: https://quicksight.aws.amazon.com"
   ```

2. **S3 Permissions Issues**:
   ```bash
   # Verify IAM role has S3 access
   aws iam list-attached-role-policies \
       --role-name QuickSight-DataSource-Role
   ```

3. **Region Compatibility**:
   ```bash
   # QuickSight is not available in all regions
   # Supported regions: us-east-1, us-west-2, eu-west-1, ap-southeast-1, ap-southeast-2, ap-south-1
   ```

4. **Cost Concerns**:
   ```bash
   # Monitor QuickSight usage and costs
   aws quicksight list-users \
       --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
       --namespace default
   ```

### Logs and Monitoring

```bash
# CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name quicksight-bi-dashboards

# CloudTrail for QuickSight API calls
aws logs filter-log-events \
    --log-group-name CloudTrail/QuickSightAPIHistory \
    --start-time $(date -d '1 hour ago' +%s)000
```

## Advanced Configuration

### Enterprise Features

For QuickSight Enterprise edition:

```bash
# Enable additional security features
# - Row-level security
# - Private VPC connections
# - SAML/SSO integration
# - Enhanced monitoring and auditing
```

### Custom Data Sources

Add additional data sources:

```bash
# RDS/Redshift connections
# Athena for S3 data lake queries
# Third-party database connectors
# Real-time streaming data sources
```

### Embedding and APIs

```bash
# Embed dashboards in web applications
# Use QuickSight SDK for programmatic access
# Configure custom domains
# Set up automated report delivery
```

## Security Considerations

- IAM roles follow least privilege principles
- S3 buckets use server-side encryption
- QuickSight data sources use secure connections
- User access is role-based with appropriate permissions
- All resources are tagged for governance and cost tracking

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../business-intelligence-dashboards-quicksight.md)
2. Review [AWS QuickSight documentation](https://docs.aws.amazon.com/quicksight/)
3. Consult [AWS CloudFormation documentation](https://docs.aws.amazon.com/cloudformation/)
4. Reference [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
5. Check [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Additional Resources

- [QuickSight User Guide](https://docs.aws.amazon.com/quicksight/latest/user/)
- [QuickSight API Reference](https://docs.aws.amazon.com/quicksight/latest/APIReference/)
- [AWS BI/Analytics Services](https://aws.amazon.com/big-data/datalakes-and-analytics/)
- [QuickSight Pricing](https://aws.amazon.com/quicksight/pricing/)
- [QuickSight Best Practices](https://docs.aws.amazon.com/quicksight/latest/user/best-practices.html)