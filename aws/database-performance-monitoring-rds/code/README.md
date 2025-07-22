# Infrastructure as Code for Database Performance Monitoring with RDS Insights

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Performance Monitoring with RDS Insights".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a comprehensive database performance monitoring system using:

- **RDS MySQL Instance** with Performance Insights enabled
- **Lambda Functions** for automated performance analysis
- **CloudWatch Alarms** for proactive monitoring
- **EventBridge Rules** for automated scheduling
- **S3 Bucket** for performance report storage
- **SNS Topic** for alert notifications
- **IAM Roles** with least privilege access

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with administrative permissions for RDS, Lambda, CloudWatch, and IAM
- Email address for receiving performance alerts
- Basic understanding of database performance monitoring concepts

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CloudFormation CLI (included with AWS CLI)
- Appropriate IAM permissions for CloudFormation stack operations

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK v2 (`npm install -g aws-cdk`)
- TypeScript (`npm install -g typescript`)

#### CDK Python
- Python 3.9 or later
- AWS CDK v2 (`pip install aws-cdk-lib`)
- Required Python packages (see `requirements.txt`)

#### Terraform
- Terraform 1.0 or later
- AWS Provider for Terraform

#### Bash Scripts
- Bash shell environment
- AWS CLI v2 configured with appropriate credentials

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name rds-performance-monitoring \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name rds-performance-monitoring \
    --query 'Stacks[0].StackStatus'

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name rds-performance-monitoring
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Configure notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Configure notification email
export NOTIFICATION_EMAIL=your-email@example.com

# Deploy the stack
cdk deploy --require-approval never

# View stack outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
notification_email = "your-email@example.com"
db_instance_class = "db.t3.small"
enable_enhanced_monitoring = true
performance_insights_retention_period = 7
EOF

# Review planned changes
terraform plan

# Apply configuration
terraform apply -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=$(aws configure get region)

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for confirmation and display progress
```

## Post-Deployment Configuration

### 1. Confirm SNS Subscription

After deployment, check your email for an SNS subscription confirmation and click the confirmation link.

### 2. Generate Test Load

Connect to your RDS instance and run some queries to generate performance data:

```bash
# Get RDS endpoint from outputs
DB_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier <your-db-identifier> \
    --query "DBInstances[0].Endpoint.Address" \
    --output text)

# Connect and run test queries
mysql -h $DB_ENDPOINT -u admin -p
```

### 3. View Performance Insights

Access the Performance Insights dashboard:
- Navigate to RDS in AWS Console
- Select your database instance
- Click on "Performance Insights" tab

### 4. Monitor CloudWatch Dashboard

Access the custom CloudWatch dashboard to view comprehensive performance metrics.

## Customization

### CloudFormation Parameters

- `NotificationEmail`: Email address for performance alerts
- `DBInstanceClass`: RDS instance size (default: db.t3.small)
- `DBUsername`: Database master username (default: admin)
- `EnableEnhancedMonitoring`: Enable detailed OS metrics (default: true)
- `PerformanceInsightsRetentionPeriod`: Data retention days (default: 7)

### CDK Context Variables

Configure in `cdk.context.json` or via environment variables:

```json
{
  "notification-email": "your-email@example.com",
  "db-instance-class": "db.t3.small",
  "enable-enhanced-monitoring": true,
  "performance-insights-retention": 7
}
```

### Terraform Variables

Modify `terraform.tfvars` or use environment variables:

```hcl
notification_email = "your-email@example.com"
db_instance_class = "db.t3.small"
db_username = "admin"
enable_enhanced_monitoring = true
performance_insights_retention_period = 7
allocated_storage = 20
backup_retention_period = 7
```

### Script Environment Variables

Set these before running bash scripts:

```bash
export NOTIFICATION_EMAIL=your-email@example.com
export DB_INSTANCE_CLASS=db.t3.small
export PERFORMANCE_INSIGHTS_RETENTION=7
export ENABLE_ENHANCED_MONITORING=true
```

## Monitoring and Validation

### Verify Deployment

1. **RDS Instance**: Confirm Performance Insights is enabled
2. **Lambda Functions**: Test automated analysis execution
3. **CloudWatch Alarms**: Verify alarm states and thresholds
4. **S3 Bucket**: Check for performance report generation
5. **EventBridge Rules**: Confirm automated scheduling

### Access Monitoring Resources

- **Performance Insights Dashboard**: RDS Console → Performance Insights
- **CloudWatch Dashboard**: CloudWatch Console → Dashboards
- **Lambda Logs**: CloudWatch Logs → `/aws/lambda/performance-analyzer-*`
- **Analysis Reports**: S3 Console → performance-reports bucket

### Key Metrics to Monitor

- Database Load Average
- CPU Utilization
- Database Connections
- I/O Operations Per Second
- Wait Events
- Query Performance

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name rds-performance-monitoring

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name rds-performance-monitoring
```

### Using CDK

```bash
# From CDK directory
cdk destroy --force

# Confirm destruction when prompted
```

### Using Terraform

```bash
# From terraform directory
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Optimization

### Estimated Monthly Costs

- **RDS db.t3.small**: ~$15-25 (On-Demand)
- **Performance Insights**: ~$0.02-0.09 per vCPU hour
- **Lambda Functions**: ~$0.20 per million requests
- **CloudWatch**: ~$0.02 per 1000 custom metrics
- **S3 Storage**: ~$0.023 per GB
- **Enhanced Monitoring**: ~$0.75 per instance per month

### Cost Reduction Strategies

1. **Reserved Instances**: Use RDS Reserved Instances for production
2. **Performance Insights**: Use 7-day retention for non-production
3. **Lambda Optimization**: Adjust memory allocation based on usage
4. **S3 Lifecycle**: Implement lifecycle policies for old reports
5. **CloudWatch Logs**: Set retention periods for log groups

## Troubleshooting

### Common Issues

1. **SNS Subscription**: Check email for confirmation link
2. **Lambda Permissions**: Verify IAM role has Performance Insights access
3. **RDS Connectivity**: Ensure security groups allow access
4. **EventBridge Rules**: Confirm rules are enabled and targets configured

### Debug Steps

1. Check CloudWatch Logs for Lambda function errors
2. Verify Performance Insights is enabled on RDS instance
3. Confirm S3 bucket permissions for report storage
4. Test SNS topic by publishing manual message

### Support Resources

- [AWS RDS Performance Insights Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [CloudWatch Monitoring Best Practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_best_practices.html)

## Security Considerations

### IAM Permissions

- All IAM roles follow least privilege principle
- Lambda functions have minimal required permissions
- Enhanced monitoring role uses AWS managed policy

### Data Protection

- Performance Insights data encrypted at rest
- S3 bucket uses server-side encryption
- CloudWatch Logs encrypted using AWS KMS

### Network Security

- RDS instance deployed in private subnets
- Security groups restrict access to necessary ports
- No public accessibility for database instances

## Advanced Features

### Extending the Solution

1. **Multi-Region Deployment**: Modify for cross-region monitoring
2. **Custom Metrics**: Add application-specific performance metrics
3. **Machine Learning**: Integrate with Amazon SageMaker for anomaly detection
4. **Automation**: Add auto-scaling based on performance metrics

### Integration Options

- **CI/CD Pipelines**: Integrate with AWS CodePipeline
- **Third-Party Tools**: Connect with monitoring platforms
- **Alerting Systems**: Integrate with PagerDuty or Slack
- **Reporting**: Generate scheduled performance reports

## Support

For issues with this infrastructure code, refer to:

1. Original recipe documentation
2. AWS service documentation
3. Provider-specific troubleshooting guides
4. AWS Support (for account-specific issues)

## License

This infrastructure code is provided as-is for educational and reference purposes. Refer to AWS pricing and service terms for production deployments.