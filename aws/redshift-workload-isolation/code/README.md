# Infrastructure as Code for Redshift Analytics Workload Isolation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Redshift Analytics Workload Isolation".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating:
  - Amazon Redshift clusters and parameter groups
  - IAM roles and policies
  - CloudWatch alarms and dashboards
  - SNS topics and subscriptions
- Basic understanding of SQL and data warehousing concepts
- Estimated cost: $50-200 per day for testing cluster (varies by instance type and region)

### Tool-Specific Prerequisites

**CloudFormation:**
- No additional tools required

**CDK TypeScript:**
- Node.js 18+ and npm
- AWS CDK CLI (`npm install -g aws-cdk`)

**CDK Python:**
- Python 3.8+ and pip
- AWS CDK CLI (`pip install aws-cdk-lib`)

**Terraform:**
- Terraform 1.5+ installed
- Basic understanding of HCL syntax

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name redshift-wlm-analytics \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterIdentifier,ParameterValue=analytics-wlm-cluster \
                 ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name redshift-wlm-analytics

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name redshift-wlm-analytics \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters notificationEmail=your-email@example.com

# View deployed resources
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters notification-email=your-email@example.com

# View deployed resources
cdk list
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="cluster_identifier=analytics-wlm-cluster" \
    -var="notification_email=your-email@example.com"

# Apply the configuration
terraform apply \
    -var="cluster_identifier=analytics-wlm-cluster" \
    -var="notification_email=your-email@example.com"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL="your-email@example.com"
export CLUSTER_IDENTIFIER="analytics-wlm-cluster"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
aws redshift describe-clusters \
    --cluster-identifier $CLUSTER_IDENTIFIER
```

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to configure database users and groups:

1. **Connect to your Redshift cluster** using your preferred SQL client
2. **Run the user setup script** (generated during deployment):
   ```sql
   -- Create user groups for workload isolation
   CREATE GROUP "bi-dashboard-group";
   CREATE GROUP "data-science-group";
   CREATE GROUP "etl-process-group";
   
   -- Create users for different workload types
   CREATE USER dashboard_user1 PASSWORD 'BiUser123!@#' IN GROUP "bi-dashboard-group";
   CREATE USER analytics_user1 PASSWORD 'DsUser123!@#' IN GROUP "data-science-group";
   CREATE USER etl_user1 PASSWORD 'EtlUser123!@#' IN GROUP "etl-process-group";
   
   -- Grant appropriate permissions
   GRANT ALL ON SCHEMA public TO GROUP "bi-dashboard-group";
   GRANT ALL ON SCHEMA public TO GROUP "data-science-group";
   GRANT ALL ON SCHEMA public TO GROUP "etl-process-group";
   ```

3. **Confirm SNS email subscription** for CloudWatch alerts
4. **Test workload isolation** using the provided test queries

## Validation

### Verify WLM Configuration
```bash
# Check parameter group status
aws redshift describe-cluster-parameter-groups \
    --parameter-group-name $(terraform output -raw parameter_group_name)

# Verify cluster is using custom parameter group
aws redshift describe-clusters \
    --cluster-identifier $(terraform output -raw cluster_identifier) \
    --query 'Clusters[0].ClusterParameterGroups'
```

### Test Queue Assignment
Connect to your Redshift cluster and run:
```sql
-- Verify WLM configuration
SELECT * FROM stv_wlm_classification_config ORDER BY service_class;

-- Check active queues
SELECT 
    service_class,
    num_query_tasks,
    num_executing_queries,
    num_queued_queries
FROM stv_wlm_service_class_state 
WHERE service_class >= 5;
```

### Monitor Performance
```bash
# View CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name $(terraform output -raw dashboard_name)

# Check alarm status
aws cloudwatch describe-alarms \
    --alarm-names $(terraform output -raw alarm_names)
```

## Customization

### Key Configuration Variables

**CloudFormation Parameters:**
- `ClusterIdentifier`: Unique identifier for the Redshift cluster
- `InstanceType`: Redshift node instance type (default: dc2.large)
- `NotificationEmail`: Email address for CloudWatch alerts
- `Environment`: Environment tag (dev/staging/prod)

**CDK Context Variables:**
- `clusterIdentifier`: Unique identifier for the Redshift cluster
- `notificationEmail`: Email address for CloudWatch alerts
- `instanceType`: Redshift node instance type
- `enableLogging`: Enable audit logging (default: true)

**Terraform Variables:**
- `cluster_identifier`: Unique identifier for the Redshift cluster
- `instance_type`: Redshift node instance type (default: dc2.large)
- `notification_email`: Email address for CloudWatch alerts
- `region`: AWS region for deployment
- `environment`: Environment tag (dev/staging/prod)

### WLM Queue Customization

To modify queue configurations, update the WLM JSON in your chosen IaC implementation:

```json
{
  "user_group": "custom-group",
  "query_group": "custom",
  "query_concurrency": 10,
  "memory_percent_to_use": 30,
  "max_execution_time": 1800000
}
```

### Adding Query Monitoring Rules

Extend the WLM configuration with custom rules:

```json
{
  "rules": [
    {
      "rule_name": "custom_timeout_rule",
      "predicate": "query_execution_time > 300",
      "action": "abort"
    }
  ]
}
```

## Monitoring and Alerting

The deployment includes:

- **CloudWatch Dashboard**: Visual monitoring of WLM metrics
- **CloudWatch Alarms**: Automated alerting for performance issues
- **SNS Topic**: Email notifications for critical events

### Key Metrics to Monitor

- **Queue Length**: Indicates query backlog and resource contention
- **CPU Utilization**: Shows overall cluster load
- **Query Completion Rate**: Detects system performance degradation
- **Query Abort Rate**: Monitors query monitoring rule effectiveness

### Custom SQL Views

Use the monitoring views created during deployment:

```sql
-- Monitor queue performance
SELECT * FROM wlm_queue_performance;

-- View query monitoring rule actions
SELECT * FROM wlm_rule_actions;

-- Analyze queue wait times
SELECT * FROM wlm_queue_wait_analysis;
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name redshift-wlm-analytics

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name redshift-wlm-analytics
```

### Using CDK TypeScript/Python
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the infrastructure
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Plan destruction
terraform plan -destroy

# Destroy the infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm when prompted
```

## Troubleshooting

### Common Issues

**Parameter Group Not Applied:**
- Ensure cluster has been rebooted after parameter group modification
- Check cluster status: `aws redshift describe-clusters`

**Users Cannot Access Specific Queues:**
- Verify user group membership in Redshift
- Check WLM configuration: `SELECT * FROM stv_wlm_classification_config`

**CloudWatch Alarms Not Triggering:**
- Confirm SNS email subscription is confirmed
- Verify alarm thresholds are appropriate for your workload

**High Queue Wait Times:**
- Review query patterns and resource allocation
- Consider adjusting queue concurrency or memory allocation
- Check for runaway queries using monitoring views

### Performance Optimization

- **Monitor queue utilization** regularly and adjust memory allocation
- **Review query monitoring rules** quarterly and update thresholds
- **Analyze workload patterns** to optimize queue configurations
- **Consider automatic WLM** for simpler management (trade-off: less control)

### Security Considerations

- **Rotate database passwords** regularly
- **Review IAM permissions** periodically
- **Enable cluster encryption** for sensitive data
- **Monitor access patterns** using CloudTrail
- **Implement VPC security groups** to restrict network access

## Cost Optimization

- **Use Reserved Instances** for production workloads
- **Monitor cluster utilization** and right-size instances
- **Implement pause/resume** for development clusters
- **Review storage costs** and implement data archiving
- **Optimize query performance** to reduce compute time

## Support

For issues with this infrastructure code:

1. **Review the original recipe documentation** for implementation details
2. **Check AWS Redshift documentation** for service-specific guidance
3. **Consult provider documentation** for IaC tool support
4. **Monitor CloudWatch logs** for deployment and runtime issues

### Useful Resources

- [Amazon Redshift Documentation](https://docs.aws.amazon.com/redshift/)
- [WLM Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/cm-c-implementing-workload-management.html)
- [Query Monitoring Rules](https://docs.aws.amazon.com/redshift/latest/mgmt/parameter-group-modify-qmr-console.html)
- [Redshift Performance Tuning](https://docs.aws.amazon.com/redshift/latest/dg/c-optimizing-query-performance.html)