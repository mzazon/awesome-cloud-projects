# Infrastructure as Code for Data Catalog Governance with AWS Glue

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Catalog Governance with AWS Glue".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Glue (Data Catalog, Crawlers, Classifiers)
  - AWS Lake Formation (Data Lake settings, Resource registration)
  - AWS CloudTrail (Trail creation and configuration)
  - AWS CloudWatch (Dashboard creation)
  - AWS IAM (Role and policy management)
  - Amazon S3 (Bucket creation and management)
- Basic understanding of data governance concepts
- Estimated cost: $20-40 for running crawlers, classifiers, and storing audit logs

## Quick Start

### Using CloudFormation
```bash
# Create the stack
aws cloudformation create-stack \
    --stack-name data-catalog-governance-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=dev \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name data-catalog-governance-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name data-catalog-governance-stack \
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
cdk deploy DataCatalogGovernanceStack

# View outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy DataCatalogGovernanceStack

# View outputs
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
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

# View deployment status
echo "Check AWS Console for resource creation status"
```

## Architecture Components

The infrastructure deployment includes:

- **AWS Glue Data Catalog**: Central metadata repository
- **AWS Glue Crawler**: Automated schema discovery and PII classification
- **AWS Glue Classifier**: Custom PII detection classifier
- **AWS Lake Formation**: Fine-grained access control and data governance
- **AWS CloudTrail**: Comprehensive audit logging
- **AWS CloudWatch**: Monitoring dashboard and metrics
- **Amazon S3**: Data storage and audit log storage
- **AWS IAM**: Security roles and policies

## Configuration Options

### Environment Variables
All implementations support these environment variables:

- `AWS_REGION`: Target AWS region (default: us-east-1)
- `ENVIRONMENT`: Environment tag (dev/staging/prod)
- `PROJECT_NAME`: Project identifier for resource naming

### CloudFormation Parameters
- `Environment`: Environment name (dev/staging/prod)
- `ProjectName`: Project identifier
- `DataBucketName`: S3 bucket name for data storage
- `AuditBucketName`: S3 bucket name for audit logs

### Terraform Variables
- `region`: AWS region
- `environment`: Environment tag
- `project_name`: Project identifier
- `data_bucket_name`: S3 bucket for data
- `audit_bucket_name`: S3 bucket for audit logs
- `crawler_schedule`: Crawler execution schedule

### CDK Context
- `environment`: Environment configuration
- `project_name`: Project identifier
- `enable_monitoring`: Enable CloudWatch monitoring

## Post-Deployment Steps

1. **Upload Sample Data**:
   ```bash
   # Upload sample CSV with PII data
   aws s3 cp sample_data.csv s3://your-data-bucket/data/
   ```

2. **Run Initial Crawler**:
   ```bash
   # Start the crawler to discover data
   aws glue start-crawler --name governance-crawler
   ```

3. **Configure Lake Formation**:
   ```bash
   # Register S3 location with Lake Formation
   aws lakeformation register-resource \
       --resource-arn arn:aws:s3:::your-data-bucket/data/ \
       --use-service-linked-role
   ```

4. **Verify Data Classification**:
   ```bash
   # Check table metadata for PII classification
   aws glue get-table \
       --database-name governance_catalog \
       --name your_table_name
   ```

## Monitoring and Validation

### CloudWatch Dashboard
Access the created dashboard to monitor:
- Crawler execution metrics
- PII detection events
- Data access patterns
- System health indicators

### CloudTrail Logs
Review audit logs for:
- Data Catalog access events
- Lake Formation permission changes
- Administrative actions
- Security-related activities

### Lake Formation Permissions
Verify access controls:
```bash
# List current permissions
aws lakeformation list-permissions \
    --resource Table='{DatabaseName=governance_catalog,Name=your_table}'
```

## Security Considerations

- All IAM roles follow least privilege principle
- S3 buckets have encryption enabled by default
- CloudTrail logs are encrypted and have log file validation
- Lake Formation provides fine-grained access controls
- PII data is automatically classified and protected

## Troubleshooting

### Common Issues

1. **Crawler Fails to Start**:
   - Verify IAM role has necessary S3 permissions
   - Check S3 bucket exists and is accessible
   - Ensure Data Catalog database exists

2. **PII Classification Not Working**:
   - Verify classifier is properly configured
   - Check data format matches classifier expectations
   - Review CloudWatch logs for classifier errors

3. **Lake Formation Access Denied**:
   - Verify resource registration with Lake Formation
   - Check IAM permissions for Lake Formation
   - Review permission grants for affected principals

### Support Resources
- [AWS Glue Documentation](https://docs.aws.amazon.com/glue/)
- [Lake Formation Best Practices](https://docs.aws.amazon.com/lake-formation/latest/dg/best-practices.html)
- [CloudTrail User Guide](https://docs.aws.amazon.com/cloudtrail/latest/userguide/)

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name data-catalog-governance-stack

# Wait for completion
aws cloudformation wait stack-delete-complete \
    --stack-name data-catalog-governance-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy DataCatalogGovernanceStack

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

## Customization

### Adding Custom Classifiers
To add custom data classifiers:

1. **CloudFormation**: Add classifier resources in the template
2. **CDK**: Extend the classifier construct with new patterns
3. **Terraform**: Add classifier resources to main.tf
4. **Bash**: Add classifier creation commands to deploy.sh

### Extending Access Controls
To implement additional access controls:

1. Create new IAM roles for different user types
2. Configure Lake Formation permissions for new roles
3. Add CloudTrail event selectors for new resources
4. Update monitoring dashboard for new metrics

### Multi-Account Setup
For cross-account data sharing:

1. Configure Lake Formation cross-account access
2. Set up resource sharing with AWS RAM
3. Implement cross-account CloudTrail logging
4. Configure centralized monitoring

## Cost Optimization

- Crawler runs can be scheduled to minimize costs
- S3 storage classes can be optimized for audit logs
- CloudWatch log retention can be configured
- Unused classifiers and crawlers should be removed

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service documentation
3. Verify IAM permissions and resource configurations
4. Review CloudWatch and CloudTrail logs for error details

## Version History

- v1.0: Initial implementation with basic governance features
- v1.1: Added enhanced PII detection and monitoring
- v1.2: Improved security controls and audit capabilities