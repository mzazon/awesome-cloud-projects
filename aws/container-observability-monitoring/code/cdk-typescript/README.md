# Container Observability and Performance Monitoring CDK

This CDK TypeScript application implements a comprehensive container observability platform combining CloudWatch Container Insights, AWS X-Ray distributed tracing, Prometheus metrics collection, and custom performance monitoring dashboards.

## Architecture Overview

The solution provides end-to-end visibility from infrastructure metrics to application-level performance data, enabling proactive monitoring, automated alerting, and performance optimization across both EKS and ECS container environments.

### Key Components

- **EKS Cluster**: Managed Kubernetes cluster with enhanced monitoring and Container Insights
- **ECS Cluster**: Fargate-based container orchestration with built-in observability
- **CloudWatch Monitoring**: Advanced alarms, anomaly detection, and custom dashboards
- **OpenSearch**: Log analytics and search capabilities
- **X-Ray Tracing**: Distributed tracing across microservices
- **Performance Optimization**: Automated Lambda-based resource optimization recommendations
- **Prometheus & Grafana**: Kubernetes-native monitoring and visualization

## Prerequisites

- Node.js 18.x or later
- AWS CLI configured with appropriate permissions
- Docker installed for local development
- AWS CDK CLI installed globally (`npm install -g aws-cdk`)

### Required AWS Permissions

Your AWS user/role needs permissions for:
- EKS (cluster creation, node groups, addons)
- ECS (cluster creation, task definitions, services)
- CloudWatch (metrics, alarms, dashboards, logs)
- X-Ray (tracing configuration)
- OpenSearch (domain creation)
- Lambda (function creation and execution)
- SNS (topic creation and subscriptions)
- IAM (roles and policies for services)
- EC2 (VPC, subnets, security groups)

## Getting Started

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not already done)

```bash
cdk bootstrap
```

### 3. Configure Environment Variables (Optional)

```bash
# Set environment identifier
export ENVIRONMENT_ID=dev

# Set alert email for notifications
export ALERT_EMAIL=your-email@example.com

# Set AWS region
export AWS_DEFAULT_REGION=us-west-2
```

### 4. Deploy the Stack

```bash
# Deploy with default settings
npm run deploy

# Deploy with specific environment
npm run deploy:dev

# Deploy with custom context
cdk deploy --context environmentId=staging --context alertEmail=alerts@company.com
```

## Configuration Options

### Context Parameters

You can customize the deployment using CDK context parameters:

```bash
# Deploy with custom configuration
cdk deploy \
  --context environmentId=production \
  --context alertEmail=alerts@company.com \
  --context enableEnhancedMonitoring=true
```

### Environment Variables

- `ENVIRONMENT_ID`: Unique identifier for the deployment (default: auto-generated)
- `ALERT_EMAIL`: Email address for CloudWatch alarm notifications
- `CDK_DEFAULT_ACCOUNT`: AWS account ID
- `CDK_DEFAULT_REGION`: AWS region for deployment

## Post-Deployment Setup

### 1. Configure kubectl for EKS

```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

### 2. Install Container Insights

The CDK automatically installs Container Insights, but you can verify:

```bash
kubectl get pods -n amazon-cloudwatch
```

### 3. Access Grafana Dashboard

```bash
# Get Grafana LoadBalancer URL
kubectl get svc -n monitoring grafana

# Default credentials:
# Username: admin
# Password: observability123!
```

### 4. Verify Prometheus Metrics

```bash
# Port forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80

# Access Prometheus UI at http://localhost:9090
```

## Monitoring and Observability

### CloudWatch Dashboards

The deployment creates a comprehensive CloudWatch dashboard with:

- EKS pod resource utilization
- ECS service performance metrics
- Network I/O statistics
- Task health and counts
- Log insights and error tracking

### Alarms and Notifications

Configured alarms include:

- **EKS High CPU Utilization**: Triggers when pod CPU usage exceeds 80%
- **EKS High Memory Utilization**: Triggers when pod memory usage exceeds 80%
- **ECS Unhealthy Tasks**: Triggers when running task count drops below threshold
- **Anomaly Detection**: ML-based detection for CPU and memory patterns

### Performance Optimization

The automated performance optimizer Lambda function:

- Analyzes container resource utilization patterns
- Generates optimization recommendations
- Runs hourly to identify over/under-provisioned resources
- Provides cost optimization insights

### Log Analytics

OpenSearch integration provides:

- Full-text search across container logs
- Real-time log streaming
- Advanced log aggregation and analysis
- Custom dashboards for log insights

## Customization

### Modifying EKS Configuration

Edit the `createEksCluster` method in `app.ts`:

```typescript
const cluster = new eks.Cluster(this, 'EksCluster', {
  // Customize cluster settings
  version: eks.KubernetesVersion.V1_29,
  defaultCapacity: 0,
  // Add your customizations here
});
```

### Adding Custom Metrics

Create custom CloudWatch metrics:

```typescript
const customMetric = new cloudwatch.Metric({
  namespace: 'Custom/Application',
  metricName: 'BusinessMetric',
  dimensionsMap: {
    Environment: environmentId,
  },
});
```

### Extending Lambda Functions

Add custom optimization logic to the performance optimizer:

```typescript
// Modify the Lambda function code in createPerformanceOptimizerFunction
const performanceOptimizerFunction = new lambda.Function(this, 'PerformanceOptimizerFunction', {
  code: lambda.Code.fromInline(`
    // Add your custom optimization logic here
  `),
});
```

## Development Workflow

### Local Development

```bash
# Watch for changes during development
npm run watch

# Run tests
npm run test

# Lint code
npm run lint

# Fix linting issues
npm run lint:fix
```

### Testing Changes

```bash
# Synthesize CloudFormation template
npm run synth

# Compare changes with deployed stack
npm run diff

# Validate template
cdk doctor
```

## Troubleshooting

### Common Issues

1. **EKS Cluster Creation Timeout**
   - Check VPC configuration and subnet availability
   - Verify IAM permissions for EKS service role

2. **Container Insights Not Working**
   - Ensure CloudWatch agent has proper permissions
   - Check DaemonSet pod status: `kubectl get pods -n amazon-cloudwatch`

3. **Grafana Dashboard Not Accessible**
   - Verify LoadBalancer service is created
   - Check security groups allow inbound traffic

4. **Lambda Function Errors**
   - Check CloudWatch logs for the performance optimizer function
   - Verify IAM permissions for CloudWatch metrics access

### Debugging Commands

```bash
# Check EKS cluster status
aws eks describe-cluster --name <cluster-name>

# View ECS service events
aws ecs describe-services --cluster <cluster-name> --services <service-name>

# Check CloudWatch metrics
aws cloudwatch list-metrics --namespace AWS/ContainerInsights

# View Lambda function logs
aws logs tail /aws/lambda/<function-name>
```

## Security Considerations

### IAM Permissions

The CDK creates minimal IAM roles with least-privilege access:

- EKS node groups have only necessary permissions
- Lambda functions use scoped IAM policies
- Service accounts follow AWS best practices

### Network Security

- EKS nodes run in private subnets
- Security groups restrict unnecessary access
- VPC endpoints used where possible

### Data Protection

- CloudWatch logs encrypted at rest
- OpenSearch domain uses encryption
- S3 buckets have versioning and encryption enabled

## Cost Optimization

### Monitoring Costs

- Set up billing alerts for CloudWatch usage
- Monitor EKS node group scaling
- Use Fargate Spot for ECS tasks where appropriate

### Resource Optimization

- The performance optimizer provides cost recommendations
- Use scheduled scaling for predictable workloads
- Monitor unused resources through CloudWatch insights

## Cleanup

To remove all resources:

```bash
# Destroy the stack
npm run destroy

# Or use CDK directly
cdk destroy --force
```

**Warning**: This will delete all resources including data in OpenSearch and CloudWatch logs.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and linting
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:

1. Check the troubleshooting section
2. Review AWS documentation for specific services
3. Submit issues through the repository issue tracker
4. For AWS-specific issues, use AWS Support

## Additional Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Amazon ECS Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/)
- [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [AWS X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)