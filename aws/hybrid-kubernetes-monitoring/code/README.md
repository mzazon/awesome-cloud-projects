# Infrastructure as Code for Hybrid Kubernetes Monitoring with EKS Hybrid Nodes

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid Kubernetes Monitoring with EKS Hybrid Nodes".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a hybrid Kubernetes monitoring infrastructure that includes:

- Amazon EKS cluster with hybrid node support
- AWS Fargate for serverless container execution
- Amazon CloudWatch with Container Insights
- Custom VPC with public and private subnets
- NAT Gateway for private subnet internet access
- IAM roles and policies for service integration
- CloudWatch dashboards and alarms for monitoring
- Sample applications for testing

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl installed (version 1.28 or later)
- AWS account with appropriate permissions for:
  - Amazon EKS
  - AWS Fargate
  - Amazon CloudWatch
  - AWS Systems Manager
  - VPC and networking resources
  - IAM role and policy management
- On-premises infrastructure with network connectivity to AWS (for hybrid nodes)
- Basic understanding of Kubernetes concepts and container orchestration
- Estimated cost: $150-300/month for cluster, Fargate tasks, CloudWatch metrics, and hybrid node charges

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name hybrid-k8s-monitoring \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ClusterName,ParameterValue=hybrid-monitoring-cluster \
                 ParameterKey=CloudWatchNamespace,ParameterValue=EKS/HybridMonitoring

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name hybrid-k8s-monitoring

# Update kubeconfig for cluster access
aws eks update-kubeconfig \
    --name $(aws cloudformation describe-stacks \
        --stack-name hybrid-k8s-monitoring \
        --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' \
        --output text)
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Update kubeconfig
aws eks update-kubeconfig --name $(cdk list --json | jq -r '.[0]' | sed 's/-stack$//')-cluster
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --require-approval never

# Update kubeconfig
aws eks update-kubeconfig --name $(cdk list --json | jq -r '.[0]' | sed 's/-stack$//')-cluster
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferences

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply

# Update kubeconfig
aws eks update-kubeconfig --name $(terraform output -raw cluster_name)
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will automatically update kubeconfig
```

## Post-Deployment Configuration

After deploying the infrastructure, follow these steps to complete the setup:

### 1. Verify Cluster Status

```bash
# Check cluster status
kubectl get nodes

# Verify CloudWatch add-on
kubectl get pods -n amazon-cloudwatch
```

### 2. Deploy Sample Applications

```bash
# Create namespaces
kubectl create namespace cloud-apps
kubectl create namespace onprem-apps

# Deploy sample application to test Fargate
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloud-sample-app
  namespace: cloud-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloud-sample-app
  template:
    metadata:
      labels:
        app: cloud-sample-app
    spec:
      containers:
      - name: sample-app
        image: public.ecr.aws/docker/library/nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF
```

### 3. Access CloudWatch Dashboard

The deployment creates a CloudWatch dashboard for monitoring. Access it via:

```bash
# Get dashboard URL
echo "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=$(aws configure get region)#dashboards:name=EKS-Hybrid-Monitoring-$(aws eks list-clusters --query 'clusters[0]' --output text)"
```

## Hybrid Node Configuration

To connect on-premises infrastructure as hybrid nodes:

1. **Network Connectivity**: Ensure reliable network connectivity between your on-premises environment and AWS via Direct Connect or Site-to-Site VPN.

2. **Download Node Agent**: Download the EKS Hybrid Node agent from your EKS cluster:

```bash
# Get the node agent download command from EKS console
aws eks describe-cluster --name <cluster-name> --query 'cluster.platformVersion'
```

3. **Install Agent**: Follow the EKS Hybrid Nodes documentation to install and configure the agent on your on-premises servers.

4. **Verify Connection**: Verify that hybrid nodes appear in your cluster:

```bash
kubectl get nodes -l node.kubernetes.io/instance-type=hybrid
```

## Monitoring and Observability

### CloudWatch Dashboards

The deployment creates comprehensive dashboards showing:

- Hybrid cluster capacity metrics
- Pod resource utilization across environments
- Application logs from cloud workloads
- Custom metrics for hybrid vs. Fargate distribution

### CloudWatch Alarms

Automated alarms monitor:

- High CPU utilization (>80%)
- High memory utilization (>80%)
- Low hybrid node count (<1)

### Custom Metrics

The solution includes custom metrics collection for:

- Hybrid node count
- Fargate pod count
- Total pod distribution

## Validation and Testing

### Test Application Connectivity

```bash
# Test the sample application
kubectl port-forward -n cloud-apps service/cloud-sample-service 8080:80 &
curl http://localhost:8080
pkill -f "kubectl port-forward"
```

### Verify Metrics Flow

```bash
# Check custom metrics in CloudWatch
aws cloudwatch list-metrics --namespace "EKS/HybridMonitoring"

# View Container Insights metrics
aws cloudwatch list-metrics \
    --namespace AWS/ContainerInsights \
    --dimensions Name=ClusterName,Value=$(aws eks list-clusters --query 'clusters[0]' --output text)
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack --stack-name hybrid-k8s-monitoring

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name hybrid-k8s-monitoring
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Deactivate virtual environment (Python only)
deactivate
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Clean up state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Customization

### Configuration Variables

Each implementation supports customization through variables:

#### CloudFormation Parameters
- `ClusterName`: Name for the EKS cluster
- `CloudWatchNamespace`: Custom namespace for metrics
- `VpcCidr`: CIDR block for the VPC
- `OnPremisesCidr`: CIDR block for on-premises network

#### CDK Configuration
Modify the following in the CDK code:
- Cluster configuration settings
- Fargate profile specifications
- CloudWatch dashboard layout
- Custom metric definitions

#### Terraform Variables
- `cluster_name`: EKS cluster name
- `cloudwatch_namespace`: Custom metrics namespace
- `vpc_cidr`: VPC CIDR block
- `onpremises_cidr`: On-premises network CIDR
- `enable_container_insights`: Enable/disable Container Insights

### Security Customization

- **IAM Policies**: Modify IAM roles for least privilege access
- **Network Security**: Adjust security groups and NACLs
- **Encryption**: Configure encryption at rest and in transit
- **Monitoring**: Customize CloudWatch log retention periods

### Cost Optimization

- **Fargate Sizing**: Adjust CPU and memory requests/limits
- **CloudWatch Metrics**: Modify metric collection intervals
- **Resource Tagging**: Implement comprehensive tagging for cost allocation
- **Spot Instances**: Consider using Spot instances for non-critical workloads

## Troubleshooting

### Common Issues

1. **Cluster Creation Fails**
   - Verify IAM permissions
   - Check VPC configuration
   - Ensure region supports EKS Hybrid Nodes

2. **Fargate Pods Won't Start**
   - Verify Fargate profile configuration
   - Check private subnet routing
   - Validate NAT Gateway connectivity

3. **CloudWatch Metrics Missing**
   - Verify CloudWatch add-on installation
   - Check IAM roles for service accounts
   - Validate OIDC provider configuration

4. **Hybrid Nodes Can't Connect**
   - Verify network connectivity to AWS
   - Check security group rules
   - Validate on-premises agent configuration

### Debug Commands

```bash
# Check cluster status
aws eks describe-cluster --name <cluster-name>

# Verify add-on status
aws eks describe-addon --cluster-name <cluster-name> --addon-name amazon-cloudwatch-observability

# Check Fargate profile
aws eks describe-fargate-profile --cluster-name <cluster-name> --fargate-profile-name cloud-workloads

# View CloudWatch agent logs
kubectl logs -n amazon-cloudwatch -l app=cloudwatch-agent
```

## Support and Documentation

For additional support:

- [Amazon EKS Documentation](https://docs.aws.amazon.com/eks/)
- [EKS Hybrid Nodes Guide](https://docs.aws.amazon.com/eks/latest/userguide/hybrid-nodes-overview.html)
- [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)

For issues with this infrastructure code, refer to the original recipe documentation or AWS support resources.

## Contributing

When modifying the infrastructure code:

1. Test changes in a development environment
2. Validate security configurations
3. Update documentation accordingly
4. Follow provider best practices
5. Ensure cleanup procedures work correctly

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements and policies.