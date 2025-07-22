# Infrastructure as Code for Privacy-Preserving Analytics with Clean Rooms

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Privacy-Preserving Analytics with Clean Rooms".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- IAM permissions for Clean Rooms, QuickSight, S3, Glue, and IAM services
- QuickSight subscription (Standard or Enterprise edition)
- Basic understanding of data analytics and privacy concepts
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $50-100 for Clean Rooms collaboration, $24/month for QuickSight Standard, $5-20 for S3 and Glue usage

## Architecture Overview

This solution deploys:

- **AWS Clean Rooms**: Secure collaboration environment for privacy-preserving analytics
- **Amazon S3**: Data storage buckets for multiple organizations with encryption
- **AWS Glue**: Data catalog and ETL service for automated schema discovery
- **Amazon QuickSight**: Interactive dashboards for privacy-preserved visualizations
- **IAM Roles**: Secure access control for service interactions
- **Sample Datasets**: Synthetic customer data for demonstration purposes

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name privacy-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name privacy-analytics-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name privacy-analytics-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview deployment
cdk diff

# Deploy the stack
cdk deploy PrivacyAnalyticsStack

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

# Bootstrap CDK (first time only)
cdk bootstrap

# Preview deployment
cdk diff

# Deploy the stack
cdk deploy PrivacyAnalyticsStack

# View outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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

# The script will prompt for confirmation and display progress
# Follow the prompts to complete the deployment
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to complete these manual steps:

### 1. Configure Clean Rooms Collaboration

```bash
# Set environment variables from stack outputs
export COLLABORATION_ID=$(aws cloudformation describe-stacks \
    --stack-name privacy-analytics-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`CollaborationId`].OutputValue' \
    --output text)

# Associate configured tables with collaboration
aws cleanrooms create-configured-table-association \
    --name "org-a-association" \
    --membership-identifier "${COLLABORATION_ID}" \
    --configured-table-identifier "$(terraform output -raw org_a_table_id)" \
    --role-arn "$(terraform output -raw clean_rooms_role_arn)"
```

### 2. Execute Privacy-Preserving Queries

```bash
# Execute sample aggregation query
aws cleanrooms start-protected-query \
    --type "SQL" \
    --membership-identifier "${COLLABORATION_ID}" \
    --sql-parameters '{"queryString": "SELECT age_group, region, COUNT(*) as customer_count FROM org_a_customers GROUP BY age_group, region HAVING COUNT(*) >= 3"}' \
    --result-configuration '{"outputConfiguration": {"s3": {"resultFormat": "CSV", "bucket": "'"$(terraform output -raw results_bucket)"'", "keyPrefix": "query-results/"}}}'
```

### 3. Set Up QuickSight Dashboard

1. Navigate to the QuickSight console
2. Create a new data source pointing to the results bucket
3. Build visualizations using the privacy-preserved query results
4. Configure row-level security as needed

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Deployment environment | dev | Yes |
| OrganizationAName | Name for organization A | OrgA | No |
| OrganizationBName | Name for organization B | OrgB | No |
| EnableEncryption | Enable S3 bucket encryption | true | No |
| QuickSightEdition | QuickSight subscription edition | STANDARD | No |

### CDK Context Variables

```json
{
  "environment": "dev",
  "enableDifferentialPrivacy": true,
  "quicksightEdition": "STANDARD",
  "retentionPeriod": 30
}
```

### Terraform Variables

```hcl
# terraform.tfvars
environment = "dev"
organization_a_name = "CompanyA"
organization_b_name = "CompanyB"
enable_encryption = true
quicksight_edition = "STANDARD"
tags = {
  Project = "PrivacyAnalytics"
  Owner   = "DataTeam"
}
```

## Customization

### Adding Custom Data Sources

1. **S3 Integration**: Modify the S3 bucket policies to include additional data sources
2. **Glue Crawlers**: Update crawler configurations to include new data paths
3. **Clean Rooms Tables**: Configure additional tables with appropriate privacy settings

### Differential Privacy Configuration

Adjust privacy parameters in the Clean Rooms configuration:

```yaml
# CloudFormation example
DifferentialPrivacyConfig:
  Type: AWS::CleanRooms::ConfiguredTable
  Properties:
    AnalysisRules:
      - Type: AGGREGATION
        Policy:
          V1:
            AggregateColumns:
              - ColumnNames: ["customer_count"]
                Function: "COUNT"
            DimensionColumns: ["age_group", "region"]
            OutputColumns: ["customer_count"]
            AllowedJoinOperators: ["INNER"]
```

### Security Hardening

1. **Bucket Policies**: Restrict S3 access to specific IP ranges or VPCs
2. **IAM Conditions**: Add time-based or resource-specific access conditions
3. **KMS Encryption**: Use customer-managed KMS keys for enhanced encryption control
4. **VPC Endpoints**: Route traffic through VPC endpoints for enhanced security

## Validation and Testing

### Automated Testing

```bash
# Test S3 bucket creation and policies
aws s3api head-bucket --bucket $(terraform output -raw org_a_bucket)
aws s3api get-bucket-encryption --bucket $(terraform output -raw org_a_bucket)

# Verify Glue database and tables
aws glue get-database --name $(terraform output -raw glue_database)
aws glue get-tables --database-name $(terraform output -raw glue_database)

# Check Clean Rooms collaboration status
aws cleanrooms get-collaboration --collaboration-identifier $(terraform output -raw collaboration_id)

# Verify QuickSight data source
aws quicksight describe-data-source \
    --aws-account-id $(aws sts get-caller-identity --query Account --output text) \
    --data-source-id $(terraform output -raw quicksight_data_source_id)
```

### Manual Verification

1. **AWS Console**: Verify resources are created in the AWS Management Console
2. **QuickSight Dashboard**: Access QuickSight to confirm dashboard functionality
3. **Clean Rooms Queries**: Execute test queries to validate privacy protections
4. **Data Lineage**: Verify data flow from S3 through Glue to Clean Rooms

## Monitoring and Logging

### CloudWatch Integration

The deployment includes CloudWatch logging for:

- Clean Rooms query execution logs
- Glue crawler run logs
- S3 access logs
- QuickSight usage metrics

### Cost Monitoring

```bash
# Set up billing alerts
aws budgets create-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget file://budget-config.json
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name privacy-analytics-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name privacy-analytics-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy PrivacyAnalyticsStack

# Confirm when prompted
```

### Using Terraform

```bash
cd terraform/

# Plan the destruction
terraform plan -destroy

# Destroy the infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

### Manual Cleanup Steps

Some resources may require manual cleanup:

1. **QuickSight Resources**: Delete analyses, datasets, and data sources
2. **S3 Objects**: Remove any remaining objects in S3 buckets
3. **Clean Rooms Data**: Ensure all query results are properly archived or deleted

## Troubleshooting

### Common Issues

**Issue**: Clean Rooms collaboration creation fails
**Solution**: Verify IAM permissions and ensure QuickSight is properly set up

**Issue**: Glue crawlers not discovering schemas
**Solution**: Check S3 bucket permissions and data file formats

**Issue**: QuickSight data source connection fails
**Solution**: Verify S3 bucket policies and QuickSight service role permissions

**Issue**: Query results show insufficient data
**Solution**: Check differential privacy thresholds and aggregation rules

### Debug Commands

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name privacy-analytics-stack

# View CDK deployment logs
cdk diff --verbose

# Terraform debug mode
TF_LOG=DEBUG terraform apply

# Clean Rooms query debugging
aws cleanrooms list-protected-queries --membership-identifier $COLLABORATION_ID
```

## Security Considerations

### Data Privacy

- All data is encrypted at rest using AES-256
- Differential privacy protections prevent individual identification
- Query results are filtered to meet minimum threshold requirements
- Access logs track all data access patterns

### Access Control

- IAM roles follow least privilege principle
- Clean Rooms enforces collaboration boundaries
- QuickSight implements row-level security
- All API calls are logged to CloudTrail

### Compliance

This solution supports compliance with:

- GDPR (General Data Protection Regulation)
- CCPA (California Consumer Privacy Act)
- HIPAA (Health Insurance Portability and Accountability Act)
- SOX (Sarbanes-Oxley Act)

## Support and Resources

### Documentation Links

- [AWS Clean Rooms User Guide](https://docs.aws.amazon.com/clean-rooms/latest/userguide/)
- [Amazon QuickSight User Guide](https://docs.aws.amazon.com/quicksight/latest/user/)
- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/latest/dg/)
- [Differential Privacy in Clean Rooms](https://docs.aws.amazon.com/clean-rooms/latest/userguide/differential-privacy.html)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review AWS service documentation
3. Consult the original recipe documentation
4. Contact AWS Support for service-specific issues

### Contributing

To improve this IaC implementation:

1. Follow AWS best practices
2. Update documentation for any changes
3. Test thoroughly before submitting updates
4. Consider backward compatibility