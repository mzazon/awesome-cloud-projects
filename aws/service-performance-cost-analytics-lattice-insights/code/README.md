# Infrastructure as Code for Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an advanced analytics system that correlates VPC Lattice service mesh performance metrics with AWS costs using CloudWatch Insights queries and Cost Explorer API integration. The infrastructure includes:

- VPC Lattice Service Network with comprehensive logging
- CloudWatch Log Groups and Insights queries for performance analysis
- Lambda functions for analytics processing and cost correlation
- EventBridge scheduling for automated analysis cycles
- Cost Anomaly Detection for proactive alerting
- CloudWatch Dashboard for visualization

## Prerequisites

- AWS CLI installed and configured (version 2.x or higher)
- AWS account with permissions for VPC Lattice, CloudWatch, Cost Explorer, Lambda, EventBridge, and IAM
- Node.js 18+ (for CDK TypeScript)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Basic knowledge of service mesh concepts and CloudWatch Logs Insights query language
- Estimated cost: $15-25/month for VPC Lattice traffic processing, CloudWatch Logs storage, and Lambda execution

> **Note**: This solution requires Cost Explorer API access, which may incur additional charges based on API usage. Review [AWS Cost Explorer pricing](https://aws.amazon.com/aws-cost-management/pricing/) for current rates.

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name vpc-lattice-analytics-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=demo \
                ParameterKey=NotificationEmail,ParameterValue=admin@example.com

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name vpc-lattice-analytics-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name vpc-lattice-analytics-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done previously)
npm run cdk bootstrap

# Deploy the stack
npm run deploy

# View outputs
npm run cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Deploy the stack
cdk deploy

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

# Apply the infrastructure
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

# Follow the script prompts for configuration
```

## Configuration Options

### CloudFormation Parameters

- `Environment`: Environment tag for resources (default: demo)
- `NotificationEmail`: Email for cost anomaly alerts
- `AnalyticsSchedule`: EventBridge schedule expression (default: rate(6 hours))
- `LogRetentionDays`: CloudWatch Logs retention period (default: 7)
- `MemorySize`: Lambda function memory allocation (default: 256MB)

### CDK Configuration

Modify the following in the CDK source files:

- `ENVIRONMENT`: Environment name for resource tagging
- `NOTIFICATION_EMAIL`: Email address for alerts
- `SCHEDULE_EXPRESSION`: Analytics execution frequency
- `LOG_RETENTION_DAYS`: Log retention period
- `LAMBDA_MEMORY_SIZE`: Lambda memory allocation

### Terraform Variables

Edit `terraform/variables.tf` or create a `terraform.tfvars` file:

```hcl
environment = "demo"
notification_email = "admin@example.com"
analytics_schedule = "rate(6 hours)"
log_retention_days = 7
lambda_memory_size = 256
aws_region = "us-east-1"
```

### Bash Script Configuration

The deployment script will prompt for:

- AWS region
- Environment name
- Notification email address
- Analytics schedule preference

## Validation & Testing

### Verify Deployment

```bash
# Check VPC Lattice service network
aws vpc-lattice list-service-networks

# Verify Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `analytics`)].FunctionName'

# Check EventBridge rules
aws events list-rules --query 'Rules[?contains(Name, `analytics`)].Name'

# Test the analytics pipeline
aws lambda invoke \
    --function-name <report-generator-function-name> \
    --payload '{"test": true}' \
    response.json

cat response.json
```

### Access Resources

- **CloudWatch Dashboard**: Navigate to CloudWatch Console > Dashboards
- **VPC Lattice Console**: VPC Console > Service Networks
- **Cost Explorer**: Billing Console > Cost Explorer
- **Lambda Functions**: Lambda Console > Functions

## Monitoring & Operations

### Key Metrics to Monitor

- VPC Lattice connection counts and response times
- Lambda function execution duration and errors
- CloudWatch Logs Insights query performance
- Cost Explorer API usage and throttling
- EventBridge rule execution success rate

### Troubleshooting

1. **Lambda Function Errors**:
   ```bash
   # Check function logs
   aws logs tail /aws/lambda/<function-name> --follow
   ```

2. **VPC Lattice Configuration Issues**:
   ```bash
   # Verify service network status
   aws vpc-lattice describe-service-network --service-network-identifier <network-id>
   ```

3. **Cost Explorer API Errors**:
   - Verify Cost Explorer is enabled in the account
   - Check IAM permissions for Cost Explorer API access
   - Review API usage limits and throttling

### Scaling Considerations

- **Lambda Memory**: Increase memory for cost correlator function if processing large datasets
- **CloudWatch Logs Retention**: Adjust retention period based on analysis requirements
- **EventBridge Frequency**: Modify schedule based on business needs and cost considerations
- **VPC Lattice**: Monitor service network limits and request increases if needed

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name vpc-lattice-analytics-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name vpc-lattice-analytics-stack
```

### Using CDK

```bash
# From the appropriate CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

## Customization

### Adding Custom Metrics

1. **Performance Metrics**: Modify the performance analyzer Lambda function to calculate additional metrics
2. **Cost Dimensions**: Update the cost correlator to analyze additional cost dimensions or services
3. **Dashboard Widgets**: Enhance the CloudWatch dashboard with custom visualizations

### Extending Analytics

1. **Real-time Processing**: Integrate with Kinesis Data Streams for real-time analytics
2. **Machine Learning**: Add SageMaker integration for predictive cost modeling
3. **Multi-Region**: Extend to correlate costs across multiple AWS regions
4. **Advanced Reporting**: Integrate with QuickSight for executive dashboards

### Security Enhancements

1. **Encryption**: Enable encryption for CloudWatch Logs and Lambda environment variables
2. **Network Security**: Implement VPC endpoints for private API communication
3. **Access Control**: Implement fine-grained IAM policies and resource-based policies
4. **Compliance**: Add AWS Config rules for compliance monitoring

## Cost Optimization

### Resource Optimization

- Use Lambda Provisioned Concurrency judiciously based on usage patterns
- Optimize CloudWatch Logs retention periods to balance analysis needs with storage costs
- Implement intelligent tiering for long-term log storage using S3 lifecycle policies
- Monitor and optimize VPC Lattice data processing units based on actual traffic

### Cost Monitoring

- Set up additional Cost Anomaly Detection for Lambda and CloudWatch services
- Implement budget alerts for the analytics infrastructure components
- Use Cost Explorer to analyze the cost-effectiveness of the analytics solution itself
- Consider Reserved Capacity for consistent workloads

## Support

### Documentation References

- [AWS VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/what-is-vpc-lattice.html)
- [CloudWatch Logs Insights Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html)
- [Cost Explorer API Reference](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)

### Common Issues

1. **Cost Explorer API Access**: Ensure Cost Explorer is enabled and has sufficient permissions
2. **VPC Lattice Limits**: Review service and resource limits in the AWS documentation
3. **Lambda Timeout**: Increase timeout values for functions processing large datasets
4. **CloudWatch Insights Quota**: Monitor query concurrency limits and optimize query patterns

### Getting Help

- For AWS service issues: AWS Support or AWS re:Post community
- For Infrastructure code issues: Review the original recipe documentation
- For specific implementation questions: Consult the respective tool documentation (CDK, Terraform, etc.)

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Compatible AWS CLI**: 2.x
- **Compatible CDK**: 2.x
- **Compatible Terraform**: 1.0+

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's security and compliance requirements before production use.