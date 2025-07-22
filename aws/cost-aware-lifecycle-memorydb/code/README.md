# Infrastructure as Code for Cost-Aware Resource Lifecycle with MemoryDB

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cost-Aware Resource Lifecycle with MemoryDB".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured with appropriate permissions
- AWS account with access to MemoryDB, EventBridge Scheduler, Lambda, and Cost Explorer
- For CDK deployments: Node.js 18+ (TypeScript) or Python 3.9+ (Python)
- For Terraform deployments: Terraform 1.0+ installed
- IAM permissions for creating:
  - MemoryDB clusters and subnet groups
  - Lambda functions and execution roles
  - EventBridge Scheduler rules and groups
  - CloudWatch dashboards and alarms
  - Cost Explorer and AWS Budgets resources

## Architecture Overview

This solution implements an intelligent cost optimization system that:

- **Automatically scales MemoryDB clusters** based on business hours and cost thresholds
- **Monitors costs** using Cost Explorer API integration
- **Schedules optimization actions** with EventBridge Scheduler
- **Provides monitoring** through CloudWatch dashboards and alarms
- **Manages budgets** with proactive cost alerting

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
    --stack-name memorydb-cost-optimization \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=my-memorydb-cluster \
                 ParameterKey=NotificationEmail,ParameterValue=admin@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npm install
npm run build

# Deploy with custom parameters
cdk deploy --parameters clusterName=my-memorydb-cluster \
           --parameters notificationEmail=admin@example.com
```

### Using CDK Python

```bash
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Deploy with environment variables
export CLUSTER_NAME=my-memorydb-cluster
export NOTIFICATION_EMAIL=admin@example.com
cdk deploy
```

### Using Terraform

```bash
cd terraform/
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
cluster_name = "my-memorydb-cluster"
notification_email = "admin@example.com"
aws_region = "us-west-2"
cost_threshold = 200
EOF

terraform plan
terraform apply
```

### Using Bash Scripts

```bash
# Set required environment variables
export CLUSTER_NAME=my-memorydb-cluster
export NOTIFICATION_EMAIL=admin@example.com
export AWS_REGION=us-west-2

chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Parameters

### Required Parameters

- **Cluster Name**: Name for the MemoryDB cluster
- **Notification Email**: Email address for budget alerts and cost notifications
- **AWS Region**: AWS region for resource deployment

### Optional Parameters

- **Cost Threshold**: Monthly budget threshold for cost alerts (default: $200)
- **Node Type**: Initial MemoryDB node type (default: db.t4g.small)
- **Business Hours**: Schedule for scale-up operations (default: 8 AM weekdays)
- **Off Hours**: Schedule for scale-down operations (default: 6 PM weekdays)

## Cost Optimization Features

### Automatic Scaling Schedules

- **Business Hours Scale-Up**: Weekdays at 8 AM (cron: `0 8 ? * MON-FRI *`)
- **Off-Hours Scale-Down**: Weekdays at 6 PM (cron: `0 18 ? * MON-FRI *`)
- **Weekly Cost Analysis**: Mondays at 9 AM (cron: `0 9 ? * MON *`)

### Cost Monitoring

- **Real-time cost tracking** via Cost Explorer API
- **Budget alerts** at 80% actual and 90% forecasted spend
- **CloudWatch custom metrics** for optimization actions
- **Performance impact monitoring** during scaling operations

### Intelligence Engine

The Lambda function provides:

- **Cost pattern analysis** using 7-day rolling averages
- **Smart scaling decisions** based on cost thresholds and usage patterns
- **Node type optimization** for different time periods
- **Error handling and retry logic** for reliable operations

## Monitoring and Observability

### CloudWatch Dashboard

The solution creates a comprehensive dashboard showing:

- **Cost Optimization Metrics**: Weekly costs and optimization actions
- **MemoryDB Performance**: CPU utilization and network metrics
- **Lambda Health**: Function duration, errors, and invocations

### Alarms and Notifications

- **High Cost Alert**: Triggers when weekly MemoryDB costs exceed threshold
- **Lambda Error Alert**: Monitors automation health and failures
- **Budget Notifications**: Email alerts for budget threshold breaches

## Validation and Testing

After deployment, validate the solution:

```bash
# Check MemoryDB cluster status
aws memorydb describe-clusters --cluster-name <cluster-name>

# Verify EventBridge schedules
aws scheduler list-schedules --group-name <scheduler-group-name>

# Test Lambda function
aws lambda invoke \
    --function-name <lambda-function-name> \
    --payload '{"cluster_name":"<cluster-name>","action":"analyze"}' \
    response.json

# View CloudWatch dashboard
aws cloudwatch get-dashboard --dashboard-name <dashboard-name>
```

## Customization Options

### Scaling Policies

Modify the Lambda function to implement custom scaling logic:

- **Performance-based scaling**: Use CloudWatch metrics for scaling decisions
- **Predictive scaling**: Integrate with Amazon Forecast for usage prediction
- **Multi-cluster orchestration**: Scale multiple clusters based on application needs

### Cost Thresholds

Adjust cost thresholds in the configuration:

- **Environment-specific budgets**: Different thresholds for dev/staging/prod
- **Service-level budgets**: Per-application or team cost allocation
- **Dynamic thresholds**: Adjust based on business growth or seasonal patterns

### Scheduling Flexibility

EventBridge Scheduler expressions can be customized for:

- **Regional business hours**: Different schedules per geographic region
- **Seasonal adjustments**: Holiday and peak season scheduling
- **Maintenance windows**: Coordinate with planned maintenance activities

## Security Considerations

### IAM Permissions

The solution follows least-privilege principles:

- **Lambda execution role**: Minimal permissions for MemoryDB and cost operations
- **EventBridge Scheduler role**: Limited to Lambda function invocation
- **Cross-service access**: Proper service-to-service authentication

### Data Protection

- **Encryption in transit**: All API communications use TLS
- **Encryption at rest**: MemoryDB data encryption enabled by default
- **Secrets management**: No hardcoded credentials in code

### Network Security

- **VPC deployment**: MemoryDB deployed in private subnets
- **Security groups**: Restrictive network access controls
- **Subnet groups**: Isolated network segments for database access

## Troubleshooting

### Common Issues

1. **Lambda timeout errors**: Increase timeout or optimize function code
2. **IAM permission issues**: Verify all required policies are attached
3. **MemoryDB modification failures**: Check cluster status and timing
4. **Cost data unavailability**: Ensure Cost Explorer is enabled

### Debug Commands

```bash
# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
aws logs tail /aws/lambda/<function-name> --follow

# Verify EventBridge Scheduler execution
aws scheduler get-schedule --name <schedule-name> --group-name <group-name>

# Check MemoryDB cluster events
aws memorydb describe-events --source-identifier <cluster-name>
```

## Cost Estimation

### Expected Costs (US East 1)

- **MemoryDB db.t4g.small**: ~$45/month (with 50% optimization savings)
- **Lambda executions**: ~$1/month (based on scheduled invocations)
- **EventBridge Scheduler**: ~$1/month (3 schedules)
- **CloudWatch**: ~$3/month (dashboard and custom metrics)

**Total estimated cost**: ~$50/month (varies by region and usage)

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name memorydb-cost-optimization
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
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Best Practices

### Deployment

- **Test in non-production**: Validate scaling behavior before production deployment
- **Monitor initially**: Closely monitor cost and performance impacts during first week
- **Document customizations**: Keep track of any configuration changes for your environment

### Operations

- **Regular review**: Monthly review of cost optimization effectiveness
- **Performance validation**: Ensure scaling actions don't impact application performance
- **Alert tuning**: Adjust thresholds based on actual usage patterns

### Maintenance

- **Function updates**: Keep Lambda runtime and dependencies current
- **Cost threshold adjustments**: Update budgets based on business growth
- **Schedule optimization**: Refine schedules based on actual usage patterns

## Support and Documentation

- **Original Recipe**: Reference the complete recipe documentation for detailed implementation guidance
- **AWS Documentation**: [MemoryDB User Guide](https://docs.aws.amazon.com/memorydb/)
- **Cost Optimization**: [AWS Well-Architected Cost Optimization Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/)
- **EventBridge Scheduler**: [EventBridge Scheduler User Guide](https://docs.aws.amazon.com/scheduler/)

## Contributing

To improve this infrastructure code:

1. Follow AWS best practices and security guidelines
2. Test all changes in a development environment
3. Update documentation for any configuration changes
4. Validate cost impact of modifications

---

**Note**: This infrastructure deploys real AWS resources that incur costs. Always review the estimated costs and clean up resources when no longer needed to avoid unexpected charges.