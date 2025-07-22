# Infrastructure as Code for Containerized Web Applications with App Runner

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Containerized Web Applications with App Runner".

## Overview

This solution deploys a containerized web application using AWS App Runner with an RDS PostgreSQL database backend, leveraging Secrets Manager for secure credential management and CloudWatch for comprehensive monitoring. The implementation provides fully managed container deployment with automatic scaling and load balancing while maintaining secure database connectivity.

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

The solution deploys the following AWS resources:

- **Amazon ECR Repository**: Secure container image registry
- **AWS App Runner Service**: Fully managed container hosting with auto-scaling
- **Amazon RDS PostgreSQL**: Managed database with automated backups
- **AWS Secrets Manager**: Secure credential storage and rotation
- **Amazon CloudWatch**: Comprehensive monitoring and alerting
- **IAM Roles**: Least-privilege service roles for secure access
- **VPC Resources**: Private networking for database security

## Prerequisites

- AWS CLI installed and configured (version 2.0 or later)
- Docker installed for building container images
- Appropriate AWS permissions for:
  - App Runner service management
  - RDS database creation and management
  - Secrets Manager secret creation and access
  - ECR repository creation and image management
  - CloudWatch metrics and alarms
  - IAM role and policy management
  - VPC and networking resource management
- Basic knowledge of containerization and database concepts
- Estimated cost: $25-50/month for development usage

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name containerized-webapp-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=AppName,ParameterValue=my-webapp \
                ParameterKey=ContainerImage,ParameterValue=your-account.dkr.ecr.region.amazonaws.com/your-repo:latest

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name containerized-webapp-stack

# Get the application URL
aws cloudformation describe-stacks \
    --stack-name containerized-webapp-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`AppRunnerServiceURL`].OutputValue' \
    --output text
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Configure deployment parameters (optional)
export CDK_DEFAULT_REGION=us-east-1
export APP_NAME=my-webapp

# Deploy the stack
cdk deploy

# Get outputs
cdk list
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure deployment parameters (optional)
export CDK_DEFAULT_REGION=us-east-1
export APP_NAME=my-webapp

# Deploy the stack
cdk deploy

# Get outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
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

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters and deploy all resources
```

## Configuration Parameters

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `AppName` | Name for the App Runner service | `containerized-webapp` | Yes |
| `ContainerImage` | ECR image URI for the application | - | Yes |
| `DBInstanceClass` | RDS instance class | `db.t3.micro` | No |
| `DBAllocatedStorage` | Database storage in GB | `20` | No |
| `EnvironmentName` | Environment name for tagging | `dev` | No |

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
app_name = "my-webapp"
container_image = "your-account.dkr.ecr.region.amazonaws.com/your-repo:latest"
db_instance_class = "db.t3.micro"
db_allocated_storage = 20
environment = "dev"
region = "us-east-1"
```

### CDK Configuration

Set environment variables or modify the stack configuration:

```bash
export APP_NAME=my-webapp
export CONTAINER_IMAGE=your-account.dkr.ecr.region.amazonaws.com/your-repo:latest
export DB_INSTANCE_CLASS=db.t3.micro
export ENVIRONMENT=dev
```

## Container Application Requirements

Your container application must:

1. **Listen on Port 8080**: App Runner expects the application to listen on port 8080
2. **Implement Health Check**: Provide a `/health` endpoint for health monitoring
3. **Database Integration**: Use Secrets Manager for database credentials
4. **Environment Variables**: Support these environment variables:
   - `NODE_ENV`: Application environment
   - `AWS_REGION`: AWS region for service calls
   - `DB_SECRET_NAME`: Secrets Manager secret name

### Sample Application Structure

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 8080
CMD ["npm", "start"]
```

```javascript
// Sample server.js structure
const express = require('express');
const { Client } = require('pg');
const AWS = require('aws-sdk');

const app = express();
const port = process.env.PORT || 8080;

// Health check endpoint (required)
app.get('/health', async (req, res) => {
  // Implement database connectivity check
  res.json({ status: 'healthy', database: 'connected' });
});

// Main application endpoint
app.get('/', (req, res) => {
  res.json({ 
    message: 'Hello from App Runner!',
    timestamp: new Date().toISOString()
  });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

## Post-Deployment Configuration

After deployment, complete these steps:

1. **Build and Push Container Image**:
   ```bash
   # Get ECR login
   aws ecr get-login-password --region <region> | \
       docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
   
   # Build and push image
   docker build -t <ecr-repo-uri>:latest .
   docker push <ecr-repo-uri>:latest
   ```

2. **Update App Runner Service** (if using existing image):
   ```bash
   # Trigger new deployment with updated image
   aws apprunner start-deployment --service-arn <service-arn>
   ```

3. **Monitor Application**:
   ```bash
   # Check service status
   aws apprunner describe-service --service-arn <service-arn>
   
   # View application logs
   aws logs filter-log-events \
       --log-group-name "/aws/apprunner/<service-name>/application" \
       --start-time $(date -d '10 minutes ago' +%s)000
   ```

## Monitoring and Troubleshooting

### CloudWatch Metrics

Key metrics to monitor:

- **CPUUtilization**: Service CPU usage
- **MemoryUtilization**: Service memory usage
- **ActiveInstances**: Number of running instances
- **RequestLatency**: Response time
- **2xxStatusResponses**: Successful requests
- **4xxStatusResponses**: Client errors
- **5xxStatusResponses**: Server errors

### CloudWatch Alarms

The infrastructure includes pre-configured alarms for:

- High CPU utilization (>80%)
- High memory utilization (>80%)
- High request latency (>2 seconds)

### Troubleshooting Common Issues

1. **Service Won't Start**:
   - Check container logs in CloudWatch
   - Verify container listens on port 8080
   - Ensure health check endpoint returns 200 status

2. **Database Connection Issues**:
   - Verify Secrets Manager permissions
   - Check security group rules
   - Confirm database instance is available

3. **High Latency**:
   - Monitor database performance metrics
   - Consider connection pooling
   - Review application code for bottlenecks

## Security Considerations

### Implemented Security Features

- **Network Isolation**: RDS deployed in private subnets
- **Encryption**: Database encryption at rest enabled
- **Secrets Management**: Database credentials stored in Secrets Manager
- **IAM Roles**: Least-privilege service roles
- **Security Groups**: Restrictive database access rules

### Additional Security Recommendations

1. **Enable VPC Flow Logs** for network monitoring
2. **Implement AWS WAF** for web application protection
3. **Use AWS Config** for compliance monitoring
4. **Enable GuardDuty** for threat detection
5. **Regular security assessments** with AWS Inspector

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name containerized-webapp-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name containerized-webapp-stack
```

### Using CDK

```bash
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
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Cost Optimization

### Development Environment

- Use `db.t3.micro` for RDS instances
- Set App Runner to minimum instance size (0.25 vCPU, 0.5 GB)
- Enable automatic pause for development workloads
- Use CloudWatch log retention policies

### Production Environment

- Right-size RDS instances based on performance metrics
- Implement App Runner auto-scaling policies
- Use Reserved Instances for predictable workloads
- Monitor and optimize container resource usage

## Customization Examples

### Adding Custom Domain

```bash
# Create Route 53 hosted zone and certificate
aws route53 create-hosted-zone --name example.com --caller-reference $(date +%s)
aws acm request-certificate --domain-name app.example.com --validation-method DNS

# Associate custom domain with App Runner service
aws apprunner associate-custom-domain \
    --service-arn <service-arn> \
    --domain-name app.example.com \
    --certificate-arn <certificate-arn>
```

### Scaling Configuration

```bash
# Create custom auto scaling configuration
aws apprunner create-auto-scaling-configuration \
    --auto-scaling-configuration-name custom-scaling \
    --max-concurrency 100 \
    --max-size 25 \
    --min-size 2
```

### Database Performance Optimization

```bash
# Create custom parameter group
aws rds create-db-parameter-group \
    --db-parameter-group-name custom-postgres-params \
    --db-parameter-group-family postgres14 \
    --description "Custom PostgreSQL parameters"

# Modify parameters for performance
aws rds modify-db-parameter-group \
    --db-parameter-group-name custom-postgres-params \
    --parameters ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements
```

## Support and Resources

- [AWS App Runner Developer Guide](https://docs.aws.amazon.com/apprunner/latest/dg/)
- [Amazon RDS User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/)
- [AWS Secrets Manager User Guide](https://docs.aws.amazon.com/secretsmanager/latest/userguide/)
- [CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new parameters or outputs
3. Ensure cleanup scripts remove all created resources
4. Validate security configurations follow AWS best practices
5. Update cost estimates for any new resources