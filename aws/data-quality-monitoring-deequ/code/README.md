# Infrastructure as Code for Real-time Data Quality Monitoring with Deequ on EMR

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Monitoring Data Quality with Deequ on EMR".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)  
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for EMR, S3, CloudWatch, SNS, and IAM
- Email address for SNS notifications
- Basic understanding of data quality concepts and EMR

### Required AWS Permissions

Your AWS credentials must have permissions for:
- EMR cluster creation and management
- S3 bucket creation and object management
- IAM role creation and policy attachment
- CloudWatch dashboard and metrics management
- SNS topic creation and subscription management

### Cost Considerations

- EMR cluster: ~$15-25/hour (m5.xlarge instances)
- S3 storage: Minimal for test data and logs
- CloudWatch: Minimal for metrics and dashboard
- Data transfer: Minimal for this implementation

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name deequ-data-quality-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NotificationEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name deequ-data-quality-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name deequ-data-quality-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=$NOTIFICATION_EMAIL

# View outputs
cdk list --long
```

### Using CDK Python

```bash
cd cdk-python/

# Install dependencies
pip install -r requirements.txt

# Configure email for notifications
export NOTIFICATION_EMAIL=your-email@example.com

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters notificationEmail=$NOTIFICATION_EMAIL

# View outputs
cdk list --long
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Configure variables (create terraform.tfvars)
echo 'notification_email = "your-email@example.com"' > terraform.tfvars
echo 'aws_region = "us-east-1"' >> terraform.tfvars

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NOTIFICATION_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy infrastructure
./scripts/deploy.sh

# The script will output important values like cluster ID and bucket name
```

## Post-Deployment Steps

After deploying the infrastructure, you'll need to:

1. **Confirm SNS subscription**: Check your email and confirm the SNS topic subscription
2. **Upload sample data**: Use the provided scripts to upload test data to S3
3. **Submit monitoring jobs**: Run the data quality monitoring applications
4. **View results**: Check CloudWatch dashboard and S3 reports

### Running Data Quality Monitoring

```bash
# Get cluster ID from deployment outputs
export CLUSTER_ID=j-XXXXXXXXX  # Replace with actual cluster ID
export S3_BUCKET_NAME=deequ-data-quality-xxxxx  # Replace with actual bucket name
export SNS_TOPIC_ARN=arn:aws:sns:us-east-1:xxxx:data-quality-alerts-xxxxx

# Submit monitoring job
aws emr add-steps --cluster-id $CLUSTER_ID \
    --steps '[
        {
            "Name": "DeeQuDataQualityMonitoring",
            "ActionOnFailure": "CONTINUE", 
            "HadoopJarStep": {
                "Jar": "command-runner.jar",
                "Args": [
                    "spark-submit",
                    "--deploy-mode", "cluster",
                    "--master", "yarn",
                    "s3://'$S3_BUCKET_NAME'/scripts/deequ-quality-monitor.py",
                    "'$S3_BUCKET_NAME'",
                    "s3://'$S3_BUCKET_NAME'/raw-data/sample_customer_data.csv",
                    "'$SNS_TOPIC_ARN'"
                ]
            }
        }
    ]'
```

### Accessing Results

- **CloudWatch Dashboard**: Navigate to CloudWatch console → Dashboards → "DeeQuDataQualityMonitoring"
- **Quality Reports**: Check S3 bucket under `quality-reports/` prefix
- **Cluster Logs**: Available in S3 under `logs/` prefix
- **Email Alerts**: Delivered to configured email address when quality issues detected

## Cleanup

### Using CloudFormation

```bash
# Delete the stack (this will clean up all resources)
aws cloudformation delete-stack --stack-name deequ-data-quality-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name deequ-data-quality-stack
```

### Using CDK

```bash
# Destroy the stack
cd cdk-typescript/  # or cdk-python/
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
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Architecture Overview

The infrastructure deploys:

- **EMR Cluster**: 3-node cluster (1 master, 2 core) with m5.xlarge instances
- **S3 Bucket**: Stores data, scripts, logs, and quality reports
- **IAM Roles**: EMR service role and EC2 instance profile with appropriate permissions
- **SNS Topic**: Sends email notifications for data quality alerts
- **CloudWatch Dashboard**: Visualizes data quality metrics
- **Bootstrap Actions**: Automatically installs Deequ on cluster startup

## Customization

### Environment Variables

Key variables you can customize:

- `NOTIFICATION_EMAIL`: Email address for quality alerts
- `AWS_REGION`: AWS region for deployment
- `CLUSTER_NAME`: Name prefix for EMR cluster
- `INSTANCE_TYPE`: EC2 instance type for EMR nodes (default: m5.xlarge)
- `INSTANCE_COUNT`: Number of cluster nodes (default: 3)

### Terraform Variables

Located in `terraform/variables.tf`:

```hcl
variable "notification_email" {
  description = "Email address for data quality notifications"
  type        = string
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for EMR cluster"
  type        = string
  default     = "m5.xlarge"
}

variable "instance_count" {
  description = "Number of instances in EMR cluster"
  type        = number
  default     = 3
}
```

### CloudFormation Parameters

Available parameters in CloudFormation template:

- `NotificationEmail`: Email for SNS notifications
- `InstanceType`: EMR node instance type
- `InstanceCount`: Number of cluster instances
- `EMRReleaseLabel`: EMR software version

### CDK Configuration

Customize through context variables or constructor parameters:

```typescript
// CDK TypeScript example
const cluster = new emr.Cluster(this, 'DeeQuCluster', {
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE),
  instanceCount: 3,
  releaseLabel: 'emr-6.15.0'
});
```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Monitor these key metrics in the dashboard:

- **Size**: Number of records processed
- **Completeness**: Percentage of non-null values
- **Uniqueness**: Percentage of unique values
- **Mean/StandardDeviation**: Statistical distribution metrics

### Common Issues

1. **EMR Cluster Fails to Start**
   - Check IAM permissions
   - Verify subnet has internet access
   - Check EMR service limits

2. **Deequ Jobs Fail**
   - Verify bootstrap script executed successfully
   - Check cluster logs in S3
   - Ensure sufficient cluster resources

3. **No Metrics in CloudWatch**
   - Verify IAM permissions for CloudWatch
   - Check Spark application logs
   - Ensure metrics publication code executed

4. **SNS Alerts Not Received**
   - Confirm email subscription
   - Check SNS topic permissions
   - Verify alert triggering logic

### Log Locations

- **EMR Cluster Logs**: `s3://bucket-name/logs/cluster-id/`
- **Application Logs**: `s3://bucket-name/logs/cluster-id/steps/step-id/`
- **Quality Reports**: `s3://bucket-name/quality-reports/`

## Security Considerations

### IAM Best Practices

- Uses least-privilege access patterns
- Separate roles for EMR service and EC2 instances
- No hardcoded credentials in code

### Data Protection

- S3 bucket with appropriate access controls
- EMR cluster in private subnets (recommended)
- Encryption at rest and in transit supported

### Network Security

- Configure VPC security groups appropriately
- Use private subnets for EMR clusters in production
- Implement VPC endpoints for AWS services if needed

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **AWS Documentation**: Check official AWS service documentation
3. **Provider Forums**: AWS forums and Stack Overflow
4. **Service Limits**: Verify AWS service limits in your account

### Useful AWS CLI Commands

```bash
# Check EMR cluster status
aws emr describe-cluster --cluster-id j-XXXXXXXXX

# List EMR steps
aws emr list-steps --cluster-id j-XXXXXXXXX

# Check S3 bucket contents
aws s3 ls s3://bucket-name --recursive

# View CloudWatch metrics
aws cloudwatch list-metrics --namespace "DataQuality/Deequ"

# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn arn:aws:sns:region:account:topic
```

## Cost Optimization

- **EMR Clusters**: Terminate when not in use
- **S3 Lifecycle Policies**: Archive old reports to cheaper storage classes
- **CloudWatch Logs**: Set retention periods appropriately
- **Spot Instances**: Consider using spot instances for cost savings

## Next Steps

After successful deployment:

1. Customize data quality rules for your datasets
2. Integrate with your data pipelines
3. Set up automated monitoring schedules
4. Implement data remediation workflows
5. Expand to additional data sources