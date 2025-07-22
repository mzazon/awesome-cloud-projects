# Container Health Checks and Self-Healing Applications - CDK TypeScript

This CDK application deploys a comprehensive container health checking and self-healing solution on AWS using ECS Fargate, Application Load Balancer, CloudWatch monitoring, and Lambda-based auto-remediation.

## Architecture Overview

The solution implements multi-layered health checking:

- **Container Health Checks**: ECS health check commands validate application health
- **Load Balancer Health Checks**: ALB target group health checks manage traffic routing
- **CloudWatch Alarms**: Monitor infrastructure and application metrics
- **Self-Healing Lambda**: Automated remediation for health check failures
- **Auto Scaling**: Automatic capacity adjustment based on metrics

## Prerequisites

- AWS CLI installed and configured
- Node.js 18.x or later
- npm or yarn package manager
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for ECS, ALB, CloudWatch, Lambda, and IAM

## Quick Start

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

3. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

4. **Access the application**:
   - The deployment outputs will include the Load Balancer DNS name
   - Test the health endpoint: `http://<load-balancer-dns>/health`

## Project Structure

```
├── app.ts                           # CDK app entry point
├── lib/
│   └── container-health-check-stack.ts  # Main stack definition
├── package.json                     # Dependencies and scripts
├── tsconfig.json                    # TypeScript configuration
├── cdk.json                         # CDK configuration
└── README.md                        # This file
```

## Key Components

### ECS Service
- **Cluster**: Fargate-based ECS cluster with Container Insights
- **Task Definition**: Includes health check configuration
- **Service**: Maintains desired container count with health monitoring
- **Auto Scaling**: CPU and memory-based scaling policies

### Load Balancer
- **Application Load Balancer**: Internet-facing ALB with health checks
- **Target Group**: Health check configuration for container endpoints
- **Security Groups**: Network access control

### Monitoring & Alerting
- **CloudWatch Alarms**: Monitor unhealthy targets, response times, and task counts
- **SNS Topic**: Central alerting for health check failures
- **Lambda Function**: Self-healing automation

### Networking
- **VPC**: Multi-AZ VPC with public and private subnets
- **Security Groups**: Proper network isolation and access control

## Health Check Configuration

### Container Health Checks
- **Command**: `curl -f http://localhost/health || exit 1`
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Retries**: 3
- **Start Period**: 60 seconds

### Load Balancer Health Checks
- **Path**: `/health`
- **Interval**: 30 seconds
- **Timeout**: 5 seconds
- **Healthy Threshold**: 2
- **Unhealthy Threshold**: 3

### CloudWatch Alarms
- **Unhealthy Targets**: Triggers when targets fail health checks
- **High Response Time**: Alerts on performance degradation
- **Low Task Count**: Monitors service capacity

## Self-Healing Capabilities

The Lambda function automatically responds to health check failures:

1. **ECS Task Restart**: Forces new deployment for unhealthy tasks
2. **Traffic Management**: ALB automatically routes traffic away from unhealthy targets
3. **Auto Scaling**: Adjusts capacity based on CPU/memory utilization
4. **Alerting**: SNS notifications for manual intervention when needed

## Configuration

### Environment Variables
- `CDK_DEFAULT_ACCOUNT`: AWS account ID
- `CDK_DEFAULT_REGION`: AWS region

### Context Parameters
You can override default values using CDK context:

```bash
cdk deploy -c environment=prod -c region=us-west-2
```

### Customization
Modify the following parameters in `lib/container-health-check-stack.ts`:

- `containerPort`: Application port (default: 80)
- `desiredCount`: Number of containers (default: 2)
- `minCapacity`: Minimum auto-scaling capacity (default: 1)
- `maxCapacity`: Maximum auto-scaling capacity (default: 10)
- `cpuTargetUtilization`: CPU scaling threshold (default: 70%)

## Testing

### Health Check Endpoints
- **Application**: `http://<load-balancer-dns>/`
- **Health Check**: `http://<load-balancer-dns>/health`
- **Readiness**: `http://<load-balancer-dns>/ready`

### Failure Simulation
Test self-healing capabilities by:

1. **Stopping tasks**: Force container failures
2. **Load testing**: Trigger auto-scaling
3. **Network issues**: Test health check failures

### Monitoring
View metrics in CloudWatch:
- ECS service metrics
- ALB target group metrics
- Custom application metrics

## Deployment Commands

```bash
# Synthesize CloudFormation template
cdk synth

# Show diff with deployed stack
cdk diff

# Deploy with approval
cdk deploy --require-approval never

# Deploy specific stack
cdk deploy ContainerHealthCheckStack

# Destroy resources
cdk destroy
```

## Cost Considerations

This solution includes:
- **ECS Fargate**: Pay-per-use containers
- **Application Load Balancer**: Hourly charges + LCU pricing
- **CloudWatch**: Metric storage and alarm charges
- **Lambda**: Pay-per-invocation for self-healing
- **Data Transfer**: Cross-AZ and internet charges

Estimated monthly cost: $50-150 depending on usage patterns.

## Security Features

- **IAM Roles**: Least privilege access for all services
- **Security Groups**: Network-level access control
- **VPC**: Isolated network environment
- **Private Subnets**: Containers run in private subnets
- **CloudWatch Logs**: Centralized logging with retention

## Troubleshooting

### Common Issues

1. **Health Check Failures**:
   - Check container logs: `aws logs tail /ecs/health-check-app`
   - Verify health endpoint responds: `curl http://<container-ip>/health`

2. **Auto Scaling Issues**:
   - Check CloudWatch metrics for CPU/memory utilization
   - Review scaling policies and thresholds

3. **Load Balancer Issues**:
   - Check target group health status
   - Verify security group configurations

### Debugging Commands

```bash
# View ECS service status
aws ecs describe-services --cluster <cluster-name> --services <service-name>

# Check target group health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>

# View CloudWatch alarms
aws cloudwatch describe-alarms --alarm-names <alarm-name>

# Check Lambda function logs
aws logs tail /aws/lambda/<function-name>
```

## Next Steps

1. **Custom Metrics**: Add application-specific health metrics
2. **Blue-Green Deployment**: Implement zero-downtime deployments
3. **Multi-Region**: Extend to multiple regions for high availability
4. **Chaos Engineering**: Test resilience with failure injection
5. **Cost Optimization**: Implement spot instances and reserved capacity

## Support

For issues and questions:
- Check AWS documentation for service-specific guidance
- Review CloudWatch logs for error details
- Use AWS Support for production issues

## License

This project is licensed under the MIT License. See the LICENSE file for details.