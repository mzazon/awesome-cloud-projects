# Infrastructure as Code for Container Resource Optimization with EKS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container Resource Optimization with EKS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Existing EKS cluster with worker nodes (minimum 2 nodes)
- kubectl installed and configured for EKS cluster access
- Appropriate IAM permissions for:
  - EKS cluster administration
  - CloudWatch metrics and dashboard creation
  - SNS topic creation
  - Container Insights configuration
  - Lambda function deployment (for automation)
- Basic understanding of Kubernetes resource management concepts
- Estimated cost: $10-50/month for additional CloudWatch metrics and logging

> **Note**: This implementation assumes you have an existing EKS cluster. The infrastructure code focuses on deploying the cost optimization components (VPA, monitoring, alerting) rather than creating the base EKS cluster.

## Quick Start

### Using CloudFormation
```bash
# Set your EKS cluster name
export CLUSTER_NAME="your-eks-cluster-name"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name eks-cost-optimization \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=$CLUSTER_NAME \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-west-2
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Set cluster name in environment
export CLUSTER_NAME="your-eks-cluster-name"

# Deploy the stack
cdk deploy --parameters ClusterName=$CLUSTER_NAME
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Set cluster name in environment
export CLUSTER_NAME="your-eks-cluster-name"

# Deploy the stack
cdk deploy --parameters ClusterName=$CLUSTER_NAME
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars <<EOF
cluster_name = "your-eks-cluster-name"
aws_region   = "us-west-2"
EOF

# Plan and apply
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
# Set required environment variables
export CLUSTER_NAME="your-eks-cluster-name"
export AWS_REGION="us-west-2"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## What Gets Deployed

This infrastructure code deploys the following components:

### Kubernetes Resources
- Vertical Pod Autoscaler (VPA) components
- Kubernetes Metrics Server
- Sample application for testing resource optimization
- VPA policies for automated resource recommendations
- Test namespace and RBAC configurations

### AWS Cloud Resources
- CloudWatch Container Insights configuration
- CloudWatch Dashboard for cost monitoring
- SNS topic for cost optimization alerts
- CloudWatch alarms for resource utilization monitoring
- IAM roles and policies for Container Insights
- Lambda function for automated cost optimization (optional)

### Monitoring and Alerting
- Resource utilization dashboards
- Cost optimization alerts
- VPA recommendation reporting
- Automated notification system

## Validation Steps

After deployment, validate the solution:

```bash
# Verify VPA components are running
kubectl get pods -n kube-system | grep vpa

# Check Container Insights deployment
kubectl get pods -n amazon-cloudwatch

# View VPA recommendations (after 10-15 minutes)
kubectl describe vpa -n cost-optimization

# Check CloudWatch dashboard
echo "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:"

# Test resource optimization
kubectl top pods -n cost-optimization
```

## Customization

### Key Configuration Options

- **Cluster Name**: Update the EKS cluster name in parameters
- **VPA Update Mode**: Configure automatic vs. recommendation-only mode
- **Resource Boundaries**: Adjust min/max resource limits for safety
- **Alert Thresholds**: Customize utilization thresholds for cost alerts
- **Monitoring Retention**: Configure CloudWatch log retention periods

### Environment Variables

```bash
# Required
export CLUSTER_NAME="your-eks-cluster-name"
export AWS_REGION="your-preferred-region"

# Optional customization
export VPA_UPDATE_MODE="Auto"  # or "Off" for recommendations only
export COST_ALERT_THRESHOLD="30"  # CPU utilization threshold percentage
export DASHBOARD_REFRESH_INTERVAL="300"  # seconds
```

### Terraform Variables

```hcl
# terraform.tfvars
cluster_name                = "my-eks-cluster"
aws_region                 = "us-west-2"
vpa_update_mode           = "Auto"
cost_alert_threshold      = 30
enable_container_insights = true
create_test_application   = true
```

## Cleanup

### Using CloudFormation
```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name eks-cost-optimization

# Manually clean up Kubernetes resources
kubectl delete namespace cost-optimization
kubectl delete namespace amazon-cloudwatch
```

### Using CDK
```bash
# Destroy CDK stack
cdk destroy

# Clean up Kubernetes resources
kubectl delete namespace cost-optimization
kubectl delete namespace amazon-cloudwatch
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up any remaining Kubernetes resources
kubectl delete namespace cost-optimization --ignore-not-found
kubectl delete namespace amazon-cloudwatch --ignore-not-found
```

### Using Bash Scripts
```bash
# Run cleanup script
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Architecture Overview

The deployed infrastructure implements a comprehensive container cost optimization solution:

```
┌─────────────────────────────────────────────────────────┐
│                    EKS Cluster                          │
│  ┌─────────────────┐    ┌─────────────────────────────┐ │
│  │ VPA Components  │    │    Application Workloads    │ │
│  │ • Recommender   │◄──►│  • Sample Apps              │ │
│  │ • Updater       │    │  • Production Workloads    │ │
│  │ • Admission Ctrl│    │                             │ │
│  └─────────────────┘    └─────────────────────────────┘ │
│             │                        │                  │
│             ▼                        ▼                  │
│  ┌─────────────────────────────────────────────────────┐ │
│  │            Metrics Server                           │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────┬───────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│                 AWS Services                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ CloudWatch   │  │     SNS      │  │ Cost Explorer│   │
│  │ • Dashboards │  │ • Alerts     │  │ • Reports    │   │
│  │ • Insights   │  │ • Topics     │  │ • Analysis   │   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Best Practices

1. **Start with Recommendation Mode**: Begin with VPA in "Off" mode to review recommendations before enabling automatic updates

2. **Set Appropriate Boundaries**: Configure min/max resource limits to prevent VPA from making overly aggressive or conservative recommendations

3. **Monitor Gradually**: Allow 10-15 minutes for VPA to collect sufficient data before expecting meaningful recommendations

4. **Test in Non-Production**: Validate VPA behavior with test workloads before applying to production applications

5. **Review Cost Impact**: Use CloudWatch dashboards to track actual cost savings and resource efficiency improvements

## Troubleshooting

### Common Issues

**VPA not generating recommendations:**
- Ensure Metrics Server is running and collecting data
- Verify sufficient time has passed (10-15 minutes minimum)
- Check that workloads have resource requests defined

**Container Insights not showing data:**
- Verify CloudWatch agent pods are running
- Check IAM permissions for Container Insights
- Confirm cluster logging is enabled

**High resource utilization after VPA updates:**
- Review VPA resource boundaries (minAllowed/maxAllowed)
- Consider adjusting VPA update mode to "Initial" for new pods only
- Monitor application performance metrics

### Useful Commands

```bash
# Debug VPA status
kubectl describe vpa -A

# Check Metrics Server
kubectl top nodes
kubectl top pods -A

# View CloudWatch agent logs
kubectl logs -n amazon-cloudwatch -l name=cloudwatch-agent

# Get VPA recommendations
kubectl get vpa -A -o yaml
```

## Security Considerations

- All IAM roles follow least privilege principle
- Container Insights uses dedicated service accounts
- SNS topics are encrypted in transit
- CloudWatch logs support encryption at rest
- VPA admission controller runs with restricted permissions

## Cost Optimization Impact

Expected benefits from this implementation:
- **20-40% reduction** in wasted compute resources
- **Automated right-sizing** eliminates manual guesswork
- **Continuous optimization** adapts to changing workload patterns
- **Visibility into cost impact** through detailed dashboards
- **Proactive alerting** prevents resource waste accumulation

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check AWS EKS and VPA documentation
3. Verify IAM permissions and cluster configuration
4. Monitor CloudWatch logs for error messages

## Additional Resources

- [AWS EKS Cost Optimization Best Practices](https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt.html)
- [Kubernetes Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [AWS Cost Management](https://docs.aws.amazon.com/cost-management/)