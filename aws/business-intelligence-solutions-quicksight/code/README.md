# Infrastructure as Code for Business Intelligence Solutions with QuickSight

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Business Intelligence Solutions with QuickSight".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- QuickSight service enabled in your AWS account (must be done via AWS Console)
- Appropriate AWS permissions for:
  - QuickSight service management
  - S3 bucket creation and management
  - RDS instance creation (optional for complete demo)
  - IAM role creation and management
- For CDK implementations: Node.js 16+ or Python 3.8+
- For Terraform: Terraform v1.0+

> **Important**: QuickSight must be enabled manually via the AWS Console before running any IaC deployment. Navigate to https://quicksight.aws.amazon.com/ and complete the service setup.

## Cost Considerations

- QuickSight Standard Edition: $24/month for first 4 users, then $5/session
- S3 storage: ~$0.023/GB per month for sample data
- RDS t3.micro instance: ~$12-15/month (optional component)
- Data transfer costs may apply for cross-region usage

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name quicksight-bi-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name quicksight-bi-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name quicksight-bi-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# View outputs
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

# The script will prompt for required parameters
# and create all necessary resources
```

## Post-Deployment Configuration

After successful deployment, complete these manual steps:

1. **Access QuickSight Console**:
   ```bash
   echo "QuickSight Console: https://quicksight.aws.amazon.com/"
   ```

2. **Create Data Source Connection** (if not automated):
   - Navigate to QuickSight console
   - Go to "Manage QuickSight" → "Data sources"
   - Add S3 data source using the created bucket

3. **Build Sample Dashboard**:
   - Create new analysis from the S3 dataset
   - Add visualizations (bar charts, pie charts, line graphs)
   - Publish as dashboard for sharing

4. **Configure User Access**:
   - Invite additional users if needed
   - Set up appropriate permissions
   - Configure row-level security if required

## Architecture Components

The infrastructure deploys the following components:

### Core Resources
- **S3 Bucket**: Data storage for CSV files and data lake
- **IAM Roles**: QuickSight service permissions for S3 access
- **Sample Data**: Pre-loaded sales analytics data

### Optional Components
- **RDS MySQL Instance**: Relational database for operational data
- **VPC & Security Groups**: Network isolation for RDS
- **CloudWatch Logs**: Monitoring and logging

### QuickSight Resources
- **Data Sources**: Connections to S3 and RDS
- **Datasets**: SPICE-optimized data models
- **Refresh Schedules**: Automated data updates

## Customization

### Environment Variables
Most implementations support these customization options:

```bash
# Set custom environment
export ENVIRONMENT=prod
export AWS_REGION=us-west-2

# Custom resource naming
export PROJECT_NAME=my-bi-solution
export BUCKET_SUFFIX=unique-identifier

# RDS configuration (optional)
export ENABLE_RDS=true
export DB_INSTANCE_CLASS=db.t3.small
```

### Configuration Files
Each implementation includes variables/parameters for:

- **Region**: AWS region for deployment
- **Environment**: Environment tag (dev/staging/prod)
- **Bucket Name**: S3 bucket name (must be globally unique)
- **RDS Settings**: Database instance configuration
- **QuickSight Settings**: User and permission configuration

### Data Sources
To add custom data sources:

1. **Upload Data to S3**:
   ```bash
   aws s3 cp your-data.csv s3://your-bucket-name/data/
   ```

2. **Update Dataset Schema**: Modify the dataset configuration in your chosen IaC tool

3. **Refresh QuickSight**: Trigger dataset refresh after data upload

## Monitoring and Maintenance

### Health Checks
```bash
# Check S3 bucket status
aws s3 ls s3://your-bucket-name/

# Verify QuickSight data source
aws quicksight list-data-sources \
    --aws-account-id $(aws sts get-caller-identity --query Account --output text)

# Check RDS instance status (if deployed)
aws rds describe-db-instances \
    --query 'DBInstances[?DBInstanceIdentifier==`your-db-identifier`].DBInstanceStatus'
```

### Data Refresh
```bash
# Trigger manual dataset refresh
aws quicksight create-ingestion \
    --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
    --data-set-id your-dataset-id \
    --ingestion-id manual-refresh-$(date +%Y%m%d%H%M%S)
```

### Backup and Recovery
- S3 data is automatically replicated within the region
- Enable S3 versioning for data protection
- RDS automated backups are enabled by default
- Export QuickSight dashboards as templates for backup

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name quicksight-bi-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name quicksight-bi-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
cdk destroy --force
```

### Using CDK Python
```bash
cd cdk-python/
cdk destroy --force
```

### Using Terraform
```bash
cd terraform/
terraform destroy -auto-approve
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup
Some resources may require manual cleanup:

1. **QuickSight Resources**:
   - Delete dashboards and analyses from QuickSight console
   - Remove data sources and datasets
   - Cancel QuickSight subscription if no longer needed

2. **S3 Bucket Versions** (if versioning enabled):
   ```bash
   aws s3api delete-objects \
       --bucket your-bucket-name \
       --delete "$(aws s3api list-object-versions \
           --bucket your-bucket-name \
           --query '{Objects: [Versions[].{Key: Key, VersionId: VersionId}]}')"
   ```

## Troubleshooting

### Common Issues

1. **QuickSight Not Enabled**:
   - Error: "QuickSight service is not enabled"
   - Solution: Enable QuickSight manually via AWS Console

2. **S3 Access Denied**:
   - Error: "Access Denied" when accessing S3 data
   - Solution: Verify IAM role permissions and bucket policies

3. **RDS Connection Issues**:
   - Error: Cannot connect to RDS instance
   - Solution: Check security group rules and VPC configuration

4. **Dataset Refresh Failures**:
   - Error: SPICE refresh fails
   - Solution: Verify data source connectivity and data format

### Debug Commands
```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify QuickSight permissions
aws quicksight describe-user \
    --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
    --namespace default \
    --user-name your-username

# Test S3 bucket access
aws s3 ls s3://your-bucket-name/ --recursive

# Check CloudFormation events
aws cloudformation describe-stack-events \
    --stack-name quicksight-bi-stack \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

## Security Best Practices

- **IAM Roles**: Uses least privilege principle for QuickSight access
- **S3 Bucket Policy**: Restricts access to QuickSight service
- **RDS Security**: Database deployed in private subnets with security groups
- **Encryption**: S3 server-side encryption enabled by default
- **VPC**: Network isolation for database components
- **Access Logging**: CloudTrail integration for audit trails

## Performance Optimization

- **SPICE Engine**: Automatically optimizes query performance
- **Data Compression**: Use Parquet format for large datasets
- **Incremental Refresh**: Configure for large, frequently updated datasets
- **Query Optimization**: Design datasets with appropriate granularity
- **Caching**: Leverage QuickSight's built-in caching mechanisms

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **AWS Documentation**: [QuickSight User Guide](https://docs.aws.amazon.com/quicksight/)
3. **Service Limits**: [QuickSight Quotas](https://docs.aws.amazon.com/quicksight/latest/user/quotas.html)
4. **Pricing Information**: [QuickSight Pricing](https://aws.amazon.com/quicksight/pricing/)
5. **Community Support**: AWS re:Post and Stack Overflow

## Contributing

To improve these IaC implementations:

1. Follow AWS best practices for your changes
2. Test deployments in a development environment
3. Update documentation for any new features
4. Ensure backward compatibility when possible
5. Add appropriate tags and comments to resources