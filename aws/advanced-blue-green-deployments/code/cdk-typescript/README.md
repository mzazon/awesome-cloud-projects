# CDK TypeScript - Advanced Blue-Green Deployments

This directory contains a CDK TypeScript implementation for the advanced blue-green deployments recipe with ECS, Lambda, and CodeDeploy.

## Architecture Overview

This CDK application deploys:

- **ECS Fargate Cluster** with blue-green deployment capabilities
- **Application Load Balancer** with blue/green target groups
- **Lambda Function** with alias-based blue-green deployments
- **CodeDeploy Applications** for both ECS and Lambda
- **CloudWatch Monitoring** with alarms and dashboard
- **Deployment Hooks** for pre/post deployment validation
- **ECR Repository** for container images

## Prerequisites

- AWS CLI installed and configured
- Node.js 18+ installed
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Docker installed (for building container images)
- Appropriate AWS permissions for all services

## Project Structure

```
cdk-typescript/
├── app.ts                          # Main CDK application entry point
├── lib/
│   └── advanced-blue-green-deployment-stack.ts  # Main stack definition
├── lambda/                         # Lambda function code
│   └── lambda_function.py
├── hooks/                          # Deployment hook functions
│   ├── pre_deployment_hook.py
│   └── post_deployment_hook.py
├── package.json                    # Node.js dependencies
├── tsconfig.json                   # TypeScript configuration
├── cdk.json                        # CDK configuration
└── README.md                       # This file
```

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 3. Synthesize CloudFormation Template

```bash
npm run synth
```

### 4. Deploy the Stack

```bash
npm run deploy
```

Or with custom context values:

```bash
cdk deploy -c projectName=my-project -c environment=production
```

### 5. Build and Push Container Images

After deployment, build and push your container images to the ECR repository:

```bash
# Get the ECR repository URI from stack outputs
ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name AdvancedBlueGreenDeploymentStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
    --output text)

# Login to ECR
aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_URI

# Build and push your application image
docker build -t $ECR_URI:1.0.0 ./path/to/your/app
docker push $ECR_URI:1.0.0
```

## Configuration

The CDK application accepts these context variables:

- `projectName`: Name prefix for resources (default: "advanced-deployment")
- `environment`: Environment tag (default: "dev")

Set these in `cdk.json` or pass them via the CLI:

```bash
cdk deploy -c projectName=my-app -c environment=prod
```

## Deployed Resources

### Core Infrastructure
- **VPC**: Uses the default VPC in your account
- **ECR Repository**: For storing container images with lifecycle policies
- **ALB**: Internet-facing load balancer with HTTP listener
- **Target Groups**: Blue and green target groups for ECS service
- **Security Groups**: Properly configured for ALB and ECS communication

### ECS Resources
- **ECS Cluster**: Fargate cluster for running containers
- **Task Definition**: Fargate task with health checks and logging
- **ECS Service**: Service with blue-green deployment configuration
- **CloudWatch Logs**: Log group for ECS task logs

### Lambda Resources
- **Lambda Function**: API backend with versioning support
- **Lambda Alias**: Production alias for traffic management
- **Deployment Hooks**: Pre and post-deployment validation functions

### CodeDeploy Resources
- **ECS Application**: CodeDeploy application for ECS deployments
- **Lambda Application**: CodeDeploy application for Lambda deployments
- **Deployment Groups**: Configured with auto-rollback and alarms

### Monitoring
- **CloudWatch Alarms**: Error rate and performance monitoring
- **SNS Topic**: Deployment notifications
- **Dashboard**: Comprehensive monitoring dashboard

### IAM Roles
- **ECS Execution Role**: For pulling images and writing logs
- **ECS Task Role**: For application-specific permissions
- **CodeDeploy Role**: For managing deployments
- **Lambda Roles**: For function execution and deployment hooks

## Deployment Process

### ECS Blue-Green Deployment

1. Create new task definition revision with updated image
2. CodeDeploy creates new tasks in green target group
3. Traffic gradually shifts from blue to green
4. Health checks validate deployment success
5. Blue environment is terminated after successful deployment

### Lambda Blue-Green Deployment

1. Update Lambda function code and configuration
2. Create new function version
3. CodeDeploy shifts alias traffic gradually
4. Deployment hooks validate function health
5. Traffic fully shifted to new version on success

## Monitoring and Observability

The deployment includes comprehensive monitoring:

- **ALB Metrics**: Response times, error rates, target health
- **ECS Metrics**: CPU/memory utilization, task counts
- **Lambda Metrics**: Duration, invocations, errors
- **Deployment Metrics**: Success/failure rates via custom metrics
- **CloudWatch Dashboard**: Unified view of all metrics
- **Alarms**: Automated alerting for anomalies

## Security Features

- **Least Privilege IAM**: Minimal required permissions for each role
- **Security Groups**: Restrictive network access controls
- **ECR Scanning**: Automatic vulnerability scanning for images
- **HTTPS Ready**: ALB configured for SSL/TLS termination
- **Private Subnets**: ECS tasks can run in private subnets

## Cost Optimization

- **Fargate Spot**: Consider using Fargate Spot for cost savings
- **Log Retention**: Logs retained for 1 week to control costs
- **Image Lifecycle**: ECR lifecycle policies to manage storage costs
- **Rightsizing**: Minimal CPU/memory allocation for demo workloads

## Customization

### Scaling Configuration

Modify the ECS service desired count:

```typescript
const ecsService = new ecs.FargateService(this, 'ECSService', {
  // ... other props
  desiredCount: 5, // Increase for production workloads
});
```

### Health Check Settings

Customize health check parameters:

```typescript
healthCheck: {
  path: '/health',
  interval: cdk.Duration.seconds(30),
  timeout: cdk.Duration.seconds(5),
  healthyThresholdCount: 3, // More strict health checking
  unhealthyThresholdCount: 2,
}
```

### Deployment Configuration

Change CodeDeploy deployment speed:

```typescript
deploymentConfig: codedeploy.LambdaDeploymentConfig.LINEAR_10PERCENT_EVERY_2MINUTES,
```

### Alarm Thresholds

Adjust monitoring sensitivity:

```typescript
threshold: 5, // Lower threshold for more sensitive monitoring
evaluationPeriods: 2, // Faster response to issues
```

## Troubleshooting

### Common Issues

1. **ECR Authentication**: Ensure Docker is logged into ECR
2. **Task Startup**: Check CloudWatch logs for container startup issues
3. **Health Checks**: Verify application responds on `/health` endpoint
4. **Permissions**: Ensure IAM roles have required permissions
5. **Capacity**: Check ECS cluster has sufficient capacity

### Useful Commands

```bash
# View stack outputs
aws cloudformation describe-stacks --stack-name AdvancedBlueGreenDeploymentStack

# Check ECS service status
aws ecs describe-services --cluster <cluster-name> --services <service-name>

# View deployment status
aws deploy list-deployments --application-name <app-name>

# Check CloudWatch logs
aws logs describe-log-streams --log-group-name /ecs/<service-name>
```

### Debugging Deployments

1. Check CodeDeploy deployment events
2. Review CloudWatch alarm states
3. Examine ECS service events
4. Validate target group health
5. Check deployment hook function logs

## Cleanup

To destroy all resources:

```bash
npm run destroy
```

Or using CDK directly:

```bash
cdk destroy
```

**Warning**: This will delete all resources including the ECR repository and any stored images.

## Best Practices

### Development Workflow

1. **Local Testing**: Test applications locally before deployment
2. **Image Tagging**: Use semantic versioning for container images
3. **Gradual Rollout**: Start with small traffic percentages
4. **Monitoring**: Watch metrics during deployments
5. **Rollback Plan**: Always have a rollback strategy

### Production Considerations

- Enable ALB access logs for audit trails
- Use private subnets for ECS tasks
- Implement proper secrets management
- Set up cross-region backup strategies
- Configure detailed monitoring and alerting
- Use blue-green deployments for zero downtime

### Security Hardening

- Enable GuardDuty for threat detection
- Use AWS Config for compliance monitoring
- Implement AWS Systems Manager for secrets
- Enable CloudTrail for API auditing
- Regular security scanning of container images

## Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [ECS Blue-Green Deployments](https://docs.aws.amazon.com/codedeploy/latest/userguide/tutorial-ecs-deployment.html)
- [Lambda Blue-Green Deployments](https://docs.aws.amazon.com/codedeploy/latest/userguide/tutorial-lambda-deployment.html)
- [Application Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)

## Support

For issues with this CDK application:

1. Check the AWS CDK documentation
2. Review CloudFormation events in AWS Console
3. Examine CloudWatch logs for detailed error information
4. Refer to the original recipe documentation

## License

This code is provided under the MIT License. See the LICENSE file for details.