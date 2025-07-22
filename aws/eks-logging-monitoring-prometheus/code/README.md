# Infrastructure as Code for EKS Logging and Monitoring with Prometheus

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EKS Logging and Monitoring with Prometheus".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (minimum version 2.0.0)
- kubectl installed and configured for EKS cluster access
- eksctl installed for EKS cluster management (optional but recommended)
- Appropriate AWS permissions for:
  - EKS cluster creation and management
  - CloudWatch Logs and Container Insights
  - Amazon Managed Service for Prometheus
  - IAM role creation and policy attachment
  - VPC and networking resource management
- Basic knowledge of Kubernetes, logging, and monitoring concepts
- Estimated cost: $50-100/month for small clusters (varies by log volume and metrics retention)

## Architecture Overview

This solution implements a comprehensive observability stack for Amazon EKS that includes:

- **EKS Cluster**: Managed Kubernetes cluster with comprehensive control plane logging
- **CloudWatch Container Insights**: Infrastructure monitoring and performance metrics
- **Fluent Bit**: Lightweight log processor for container log collection
- **Amazon Managed Service for Prometheus**: Fully managed Prometheus-compatible monitoring
- **CloudWatch Dashboards**: Centralized visualization of cluster metrics and logs
- **CloudWatch Alarms**: Automated alerting for critical cluster events
- **VPC Networking**: Dedicated networking infrastructure for the EKS cluster

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name eks-observability-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ClusterName,ParameterValue=my-eks-cluster \
                 ParameterKey=NodeGroupName,ParameterValue=my-node-group

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name eks-observability-stack

# Update kubectl configuration
aws eks update-kubeconfig --name my-eks-cluster
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters clusterName=my-eks-cluster

# Update kubectl configuration
aws eks update-kubeconfig --name my-eks-cluster
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters clusterName=my-eks-cluster

# Update kubectl configuration
aws eks update-kubeconfig --name my-eks-cluster
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -var="cluster_name=my-eks-cluster"

# Apply the configuration
terraform apply -var="cluster_name=my-eks-cluster"

# Update kubectl configuration
aws eks update-kubeconfig --name my-eks-cluster
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export CLUSTER_NAME=my-eks-cluster
export AWS_REGION=us-west-2

# Deploy the infrastructure
./scripts/deploy.sh

# The script will automatically update kubectl configuration
```

## Configuration Parameters

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| ClusterName | Name of the EKS cluster | eks-observability-cluster | Yes |
| NodeGroupName | Name of the EKS node group | eks-observability-nodegroup | Yes |
| NodeInstanceType | EC2 instance type for worker nodes | t3.medium | No |
| NodeGroupMinSize | Minimum number of worker nodes | 2 | No |
| NodeGroupMaxSize | Maximum number of worker nodes | 4 | No |
| NodeGroupDesiredSize | Desired number of worker nodes | 2 | No |
| PrometheusWorkspaceName | Name of the Prometheus workspace | eks-prometheus-workspace | No |

### CDK Parameters

Both CDK implementations support the same parameters through context variables:

```bash
# Set parameters via context
cdk deploy -c clusterName=my-eks-cluster -c nodeInstanceType=t3.large
```

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| cluster_name | Name of the EKS cluster | string | "eks-observability-cluster" |
| node_group_name | Name of the EKS node group | string | "eks-observability-nodegroup" |
| node_instance_type | EC2 instance type for worker nodes | string | "t3.medium" |
| node_group_min_size | Minimum number of worker nodes | number | 2 |
| node_group_max_size | Maximum number of worker nodes | number | 4 |
| node_group_desired_size | Desired number of worker nodes | number | 2 |
| prometheus_workspace_name | Name of the Prometheus workspace | string | "eks-prometheus-workspace" |
| aws_region | AWS region for deployment | string | "us-west-2" |

## Post-Deployment Configuration

After deploying the infrastructure, you'll need to configure the monitoring components:

### 1. Deploy Fluent Bit and CloudWatch Agent

```bash
# Apply Kubernetes manifests for logging and monitoring
kubectl apply -f ../manifests/fluent-bit-config.yaml
kubectl apply -f ../manifests/fluent-bit-daemonset.yaml
kubectl apply -f ../manifests/cwagent-config.yaml
kubectl apply -f ../manifests/cwagent-daemonset.yaml
```

### 2. Deploy Sample Application (Optional)

```bash
# Deploy sample application with Prometheus metrics
kubectl apply -f ../manifests/sample-app-with-metrics.yaml
```

### 3. Verify Deployment

```bash
# Check cluster status
kubectl get nodes

# Check monitoring pods
kubectl get pods -n amazon-cloudwatch

# Check application pods
kubectl get pods -n default
```

## Monitoring and Observability

### CloudWatch Dashboards

The deployment creates a comprehensive CloudWatch dashboard that includes:

- EKS cluster node status and health
- Pod status and distribution
- Node resource utilization (CPU, memory, disk)
- Control plane error logs

Access the dashboard in the AWS Console:
1. Navigate to CloudWatch > Dashboards
2. Select the dashboard named `{cluster-name}-observability`

### CloudWatch Alarms

The solution includes pre-configured alarms for:

- High CPU utilization (>80% for 10 minutes)
- High memory utilization (>80% for 10 minutes)
- High number of failed pods (>5 pods)

### Prometheus Metrics

The Amazon Managed Service for Prometheus workspace collects:

- Kubernetes API server metrics
- Node and pod metrics
- Custom application metrics (from annotated services)

### Log Analysis

Use CloudWatch Logs Insights to query and analyze logs:

```sql
-- Control plane errors
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50

-- Authentication failures
fields @timestamp, @message
| filter @message like /authentication failed/
| sort @timestamp desc
| limit 50

-- Application pod errors
fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
```

## Troubleshooting

### Common Issues

1. **Cluster Creation Fails**
   - Verify AWS permissions for EKS service
   - Check VPC and subnet configuration
   - Ensure service roles have correct trust policies

2. **Nodes Not Joining Cluster**
   - Verify node group IAM role permissions
   - Check subnet routing and internet gateway
   - Ensure security group rules allow communication

3. **Monitoring Pods Not Running**
   - Check IAM roles for service accounts (IRSA)
   - Verify CloudWatch agent permissions
   - Check pod logs for error messages

4. **Prometheus Not Collecting Metrics**
   - Verify Prometheus workspace is active
   - Check scraper configuration and status
   - Ensure proper service discovery annotations

### Debugging Commands

```bash
# Check cluster status
aws eks describe-cluster --name {cluster-name}

# Check node group status
aws eks describe-nodegroup --cluster-name {cluster-name} --nodegroup-name {nodegroup-name}

# Check CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/"

# Check Prometheus workspace
aws amp describe-workspace --workspace-id {workspace-id}

# Check Kubernetes events
kubectl get events --sort-by=.metadata.creationTimestamp
```

## Cost Optimization

### Monitoring Costs

- **CloudWatch Logs**: Charges based on data ingestion and storage
- **Container Insights**: Fixed monthly charge per cluster
- **Prometheus**: Charges based on samples ingested and stored
- **EC2 Instances**: Worker node compute costs

### Cost Optimization Strategies

1. **Log Retention**: Set appropriate log retention periods
2. **Metric Filtering**: Filter unnecessary metrics at the source
3. **Instance Right-sizing**: Use appropriate instance types for workloads
4. **Spot Instances**: Consider spot instances for non-critical workloads

## Security Considerations

### IAM Best Practices

- All service roles use least privilege principle
- IAM roles for service accounts (IRSA) for secure credential management
- No long-term credentials stored in cluster

### Network Security

- VPC with private subnets for worker nodes
- Security groups with minimal required access
- Network ACLs for additional layer of security

### Monitoring Security

- Control plane audit logging enabled
- CloudWatch Logs encrypted at rest
- Prometheus metrics access controlled via IAM

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name eks-observability-stack

# Wait for stack deletion to complete
aws cloudformation wait stack-delete-complete --stack-name eks-observability-stack
```

### Using CDK

```bash
# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually delete resources in this order:

1. EKS node groups
2. EKS cluster
3. Prometheus workspace and scraper
4. CloudWatch dashboards and alarms
5. IAM roles and policies
6. VPC and networking resources

## Support and Resources

### Documentation

- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [Amazon Managed Service for Prometheus](https://docs.aws.amazon.com/prometheus/latest/userguide/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/)

### Troubleshooting Resources

- [EKS Troubleshooting Guide](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [CloudWatch Logs Troubleshooting](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWLogs_Troubleshooting.html)
- [Prometheus Troubleshooting](https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-troubleshooting.html)

### Community Support

- [AWS EKS GitHub Repository](https://github.com/aws/amazon-eks-pod-identity-webhook)
- [Fluent Bit Community](https://github.com/fluent/fluent-bit)
- [Prometheus Community](https://github.com/prometheus/prometheus)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.