# Infrastructure as Code for Multi-Region Disaster Recovery with Aurora DSQL

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Region Disaster Recovery with Aurora DSQL".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell access)
- Administrator permissions for Aurora DSQL, EventBridge, Lambda, CloudWatch, SNS, and IAM
- Advanced understanding of multi-region AWS architectures and disaster recovery concepts
- Knowledge of serverless event-driven patterns and database high availability principles
- Estimated cost: $150-300/month for Aurora DSQL multi-region clusters and supporting services

> **Note**: Aurora DSQL is available in specific regions. Verify [regional availability](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/what-is-aurora-dsql.html) before selecting your primary and secondary regions.

## Architecture Overview

This solution implements a comprehensive multi-region disaster recovery system featuring:

- **Aurora DSQL Multi-Region Clusters**: Active-active database architecture with witness region
- **EventBridge Rules**: Automated monitoring orchestration across regions  
- **Lambda Functions**: Intelligent health monitoring with custom metrics
- **CloudWatch Dashboard**: Centralized monitoring and alerting
- **SNS Topics**: Multi-region notification system
- **CloudWatch Alarms**: Proactive issue detection and alerting

## Quick Start

### Using CloudFormation

```bash
# Deploy the multi-region disaster recovery stack
aws cloudformation create-stack \
    --stack-name aurora-dsql-dr-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=PrimaryRegion,ParameterValue=us-east-1 \
                ParameterKey=SecondaryRegion,ParameterValue=us-west-2 \
                ParameterKey=WitnessRegion,ParameterValue=us-west-1 \
                ParameterKey=AlertEmail,ParameterValue=ops-team@company.com \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name aurora-dsql-dr-stack \
    --query 'Stacks[0].StackStatus' \
    --region us-east-1
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Deploy the stack
cdk deploy AuroraDsqlDrStack \
    --parameters primaryRegion=us-east-1 \
    --parameters secondaryRegion=us-west-2 \
    --parameters witnessRegion=us-west-1 \
    --parameters alertEmail=ops-team@company.com

# Verify deployment
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment and install dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Configure deployment parameters
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=us-east-1

# Deploy the stack
cdk deploy AuroraDsqlDrStack \
    --parameters primaryRegion=us-east-1 \
    --parameters secondaryRegion=us-west-2 \
    --parameters witnessRegion=us-west-1 \
    --parameters alertEmail=ops-team@company.com

# List deployed stacks
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review and customize terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
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

# Configure environment variables
export PRIMARY_REGION="us-east-1"
export SECONDARY_REGION="us-west-2"
export WITNESS_REGION="us-west-1"
export ALERT_EMAIL="ops-team@company.com"

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor deployment progress
./scripts/deploy.sh --status
```

## Configuration Options

### Key Parameters

- **Primary Region**: Main AWS region for Aurora DSQL cluster (default: us-east-1)
- **Secondary Region**: Secondary AWS region for disaster recovery (default: us-west-2)
- **Witness Region**: Tie-breaker region for cluster decisions (default: us-west-1)
- **Alert Email**: Email address for disaster recovery notifications
- **Monitoring Frequency**: EventBridge rule execution frequency (default: 2 minutes)
- **Lambda Memory**: Memory allocation for monitoring functions (default: 256 MB)
- **Lambda Timeout**: Timeout for monitoring functions (default: 60 seconds)

### Environment Variables (Bash Scripts)

```bash
export PRIMARY_REGION="us-east-1"           # Primary deployment region
export SECONDARY_REGION="us-west-2"         # Secondary deployment region  
export WITNESS_REGION="us-west-1"           # Witness region for cluster decisions
export ALERT_EMAIL="ops-team@company.com"   # Email for alerts
export CLUSTER_PREFIX="dr-dsql"             # Prefix for cluster names
export RANDOM_SUFFIX=""                     # Auto-generated unique suffix
```

## Post-Deployment Validation

### 1. Verify Aurora DSQL Clusters

```bash
# Check primary cluster status
aws dsql get-cluster \
    --region us-east-1 \
    --identifier dr-dsql-primary \
    --query '[status, arn]' \
    --output table

# Check secondary cluster status
aws dsql get-cluster \
    --region us-west-2 \
    --identifier dr-dsql-secondary \
    --query '[status, arn]' \
    --output table
```

Expected output: Both clusters should show `ACTIVE` status.

### 2. Test Lambda Function Monitoring

```bash
# Manually invoke primary region monitoring function
aws lambda invoke \
    --region us-east-1 \
    --function-name dr-monitor-primary \
    --payload '{}' \
    response.json && cat response.json

# Check CloudWatch custom metrics
aws cloudwatch get-metric-statistics \
    --region us-east-1 \
    --namespace "Aurora/DSQL/DisasterRecovery" \
    --metric-name "ClusterHealth" \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

### 3. Verify EventBridge Rules

```bash
# Check EventBridge rule execution
aws events describe-rule \
    --region us-east-1 \
    --name dr-health-monitor-primary \
    --query '[State, ScheduleExpression]' \
    --output table
```

Expected output: Rule should be in `ENABLED` state with `rate(2 minutes)` schedule.

### 4. Test Alerting System

```bash
# Send test alert
aws sns publish \
    --region us-east-1 \
    --topic-arn $(aws sns list-topics --region us-east-1 --query 'Topics[?contains(TopicArn, `dr-alerts`)].TopicArn' --output text) \
    --subject "Test: Aurora DSQL DR System" \
    --message "Test alert - disaster recovery system operational"
```

Expected result: Email notification should be received at configured email address.

## Monitoring and Observability

### CloudWatch Dashboard

Access the CloudWatch dashboard to monitor:
- Lambda function invocations and errors
- EventBridge rule executions
- Aurora DSQL cluster health metrics
- SNS topic delivery statistics

Dashboard name: `Aurora-DSQL-DR-Dashboard-{suffix}`

### CloudWatch Alarms

The following alarms are configured:
- **Lambda Errors**: Triggers on function execution errors
- **Cluster Health**: Alerts when Aurora DSQL health degrades
- **EventBridge Failures**: Notifies on rule execution failures

### Custom Metrics

Monitor these custom CloudWatch metrics:
- `Aurora/DSQL/DisasterRecovery/ClusterHealth`: Cluster health status (0-1)
- Lambda execution duration and success rates
- EventBridge rule execution frequency

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name aurora-dsql-dr-stack \
    --region us-east-1

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name aurora-dsql-dr-stack \
    --region us-east-1 \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy AuroraDsqlDrStack

# Confirm destruction when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
# Remove state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
# Verify all resources are removed
./scripts/destroy.sh --verify
```

## Troubleshooting

### Common Issues

1. **Aurora DSQL Region Availability**
   - Verify Aurora DSQL is available in your selected regions
   - Check [AWS documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/what-is-aurora-dsql.html) for current regional availability

2. **IAM Permissions**
   - Ensure your AWS credentials have administrator permissions
   - Verify permissions for Aurora DSQL, Lambda, EventBridge, CloudWatch, and SNS

3. **Resource Limits**
   - Check AWS service quotas for Lambda concurrent executions
   - Verify CloudWatch alarm limits in your account

4. **Cross-Region Dependencies**
   - Ensure all regions are accessible from your deployment environment
   - Verify EventBridge rules can invoke Lambda functions across regions

### Error Resolution

- **Aurora DSQL Cluster Creation Failures**: Check regional availability and service quotas
- **Lambda Deployment Errors**: Verify IAM role permissions and function size limits  
- **EventBridge Rule Failures**: Confirm Lambda function ARNs and permissions
- **CloudWatch Alarm Issues**: Verify metric namespaces and dimension configurations

## Security Considerations

- Aurora DSQL clusters use encryption at rest and in transit
- Lambda functions operate with least privilege IAM permissions
- SNS topics are encrypted using AWS managed keys
- EventBridge rules include retry policies and error handling
- All resources are tagged for cost allocation and governance

## Cost Optimization

- Aurora DSQL charges based on read/write capacity units
- Lambda functions use reserved concurrency to prevent runaway costs
- CloudWatch alarms and metrics have standard pricing
- EventBridge rules charge per execution (minimal cost)
- SNS notifications charge per message delivery

Estimated monthly cost: $150-300 depending on Aurora DSQL usage patterns.

## Support

For issues with this infrastructure code:
1. Review the original [recipe documentation](../building-multi-region-disaster-recovery-with-aurora-dsql-and-eventbridge.md)
2. Check AWS service documentation for specific resource configuration
3. Verify your AWS account permissions and service quotas
4. Monitor CloudWatch logs for detailed error information

## Additional Resources

- [Aurora DSQL Documentation](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/)
- [AWS Disaster Recovery Guidance](https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-workloads-on-aws.html)
- [EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [CloudWatch Documentation](https://docs.aws.amazon.com/cloudwatch/)