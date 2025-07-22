# Infrastructure as Code for Building Collaborative Task Management with Aurora DSQL

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Collaborative Task Management with Aurora DSQL".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a real-time collaborative task management system featuring:

- **Aurora DSQL Multi-Region Cluster**: Active-active distributed database with strong consistency
- **EventBridge Custom Bus**: Event-driven messaging between components
- **Lambda Functions**: Serverless task processing with automatic scaling
- **CloudWatch**: Comprehensive monitoring and logging
- **IAM Roles**: Secure service-to-service communication with least privilege access

The solution provides high availability across multiple AWS regions with real-time synchronization and automatic failover capabilities.

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions for Aurora DSQL, EventBridge, Lambda, CloudWatch, and IAM
- Two AWS regions enabled for multi-region deployment (us-east-1 and us-west-2)
- Node.js 18+ (for CDK TypeScript implementation)
- Python 3.9+ (for CDK Python implementation)
- Terraform 1.0+ (for Terraform implementation)
- Basic understanding of serverless architecture and event-driven patterns
- Estimated cost: $20-50/month for development workloads (scales with usage)

> **Important**: Aurora DSQL is currently available in limited regions. Verify region availability before deployment.

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name task-management-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=Environment,ParameterValue=dev \
        ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
        ParameterKey=SecondaryRegion,ParameterValue=us-west-2

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name task-management-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name task-management-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Set deployment context
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Deploy the application
cdk deploy --all

# View outputs
cdk outputs
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set deployment context
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Deploy the application
cdk deploy --all

# View outputs
cdk outputs
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="environment=dev" \
                -var="primary_region=us-east-1" \
                -var="secondary_region=us-west-2"

# Apply the configuration
terraform apply -var="environment=dev" \
                 -var="primary_region=us-east-1" \
                 -var="secondary_region=us-west-2"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set environment variables
export ENVIRONMENT=dev
export PRIMARY_REGION=us-east-1
export SECONDARY_REGION=us-west-2

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Options

### Environment Variables

- `ENVIRONMENT`: Deployment environment (dev, staging, prod)
- `PRIMARY_REGION`: Primary AWS region for deployment
- `SECONDARY_REGION`: Secondary AWS region for multi-region setup
- `CLUSTER_NAME_PREFIX`: Custom prefix for Aurora DSQL cluster names
- `LOG_RETENTION_DAYS`: CloudWatch log retention period (default: 7 days)

### Common Parameters

All implementations support these configuration parameters:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| Environment | Deployment environment | dev | Yes |
| PrimaryRegion | Primary AWS region | us-east-1 | Yes |
| SecondaryRegion | Secondary AWS region | us-west-2 | Yes |
| ClusterNamePrefix | Aurora DSQL cluster prefix | task-mgmt | No |
| LogRetentionDays | Log retention period | 7 | No |
| LambdaMemorySize | Lambda memory allocation | 512 | No |
| LambdaTimeout | Lambda timeout in seconds | 60 | No |

### Security Configuration

The infrastructure implements security best practices:

- **IAM Roles**: Least privilege access for all services
- **Encryption**: Data encrypted in transit and at rest
- **Network Security**: VPC isolation and security groups
- **Audit Logging**: Comprehensive CloudTrail and CloudWatch logging
- **Access Control**: Fine-grained permissions for Aurora DSQL operations

## Testing Your Deployment

### Verify Aurora DSQL Cluster

```bash
# Check cluster status
aws dsql describe-cluster \
    --cluster-identifier task-mgmt-cluster-primary

# Test database connectivity
psql -h <DSQL_ENDPOINT> -d postgres -c "SELECT version();"
```

### Test EventBridge Integration

```bash
# Send test event
aws events put-events \
    --entries '[{
        "Source": "task.management",
        "DetailType": "Task Created",
        "Detail": "{\"eventType\":\"task.created\",\"taskData\":{\"title\":\"Test Task\",\"created_by\":\"test@example.com\"}}",
        "EventBusName": "task-events-dev"
    }]'
```

### Test Lambda Function

```bash
# Invoke Lambda function directly
aws lambda invoke \
    --function-name task-processor-dev \
    --payload '{"httpMethod":"GET","path":"/tasks"}' \
    response.json

cat response.json
```

### Monitor with CloudWatch

```bash
# View Lambda logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/task-processor-dev

# Check EventBridge metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --dimensions Name=RuleName,Value=task-processing-rule \
    --start-time 2025-01-01T00:00:00Z \
    --end-time 2025-01-02T00:00:00Z \
    --period 3600 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name task-management-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name task-management-stack
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy all stacks
cdk destroy --all

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="environment=dev" \
                   -var="primary_region=us-east-1" \
                   -var="secondary_region=us-west-2"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted for destructive actions
```

## Customization

### Multi-Region Configuration

To modify regional deployments:

1. **CloudFormation**: Update `PrimaryRegion` and `SecondaryRegion` parameters
2. **CDK**: Modify region configurations in `app.ts` or `app.py`
3. **Terraform**: Update `primary_region` and `secondary_region` variables
4. **Bash**: Set `PRIMARY_REGION` and `SECONDARY_REGION` environment variables

### Scaling Configuration

Adjust Lambda and Aurora DSQL scaling:

```bash
# For high-throughput environments
export LAMBDA_MEMORY_SIZE=1024
export LAMBDA_TIMEOUT=300
export LOG_RETENTION_DAYS=30
```

### Security Hardening

For production deployments:

1. Enable VPC deployment for Lambda functions
2. Configure Aurora DSQL with custom security groups
3. Enable AWS Config for compliance monitoring
4. Set up AWS WAF for API protection
5. Configure AWS KMS for enhanced encryption

## Monitoring and Observability

### CloudWatch Dashboards

The deployment creates monitoring dashboards for:

- Aurora DSQL cluster performance
- Lambda function metrics (invocations, errors, duration)
- EventBridge event processing rates
- System-wide error rates and latencies

### Alarms and Notifications

Configured alarms monitor:

- Lambda function error rates
- Aurora DSQL connection failures
- EventBridge processing failures
- High latency scenarios

### Log Aggregation

Centralized logging includes:

- Lambda execution logs
- Aurora DSQL query logs
- EventBridge event delivery logs
- System audit trails

## Performance Optimization

### Lambda Optimization

- **Memory Allocation**: Adjust based on workload patterns
- **Timeout Settings**: Configure appropriate timeouts for task processing
- **Concurrency Limits**: Set reserved concurrency for predictable performance

### Aurora DSQL Optimization

- **Query Patterns**: Optimize for distributed query patterns
- **Connection Pooling**: Implement connection pooling for high-concurrency scenarios
- **Regional Routing**: Configure optimal routing for multi-region access

### EventBridge Optimization

- **Event Filtering**: Use content filtering to reduce processing overhead
- **Batch Processing**: Configure batch settings for high-volume scenarios
- **Dead Letter Queues**: Implement error handling and retry mechanisms

## Troubleshooting

### Common Issues

1. **Region Availability**: Verify Aurora DSQL availability in target regions
2. **IAM Permissions**: Ensure service roles have necessary permissions
3. **Network Connectivity**: Check VPC and security group configurations
4. **Resource Limits**: Verify account limits for concurrent Lambda executions

### Debug Commands

```bash
# Check Aurora DSQL cluster status
aws dsql describe-cluster --cluster-identifier <cluster-name>

# View Lambda function configuration
aws lambda get-function --function-name <function-name>

# Check EventBridge rule status
aws events list-rules --name-prefix task-processing

# Review CloudWatch logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/<function-name> \
    --start-time <timestamp>
```

## Cost Optimization

### Cost Monitoring

- Enable AWS Cost Explorer for detailed cost analysis
- Set up billing alarms for budget management
- Use AWS Cost Anomaly Detection for unusual spending patterns

### Optimization Strategies

- **Lambda**: Use ARM-based Graviton processors for better price-performance
- **Aurora DSQL**: Leverage automatic scaling to optimize for actual usage
- **CloudWatch**: Configure appropriate log retention periods
- **EventBridge**: Use event filtering to reduce processing costs

## Support and Documentation

### Official Documentation

- [Aurora DSQL User Guide](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/)
- [EventBridge Developer Guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

### Best Practices

- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/)
- [Serverless Application Lens](https://docs.aws.amazon.com/wellarchitected/latest/serverless-applications-lens/)
- [Multi-Region Architecture](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/)

For issues with this infrastructure code, refer to the original recipe documentation or submit issues to the repository maintainers.

## License

This infrastructure code is provided under the same license as the parent repository. Refer to the LICENSE file for details.