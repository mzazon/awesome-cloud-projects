# Infrastructure as Code for Aurora Serverless Cost Optimization Patterns

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Aurora Serverless Cost Optimization Patterns".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements Aurora Serverless v2 with intelligent auto-scaling patterns that automatically adjust capacity based on workload demands while incorporating cost optimization strategies including:

- Aurora Serverless v2 cluster with optimized scaling boundaries (0.5-16 ACUs)
- Primary writer instance and multiple read replicas with different scaling tiers
- Lambda-based intelligent scaling functions for cost-aware capacity management
- Automated pause/resume functionality for development environments
- EventBridge-driven scheduling for scaling automation
- Comprehensive cost monitoring and alerting system
- CloudWatch metrics integration for data-driven scaling decisions

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- AWS account with appropriate permissions for:
  - Aurora Serverless v2 (RDS)
  - Lambda
  - EventBridge
  - CloudWatch
  - IAM
  - SNS
  - AWS Budgets
- VPC and subnet groups configured for Aurora
- Understanding of Aurora Serverless v2 scaling concepts and ACU calculations
- Estimated cost: $50-200/month depending on workload patterns and scaling configurations

> **Note**: Aurora Serverless v2 charges are based on actual ACU consumption per second, making cost prediction dependent on workload patterns.

## Quick Start

### Using CloudFormation

```bash
# Validate the template
aws cloudformation validate-template \
    --template-body file://cloudformation.yaml

# Create the stack
aws cloudformation create-stack \
    --stack-name aurora-sv2-cost-optimization \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=Environment,ParameterValue=development \
                 ParameterKey=MasterPassword,ParameterValue=SecurePassword123! \
    --capabilities CAPABILITY_IAM

# Monitor stack creation
aws cloudformation wait stack-create-complete \
    --stack-name aurora-sv2-cost-optimization

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name aurora-sv2-cost-optimization \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --parameters environment=development \
               --parameters masterPassword=SecurePassword123!

# View outputs
npx cdk deploy --outputs-file outputs.json
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters environment=development \
           --parameters masterPassword=SecurePassword123!

# View stack information
cdk list
cdk diff
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the plan
terraform plan -var="environment=development" \
               -var="master_password=SecurePassword123!"

# Apply the configuration
terraform apply -var="environment=development" \
                -var="master_password=SecurePassword123!"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the infrastructure
./deploy.sh

# The script will prompt for required parameters:
# - Environment type (development/staging/production)
# - Master password for Aurora cluster
# - AWS region (if not set)
```

## Configuration Options

### Environment Variables

All implementations support the following environment variables:

- `ENVIRONMENT`: Environment type (development, staging, production) - affects auto-pause behavior
- `MASTER_PASSWORD`: Master password for Aurora cluster (minimum 8 characters)
- `AWS_REGION`: AWS region for deployment
- `MIN_CAPACITY`: Minimum ACU capacity (default: 0.5)
- `MAX_CAPACITY`: Maximum ACU capacity (default: 16 for writer, 8/4 for readers)
- `BACKUP_RETENTION_DAYS`: Backup retention period (default: 7 days)

### Scaling Configuration

The solution implements tiered scaling patterns:

- **Writer Instance**: Min 0.5 ACU, Max 16 ACU (production workloads)
- **Reader Instance 1**: Min 0.5 ACU, Max 8 ACU (standard scaling)
- **Reader Instance 2**: Min 0 ACU, Max 4 ACU (aggressive cost optimization)

### Auto-Pause/Resume Schedule

Development environments automatically scale down during off-hours:

- **Development**: 8 AM - 8 PM UTC (active), minimal capacity outside hours
- **Staging**: 6 AM - 10 PM UTC (active), minimal capacity outside hours
- **Production**: Always active, no auto-pause

## Deployed Resources

### Core Infrastructure

- Aurora Serverless v2 PostgreSQL cluster
- Custom cluster parameter group optimized for cost
- Primary writer instance (db.serverless)
- Two read replica instances with different scaling profiles
- VPC security groups for Aurora access

### Automation & Monitoring

- Cost-aware scaling Lambda function (Python)
- Auto-pause/resume Lambda function (Python)
- EventBridge rules for scheduled scaling (15 minutes for cost-aware, 1 hour for pause/resume)
- CloudWatch alarms for capacity monitoring
- SNS topic for cost alerts
- AWS Budget for Aurora cost control

### IAM & Security

- Lambda execution role with minimal required permissions
- IAM policies for Aurora management and CloudWatch metrics
- Encrypted Aurora cluster with KMS
- VPC security groups restricting database access

## Monitoring & Observability

The solution provides comprehensive monitoring through:

### CloudWatch Metrics

- `ServerlessDatabaseCapacity`: Current ACU usage per instance
- `CPUUtilization`: Database CPU utilization
- `DatabaseConnections`: Active connection count
- Custom metrics in `Aurora/CostOptimization` namespace:
  - `ScalingAdjustment`: Capacity changes made by automation
  - `EstimatedCostImpact`: Financial impact of scaling decisions
  - `AutoPauseResumeActions`: Pause/resume activity tracking

### CloudWatch Alarms

- High ACU usage alert (>12 ACU average for 15 minutes)
- Sustained high capacity alert (>8 ACU average for 1.5 hours)
- Connection threshold alerts

### Cost Management

- AWS Budget with 80% actual spending alert
- Cost forecasting with 100% projected spending alert
- Resource tagging for cost allocation tracking

## Validation & Testing

### Verify Deployment

```bash
# Check Aurora cluster status
aws rds describe-db-clusters \
    --db-cluster-identifier <cluster-name> \
    --query 'DBClusters[0].Status'

# Verify Lambda functions
aws lambda list-functions \
    --query 'Functions[?starts_with(FunctionName, `aurora-sv2-cost-opt`)].FunctionName'

# Check EventBridge rules
aws events list-rules \
    --name-prefix aurora-sv2-cost-opt
```

### Test Scaling Functions

```bash
# Test cost-aware scaling
aws lambda invoke \
    --function-name <cluster-name>-cost-aware-scaler \
    --payload '{}' \
    scaling-test-output.json

# Test auto-pause/resume
aws lambda invoke \
    --function-name <cluster-name>-auto-pause-resume \
    --payload '{}' \
    pause-resume-output.json

# View function outputs
cat scaling-test-output.json
cat pause-resume-output.json
```

### Monitor Metrics

```bash
# Check current ACU usage
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name ServerlessDatabaseCapacity \
    --dimensions Name=DBClusterIdentifier,Value=<cluster-name> \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum

# Check custom cost optimization metrics
aws cloudwatch get-metric-statistics \
    --namespace Aurora/CostOptimization \
    --metric-name ScalingAdjustment \
    --dimensions Name=ClusterIdentifier,Value=<cluster-name> \
    --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name aurora-sv2-cost-optimization

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name aurora-sv2-cost-optimization

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name aurora-sv2-cost-optimization
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="environment=development" \
                  -var="master_password=SecurePassword123!"
```

### Using Bash Scripts

```bash
cd scripts/
./destroy.sh
```

## Customization

### Scaling Parameters

To customize scaling behavior, modify the following parameters in your chosen implementation:

- **Minimum Capacity**: Adjust based on baseline workload requirements
- **Maximum Capacity**: Set based on peak workload demands and budget constraints
- **Scaling Frequency**: Modify EventBridge schedules for different responsiveness
- **Cost Thresholds**: Update budget amounts and alarm thresholds

### Environment-Specific Configuration

The solution supports different configurations per environment:

```yaml
# Example environment-specific parameters
Development:
  MinCapacity: 0.5
  MaxCapacity: 4
  AutoPauseEnabled: true
  
Staging:
  MinCapacity: 0.5
  MaxCapacity: 8
  AutoPauseEnabled: true
  
Production:
  MinCapacity: 1
  MaxCapacity: 32
  AutoPauseEnabled: false
```

### Cost Optimization Algorithms

The Lambda scaling functions can be customized to implement different cost optimization strategies:

- **Aggressive**: Minimize capacity during low-usage periods
- **Conservative**: Maintain higher baseline for consistent performance
- **Predictive**: Use historical patterns to anticipate scaling needs
- **Business-Hours Aware**: Scale based on business operation schedules

## Troubleshooting

### Common Issues

1. **Lambda Function Timeouts**
   - Increase timeout values in Lambda configuration
   - Optimize scaling logic for better performance

2. **Aurora Cluster Connection Issues**
   - Verify VPC security groups allow Lambda access
   - Check Aurora cluster status and availability

3. **EventBridge Rules Not Triggering**
   - Verify Lambda function permissions for EventBridge
   - Check EventBridge rule schedules and targets

4. **High Costs Despite Optimization**
   - Review CloudWatch metrics for capacity utilization patterns
   - Adjust scaling thresholds and minimum capacity settings
   - Verify auto-pause functionality for development environments

### Debug Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/aurora-sv2-cost-opt

# View recent scaling activities
aws logs filter-log-events \
    --log-group-name /aws/lambda/<function-name> \
    --start-time $(date -d '1 hour ago' +%s)000

# Monitor Aurora cluster events
aws rds describe-events \
    --source-identifier <cluster-name> \
    --source-type db-cluster \
    --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S)
```

## Performance Considerations

### Scaling Response Time

- Aurora Serverless v2 provides sub-second scaling
- Lambda functions typically execute within 30-60 seconds
- EventBridge scheduling provides reliable trigger timing
- Total scaling decision-to-implementation: ~2-3 minutes

### Cost Impact

- Aurora Serverless v2 billing is per-second based on actual ACU consumption
- Lambda functions cost ~$0.20-$2.00 per month depending on execution frequency
- CloudWatch metrics and alarms: ~$1-$5 per month
- EventBridge rules: minimal cost (~$0.10 per month)

### Security Best Practices

- All resources use least-privilege IAM policies
- Aurora cluster encryption enabled by default
- Lambda functions run in VPC when accessing Aurora
- CloudWatch Logs encrypted for sensitive scaling decisions
- Resource tagging for compliance and cost allocation

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../aurora-serverless-v2-cost-optimization-patterns.md)
- [AWS Aurora Serverless v2 Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
- [CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Additional Resources

- [Aurora Serverless v2 Capacity Planning Guide](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.setting-capacity.html)
- [AWS Cost Optimization Best Practices](https://aws.amazon.com/pricing/cost-optimization/)
- [CloudWatch Metrics and Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/)
- [AWS Budgets User Guide](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-managing-costs.html)