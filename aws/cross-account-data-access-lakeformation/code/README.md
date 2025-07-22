# Infrastructure as Code for Cross-Account Data Access with Lake Formation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Account Data Access with Lake Formation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Two AWS accounts with appropriate cross-account trust relationships
- Administrator permissions in both producer and consumer accounts
- Node.js 18+ for CDK TypeScript implementation
- Python 3.8+ for CDK Python implementation
- Terraform 1.0+ for Terraform implementation
- Basic understanding of Lake Formation concepts including LF-Tags and resource links
- Consumer account ID for cross-account sharing configuration

## Quick Start

### Using CloudFormation
```bash
# Deploy in producer account first
aws cloudformation create-stack \
    --stack-name lake-formation-producer \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ConsumerAccountId,ParameterValue=123456789012 \
    --capabilities CAPABILITY_IAM

# Wait for producer stack completion
aws cloudformation wait stack-create-complete \
    --stack-name lake-formation-producer

# Deploy consumer stack in consumer account
aws cloudformation create-stack \
    --stack-name lake-formation-consumer \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ProducerAccountId,ParameterValue=111111111111 \
    --capabilities CAPABILITY_IAM
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Configure account IDs
export CONSUMER_ACCOUNT_ID=123456789012
export PRODUCER_ACCOUNT_ID=111111111111

# Deploy producer stack
cdk deploy LakeFormationProducerStack

# Deploy consumer stack
cdk deploy LakeFormationConsumerStack
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Configure account IDs
export CONSUMER_ACCOUNT_ID=123456789012
export PRODUCER_ACCOUNT_ID=111111111111

# Deploy producer stack
cdk deploy LakeFormationProducerStack

# Deploy consumer stack
cdk deploy LakeFormationConsumerStack
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your account IDs

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export CONSUMER_ACCOUNT_ID=123456789012
export PRODUCER_ACCOUNT_ID=111111111111

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This implementation creates:

### Producer Account Resources
- **S3 Data Lake Bucket**: Central storage for financial and customer data
- **AWS Glue Data Catalog**: Databases and tables for data discovery
- **Lake Formation Configuration**: Data lake administration and governance
- **LF-Tags**: Tag-based access control taxonomy (department, classification, data-category)
- **AWS RAM Resource Share**: Cross-account sharing configuration
- **IAM Roles**: Service roles for Glue crawler operations

### Consumer Account Resources
- **Lake Formation Configuration**: Consumer-side data lake administration
- **Resource Links**: Local references to shared databases
- **Data Analyst Role**: IAM role with appropriate Lake Formation permissions
- **Cross-Account Permissions**: Tag-based access grants for finance data

### Cross-Account Integration
- **AWS RAM Invitations**: Secure resource sharing between accounts
- **Lake Formation Permissions**: Fine-grained data access controls
- **Tag-Based Access Control**: Scalable attribute-based permissions

## Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `CONSUMER_ACCOUNT_ID` | AWS account ID for data consumers | `123456789012` |
| `PRODUCER_ACCOUNT_ID` | AWS account ID for data producers | `111111111111` |
| `AWS_REGION` | AWS region for deployment | `us-east-1` |
| `DATA_LAKE_BUCKET_NAME` | Custom S3 bucket name (optional) | `my-data-lake-bucket` |

### Terraform Variables

```hcl
# terraform.tfvars
consumer_account_id = "123456789012"
producer_account_id = "111111111111"
aws_region = "us-east-1"
environment = "dev"
```

### CDK Context

```json
{
  "consumer-account-id": "123456789012",
  "producer-account-id": "111111111111",
  "environment": "dev"
}
```

## Validation & Testing

### Verify Lake Formation Setup
```bash
# Check LF-Tags creation
aws lakeformation get-lf-tag --tag-key "department"

# Verify resource tagging
aws lakeformation get-resource-lf-tags \
    --resource Database='{Name=financial_db}'

# Check cross-account permissions
aws lakeformation list-permissions \
    --principal "$CONSUMER_ACCOUNT_ID"
```

### Test Cross-Account Access
```bash
# In consumer account - test Athena query
aws athena start-query-execution \
    --query-string "SELECT department, revenue FROM shared_financial_db.financial_reports LIMIT 10" \
    --result-configuration "OutputLocation=s3://athena-results-bucket/" \
    --work-group "primary"
```

### Monitor Access Patterns
```bash
# View CloudTrail events for Lake Formation
aws logs filter-log-events \
    --log-group-name "/aws/cloudtrail" \
    --filter-pattern "{ $.eventSource = lakeformation.amazonaws.com }"
```

## Security Considerations

### Least Privilege Access
- Data analyst roles only have access to specific departments through LF-Tags
- Column-level security prevents access to sensitive financial data
- Row-level filtering based on department tags

### Cross-Account Security
- AWS RAM provides secure resource sharing without exposing credentials
- Lake Formation maintains centralized access control across accounts
- Resource links enable local access patterns while preserving original permissions

### Compliance and Auditing
- All data access is logged through CloudTrail
- Lake Formation provides detailed audit trails for permission grants
- Tag-based access control supports compliance reporting

## Troubleshooting

### Common Issues

**Resource Share Invitation Not Received**
```bash
# Check RAM invitations in consumer account
aws ram get-resource-share-invitations \
    --resource-share-arns arn:aws:ram:region:account:resource-share/share-id
```

**Permission Denied Errors**
```bash
# Verify Lake Formation permissions
aws lakeformation list-permissions \
    --resource Database='{Name=shared_financial_db}'

# Check IAM role trust relationships
aws iam get-role --role-name DataAnalystRole
```

**Crawler Not Discovering Schema**
```bash
# Check crawler status
aws glue get-crawler --name financial-reports-crawler

# View crawler logs
aws logs get-log-events \
    --log-group-name "/aws-glue/crawlers"
```

### Debug Commands

```bash
# Enable debug logging for AWS CLI
export AWS_CLI_AUTO_PROMPT=on-partial
export AWS_CLI_PAGER=""

# Test Lake Formation service availability
aws lakeformation describe-resource \
    --resource-arn "arn:aws:s3:::your-data-lake-bucket"
```

## Cost Optimization

### Resource Cleanup
- Use lifecycle policies for S3 data lake storage
- Configure Glue crawler schedules to run only when needed
- Monitor Lake Formation usage through AWS Cost Explorer

### Estimated Costs
- **S3 Storage**: $0.023/GB per month (Standard tier)
- **Glue Crawler**: $0.44 per DPU-hour
- **Athena Queries**: $5 per TB scanned
- **Lake Formation**: No additional charges

## Cleanup

### Using CloudFormation
```bash
# Delete consumer stack first
aws cloudformation delete-stack --stack-name lake-formation-consumer

# Wait for consumer stack deletion
aws cloudformation wait stack-delete-complete \
    --stack-name lake-formation-consumer

# Delete producer stack
aws cloudformation delete-stack --stack-name lake-formation-producer
```

### Using CDK
```bash
# Destroy consumer stack first
cdk destroy LakeFormationConsumerStack

# Destroy producer stack
cdk destroy LakeFormationProducerStack
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

## Advanced Configuration

### Multi-Account Organization Setup
For AWS Organizations with multiple accounts:

```bash
# Enable Lake Formation across organization
aws organizations enable-aws-service-access \
    --service-principal lakeformation.amazonaws.com

# Create organizational units for data governance
aws organizations create-organizational-unit \
    --parent-id r-xxxx \
    --name "DataLakeAccounts"
```

### Automated Tag Assignment
Implement Lambda functions for automatic LF-Tag assignment:

```python
# Example Lambda function for automatic tagging
import boto3

def lambda_handler(event, context):
    lakeformation = boto3.client('lakeformation')
    
    # Auto-tag based on S3 object metadata
    if 'finance' in event['Records'][0]['s3']['object']['key']:
        lakeformation.add_lf_tags_to_resource(
            Resource={'Table': {'DatabaseName': 'auto_db', 'Name': table_name}},
            LFTags=[{'TagKey': 'department', 'TagValues': ['finance']}]
        )
```

### Integration with CI/CD
Example GitHub Actions workflow:

```yaml
name: Deploy Lake Formation
on:
  push:
    branches: [main]
    paths: ['aws/cross-account-data-access-lake-formation/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Deploy with Terraform
        run: |
          cd aws/cross-account-data-access-lake-formation/code/terraform
          terraform init
          terraform apply -auto-approve
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **AWS Documentation**: [Lake Formation Developer Guide](https://docs.aws.amazon.com/lake-formation/latest/dg/)
3. **Cross-Account Sharing**: [Lake Formation Cross-Account Data Sharing](https://docs.aws.amazon.com/lake-formation/latest/dg/cross-account-permissions.html)
4. **AWS Support**: Create a support case for infrastructure-specific issues
5. **Community Resources**: AWS re:Post forums for community assistance

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Validate security configurations before deployment
3. Update documentation to reflect any changes
4. Follow AWS Well-Architected Framework principles
5. Ensure compatibility across all IaC implementations