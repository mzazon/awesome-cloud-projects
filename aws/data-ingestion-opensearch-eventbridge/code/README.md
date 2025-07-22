# Infrastructure as Code for OpenSearch Data Ingestion Pipelines

This directory contains Infrastructure as Code (IaC) implementations for the recipe "OpenSearch Data Ingestion Pipelines".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon OpenSearch Service
  - OpenSearch Ingestion (OSIS)
  - Amazon EventBridge Scheduler
  - Amazon S3
  - AWS IAM
  - AWS CloudWatch
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $50-100/month for test environment

> **Note**: OpenSearch Ingestion is available in select AWS regions. Verify service availability in your target region before proceeding.

## Quick Start

### Using CloudFormation

```bash
# Set required parameters
export STACK_NAME="data-ingestion-pipeline-stack"
export BUCKET_NAME="data-ingestion-$(openssl rand -hex 3)"
export OPENSEARCH_DOMAIN="analytics-domain-$(openssl rand -hex 3)"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=BucketName,ParameterValue=${BUCKET_NAME} \
                 ParameterKey=OpenSearchDomainName,ParameterValue=${OPENSEARCH_DOMAIN} \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name ${STACK_NAME}

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
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

# Get outputs
cdk output
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
cdk deploy --require-approval never

# Get outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
aws_region = "us-east-1"
bucket_name = "data-ingestion-$(openssl rand -hex 3)"
opensearch_domain_name = "analytics-domain-$(openssl rand -hex 3)"
pipeline_name = "data-pipeline-$(openssl rand -hex 3)"
schedule_group_name = "ingestion-schedules-$(openssl rand -hex 3)"
environment = "development"
project_name = "data-ingestion"
EOF

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply -auto-approve

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration parameters
# The script will create all necessary resources and provide output values
```

## Post-Deployment Configuration

After deploying the infrastructure, follow these steps to complete the setup:

### 1. Upload Sample Data

```bash
# Set variables (replace with your actual values from outputs)
export BUCKET_NAME="your-bucket-name"
export AWS_REGION="your-aws-region"

# Create sample log data
cat > sample-logs.log << EOF
2023-07-12T08:30:00Z INFO Application started successfully
2023-07-12T08:30:15Z DEBUG Database connection established
2023-07-12T08:30:30Z WARN High memory usage detected: 85%
2023-07-12T08:30:45Z ERROR Failed to process user request: timeout
2023-07-12T08:31:00Z INFO Request processed successfully
EOF

# Upload to S3
aws s3 cp sample-logs.log s3://${BUCKET_NAME}/logs/2023/07/12/
```

### 2. Verify Pipeline Status

```bash
# Check OpenSearch Ingestion pipeline
export PIPELINE_NAME="your-pipeline-name"
aws osis get-pipeline --pipeline-name ${PIPELINE_NAME}

# Check EventBridge schedules
export SCHEDULE_GROUP_NAME="your-schedule-group-name"
aws scheduler list-schedules --group-name ${SCHEDULE_GROUP_NAME}
```

### 3. Access OpenSearch Dashboards

```bash
# Get OpenSearch endpoint
export OPENSEARCH_ENDPOINT="your-opensearch-endpoint"
echo "OpenSearch Dashboards URL: https://${OPENSEARCH_ENDPOINT}/_dashboards"

# Query ingested data
curl -X GET "https://${OPENSEARCH_ENDPOINT}/application-logs-*/_search" \
     -H "Content-Type: application/json" \
     -d '{"query": {"match_all": {}}, "size": 10}'
```

## Configuration Options

### Environment Variables

The following environment variables can be set to customize the deployment:

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_REGION` | AWS region for deployment | `us-east-1` |
| `ENVIRONMENT` | Environment tag (dev/staging/prod) | `development` |
| `PROJECT_NAME` | Project name for resource tagging | `data-ingestion` |
| `PIPELINE_MIN_UNITS` | Minimum pipeline processing units | `1` |
| `PIPELINE_MAX_UNITS` | Maximum pipeline processing units | `4` |
| `OPENSEARCH_INSTANCE_TYPE` | OpenSearch instance type | `t3.small.search` |
| `OPENSEARCH_VOLUME_SIZE` | OpenSearch EBS volume size (GB) | `20` |

### Schedule Configuration

The default schedule configuration can be modified:

- **Start Time**: 8:00 AM UTC (weekdays)
- **Stop Time**: 6:00 PM UTC (weekdays)
- **Retry Policy**: 3 attempts with 1-hour maximum age
- **Flexible Window**: 15 minutes

To modify schedules after deployment, update the EventBridge Scheduler configurations through the AWS Console or CLI.

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor pipeline operations through CloudWatch Logs:

```bash
# View OpenSearch Ingestion logs
aws logs describe-log-groups --log-group-name-prefix "/aws/opensearch-ingestion"

# View specific log events
aws logs get-log-events \
    --log-group-name "/aws/opensearch-ingestion/your-pipeline-name" \
    --log-stream-name "your-log-stream"
```

### Pipeline Metrics

Key metrics to monitor:

- `OSIS.DocumentsIngested` - Number of documents processed
- `OSIS.DocumentsWritten` - Number of documents written to OpenSearch
- `OSIS.ProcessingErrors` - Number of processing errors
- `ES.ClusterStatus.green` - OpenSearch cluster health

### Common Issues

1. **Pipeline Not Processing Data**:
   - Verify S3 bucket permissions
   - Check pipeline configuration YAML syntax
   - Ensure OpenSearch domain is accessible

2. **Schedule Not Triggering**:
   - Verify EventBridge Scheduler IAM permissions
   - Check schedule expressions and time zones
   - Review schedule target configuration

3. **OpenSearch Connection Issues**:
   - Verify domain access policies
   - Check VPC configuration if using VPC deployment
   - Ensure IAM roles have correct permissions

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name ${STACK_NAME}

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME}
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy
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

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete resources in this order:

1. EventBridge Scheduler schedules and schedule groups
2. OpenSearch Ingestion pipeline
3. OpenSearch Service domain
4. S3 bucket contents and bucket
5. IAM roles and policies
6. CloudWatch log groups

```bash
# Emergency cleanup commands
aws scheduler delete-schedule --name start-ingestion-pipeline --group-name ${SCHEDULE_GROUP_NAME}
aws scheduler delete-schedule --name stop-ingestion-pipeline --group-name ${SCHEDULE_GROUP_NAME}
aws scheduler delete-schedule-group --name ${SCHEDULE_GROUP_NAME}
aws osis delete-pipeline --pipeline-name ${PIPELINE_NAME}
aws opensearch delete-domain --domain-name ${OPENSEARCH_DOMAIN}
aws s3 rm s3://${BUCKET_NAME} --recursive
aws s3 rb s3://${BUCKET_NAME}
```

## Security Considerations

This implementation follows AWS security best practices:

- **IAM Roles**: Least privilege access for all services
- **Encryption**: Data encrypted at rest and in transit
- **Access Policies**: Restrictive OpenSearch domain access
- **Network Security**: HTTPS enforcement and VPC isolation options
- **Resource Tagging**: Comprehensive tagging for governance

## Cost Optimization

To optimize costs:

1. **Use Scheduled Pipelines**: Automatically start/stop based on business hours
2. **Right-size OpenSearch**: Choose appropriate instance types and storage
3. **Monitor Usage**: Set up billing alerts for unexpected costs
4. **Reserved Capacity**: Consider reserved instances for production workloads
5. **Data Lifecycle**: Implement S3 lifecycle policies for source data

## Support and Documentation

- [Amazon OpenSearch Ingestion User Guide](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ingestion.html)
- [EventBridge Scheduler User Guide](https://docs.aws.amazon.com/scheduler/latest/UserGuide/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/)
- [OpenSearch Documentation](https://opensearch.org/docs/)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment
2. Update documentation for any new parameters
3. Follow AWS and tool-specific best practices
4. Validate security configurations
5. Update cost estimates if applicable

## License

This infrastructure code is provided under the same license as the recipe repository.