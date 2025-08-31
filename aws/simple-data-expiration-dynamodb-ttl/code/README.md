# Infrastructure as Code for Data Expiration Automation with DynamoDB TTL

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Expiration Automation with DynamoDB TTL".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements automated data expiration using DynamoDB's Time-To-Live (TTL) feature. The infrastructure includes:

- DynamoDB table with composite primary key (user_id, session_id)
- TTL configuration on the `expires_at` attribute
- CloudWatch monitoring for TTL metrics
- On-demand billing mode for cost optimization

## Prerequisites

- AWS CLI installed and configured (version 2.0+)
- Appropriate AWS permissions:
  - `dynamodb:CreateTable`
  - `dynamodb:UpdateTimeToLive`
  - `dynamodb:PutItem`
  - `dynamodb:Scan`
  - `dynamodb:DescribeTimeToLive`
  - `dynamodb:DeleteTable`
  - `cloudwatch:GetMetricStatistics`
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+

**Estimated Cost**: $0.25 per month for testing workloads with on-demand pricing

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name dynamodb-ttl-demo \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=TableName,ParameterValue=session-data-demo \
                 ParameterKey=TTLAttribute,ParameterValue=expires_at \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name dynamodb-ttl-demo

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name dynamodb-ttl-demo \
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
cdk deploy

# View deployed resources
cdk ls
```

### Using CDK Python (AWS)

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
cdk deploy

# View deployed resources
cdk ls
```

### Using Terraform

```bash
# Navigate to Terraform directory
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

# View deployment status
aws dynamodb describe-table --table-name session-data-$(whoami)
```

## Testing the Deployment

After deployment, test the TTL functionality:

```bash
# Set environment variables (replace with your actual values)
export TABLE_NAME="your-table-name"
export TTL_ATTRIBUTE="expires_at"

# Insert a test item that expires in 5 minutes
CURRENT_TIME=$(date +%s)
TEST_TTL=$((CURRENT_TIME + 300))

aws dynamodb put-item \
    --table-name ${TABLE_NAME} \
    --item '{
        "user_id": {"S": "test_user"},
        "session_id": {"S": "test_session"},
        "test_data": {"S": "This will expire in 5 minutes"},
        "'${TTL_ATTRIBUTE}'": {"N": "'${TEST_TTL}'"}
    }'

# Verify TTL configuration
aws dynamodb describe-time-to-live --table-name ${TABLE_NAME}

# Query non-expired items
aws dynamodb scan \
    --table-name ${TABLE_NAME} \
    --filter-expression "#ttl > :current_time" \
    --expression-attribute-names '{"#ttl": "'${TTL_ATTRIBUTE}'"}' \
    --expression-attribute-values '{":current_time": {"N": "'${CURRENT_TIME}'"}}' \
    --output table
```

## Monitoring

Monitor TTL deletions using CloudWatch:

```bash
# View TTL deletion metrics
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")

aws cloudwatch get-metric-statistics \
    --namespace "AWS/DynamoDB" \
    --metric-name "TimeToLiveDeletedItemCount" \
    --dimensions Name=TableName,Value=${TABLE_NAME} \
    --start-time ${START_TIME} \
    --end-time ${END_TIME} \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name dynamodb-ttl-demo

# Wait for stack deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name dynamodb-ttl-demo
```

### Using CDK (AWS)

```bash
# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

## Customization

### CloudFormation Parameters

- `TableName`: Name for the DynamoDB table (default: session-data-demo)
- `TTLAttribute`: Name of the TTL attribute (default: expires_at)
- `BillingMode`: DynamoDB billing mode (default: ON_DEMAND)

### CDK Context Variables

Modify `cdk.json` or pass context variables:

```bash
cdk deploy -c tableName=my-custom-table -c ttlAttribute=my_expiry_field
```

### Terraform Variables

Edit `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
table_name = "my-session-table"
ttl_attribute = "expiration_time"
billing_mode = "ON_DEMAND"
```

### Environment-Specific Configuration

Each implementation supports environment-specific customization:

- **Development**: Lower capacity, shorter TTL values for testing
- **Staging**: Production-like configuration with monitoring
- **Production**: Optimized capacity, comprehensive monitoring, backup enabled

## Security Considerations

The generated infrastructure implements security best practices:

- **Least Privilege IAM**: Only necessary permissions granted
- **Encryption**: DynamoDB encryption at rest enabled by default
- **VPC Endpoints**: Optional VPC endpoint configuration for private access
- **Resource Tagging**: Consistent tagging for cost allocation and governance

## Troubleshooting

### Common Issues

1. **TTL Not Working**:
   - Verify TTL is enabled: `aws dynamodb describe-time-to-live --table-name TABLE_NAME`
   - Check attribute contains valid Unix timestamp
   - TTL deletions occur within 48 hours of expiration

2. **Permission Errors**:
   - Ensure AWS CLI is configured with appropriate permissions
   - Check IAM policies include required DynamoDB actions

3. **CDK Bootstrap Issues**:
   - Run `cdk bootstrap aws://ACCOUNT-NUMBER/REGION`
   - Ensure CDK CLI version matches project version

4. **Terraform State Issues**:
   - Consider using remote state backend for team environments
   - Run `terraform refresh` to sync state with actual resources

### Getting Help

- **AWS Documentation**: [DynamoDB TTL Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/TTL.html)
- **CloudFormation**: [AWS CloudFormation User Guide](https://docs.aws.amazon.com/cloudformation/)
- **CDK**: [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- **Terraform**: [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Refer to the original recipe documentation
3. Consult the provider-specific documentation links
4. Review AWS service limits and quotas for DynamoDB

## Contributing

When modifying the infrastructure code:

1. Follow the provider's best practices and naming conventions
2. Update variable descriptions and documentation
3. Test changes in a non-production environment
4. Update this README with any new configuration options or requirements