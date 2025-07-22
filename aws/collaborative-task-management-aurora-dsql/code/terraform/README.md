# Real-Time Collaborative Task Management Infrastructure

This Terraform configuration creates a comprehensive serverless task management system using Aurora PostgreSQL Serverless v2, EventBridge, Lambda, and CloudWatch. The infrastructure provides real-time event-driven task processing with multi-region high availability capabilities.

## Architecture Overview

The solution deploys a modern serverless architecture with the following key components:

- **Aurora PostgreSQL Serverless v2**: Global database with active-active multi-region support
- **EventBridge**: Event-driven architecture for decoupled task processing
- **Lambda Functions**: Serverless task processors with automatic scaling
- **CloudWatch**: Comprehensive monitoring, logging, and alerting
- **VPC Networking**: Secure network isolation with private subnets
- **Secrets Manager**: Secure database credential management
- **Dead Letter Queues**: Error handling and message durability

## Features

### Core Capabilities
- ✅ Real-time collaborative task management
- ✅ Event-driven architecture with EventBridge
- ✅ Multi-region deployment for high availability
- ✅ Serverless auto-scaling with Aurora Serverless v2
- ✅ Comprehensive monitoring and alerting
- ✅ Secure networking with VPC and security groups
- ✅ Encrypted data at rest and in transit
- ✅ Dead letter queues for error handling

### Advanced Features
- ✅ X-Ray distributed tracing
- ✅ CloudWatch Insights for log analysis
- ✅ Custom CloudWatch dashboards
- ✅ Provisioned concurrency options
- ✅ Cost allocation tags
- ✅ Event replay capabilities
- ✅ Performance Insights for database monitoring

## Prerequisites

1. **AWS Account**: Active AWS account with appropriate permissions
2. **Terraform**: Version >= 1.5.0 installed
3. **AWS CLI**: Version 2.x configured with credentials
4. **Permissions**: IAM permissions for creating all required resources

### Required AWS Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:*",
        "lambda:*",
        "events:*",
        "ec2:*",
        "iam:*",
        "logs:*",
        "secretsmanager:*",
        "kms:*",
        "sqs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository (if needed)
git clone <repository-url>
cd aws/real-time-collaborative-task-management-aurora-dsql-eventbridge/code/terraform/

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your configuration
vi terraform.tfvars
```

### 2. Initialize and Plan

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Apply the configuration
terraform apply

# Confirm deployment
# Type 'yes' when prompted
```

### 4. Verify Deployment

```bash
# Check Lambda function
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `real-time-task-mgmt`)].FunctionName'

# Check Aurora cluster
aws rds describe-db-clusters --query 'DBClusters[?starts_with(DBClusterIdentifier, `real-time-task-mgmt`)].Status'

# Check EventBridge bus
aws events list-event-buses --query 'EventBuses[?starts_with(Name, `real-time-task-mgmt`)].Name'
```

## Configuration

### Basic Configuration

The most common variables you'll need to configure:

```hcl
# terraform.tfvars
environment = "dev"
aws_region = "us-east-1"
secondary_region = "us-west-2"
project_name = "my-task-system"

# Enable multi-region for production
enable_multi_region_deployment = true

# Database settings
enable_database_encryption = true
dsql_deletion_protection = false  # Set to true for production
```

### Production Configuration

For production environments, consider these settings:

```hcl
# terraform.tfvars (production)
environment = "prod"
dsql_deletion_protection = true
lambda_memory_size = 1024
lambda_timeout = 300
lambda_reserved_concurrency = 100
lambda_provisioned_concurrency = 10
log_retention_days = 30
enable_multi_region_deployment = true
enable_dead_letter_queue = true
allowed_cidr_blocks = ["10.0.0.0/8"]  # Restrict network access
```

## Usage

### Testing the Task Management API

1. **Create a Test Task**:
```bash
# Send test event to EventBridge
aws events put-events --entries '[{
  "Source": "task.management",
  "DetailType": "Task Created",
  "Detail": "{\"eventType\":\"task.created\",\"taskData\":{\"title\":\"Test Task\",\"description\":\"Testing the system\",\"priority\":\"high\",\"assigned_to\":\"user@example.com\",\"created_by\":\"manager@example.com\"}}",
  "EventBusName": "real-time-task-mgmt-events-xxxxx"
}]'
```

2. **Invoke Lambda Directly**:
```bash
# Get all tasks
aws lambda invoke \
  --function-name real-time-task-mgmt-processor-xxxxx \
  --payload '{"httpMethod":"GET","path":"/tasks"}' \
  response.json

cat response.json
```

3. **Monitor Logs**:
```bash
# View recent Lambda logs
aws logs tail /aws/lambda/real-time-task-mgmt-processor-xxxxx --follow
```

### Database Schema

The system automatically creates these PostgreSQL tables:

- **tasks**: Main task storage with metadata
- **task_updates**: Audit trail for task changes

Connect to the database using the credentials from Secrets Manager:

```bash
# Get database credentials
aws secretsmanager get-secret-value --secret-id real-time-task-mgmt-cluster-xxxxx-credentials

# Connect using psql (example)
psql -h cluster-endpoint -U postgres -d taskmanagement
```

## Monitoring

### CloudWatch Dashboard

Access the monitoring dashboard:
```
https://us-east-1.console.aws.amazon.com/cloudwatch/home#dashboards:name=real-time-task-mgmt-dashboard
```

Key metrics monitored:
- Lambda function invocations, errors, duration
- EventBridge successful/failed invocations  
- Aurora cluster performance metrics
- VPC networking metrics

### Alarms and Notifications

The system creates CloudWatch alarms for:
- Lambda function errors (> 5 errors in 10 minutes)
- Lambda function duration (> 80% of timeout)
- Lambda function throttles

Configure SNS notifications by setting the `notification_endpoints` variable:

```hcl
notification_endpoints = [
  "arn:aws:sns:us-east-1:123456789012:task-management-alerts"
]
```

## Cost Optimization

### Estimated Monthly Costs (Development)

| Service | Cost Range |
|---------|------------|
| Aurora PostgreSQL Serverless v2 | $15-30 |
| Lambda (based on invocations) | $5-15 |
| EventBridge (based on events) | $1-5 |
| CloudWatch (logs and metrics) | $2-8 |
| VPC (NAT Gateway) | $5-10 |
| KMS, Secrets Manager | $1-2 |
| **Total Estimated** | **$29-70/month** |

**Note**: Production workloads and multi-region deployment will have higher costs.

### Cost Optimization Tips

1. **Use Provisioned Concurrency Sparingly**: Only for functions requiring consistent low latency
2. **Optimize Lambda Memory**: Right-size based on actual usage patterns
3. **Configure Log Retention**: Set appropriate retention periods (7-30 days)
4. **Monitor Reserved Concurrency**: Avoid over-provisioning concurrent executions
5. **Use Spot Instances**: For development/test environments (not applicable to serverless)

## Security

### Security Features

- **Encryption**: All data encrypted at rest and in transit
- **Network Security**: Private VPC with security groups
- **Access Control**: IAM roles with least privilege
- **Secrets Management**: Database credentials in Secrets Manager
- **Audit Trail**: All task changes logged in database
- **Monitoring**: CloudWatch logs and X-Ray tracing

### Security Best Practices

1. **Restrict Network Access**: Update `allowed_cidr_blocks` for production
2. **Enable Deletion Protection**: Set `dsql_deletion_protection = true`
3. **Regular Rotation**: Enable automatic secret rotation
4. **Monitor Access**: Review CloudTrail logs regularly
5. **Update Dependencies**: Keep Lambda runtime updated

## Troubleshooting

### Common Issues

1. **Lambda VPC Timeout**:
   - Check NAT Gateway configuration
   - Verify security group rules
   - Ensure proper subnet routing

2. **Database Connection Errors**:
   - Verify Aurora cluster is in "available" state
   - Check security group allows port 5432
   - Confirm Lambda is in correct VPC subnets

3. **EventBridge Events Not Processing**:
   - Check EventBridge rule patterns
   - Verify Lambda permissions
   - Review dead letter queue messages

4. **High Costs**:
   - Check NAT Gateway data transfer
   - Review Lambda memory/timeout settings
   - Monitor Aurora scaling patterns

### Debug Commands

```bash
# Check Terraform state
terraform state list
terraform show

# Validate configuration
terraform validate
terraform plan

# Check AWS resources
aws lambda get-function --function-name <function-name>
aws rds describe-db-clusters --db-cluster-identifier <cluster-id>
aws events describe-rule --name <rule-name> --event-bus-name <bus-name>

# View logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
aws logs tail <log-group-name> --follow
```

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

### Manual Cleanup (if needed)

Some resources might require manual cleanup:

```bash
# Delete remaining Lambda ENIs (if VPC deployment fails)
aws ec2 describe-network-interfaces --filters Name=description,Values="AWS Lambda VPC ENI*" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text | xargs -r aws ec2 delete-network-interface --network-interface-id

# Empty and delete S3 buckets (if any were created)
# Check for any remaining resources in AWS Console
```

## Support and Contributing

### Getting Help

1. **Documentation**: Refer to AWS service documentation
2. **Terraform Registry**: Check provider documentation
3. **GitHub Issues**: Report bugs or request features
4. **AWS Support**: For service-specific issues

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable  
5. Submit a pull request

## License

This Terraform configuration is provided as-is under the MIT License. See LICENSE file for details.

---

**Note**: This infrastructure creates real AWS resources that incur charges. Always review costs and destroy resources when no longer needed.