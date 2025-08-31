# Infrastructure as Code for Simple Web Application Deployment with Elastic Beanstalk and CloudWatch

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Web Application Deployment with Elastic Beanstalk and CloudWatch".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- AWS account with Elastic Beanstalk, CloudWatch, and IAM permissions
- Node.js 18+ (for CDK TypeScript)
- Python 3.11+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Appropriate permissions for creating:
  - Elastic Beanstalk applications and environments
  - CloudWatch alarms and log groups
  - IAM roles and policies
  - EC2 instances and security groups
  - S3 buckets for application versions
  - Auto Scaling groups and load balancers

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name simple-web-app-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ApplicationName,ParameterValue=my-simple-app \
                 ParameterKey=EnvironmentName,ParameterValue=my-simple-env \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name simple-web-app-stack

# Get the application URL
aws cloudformation describe-stacks \
    --stack-name simple-web-app-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApplicationURL`].OutputValue' \
    --output text
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Deploy the stack
cdk deploy

# The application URL will be displayed in the output
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not done previously)
cdk bootstrap

# Deploy the stack
cdk deploy

# The application URL will be displayed in the output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get the application URL
terraform output application_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the application URL when complete
```

## Architecture Overview

The infrastructure includes:

- **Elastic Beanstalk Application**: Container for application versions
- **Elastic Beanstalk Environment**: Running infrastructure with auto-scaling
- **CloudWatch Log Groups**: Application and platform log aggregation
- **CloudWatch Alarms**: Monitoring for environment health and error rates
- **IAM Roles**: Service permissions for Elastic Beanstalk and CloudWatch
- **Security Groups**: Network access control for application instances
- **Application Load Balancer**: Traffic distribution and health checks
- **Auto Scaling Group**: Dynamic instance scaling based on demand

## Configuration Options

### Common Parameters

- **Application Name**: Name for the Elastic Beanstalk application
- **Environment Name**: Name for the Elastic Beanstalk environment
- **Instance Type**: EC2 instance type (default: t3.micro)
- **Platform Version**: Elastic Beanstalk platform version for Python
- **Log Retention**: CloudWatch log retention period (default: 7 days)
- **Health Check Path**: Application health check endpoint (default: /health)

### Environment Variables

The implementations support these environment variables:

```bash
export AWS_REGION=us-east-1                    # AWS region
export APP_NAME=my-simple-web-app              # Application name
export ENV_NAME=my-simple-web-env              # Environment name
export INSTANCE_TYPE=t3.micro                 # EC2 instance type
export LOG_RETENTION_DAYS=7                   # CloudWatch log retention
```

## Monitoring and Alerting

The deployed infrastructure includes:

### CloudWatch Alarms

1. **Environment Health Alarm**: Monitors Elastic Beanstalk environment health status
2. **Application Error Alarm**: Monitors 4xx HTTP error rates
3. **Response Time Alarm**: Monitors application response latency (advanced implementations)

### CloudWatch Logs

1. **Application Logs**: Python Flask application logs with structured logging
2. **Platform Logs**: Elastic Beanstalk platform and web server logs
3. **Health Logs**: Enhanced health reporting data

### Metrics Available

- Environment health score
- HTTP request counts and error rates
- Application response times
- Instance CPU and memory utilization
- Load balancer metrics

## Application Details

The deployed application includes:

- **Main Route** (`/`): Welcome page with application status
- **Health Check** (`/health`): JSON health endpoint for monitoring
- **Info API** (`/api/info`): Application metadata endpoint
- **Structured Logging**: Automatic CloudWatch integration
- **Error Handling**: Graceful error responses

## Cost Considerations

Estimated costs (US East region):

- **t3.micro instance**: ~$0.0104/hour (Free Tier eligible)
- **Application Load Balancer**: ~$0.0225/hour
- **CloudWatch Logs**: ~$0.50/GB ingested
- **CloudWatch Alarms**: $0.10/alarm/month
- **S3 Storage**: ~$0.023/GB/month (for application versions)

**Total estimated cost**: $0.50-$2.00/day for development/testing

> **Note**: Actual costs may vary based on usage patterns and AWS Free Tier eligibility.

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name simple-web-app-stack

# Wait for stack deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name simple-web-app-stack
```

### Using CDK (AWS)

```bash
# Destroy the CDK stack
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

## Customization

### Adding Custom Metrics

To add custom CloudWatch metrics to your application:

```python
import boto3

cloudwatch = boto3.client('cloudwatch')

def put_custom_metric(metric_name, value, unit='Count'):
    cloudwatch.put_metric_data(
        Namespace='SimpleWebApp/Custom',
        MetricData=[
            {
                'MetricName': metric_name,
                'Value': value,
                'Unit': unit
            }
        ]
    )
```

### Environment Configuration

Create `.ebextensions/environment.config` for custom environment variables:

```yaml
option_settings:
  aws:elasticbeanstalk:application:environment:
    DEBUG: false
    LOG_LEVEL: INFO
    CUSTOM_CONFIG: production
```

### Database Integration

To add RDS database support, update the infrastructure code to include:

- RDS instance configuration
- Database security groups
- Environment variables for database connection
- IAM permissions for RDS access

### SSL/TLS Certificate

To add HTTPS support:

1. Request an SSL certificate through AWS Certificate Manager
2. Configure the load balancer to use the certificate
3. Update security groups to allow HTTPS traffic
4. Redirect HTTP to HTTPS

## Troubleshooting

### Common Issues

1. **Deployment Fails**: Check IAM permissions and resource limits
2. **Application Won't Start**: Review CloudWatch logs for startup errors
3. **Health Check Fails**: Verify the `/health` endpoint responds correctly
4. **High Costs**: Check if resources are properly sized and cleaned up

### Debugging Commands

```bash
# Check environment status
aws elasticbeanstalk describe-environments \
    --environment-names YOUR_ENV_NAME

# View recent logs
aws logs describe-log-streams \
    --log-group-name "/aws/elasticbeanstalk/YOUR_ENV_NAME/var/log/eb-engine.log"

# Check alarm status
aws cloudwatch describe-alarms \
    --state-value ALARM
```

## Security Best Practices

The infrastructure implements:

- **Least Privilege IAM**: Minimal required permissions for each service
- **Security Groups**: Restricted network access
- **Log Encryption**: CloudWatch logs encrypted at rest
- **Platform Updates**: Latest Elastic Beanstalk platform version
- **Health Monitoring**: Continuous environment health monitoring

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation at `../simple-web-deployment-beanstalk-cloudwatch.md`
2. Check AWS Elastic Beanstalk documentation: https://docs.aws.amazon.com/elasticbeanstalk/
3. Review CloudWatch documentation: https://docs.aws.amazon.com/cloudwatch/
4. AWS support forums and Stack Overflow for community assistance

## Contributing

To improve these Infrastructure as Code implementations:

1. Test changes in a development environment
2. Follow AWS best practices and security guidelines  
3. Update documentation to match any infrastructure changes
4. Validate all code syntax before submitting