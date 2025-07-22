# Containerized Web Applications with App Runner and RDS - CDK TypeScript

This CDK TypeScript application deploys a containerized web application using AWS App Runner with an RDS PostgreSQL database backend, implementing security best practices with Secrets Manager and comprehensive monitoring with CloudWatch.

## Architecture

The CDK application creates:

- **VPC**: Isolated network for RDS database with private subnets
- **RDS PostgreSQL**: Managed database with automated backups and encryption
- **Secrets Manager**: Secure storage for database credentials with automatic rotation capability
- **ECR Repository**: Container registry for application images with security scanning
- **App Runner Service**: Fully managed container deployment with auto-scaling
- **CloudWatch Monitoring**: Comprehensive metrics, alarms, and logging
- **IAM Roles**: Least-privilege access for App Runner service and task execution

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+ and npm installed
- Docker for building container images
- CDK CLI installed (`npm install -g aws-cdk`)

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not done previously)**:
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

4. **Build and push container image** (after stack deployment):
   ```bash
   # Get ECR repository URI from stack outputs
   ECR_URI=$(aws cloudformation describe-stacks \
     --stack-name ContainerizedWebAppStack \
     --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryUri`].OutputValue' \
     --output text)
   
   # Authenticate Docker to ECR
   aws ecr get-login-password --region $AWS_DEFAULT_REGION | \
     docker login --username AWS --password-stdin $ECR_URI
   
   # Build and push your application image
   docker build -t $ECR_URI:latest .
   docker push $ECR_URI:latest
   ```

## Available CDK Commands

- `npm run build` - Compile TypeScript to JavaScript
- `npm run watch` - Watch for changes and compile
- `npm run test` - Perform unit tests
- `cdk synth` - Synthesize CloudFormation template
- `cdk deploy` - Deploy stack to AWS
- `cdk diff` - Compare deployed stack with current state
- `cdk destroy` - Remove all resources

## Stack Outputs

After deployment, the stack provides these outputs:

- **AppRunnerServiceUrl**: HTTPS URL for your web application
- **ECRRepositoryUri**: Container registry URI for pushing images
- **DatabaseEndpoint**: RDS database endpoint (for reference)
- **DatabaseSecretArn**: ARN of the database credentials secret

## Security Features

- **Encryption at Rest**: RDS database storage is encrypted using AWS managed keys
- **Network Isolation**: Database runs in private subnets with security group controls
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **Least Privilege IAM**: Custom roles with minimal required permissions
- **Container Scanning**: ECR repository scans images for vulnerabilities
- **CDK Nag Integration**: Automated security best practices validation

## Monitoring and Observability

The stack includes comprehensive monitoring:

- **CloudWatch Alarms**:
  - High CPU utilization (>80%)
  - High memory utilization (>80%)
  - High response latency (>2 seconds)
- **Application Logs**: Centralized logging in CloudWatch
- **Health Checks**: App Runner health monitoring on `/health` endpoint
- **Custom Metrics**: App Runner service metrics for scaling decisions

## Cost Optimization

- **Instance Sizing**: Uses cost-effective instance types (t3.micro for RDS)
- **Storage**: General Purpose SSD storage for balanced performance and cost
- **Auto Scaling**: App Runner scales to zero when not in use
- **Image Lifecycle**: ECR repository automatically removes old images

## Customization

Key configuration options in the CDK code:

```typescript
// Database configuration
engine: rds.DatabaseInstanceEngine.postgres({
  version: rds.PostgresEngineVersion.VER_14_9,
}),
instanceType: ec2.InstanceType.of(ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MICRO),

// App Runner configuration
cpu: apprunner.Cpu.ONE_VCPU,
memory: apprunner.Memory.TWO_GB,
maxSize: 10,
maxConcurrency: 100,
```

## Application Requirements

Your containerized application should:

1. **Listen on port 8080** (configured in App Runner)
2. **Implement health check endpoint** at `/health`
3. **Use environment variables**:
   - `AWS_REGION`: AWS region for SDK configuration
   - `DB_SECRET_NAME`: Secrets Manager secret name for database credentials
   - `NODE_ENV`: Environment setting (set to 'production')

## Sample Application Code

The stack expects a Node.js application similar to this structure:

```javascript
const express = require('express');
const { Client } = require('pg');
const AWS = require('aws-sdk');

const app = express();
const port = process.env.PORT || 8080;

// Health check endpoint (required)
app.get('/health', async (req, res) => {
  // Implement database connectivity check
  res.json({ status: 'healthy' });
});

// Main application endpoint
app.get('/', (req, res) => {
  res.json({ message: 'Hello from App Runner!' });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

## Cleanup

To remove all resources:

```bash
cdk destroy
```

**Note**: Ensure you have removed any data from the RDS database that you want to preserve before destroying the stack.

## Troubleshooting

### Common Issues

1. **Container fails to start**: Check CloudWatch logs for application errors
2. **Database connection issues**: Verify security group rules and secret configuration
3. **CDK deployment fails**: Ensure proper AWS credentials and permissions

### Useful Commands

```bash
# View App Runner service logs
aws logs tail /aws/apprunner/webapp-{suffix}/application --follow

# Check database connectivity from command line
aws rds describe-db-instances --db-instance-identifier webapp-db-{suffix}

# Retrieve database credentials
aws secretsmanager get-secret-value --secret-id webapp-db-credentials-{suffix}
```

## Best Practices

- **Security**: Never hardcode database credentials in your application
- **Monitoring**: Implement custom metrics for business-specific KPIs  
- **Testing**: Use health checks to ensure database connectivity
- **Deployment**: Use CI/CD pipelines for automated container builds and deployments
- **Costs**: Monitor RDS usage and consider scheduled scaling for development environments

For more information, refer to the [AWS App Runner Developer Guide](https://docs.aws.amazon.com/apprunner/latest/dg/) and [Amazon RDS User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/).