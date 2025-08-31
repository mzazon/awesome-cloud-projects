# Infrastructure as Code for Service Mesh Cost Analytics with VPC Lattice and Cost Explorer

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Service Mesh Cost Analytics with VPC Lattice and Cost Explorer".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys an automated cost analytics platform that combines VPC Lattice monitoring capabilities with Cost Explorer APIs to provide comprehensive service mesh cost insights. The infrastructure includes:

- VPC Lattice service network and sample service
- Lambda function for cost data processing
- S3 bucket for analytics data storage
- CloudWatch dashboard for cost visualization
- EventBridge rule for automated scheduling
- IAM roles and policies with least privilege access
- Cost allocation tags for granular tracking

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - VPC Lattice
  - Cost Explorer
  - CloudWatch
  - Lambda
  - S3
  - EventBridge
  - IAM
- Cost Explorer enabled in your AWS account (may take up to 24 hours)
- For CDK deployments: Node.js 18+ or Python 3.8+
- For Terraform: Terraform 1.0+

> **Note**: Cost Explorer requires activation and may take up to 24 hours to provide data. Ensure it's enabled before deployment.

## Estimated Costs

- **Analytics Infrastructure**: $15-25 per month
- **Lambda Execution**: <$1 per month (based on daily execution)
- **S3 Storage**: <$1 per month for analytics data
- **CloudWatch**: <$5 per month for custom metrics and dashboards
- **VPC Lattice**: Variable based on traffic volume

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name lattice-cost-analytics \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ProjectName,ParameterValue=lattice-analytics

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name lattice-cost-analytics \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name lattice-cost-analytics \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters projectName=lattice-analytics

# View stack outputs
cdk list
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

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters project_name=lattice-analytics

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan -var="project_name=lattice-analytics"

# Apply the configuration
terraform apply -var="project_name=lattice-analytics"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment results
cat deployment_outputs.txt
```

## Configuration Options

### Common Parameters

- **Project Name**: Identifier for resource naming (default: `lattice-cost-analytics`)
- **Environment**: Environment tag for resources (default: `demo`)
- **Cost Center**: Cost allocation tag (default: `engineering`)
- **AWS Region**: Deployment region (uses current AWS CLI region)

### CloudFormation Parameters

```yaml
Parameters:
  ProjectName:
    Type: String
    Default: lattice-cost-analytics
  Environment:
    Type: String
    Default: demo
  CostCenter:
    Type: String
    Default: engineering
```

### Terraform Variables

```hcl
variable "project_name" {
  description = "Name for the project"
  type        = string
  default     = "lattice-cost-analytics"
}

variable "environment" {
  description = "Environment for resource tagging"
  type        = string
  default     = "demo"
}

variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = "engineering"
}
```

### CDK Context Variables

```json
{
  "projectName": "lattice-cost-analytics",
  "environment": "demo",
  "costCenter": "engineering"
}
```

## Post-Deployment Verification

### 1. Verify Lambda Function

```bash
# Get function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name lattice-cost-analytics \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Test the function
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response.json

# Check the response
cat response.json
```

### 2. Verify S3 Analytics Storage

```bash
# Get bucket name from outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name lattice-cost-analytics \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

# List bucket contents
aws s3 ls s3://$BUCKET_NAME --recursive
```

### 3. Check CloudWatch Dashboard

```bash
# Get dashboard name from outputs
DASHBOARD_NAME=$(aws cloudformation describe-stacks \
    --stack-name lattice-cost-analytics \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardName`].OutputValue' \
    --output text)

# View dashboard URL
echo "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home#dashboards:name=$DASHBOARD_NAME"
```

### 4. Verify VPC Lattice Service Network

```bash
# Get service network ID from outputs
SERVICE_NETWORK_ID=$(aws cloudformation describe-stacks \
    --stack-name lattice-cost-analytics \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceNetworkId`].OutputValue' \
    --output text)

# Check service network status
aws vpc-lattice get-service-network \
    --service-network-identifier $SERVICE_NETWORK_ID
```

## Monitoring and Maintenance

### CloudWatch Metrics

The solution publishes custom metrics to the `VPCLattice/CostAnalytics` namespace:

- `TotalCost`: Total cost for the analysis period
- `TotalRequests`: Total number of requests processed
- `CostPerRequest`: Calculated efficiency metric

### EventBridge Automation

The solution includes automated daily cost analysis. Check the rule status:

```bash
# List EventBridge rules
aws events list-rules --name-prefix lattice-cost-analysis

# View rule details
aws events describe-rule --name lattice-cost-analysis-*
```

### Cost Allocation Tags

All resources are tagged with:
- `Project`: Project identifier
- `Environment`: Environment designation
- `CostCenter`: Cost center for billing
- `ServiceMesh`: Identifies VPC Lattice resources

## Troubleshooting

### Common Issues

1. **Cost Explorer Not Enabled**
   ```bash
   # Test Cost Explorer access
   aws ce get-cost-and-usage \
       --time-period Start=2025-01-01,End=2025-01-02 \
       --granularity MONTHLY \
       --metrics BlendedCost
   ```

2. **IAM Permissions Insufficient**
   - Ensure your AWS credentials have sufficient permissions
   - Check CloudFormation events for permission errors

3. **Lambda Function Timeout**
   - Check CloudWatch logs for the Lambda function
   - Increase timeout if processing large amounts of data

4. **VPC Lattice Service Creation Fails**
   - Verify VPC Lattice is available in your region
   - Check IAM permissions for VPC Lattice operations

### Logs and Debugging

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"

# Get recent log events
aws logs get-log-events \
    --log-group-name "/aws/lambda/$FUNCTION_NAME" \
    --log-stream-name $(aws logs describe-log-streams \
        --log-group-name "/aws/lambda/$FUNCTION_NAME" \
        --order-by LastEventTime \
        --descending \
        --limit 1 \
        --query 'logStreams[0].logStreamName' \
        --output text)
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name lattice-cost-analytics

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name lattice-cost-analytics \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_name=lattice-analytics"

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources:

```bash
# Remove S3 bucket contents first
aws s3 rm s3://$BUCKET_NAME --recursive

# Then delete the bucket
aws s3 rb s3://$BUCKET_NAME

# Delete Lambda function
aws lambda delete-function --function-name $FUNCTION_NAME

# Delete IAM role and policies
aws iam delete-role --role-name $ROLE_NAME
```

## Security Considerations

### IAM Policies

The solution implements least privilege access with:
- Lambda execution role with minimal required permissions
- Cost Explorer read-only access
- S3 bucket-specific permissions
- CloudWatch metrics and logs access

### Data Protection

- S3 bucket encryption at rest (AES-256)
- CloudWatch logs encryption
- No sensitive data in Lambda environment variables
- Cost allocation tags for audit trails

### Network Security

- VPC Lattice service network uses AWS IAM authentication
- No public internet access required for core functionality
- All API calls use AWS service endpoints

## Customization

### Adding Custom Cost Filters

Modify the Lambda function to include additional cost filters:

```python
# Example: Filter by specific services
Filter={
    'And': [
        {
            'Dimensions': {
                'Key': 'SERVICE',
                'Values': ['VPC Lattice', 'Amazon VPC']
            }
        },
        {
            'Tags': {
                'Key': 'Project',
                'Values': ['your-project-name']
            }
        }
    ]
}
```

### Extending CloudWatch Dashboard

Add additional widgets by modifying the dashboard configuration:

```json
{
  "type": "metric",
  "properties": {
    "metrics": [
      [ "AWS/VpcLattice", "ErrorRate", "ServiceNetwork", "your-service-network-id" ]
    ],
    "title": "Service Network Error Rate"
  }
}
```

### Custom Notification Rules

Add SNS notifications for cost thresholds:

```bash
# Create SNS topic
aws sns create-topic --name lattice-cost-alerts

# Subscribe to topic
aws sns subscribe \
    --topic-arn arn:aws:sns:region:account:lattice-cost-alerts \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Advanced Features

### Multi-Account Cost Aggregation

For enterprise deployments, consider:
- AWS Organizations integration
- Cross-account role assumption
- Consolidated billing analysis
- Cost allocation across business units

### Machine Learning Integration

Extend with predictive analytics:
- Amazon Forecast for cost prediction
- Anomaly detection for unusual spending
- Optimization recommendations

### Integration with Third-Party Tools

- Export data to business intelligence tools
- Integration with cost optimization platforms
- Custom reporting and alerting systems

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../service-mesh-cost-analytics-lattice-explorer.md)
2. Review AWS service documentation:
   - [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/latest/ug/)
   - [Cost Explorer API Reference](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/)
   - [CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
3. Check AWS service status and regional availability
4. Review CloudFormation events for deployment issues

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow AWS Well-Architected Framework principles
3. Update documentation for any new features
4. Ensure backward compatibility where possible
5. Add appropriate cost estimates for new resources