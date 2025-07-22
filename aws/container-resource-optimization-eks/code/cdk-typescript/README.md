# Container Resource Optimization CDK TypeScript Application

This CDK TypeScript application deploys a complete container resource optimization and right-sizing solution for Amazon EKS, implementing the infrastructure described in the [Container Resource Optimization Recipe](../../container-resource-optimization-right-sizing.md).

## Architecture Overview

The application creates:

- **Amazon EKS Cluster** with managed node groups optimized for cost efficiency
- **Vertical Pod Autoscaler (VPA)** for automated resource right-sizing
- **CloudWatch Container Insights** for comprehensive monitoring
- **Cost Optimization Dashboard** with resource utilization metrics
- **Automated Cost Alerting** via SNS and CloudWatch Alarms
- **Lambda-based Automation** for proactive cost optimization

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 16+ and npm
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Appropriate AWS permissions for EKS, EC2, CloudWatch, and Lambda

## Quick Start

1. **Install Dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK** (if not done previously):
   ```bash
   cdk bootstrap
   ```

3. **Deploy the Stack**:
   ```bash
   npm run deploy
   ```

4. **Configure kubectl**:
   ```bash
   aws eks update-kubeconfig --region <your-region> --name <cluster-name>
   ```

## Configuration Options

The application supports extensive configuration through the `app.ts` file:

### Cluster Configuration
```typescript
clusterConfig: {
  version: cdk.aws_eks.KubernetesVersion.V1_28,
  capacity: {
    instanceTypes: [cdk.aws_ec2.InstanceType.of(cdk.aws_ec2.InstanceClass.M5, cdk.aws_ec2.InstanceSize.LARGE)],
    minCapacity: 2,
    maxCapacity: 10,
    desiredCapacity: 3
  },
  enableClusterLogging: true,
  enableFargateProfile: true
}
```

### Monitoring Configuration
```typescript
monitoringConfig: {
  enableContainerInsights: true,
  createCostDashboard: true,
  enableCostAlerts: true,
  lowUtilizationThreshold: 30
}
```

### VPA Configuration
```typescript
vpaConfig: {
  enableMetricsServer: true,
  enableVPA: true,
  updateMode: 'Off', // Start with recommendations only
  enableAutomation: false // Enable after testing
}
```

## Key Features

### 1. Cost-Optimized EKS Cluster
- Right-sized managed node groups
- Single NAT Gateway for cost efficiency
- Spot instance support (configurable)
- Comprehensive resource tagging for cost allocation

### 2. Vertical Pod Autoscaler (VPA)
- Automatic resource recommendation generation
- Configurable update modes (Off, Auto, Recreation)
- Safety boundaries to prevent over/under-provisioning
- Integration with sample workloads for testing

### 3. Comprehensive Monitoring
- CloudWatch Container Insights integration
- Custom cost optimization dashboard
- Real-time resource utilization tracking
- Comparison of actual vs. reserved capacity

### 4. Automated Cost Optimization
- Lambda function for continuous cost analysis
- SNS notifications for optimization opportunities
- CloudWatch alarms for low resource utilization
- Configurable thresholds and alerting rules

### 5. Security Best Practices
- Least privilege IAM roles and policies
- VPC with private subnets for worker nodes
- Security groups with minimal required access
- Encrypted data in transit and at rest

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Account                          │
├─────────────────────────────────────────────────────────────┤
│  VPC (10.0.0.0/16)                                        │
│  ├── Public Subnets (NAT Gateway, Load Balancers)         │
│  └── Private Subnets (EKS Worker Nodes)                   │
│                                                            │
│  EKS Cluster                                               │
│  ├── Managed Node Groups (M5.Large instances)             │
│  ├── Fargate Profile (cost-optimization namespace)        │
│  └── Add-ons: VPA, Metrics Server, CloudWatch Agent       │
│                                                            │
│  Monitoring & Alerting                                     │
│  ├── CloudWatch Container Insights                        │
│  ├── Cost Optimization Dashboard                          │
│  ├── SNS Topic for alerts                                 │
│  └── Lambda for automated analysis                        │
└─────────────────────────────────────────────────────────────┘
```

## Cost Considerations

### Estimated Monthly Costs
- **EKS Cluster**: $72/month (cluster management fee)
- **EC2 Instances**: $150-400/month (3x m5.large nodes)
- **CloudWatch**: $10-30/month (Container Insights metrics)
- **Data Transfer**: $5-20/month (depends on workload)

### Cost Optimization Features
- **VPA Right-sizing**: 20-40% resource cost reduction
- **Single NAT Gateway**: $32/month savings vs. multi-AZ
- **Spot Instances**: Up to 70% savings (when enabled)
- **Automated Monitoring**: Proactive cost management

## Post-Deployment Steps

1. **Verify VPA Installation**:
   ```bash
   kubectl get pods -n vpa-system
   ```

2. **Check Sample Application**:
   ```bash
   kubectl get pods -n cost-optimization
   ```

3. **View VPA Recommendations** (after 15+ minutes):
   ```bash
   kubectl describe vpa resource-test-app-vpa -n cost-optimization
   ```

4. **Access Cost Dashboard**:
   - Navigate to CloudWatch console
   - Go to Dashboards section
   - Open "cost-opt-cost-optimization" dashboard

5. **Enable VPA Auto-Updates** (after validation):
   ```bash
   kubectl patch vpa resource-test-app-vpa -n cost-optimization -p '{"spec":{"updatePolicy":{"updateMode":"Auto"}}}'
   ```

## Troubleshooting

### Common Issues

1. **VPA Not Generating Recommendations**:
   - Ensure Metrics Server is running: `kubectl get pods -n kube-system | grep metrics-server`
   - Wait 15+ minutes for data collection
   - Check pod resource utilization: `kubectl top pods -n cost-optimization`

2. **CloudWatch Metrics Missing**:
   - Verify Container Insights is enabled on the cluster
   - Check CloudWatch agent pods: `kubectl get pods -n amazon-cloudwatch`
   - Ensure proper IAM permissions for CloudWatch

3. **Cost Alerts Not Working**:
   - Verify SNS topic subscription
   - Check CloudWatch alarm configuration
   - Ensure Lambda function has proper permissions

### Useful Commands

```bash
# View all CDK stacks
cdk list

# View CloudFormation template
cdk synth

# Check differences before deployment
cdk diff

# Destroy the stack (be careful!)
cdk destroy

# Update kubectl configuration
aws eks update-kubeconfig --region $(aws configure get region) --name $(aws cloudformation describe-stacks --stack-name ContainerResourceOptimizationStack --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' --output text)
```

## Advanced Configuration

### Enabling Spot Instances
```typescript
cluster.addNodegroupCapacity('spot-nodegroup', {
  instanceTypes: [ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE)],
  capacityType: eks.CapacityType.SPOT,
  spotInstanceDraining: true
});
```

### Custom VPA Policies
```typescript
// Add custom VPA configuration for specific workloads
this.cluster.addManifest('custom-app-vpa', {
  apiVersion: 'autoscaling.k8s.io/v1',
  kind: 'VerticalPodAutoscaler',
  metadata: {
    name: 'custom-app-vpa',
    namespace: 'production'
  },
  spec: {
    targetRef: {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      name: 'custom-app'
    },
    updatePolicy: {
      updateMode: 'Auto'
    },
    resourcePolicy: {
      containerPolicies: [{
        containerName: '*',
        maxAllowed: {
          cpu: '2',
          memory: '4Gi'
        }
      }]
    }
  }
});
```

## Support and Documentation

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Kubernetes VPA Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)

## Contributing

This CDK application is generated from the container resource optimization recipe. For issues or improvements:

1. Review the original recipe documentation
2. Test changes in a development environment
3. Follow AWS CDK and TypeScript best practices
4. Ensure cost optimization features remain intact

## License

This CDK application is provided under the MIT License. See the original recipe for more details.