# EKS Observability CDK Python Application

This directory contains a comprehensive AWS CDK Python application for EKS Logging and Monitoring with Prometheus.

## Overview

This CDK application creates a complete observability stack for Amazon EKS that includes:

- **EKS Cluster**: Kubernetes cluster with comprehensive control plane logging
- **CloudWatch Container Insights**: Infrastructure monitoring and metrics collection
- **Fluent Bit**: Log collection and forwarding to CloudWatch Logs
- **Amazon Managed Prometheus**: Time-series metrics collection and storage
- **CloudWatch Dashboards**: Comprehensive monitoring dashboards
- **CloudWatch Alarms**: Automated alerting for key metrics
- **Sample Application**: Demonstrates Prometheus metrics collection

## Architecture

The solution deploys the following AWS resources:

### Core Infrastructure
- **VPC**: Multi-AZ VPC with public and private subnets
- **EKS Cluster**: Managed Kubernetes cluster with comprehensive logging
- **Node Groups**: Managed EC2 instances for worker nodes
- **IAM Roles**: Service roles with least-privilege permissions

### Logging & Monitoring
- **CloudWatch Log Groups**: Centralized log storage for control plane and applications
- **Container Insights**: Performance monitoring at cluster, node, and pod levels
- **Fluent Bit DaemonSet**: Lightweight log collection and forwarding
- **CloudWatch Agent**: Metrics collection and system monitoring

### Prometheus Integration
- **AMP Workspace**: Amazon Managed Service for Prometheus workspace
- **Prometheus Scraper**: Automated metrics collection from Kubernetes endpoints
- **Custom Metrics**: Application-level metrics collection

### Observability
- **CloudWatch Dashboards**: Real-time monitoring and visualization
- **CloudWatch Alarms**: Automated alerting for resource utilization and failures
- **VPC Flow Logs**: Network traffic monitoring and analysis

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI**: Installed and configured with appropriate credentials
2. **AWS CDK**: Version 2.156.0 or later installed globally
3. **Python**: Version 3.8 or later
4. **Node.js**: Version 18.x or later (for CDK CLI)
5. **Docker**: For building and running containers locally (optional)

### Required AWS Permissions

Your AWS credentials must have permissions to create:
- EKS clusters and node groups
- VPC, subnets, and networking resources
- IAM roles and policies
- CloudWatch logs, metrics, and dashboards
- Amazon Managed Prometheus workspaces
- EC2 instances and security groups

## Quick Start

### 1. Clone and Setup

```bash
# Navigate to the CDK Python directory
cd cdk-python/

# Create a Python virtual environment
python3 -m venv venv

# Activate the virtual environment
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Bootstrap CDK (First Time Only)

```bash
# Bootstrap CDK in your AWS account and region
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Synthesize the CloudFormation template
cdk synth

# Deploy the stack
cdk deploy

# Deploy with approval for IAM changes
cdk deploy --require-approval never
```

### 4. Configure kubectl

After deployment, configure kubectl to access your EKS cluster:

```bash
# The exact command will be shown in the CDK output
aws eks update-kubeconfig --region <your-region> --name <cluster-name>

# Verify connectivity
kubectl get nodes
kubectl get pods --all-namespaces
```

## Deployment Options

### Environment Variables

You can customize the deployment using environment variables:

```bash
# Set custom AWS account and region
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-west-2

# Deploy with custom settings
cdk deploy
```

### Custom Configuration

Modify the stack parameters in `app.py`:

```python
# Create the EKS Observability Stack with custom settings
EKSObservabilityStack(
    self,
    "EKSObservabilityStack",
    cluster_name="my-custom-cluster",  # Custom cluster name
    env=env,
    # ... other parameters
)
```

## Monitoring and Verification

### 1. Verify EKS Cluster

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check cluster info
kubectl cluster-info
```

### 2. Verify Logging Components

```bash
# Check Fluent Bit pods
kubectl get pods -n amazon-cloudwatch

# Check CloudWatch agent
kubectl get daemonset -n amazon-cloudwatch
```

### 3. Access CloudWatch

- **CloudWatch Logs**: Navigate to CloudWatch Logs in the AWS Console
- **Container Insights**: View performance metrics in CloudWatch Container Insights
- **Dashboards**: Access the created dashboard for comprehensive monitoring

### 4. Access Prometheus

- **AMP Console**: Navigate to Amazon Managed Service for Prometheus
- **Workspace**: Access the created workspace for metrics exploration
- **Grafana**: Optionally connect Amazon Managed Grafana for visualization

## Customization

### Adding Custom Metrics

To add custom application metrics:

1. **Annotate Pods**: Add Prometheus annotations to your pod specifications
2. **Expose Metrics**: Ensure your application exposes metrics on `/metrics` endpoint
3. **Configure Scraping**: The Prometheus scraper automatically discovers annotated pods

Example pod annotations:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

### Custom Dashboards

Create custom CloudWatch dashboards by modifying the `_create_cloudwatch_dashboard` method in `app.py`.

### Additional Alarms

Add custom alarms by extending the `_create_cloudwatch_alarms` method with your specific metrics and thresholds.

## Security Considerations

This CDK application follows AWS security best practices:

- **IAM Roles**: Uses service roles with least-privilege permissions
- **Network Security**: Deploys EKS in private subnets with controlled access
- **Encryption**: Enables encryption at rest and in transit where possible
- **VPC Security**: Implements proper VPC configuration with security groups

## Cost Optimization

The solution includes several cost optimization features:

- **Managed Services**: Uses managed services to reduce operational overhead
- **Right-sizing**: Configures appropriate instance types and sizes
- **Log Retention**: Sets reasonable log retention periods
- **Spot Instances**: Can be configured to use spot instances for cost savings

## Troubleshooting

### Common Issues

1. **Bootstrap Required**: If you see bootstrap errors, run `cdk bootstrap`
2. **Permissions**: Ensure your AWS credentials have sufficient permissions
3. **Region**: Verify you're deploying to the correct AWS region
4. **Quotas**: Check service quotas for EKS, EC2, and other resources

### Debugging

```bash
# Check CDK differences
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name EKSObservabilityStack

# Check EKS cluster status
aws eks describe-cluster --name <cluster-name>
```

## Cleanup

To avoid ongoing costs, destroy the stack when no longer needed:

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
cdk destroy --force
```

**Note**: Some resources may require manual cleanup:
- CloudWatch Log Groups (if retention is set)
- EBS volumes attached to worker nodes
- Load balancers created by Kubernetes services

## Development

### Code Structure

```
cdk-python/
├── app.py                 # Main CDK application
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
├── README.md             # This file
└── venv/                 # Virtual environment (created locally)
```

### Development Workflow

1. **Make Changes**: Modify the CDK code in `app.py`
2. **Synthesize**: Run `cdk synth` to generate CloudFormation
3. **Test**: Run `cdk diff` to see changes
4. **Deploy**: Run `cdk deploy` to apply changes

### Testing

```bash
# Install development dependencies
pip install -r requirements.txt

# Run tests (when available)
python -m pytest

# Type checking
mypy app.py

# Code formatting
black app.py
isort app.py
```

## Support

For issues and questions:

1. **AWS Documentation**: Reference the official AWS CDK and EKS documentation
2. **GitHub Issues**: Report issues in the cloud-recipes repository
3. **AWS Support**: Contact AWS Support for account-specific issues

## License

This code is provided under the MIT License. See the LICENSE file for details.

## Contributing

Contributions are welcome! Please read the contributing guidelines and submit pull requests for improvements.