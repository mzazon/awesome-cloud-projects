# AWS App2Container CDK TypeScript Implementation

This directory contains the AWS CDK TypeScript implementation for the App2Container modernization infrastructure. This CDK application creates a complete modernization platform including container orchestration, CI/CD pipelines, and monitoring capabilities.

## Architecture Overview

The CDK application deploys:

- **Amazon VPC** with public and private subnets across multiple AZs
- **Amazon ECS Cluster** with Fargate capacity providers
- **Amazon ECR Repository** for container image storage
- **Application Load Balancer** for high availability and traffic distribution
- **CodeCommit Repository** for source code management
- **CodeBuild Project** for container image building
- **CodePipeline** for automated CI/CD workflows
- **Auto Scaling** capabilities for dynamic scaling
- **CloudWatch Dashboard** for monitoring and observability
- **S3 Buckets** for artifact storage
- **IAM Roles and Policies** following least privilege principles

## Prerequisites

- Node.js 18.x or later
- AWS CLI v2 installed and configured
- AWS CDK v2.136.0 or later
- Docker (for local testing)
- Appropriate AWS permissions for ECS, ECR, VPC, IAM, and CodePipeline

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (if not already done)**:
   ```bash
   npm run bootstrap
   ```

3. **Build the TypeScript code**:
   ```bash
   npm run build
   ```

## Configuration

The stack accepts the following context parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `appName` | Name of the modernized application | `modernized-app` |
| `environment` | Environment name (dev, staging, prod) | `dev` |
| `account` | AWS Account ID | Auto-detected |
| `region` | AWS Region | Auto-detected |

### Setting Context Parameters

You can set context parameters in several ways:

1. **Command line**:
   ```bash
   cdk deploy --context appName=my-app --context environment=prod
   ```

2. **cdk.json file**:
   ```json
   {
     "context": {
       "appName": "my-modernized-app",
       "environment": "production"
     }
   }
   ```

3. **Environment variables**:
   ```bash
   export CDK_DEFAULT_ACCOUNT=123456789012
   export CDK_DEFAULT_REGION=us-west-2
   ```

## Deployment

### Quick Deployment

```bash
# Deploy with default settings
npm run deploy

# Deploy with custom configuration
cdk deploy --context appName=my-app --context environment=prod
```

### Step-by-Step Deployment

1. **Synthesize CloudFormation template**:
   ```bash
   npm run synth
   ```

2. **Review changes**:
   ```bash
   npm run diff
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

4. **Monitor deployment progress** in the AWS Console or CLI:
   ```bash
   aws cloudformation describe-stacks --stack-name App2ContainerStack
   ```

## Post-Deployment Configuration

After successful deployment, you'll need to:

1. **Configure App2Container** to use the created S3 bucket and ECR repository
2. **Update the ECS task definition** with your actual container image
3. **Configure the CI/CD pipeline** with your application source code
4. **Update security groups** if additional ports are needed

### Example App2Container Configuration

```bash
# Get output values from the deployed stack
export ECR_REPO_URI=$(aws cloudformation describe-stacks \
  --stack-name App2ContainerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
  --output text)

export S3_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name App2ContainerStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ArtifactsBucketName`].OutputValue' \
  --output text)

# Configure App2Container
sudo app2container init --s3-bucket ${S3_BUCKET}
```

## Monitoring and Observability

The deployment includes:

- **CloudWatch Dashboard** with key metrics
- **Application Load Balancer** health checks
- **ECS Service** health monitoring
- **Auto Scaling** based on CPU and memory utilization
- **CloudWatch Logs** for application and infrastructure logs

### Accessing the Dashboard

1. Navigate to CloudWatch in the AWS Console
2. Select "Dashboards" from the left menu
3. Open the "App2Container-{suffix}" dashboard

### Key Metrics to Monitor

- ECS Service CPU and Memory utilization
- Application Load Balancer request count and latency
- Container health check status
- Auto Scaling events

## CI/CD Pipeline

The deployed pipeline includes three stages:

1. **Source**: Retrieves code from CodeCommit repository
2. **Build**: Builds container image using CodeBuild
3. **Deploy**: Deploys updated image to ECS service

### Using the Pipeline

1. **Clone the CodeCommit repository**:
   ```bash
   git clone https://codecommit.{region}.amazonaws.com/v1/repos/app2container-pipeline-{suffix}
   ```

2. **Add your Dockerfile and application code**
3. **Commit and push changes**:
   ```bash
   git add .
   git commit -m "Add containerized application"
   git push origin main
   ```

The pipeline will automatically trigger and deploy your changes.

## Customization

### Scaling Configuration

Modify auto-scaling parameters in `lib/app2container-stack.ts`:

```typescript
// Configure auto scaling
const scalableTarget = service.autoScaleTaskCount({
  minCapacity: 2,      // Minimum number of tasks
  maxCapacity: 20,     // Maximum number of tasks
});

// CPU-based scaling
scalableTarget.scaleOnCpuUtilization('CpuScaling', {
  targetUtilizationPercent: 60,  // Lower threshold for more responsive scaling
  scaleInCooldown: cdk.Duration.seconds(300),
  scaleOutCooldown: cdk.Duration.seconds(180),
});
```

### Security Groups

Add additional ingress rules as needed:

```typescript
// Allow HTTPS traffic
albSecurityGroup.addIngressRule(
  ec2.Peer.anyIpv4(),
  ec2.Port.tcp(443),
  'Allow HTTPS traffic'
);

// Allow custom application ports
ecsSecurityGroup.addIngressRule(
  ec2.Peer.securityGroupId(albSecurityGroup.securityGroupId),
  ec2.Port.tcp(8080),
  'Allow traffic to application port'
);
```

### Resource Sizing

Adjust Fargate task sizing:

```typescript
const taskDefinition = new ecs.FargateTaskDefinition(this, 'TaskDefinition', {
  memoryLimitMiB: 4096,  // Increase memory
  cpu: 2048,             // Increase CPU
  // ... other configuration
});
```

## Troubleshooting

### Common Issues

1. **ECS Service fails to start**:
   - Check CloudWatch logs for container errors
   - Verify the container image exists in ECR
   - Ensure security groups allow required traffic

2. **Load Balancer health checks fail**:
   - Verify the health check endpoint exists
   - Check security group rules
   - Review application startup time

3. **CI/CD Pipeline failures**:
   - Check CodeBuild logs for build errors
   - Verify IAM permissions
   - Ensure Dockerfile is present in repository

### Useful Commands

```bash
# Check ECS service status
aws ecs describe-services --cluster {cluster-name} --services {service-name}

# View CloudWatch logs
aws logs tail /ecs/{app-name} --follow

# Check pipeline status
aws codepipeline get-pipeline-state --name {pipeline-name}

# Scale service manually
aws ecs update-service --cluster {cluster-name} --service {service-name} --desired-count 3
```

## Cleanup

To avoid ongoing charges, clean up all resources:

```bash
npm run destroy
```

This will delete all resources created by the CDK stack.

## Security Considerations

This implementation includes several security best practices:

- **VPC isolation** with private subnets for ECS tasks
- **IAM roles** with least privilege access
- **Security groups** with minimal required access
- **ECR image scanning** enabled
- **S3 bucket encryption** and public access blocking
- **CloudWatch logging** for audit trails

### Additional Security Recommendations

1. **Enable AWS Config** for compliance monitoring
2. **Use AWS Secrets Manager** for sensitive configuration
3. **Implement AWS WAF** for additional web application protection
4. **Enable VPC Flow Logs** for network monitoring
5. **Use AWS Security Hub** for centralized security findings

## Cost Optimization

- **Fargate Spot** can be enabled for development environments
- **ECS Service auto-scaling** reduces costs during low usage
- **S3 lifecycle policies** automatically clean up old artifacts
- **ECR lifecycle policies** limit stored image versions

## Support

For issues specific to this CDK implementation:

1. Check the CDK documentation: https://docs.aws.amazon.com/cdk/
2. Review AWS ECS best practices: https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/
3. Consult the original App2Container recipe documentation

## Contributing

When modifying this CDK code:

1. Follow TypeScript and CDK best practices
2. Update tests for any new functionality
3. Run `npm run lint` to check code style
4. Update documentation for any new features
5. Test deployments in a development environment first