# Infrastructure as Code for Optimizing Amazon Redshift Performance

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Optimizing Amazon Redshift Performance".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a comprehensive Redshift performance optimization solution including:

- Amazon Redshift cluster with optimized configuration
- Workload Management (WLM) parameter group with automatic concurrency scaling
- CloudWatch monitoring dashboard and custom metrics
- SNS topic for performance alerts
- Lambda function for automated maintenance (VACUUM/ANALYZE)
- EventBridge scheduled rules for nightly maintenance
- CloudWatch alarms for proactive monitoring
- IAM roles and policies with least privilege access

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- Node.js 18+ and npm (for CDK TypeScript)
- Python 3.8+ and pip (for CDK Python)
- Terraform 1.0+ (for Terraform deployment)
- Appropriate AWS permissions for:
  - Amazon Redshift cluster management
  - IAM role and policy creation
  - Lambda function deployment
  - CloudWatch dashboard and alarm management
  - SNS topic creation
  - EventBridge rule configuration

## Cost Considerations

This solution includes the following billable components:
- Amazon Redshift cluster (varies by node type and quantity)
- Lambda function execution (minimal cost for maintenance operations)
- CloudWatch custom metrics and alarms
- SNS message delivery
- EventBridge rule executions (minimal cost)

Estimated monthly cost: $200-2000+ depending on cluster size and usage patterns.

## Quick Start

### Using CloudFormation

```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
    --stack-name redshift-performance-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=RedshiftClusterIdentifier,ParameterValue=my-redshift-cluster \
                 ParameterKey=DatabaseName,ParameterValue=mydb \
                 ParameterKey=MasterUsername,ParameterValue=admin \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Monitor stack creation progress
aws cloudformation describe-stacks \
    --stack-name redshift-performance-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the infrastructure
cdk deploy \
    --parameters redshiftClusterIdentifier=my-redshift-cluster \
    --parameters databaseName=mydb \
    --parameters masterUsername=admin

# Verify deployment
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

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the infrastructure
cdk deploy \
    -c redshift_cluster_identifier=my-redshift-cluster \
    -c database_name=mydb \
    -c master_username=admin

# Verify deployment
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your configurations
cat > terraform.tfvars << EOF
redshift_cluster_identifier = "my-redshift-cluster"
database_name               = "mydb"
master_username            = "admin"
aws_region                 = "us-east-1"
notification_email         = "your-email@example.com"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export REDSHIFT_CLUSTER_IDENTIFIER="my-redshift-cluster"
export DATABASE_NAME="mydb"
export MASTER_USERNAME="admin"
export AWS_REGION="us-east-1"
export NOTIFICATION_EMAIL="your-email@example.com"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
aws redshift describe-clusters \
    --cluster-identifier $REDSHIFT_CLUSTER_IDENTIFIER
```

## Configuration Options

### Environment Variables

All implementations support these configuration variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `REDSHIFT_CLUSTER_IDENTIFIER` | Unique identifier for the Redshift cluster | `redshift-performance-cluster` | Yes |
| `DATABASE_NAME` | Initial database name | `perfdb` | Yes |
| `MASTER_USERNAME` | Master username for the cluster | `admin` | Yes |
| `AWS_REGION` | AWS region for deployment | `us-east-1` | Yes |
| `NOTIFICATION_EMAIL` | Email for performance alerts | - | Yes |
| `NODE_TYPE` | Redshift node type | `dc2.large` | No |
| `NUMBER_OF_NODES` | Number of nodes in cluster | `2` | No |
| `MAINTENANCE_WINDOW` | Preferred maintenance window | `Sun:03:00-Sun:04:00` | No |

### Performance Tuning Parameters

The solution configures optimal settings for:
- Automatic Workload Management (WLM)
- Concurrency scaling
- Query monitoring rules
- Maintenance scheduling
- Monitoring thresholds

## Post-Deployment Steps

1. **Configure Database Connection**:
   ```bash
   # Get cluster endpoint
   CLUSTER_ENDPOINT=$(aws redshift describe-clusters \
       --cluster-identifier $REDSHIFT_CLUSTER_IDENTIFIER \
       --query 'Clusters[0].Endpoint.Address' --output text)
   
   # Connect using psql
   psql -h $CLUSTER_ENDPOINT -U admin -d mydb -p 5439
   ```

2. **Load Sample Data** (Optional):
   ```sql
   -- Create sample table for testing
   CREATE TABLE IF NOT EXISTS sales_data (
       order_id INT,
       customer_id INT,
       order_date DATE,
       sales_amount DECIMAL(10,2),
       customer_segment VARCHAR(50)
   );
   
   -- Insert sample data for performance testing
   INSERT INTO sales_data VALUES 
   (1, 100, CURRENT_DATE - 30, 1500.00, 'Enterprise'),
   (2, 101, CURRENT_DATE - 25, 750.50, 'SMB'),
   (3, 102, CURRENT_DATE - 20, 2200.75, 'Enterprise');
   ```

3. **Verify Monitoring Setup**:
   ```bash
   # Check CloudWatch dashboard
   aws cloudwatch get-dashboard \
       --dashboard-name "Redshift-Performance-Dashboard"
   
   # Verify SNS subscription
   aws sns list-subscriptions-by-topic \
       --topic-arn $(aws sns list-topics --query 'Topics[?contains(TopicArn, `redshift-performance-alerts`)].TopicArn' --output text)
   ```

4. **Test Automated Maintenance**:
   ```bash
   # Manually trigger maintenance function
   aws lambda invoke \
       --function-name redshift-maintenance-function \
       --payload '{}' \
       response.json
   
   # Check function logs
   aws logs describe-log-groups \
       --log-group-name-prefix "/aws/lambda/redshift-maintenance"
   ```

## Monitoring and Alerting

### CloudWatch Dashboard

The solution creates a comprehensive dashboard with:
- Cluster CPU utilization
- Database connections
- Query queue metrics
- Workload management statistics
- Disk space utilization

Access the dashboard at: AWS Console → CloudWatch → Dashboards → "Redshift-Performance-Dashboard"

### Performance Alerts

Configured alerts include:
- **High CPU Usage**: Triggers when CPU > 80% for 10 minutes
- **High Queue Length**: Triggers when query queue > 10 queries
- **Storage Usage**: Triggers when disk usage > 85%
- **Connection Limit**: Triggers when connections > 90% of limit

### Maintenance Automation

The automated maintenance system:
- Runs nightly at 2:00 AM UTC
- Analyzes table statistics and unsorted data percentages
- Performs VACUUM and ANALYZE operations on tables that need it
- Sends notifications on completion or failure
- Logs detailed execution information to CloudWatch

## Troubleshooting

### Common Issues

1. **Cluster Creation Fails**:
   ```bash
   # Check cluster status
   aws redshift describe-clusters \
       --cluster-identifier $REDSHIFT_CLUSTER_IDENTIFIER
   
   # Review CloudFormation events (if using CloudFormation)
   aws cloudformation describe-stack-events \
       --stack-name redshift-performance-stack
   ```

2. **Lambda Function Errors**:
   ```bash
   # Check function logs
   aws logs filter-log-events \
       --log-group-name "/aws/lambda/redshift-maintenance-function" \
       --start-time $(date -d '1 hour ago' +%s)000
   ```

3. **Monitoring Dashboard Not Loading**:
   ```bash
   # Verify dashboard exists
   aws cloudwatch list-dashboards \
       --query 'DashboardEntries[?DashboardName==`Redshift-Performance-Dashboard`]'
   
   # Check CloudWatch permissions
   aws iam get-role-policy \
       --role-name RedshiftPerformanceRole \
       --policy-name CloudWatchAccessPolicy
   ```

### Performance Optimization Tips

1. **Monitor Query Performance**:
   ```sql
   -- Check slow queries
   SELECT query, total_exec_time/1000000.0 as exec_seconds, querytxt
   FROM stl_query 
   WHERE total_exec_time > 30000000  -- > 30 seconds
   ORDER BY total_exec_time DESC 
   LIMIT 10;
   ```

2. **Analyze Table Distribution**:
   ```sql
   -- Check table skew
   SELECT TRIM(name) as table_name,
          max_blocks_per_slice - min_blocks_per_slice as skew
   FROM svv_table_info 
   WHERE skew > 5
   ORDER BY skew DESC;
   ```

3. **Review WLM Queue Performance**:
   ```sql
   -- Check queue wait times
   SELECT service_class, queue_time, exec_time
   FROM stl_wlm_query 
   WHERE queue_time > 0
   ORDER BY queue_time DESC 
   LIMIT 10;
   ```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name redshift-performance-stack

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name redshift-performance-stack
```

### Using CDK

```bash
# CDK TypeScript
cd cdk-typescript/
cdk destroy

# CDK Python
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
aws redshift describe-clusters \
    --cluster-identifier $REDSHIFT_CLUSTER_IDENTIFIER 2>/dev/null || echo "Cluster deleted"
```

### Manual Cleanup Verification

After running any cleanup method, verify all resources are removed:

```bash
# Check for remaining resources
aws redshift describe-clusters --query 'Clusters[?ClusterIdentifier==`'$REDSHIFT_CLUSTER_IDENTIFIER'`]'
aws lambda list-functions --query 'Functions[?contains(FunctionName, `redshift-maintenance`)]'
aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `Redshift-Performance`)]'
aws sns list-topics --query 'Topics[?contains(TopicArn, `redshift-performance-alerts`)]'
```

## Customization

### Modifying Cluster Configuration

To customize the Redshift cluster:

1. **CloudFormation**: Edit parameters in `cloudformation.yaml`
2. **CDK**: Modify cluster properties in the stack definition
3. **Terraform**: Update variables in `terraform.tfvars`
4. **Scripts**: Modify environment variables in `deploy.sh`

### Adding Custom Metrics

To add custom CloudWatch metrics:

1. Modify the Lambda maintenance function
2. Add new CloudWatch alarms
3. Update the monitoring dashboard configuration
4. Configure additional SNS notifications

### Extending Maintenance Operations

To customize automated maintenance:

1. Edit the Lambda function code
2. Modify the EventBridge schedule
3. Add new maintenance criteria
4. Configure maintenance windows

## Security Considerations

This solution implements security best practices:

- **IAM Roles**: Least privilege access for all components
- **Encryption**: Encryption at rest and in transit for Redshift
- **Network Security**: VPC security groups for cluster access
- **Secret Management**: Secure handling of database credentials
- **Audit Logging**: CloudTrail integration for API calls

For production environments:
- Use AWS Secrets Manager for database passwords
- Implement VPC endpoints for service communication
- Enable GuardDuty for threat detection
- Configure AWS Config for compliance monitoring

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS service status at https://status.aws.amazon.com/
3. Consult AWS documentation for specific services
4. Use AWS Support for production issues

For questions about specific implementations:
- **CloudFormation**: [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- **CDK**: [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- **Terraform**: [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Additional Resources

- [Amazon Redshift Performance Tuning Guide](https://docs.aws.amazon.com/redshift/latest/dg/c-optimizing-query-performance.html)
- [Redshift Workload Management Best Practices](https://docs.aws.amazon.com/redshift/latest/dg/cm-c-implementing-workload-management.html)
- [CloudWatch Monitoring for Redshift](https://docs.aws.amazon.com/redshift/latest/mgmt/metrics.html)
- [Redshift System Tables Reference](https://docs.aws.amazon.com/redshift/latest/dg/c_intro_STL_tables.html)