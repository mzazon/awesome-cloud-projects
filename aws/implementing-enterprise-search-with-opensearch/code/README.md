# Infrastructure as Code for Implementing Enterprise Search with OpenSearch Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Enterprise Search with OpenSearch Service".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - OpenSearch Service (create/manage domains)
  - Lambda (create/manage functions)
  - S3 (create/manage buckets)
  - IAM (create/manage roles and policies)
  - CloudWatch (create/manage log groups, dashboards, alarms)
  - CloudFormation/CDK (for stack operations)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $200-500/month for production-ready environment

## Architecture Overview

This solution deploys:
- Multi-AZ OpenSearch Service domain with dedicated master nodes
- Lambda function for automated data indexing
- S3 bucket for data storage
- CloudWatch monitoring and alerting
- IAM roles with least privilege access
- Machine learning capabilities for search analytics

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name opensearch-search-solution \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DomainName,ParameterValue=search-demo-$(date +%s) \
                 ParameterKey=InstanceType,ParameterValue=m6g.large.search \
                 ParameterKey=MasterInstanceType,ParameterValue=m6g.medium.search \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name opensearch-search-solution \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name opensearch-search-solution \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Review the changes
cdk diff

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
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

# Bootstrap CDK (first time only)
cdk bootstrap

# Review the changes
cdk diff

# Deploy the stack
cdk deploy --require-approval never

# Get stack outputs
cdk ls --long
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="domain_name=search-demo-$(date +%s)"

# Apply the configuration
terraform apply -var="domain_name=search-demo-$(date +%s)" -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the solution
./scripts/deploy.sh

# Check deployment status
aws opensearch describe-domain --domain-name $(cat .env | grep DOMAIN_NAME | cut -d'=' -f2)
```

## Post-Deployment Configuration

After deployment, you'll need to:

1. **Update admin password** (default is temporary):
   ```bash
   # Using AWS CLI to update master user password
   aws opensearch update-domain-config \
       --domain-name YOUR_DOMAIN_NAME \
       --advanced-security-options Enabled=true,InternalUserDatabaseEnabled=true,MasterUserOptions='{MasterUserName=admin,MasterUserPassword=YourNewSecurePassword123!}'
   ```

2. **Index sample data**:
   ```bash
   # Get domain endpoint
   DOMAIN_ENDPOINT=$(aws opensearch describe-domain --domain-name YOUR_DOMAIN_NAME --query 'DomainStatus.Endpoint' --output text)
   
   # Create index with sample data
   curl -X PUT "https://${DOMAIN_ENDPOINT}/products" \
       -H "Content-Type: application/json" \
       -u admin:YourNewPassword \
       -d @sample-data.json
   ```

3. **Configure monitoring**:
   - Check CloudWatch dashboard: `OpenSearch-${DOMAIN_NAME}-Dashboard`
   - Verify alarms are active
   - Review log groups for any issues

## Validation

Verify your deployment with these commands:

```bash
# Check domain status
aws opensearch describe-domain --domain-name YOUR_DOMAIN_NAME

# Test search functionality
DOMAIN_ENDPOINT=$(aws opensearch describe-domain --domain-name YOUR_DOMAIN_NAME --query 'DomainStatus.Endpoint' --output text)
curl -X GET "https://${DOMAIN_ENDPOINT}/_cluster/health" -u admin:YourPassword

# Verify Lambda function
aws lambda get-function --function-name YOUR_LAMBDA_FUNCTION_NAME

# Check CloudWatch dashboard
aws cloudwatch get-dashboard --dashboard-name "OpenSearch-YOUR_DOMAIN_NAME-Dashboard"
```

## Customization

### Key Variables/Parameters

| Parameter | Description | Default | Type |
|-----------|-------------|---------|------|
| `domain_name` | OpenSearch domain name | `search-demo-${random}` | string |
| `instance_type` | Instance type for data nodes | `m6g.large.search` | string |
| `master_instance_type` | Instance type for master nodes | `m6g.medium.search` | string |
| `instance_count` | Number of data nodes | `3` | number |
| `ebs_volume_size` | EBS volume size in GB | `100` | number |
| `enable_ultrawarm` | Enable UltraWarm storage | `false` | boolean |
| `master_username` | Admin username | `admin` | string |
| `log_retention_days` | CloudWatch log retention | `14` | number |

### Environment-Specific Configurations

For production environments, consider:

- Increase instance sizes and counts
- Enable UltraWarm for cost optimization
- Configure VPC deployment for security
- Set up cross-region replication
- Implement fine-grained access control
- Enable audit logging

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name opensearch-search-solution

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name opensearch-search-solution
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
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Domain creation timeout**: OpenSearch domains can take 20-30 minutes to create
2. **Access denied errors**: Ensure your AWS credentials have sufficient permissions
3. **VPC configuration issues**: Check security groups and subnet configurations
4. **Certificate errors**: Verify TLS settings and certificate authority

### Debug Commands

```bash
# Check domain configuration
aws opensearch describe-domain-config --domain-name YOUR_DOMAIN_NAME

# Review CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/opensearch"

# Check Lambda function logs
aws logs describe-log-streams --log-group-name "/aws/lambda/YOUR_FUNCTION_NAME"

# Verify IAM role permissions
aws iam get-role --role-name YOUR_OPENSEARCH_ROLE
```

## Security Considerations

- All data is encrypted at rest and in transit
- Fine-grained access control is enabled
- Network isolation can be configured via VPC
- Regular security updates are applied automatically
- Audit logging is available through CloudWatch

## Cost Optimization

- Use appropriate instance types for your workload
- Enable UltraWarm for infrequently accessed data
- Configure index lifecycle policies
- Monitor usage with CloudWatch metrics
- Consider Reserved Instances for predictable workloads

## Monitoring and Alerting

The solution includes:
- CloudWatch dashboard with key metrics
- Automated alerts for high latency and errors
- Slow query logging
- Cluster health monitoring
- Performance insights

## Advanced Features

This implementation supports:
- Machine learning for anomaly detection
- Semantic search capabilities
- Real-time analytics
- Cross-cluster search
- Index rollups and transforms
- SQL query support

## Support

For issues with this infrastructure code:
1. Review the [original recipe documentation](../search-solutions-amazon-opensearch-service.md)
2. Check [AWS OpenSearch Service documentation](https://docs.aws.amazon.com/opensearch-service/)
3. Review CloudWatch logs for detailed error messages
4. Consult the [OpenSearch documentation](https://opensearch.org/docs/)

## Contributing

When modifying this infrastructure:
1. Test changes in a development environment
2. Update documentation for any new parameters
3. Validate security configurations
4. Update cost estimates if resources change
5. Ensure cleanup procedures work correctly