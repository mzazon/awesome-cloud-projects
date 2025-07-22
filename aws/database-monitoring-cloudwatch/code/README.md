# Infrastructure as Code for Database Monitoring Dashboards with CloudWatch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Monitoring Dashboards with CloudWatch".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS IAM permissions for:
  - RDS instance creation and management
  - CloudWatch dashboard and alarm creation
  - SNS topic creation and management
  - IAM role creation for enhanced monitoring
- Email address for receiving database alerts

### Required AWS Permissions

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rds:*",
                "cloudwatch:*",
                "sns:*",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:GetRole",
                "iam:DeleteRole",
                "iam:DetachRolePolicy"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Start

### Using CloudFormation

```bash
# Set your email for notifications
export ALERT_EMAIL="your-email@example.com"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name database-monitoring-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=AlertEmail,ParameterValue=${ALERT_EMAIL} \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name database-monitoring-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name database-monitoring-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables
export CDK_DEFAULT_REGION=us-east-1
export ALERT_EMAIL="your-email@example.com"

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters alertEmail=${ALERT_EMAIL}

# View outputs
cdk outputs
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export CDK_DEFAULT_REGION=us-east-1
export ALERT_EMAIL="your-email@example.com"

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters alertEmail=${ALERT_EMAIL}

# View outputs
cdk outputs
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
region = "us-east-1"
alert_email = "your-email@example.com"
db_password = "MySecurePassword123!"
EOF

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set environment variables
export AWS_REGION=us-east-1
export ALERT_EMAIL="your-email@example.com"

# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output important information including:
# - Database endpoint
# - Dashboard URL
# - SNS topic ARN
```

## Configuration Options

### CloudFormation Parameters

- `AlertEmail` (Required): Email address for database alerts
- `DBInstanceClass` (Default: db.t3.micro): RDS instance class
- `DBPassword` (Default: MySecurePassword123!): Database master password
- `MonitoringInterval` (Default: 60): Enhanced monitoring interval in seconds

### CDK Parameters

Configure parameters in `cdk.json` or pass via command line:

```json
{
  "context": {
    "alertEmail": "your-email@example.com",
    "dbInstanceClass": "db.t3.micro",
    "monitoringInterval": 60
  }
}
```

### Terraform Variables

Customize in `terraform.tfvars`:

```hcl
region = "us-east-1"
alert_email = "your-email@example.com"
db_instance_class = "db.t3.micro"
db_password = "MySecurePassword123!"
monitoring_interval = 60
allocated_storage = 20
backup_retention_period = 7
```

## Post-Deployment Steps

1. **Confirm SNS Subscription**:
   - Check your email for an SNS subscription confirmation
   - Click the confirmation link to receive alerts

2. **Access CloudWatch Dashboard**:
   - Navigate to CloudWatch console in your AWS region
   - Find the dashboard named "DatabaseMonitoring-[random-suffix]"
   - Bookmark the dashboard URL for easy access

3. **Verify Alarms**:
   - Check CloudWatch Alarms console
   - Ensure all alarms show "OK" or "INSUFFICIENT_DATA" status
   - Test alarm functionality if desired

4. **Connect to Database**:
   ```bash
   # Get database endpoint from outputs
   DB_ENDPOINT=$(aws cloudformation describe-stacks \
       --stack-name database-monitoring-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`DatabaseEndpoint`].OutputValue' \
       --output text)
   
   # Connect using MySQL client
   mysql -h ${DB_ENDPOINT} -u admin -p
   ```

## Monitoring Features

This solution provides comprehensive database monitoring including:

### CloudWatch Dashboard Widgets

- **Database Performance Overview**: CPU utilization, database connections, freeable memory
- **Storage and Latency Metrics**: Free storage space, read/write latency
- **I/O Performance Metrics**: Read/write IOPS and throughput

### CloudWatch Alarms

- **High CPU Utilization**: Triggers when CPU > 80% for 10 minutes
- **High Database Connections**: Triggers when connections > 50 for 10 minutes
- **Low Storage Space**: Triggers when free storage < 2GB

### Enhanced Monitoring

- OS-level metrics collected every 60 seconds
- Detailed CPU, memory, file system, and network statistics
- Available in CloudWatch Logs under `/aws/rds/instance/[instance-id]/enhanced-monitoring`

## Cost Considerations

Estimated monthly costs (us-east-1 region):

- **RDS db.t3.micro instance**: ~$15/month
- **Enhanced monitoring (60-second intervals)**: ~$2.50/month
- **CloudWatch dashboard**: Free (up to 3 dashboards)
- **CloudWatch alarms**: ~$0.30/month (3 alarms)
- **SNS notifications**: Minimal cost for email delivery

**Total estimated cost**: ~$18/month

## Troubleshooting

### Common Issues

1. **Database creation fails**:
   - Check VPC and security group configurations
   - Verify IAM permissions for RDS operations
   - Ensure password meets complexity requirements

2. **Alarms not triggering**:
   - Verify SNS topic subscription is confirmed
   - Check alarm thresholds and evaluation periods
   - Ensure database is generating metric data

3. **Dashboard not showing data**:
   - Wait 5-10 minutes for initial metrics to appear
   - Verify database instance is in "available" state
   - Check CloudWatch metrics in the AWS console

4. **Enhanced monitoring not working**:
   - Verify IAM role has correct permissions
   - Check monitoring interval configuration
   - Ensure monitoring role ARN is correctly specified

### Debugging Commands

```bash
# Check RDS instance status
aws rds describe-db-instances \
    --db-instance-identifier [instance-id]

# View alarm history
aws cloudwatch describe-alarm-history \
    --alarm-name [alarm-name]

# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn [topic-arn]

# View CloudWatch metrics
aws cloudwatch list-metrics \
    --namespace AWS/RDS \
    --dimensions Name=DBInstanceIdentifier,Value=[instance-id]
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name database-monitoring-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name database-monitoring-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Best Practices

This implementation follows AWS security best practices:

- **Encryption**: Database encrypted at rest using default KMS key
- **Network Security**: Database deployed in default VPC with security groups
- **Access Control**: IAM roles with least privilege permissions
- **Monitoring**: Enhanced monitoring enabled for security visibility
- **Backup**: Automated backups enabled with 7-day retention

## Customization

### Adding Custom Metrics

To monitor additional database metrics, modify the dashboard configuration:

```json
{
    "type": "metric",
    "properties": {
        "metrics": [
            ["AWS/RDS", "CustomMetricName", "DBInstanceIdentifier", "instance-id"]
        ],
        "title": "Custom Database Metrics"
    }
}
```

### Creating Additional Alarms

Add new alarms for other critical metrics:

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "DatabaseReadLatency" \
    --metric-name ReadLatency \
    --namespace AWS/RDS \
    --statistic Average \
    --threshold 0.2 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions [sns-topic-arn] \
    --dimensions Name=DBInstanceIdentifier,Value=[instance-id]
```

### Multi-Instance Monitoring

To monitor multiple database instances, modify the Terraform configuration:

```hcl
variable "db_instances" {
  description = "List of database instance configurations"
  type = list(object({
    identifier = string
    class      = string
  }))
  default = [
    {
      identifier = "prod-db"
      class      = "db.t3.small"
    },
    {
      identifier = "staging-db"
      class      = "db.t3.micro"
    }
  ]
}
```

## Support

For issues with this infrastructure code:

1. Review the [original recipe documentation](../database-monitoring-dashboards-cloudwatch.md)
2. Check AWS service documentation:
   - [Amazon RDS User Guide](https://docs.aws.amazon.com/rds/)
   - [Amazon CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)
   - [Amazon SNS Developer Guide](https://docs.aws.amazon.com/sns/)
3. Verify IAM permissions and resource limits
4. Check AWS service health dashboard for regional issues

## Additional Resources

- [Amazon RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [CloudWatch Best Practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html)
- [RDS Enhanced Monitoring](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring.OS.html)
- [Database Performance Tuning](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)