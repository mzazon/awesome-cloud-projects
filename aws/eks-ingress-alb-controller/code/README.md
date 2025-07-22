# Infrastructure as Code for EKS Ingress with AWS Load Balancer Controller

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EKS Ingress with AWS Load Balancer Controller".

## Overview

This solution automates the provisioning and management of AWS Application Load Balancers (ALB) and Network Load Balancers (NLB) for Kubernetes ingress resources using the AWS Load Balancer Controller. The infrastructure provides native AWS integration, automatic SSL certificate management, advanced routing capabilities, and seamless integration with AWS security services.

## Architecture

The solution deploys:

- **EKS Cluster**: Managed Kubernetes cluster with worker nodes
- **AWS Load Balancer Controller**: Kubernetes controller for managing ALBs and NLBs
- **IAM Roles and Policies**: Service accounts with proper permissions via IRSA
- **Application Load Balancers**: Layer 7 load balancing with advanced routing
- **Network Load Balancers**: Layer 4 load balancing for TCP/UDP traffic
- **Sample Applications**: Demo applications for testing ingress functionality
- **SSL/TLS Configuration**: Integration with AWS Certificate Manager
- **Monitoring and Logging**: CloudWatch metrics and S3 access logs

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl (version 1.21 or later) installed and configured
- Helm 3.x installed
- eksctl installed (for CloudFormation and scripts)
- Node.js 18+ and npm (for CDK TypeScript)
- Python 3.8+ and pip (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Appropriate AWS permissions for:
  - EKS cluster management
  - IAM role and policy creation
  - VPC and networking resources
  - Application and Network Load Balancers
  - CloudWatch and S3 access
- Estimated cost: $100-200/month for EKS cluster, ALB/NLB, and associated resources

## Quick Start

### Using CloudFormation

```bash
# Set required parameters
export CLUSTER_NAME="eks-ingress-demo"
export AWS_REGION="us-west-2"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name eks-ingress-controller-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=$CLUSTER_NAME \
                 ParameterKey=Region,ParameterValue=$AWS_REGION \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Wait for stack creation
aws cloudformation wait stack-create-complete \
    --stack-name eks-ingress-controller-stack

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Verify deployment
kubectl get nodes
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables
export AWS_REGION="us-west-2"
export CLUSTER_NAME="eks-ingress-demo"

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy --all --require-approval never

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Verify deployment
kubectl get nodes
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export AWS_REGION="us-west-2"
export CLUSTER_NAME="eks-ingress-demo"

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --all --require-approval never

# Update kubeconfig
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Verify deployment
kubectl get nodes
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your desired values

# Plan the deployment
terraform plan

# Deploy the infrastructure
terraform apply -auto-approve

# Update kubeconfig
aws eks update-kubeconfig \
    --region $(terraform output -raw region) \
    --name $(terraform output -raw cluster_name)

# Verify deployment
kubectl get nodes
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### Using Bash Scripts

```bash
cd scripts/

# Set required environment variables
export AWS_REGION="us-west-2"
export CLUSTER_NAME="eks-ingress-demo"

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Deploy the infrastructure
./deploy.sh

# The script will:
# 1. Create EKS cluster
# 2. Set up IAM roles and policies
# 3. Install AWS Load Balancer Controller
# 4. Deploy sample applications
# 5. Create ingress resources

# Verify deployment
kubectl get nodes
kubectl get deployment -n kube-system aws-load-balancer-controller
```

## Testing the Deployment

After successful deployment, test the ingress functionality:

```bash
# Set the namespace (default: ingress-demo)
export NAMESPACE="ingress-demo"

# Get ingress details
kubectl get ingress -n $NAMESPACE

# Test basic ALB connectivity
ALB_DNS=$(kubectl get ingress sample-app-basic-alb -n $NAMESPACE \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -H "Host: basic.demo.example.com" http://$ALB_DNS/

# Test weighted routing (multiple requests to see distribution)
WEIGHTED_DNS=$(kubectl get ingress sample-app-weighted-routing -n $NAMESPACE \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in {1..10}; do
    curl -s -H "Host: weighted.demo.example.com" http://$WEIGHTED_DNS/ | head -1
done

# Check NLB service
kubectl get service sample-app-nlb -n $NAMESPACE

# Verify load balancers in AWS console
aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].{Name:LoadBalancerName,DNS:DNSName,Type:Type}' \
    --output table
```

## Configuration Options

### CloudFormation Parameters

- `ClusterName`: Name of the EKS cluster
- `Region`: AWS region for deployment
- `NodeInstanceType`: EC2 instance type for worker nodes (default: t3.medium)
- `NodeGroupSize`: Number of worker nodes (default: 3)
- `KubernetesVersion`: EKS cluster version (default: "1.28")

### CDK Configuration

Edit the stack configuration in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const cluster = new eks.Cluster(this, 'EKSCluster', {
    clusterName: process.env.CLUSTER_NAME || 'eks-ingress-demo',
    version: eks.KubernetesVersion.V1_28,
    defaultCapacity: 3,
    defaultCapacityInstance: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.MEDIUM
    ),
});
```

### Terraform Variables

Customize `terraform.tfvars`:

```hcl
cluster_name         = "eks-ingress-demo"
region              = "us-west-2"
node_instance_type  = "t3.medium"
node_group_size     = 3
kubernetes_version  = "1.28"

# Optional: VPC configuration
vpc_cidr = "10.0.0.0/16"
enable_nat_gateway = true
enable_dns_hostnames = true
```

## Advanced Features

### SSL/TLS Configuration

To enable SSL termination with ACM certificates:

```bash
# Request a certificate
CERT_ARN=$(aws acm request-certificate \
    --domain-name "*.yourdomain.com" \
    --validation-method DNS \
    --query 'CertificateArn' --output text)

# Update ingress with certificate ARN
kubectl annotate ingress sample-app-advanced-alb \
    -n $NAMESPACE \
    alb.ingress.kubernetes.io/certificate-arn=$CERT_ARN
```

### WAF Integration

Enable AWS WAF protection:

```bash
# Create WAF ACL
aws wafv2 create-web-acl \
    --name eks-ingress-waf \
    --scope REGIONAL \
    --default-action Allow={} \
    --region $AWS_REGION

# Associate with ALB via ingress annotation
kubectl annotate ingress sample-app-advanced-alb \
    -n $NAMESPACE \
    alb.ingress.kubernetes.io/wafv2-acl-arn=$WAF_ACL_ARN
```

### Custom IngressClass

Use custom ingress classes for different environments:

```bash
# Apply custom ingress class
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: production-alb
spec:
  controller: ingress.k8s.aws/alb
  parameters:
    apiVersion: elbv2.k8s.aws/v1beta1
    kind: IngressClassParams
    name: production-params
---
apiVersion: elbv2.k8s.aws/v1beta1
kind: IngressClassParams
metadata:
  name: production-params
spec:
  scheme: internet-facing
  targetType: ip
  tags:
    Environment: production
    Team: platform
EOF
```

## Monitoring and Observability

### CloudWatch Metrics

The AWS Load Balancer Controller automatically publishes metrics to CloudWatch:

- Request count and latency
- HTTP response codes
- Target group health
- Active connection count

### Access Logs

Enable S3 access logging:

```bash
# Create S3 bucket for logs
aws s3 mb s3://your-alb-access-logs-bucket

# Enable via ingress annotation
kubectl annotate ingress sample-app-basic-alb \
    -n $NAMESPACE \
    alb.ingress.kubernetes.io/load-balancer-attributes=access_logs.s3.enabled=true,access_logs.s3.bucket=your-alb-access-logs-bucket
```

### Controller Logs

Monitor the AWS Load Balancer Controller:

```bash
# View controller logs
kubectl logs -n kube-system \
    deployment/aws-load-balancer-controller \
    --follow

# Check controller metrics
kubectl top pods -n kube-system \
    -l app.kubernetes.io/name=aws-load-balancer-controller
```

## Troubleshooting

### Common Issues

1. **Controller not creating load balancers**:
   ```bash
   # Check IAM permissions
   kubectl describe serviceaccount aws-load-balancer-controller -n kube-system
   
   # Check controller logs
   kubectl logs -n kube-system deployment/aws-load-balancer-controller
   ```

2. **Ingress not getting external IP**:
   ```bash
   # Check ingress events
   kubectl describe ingress <ingress-name> -n $NAMESPACE
   
   # Verify subnet tags
   aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>"
   ```

3. **Target group health check failures**:
   ```bash
   # Check target group health
   aws elbv2 describe-target-health --target-group-arn <target-group-arn>
   
   # Check pod readiness
   kubectl get pods -n $NAMESPACE -o wide
   ```

### Validation Commands

```bash
# Verify EKS cluster
kubectl cluster-info

# Check AWS Load Balancer Controller
kubectl get deployment -n kube-system aws-load-balancer-controller

# List all ingresses
kubectl get ingress --all-namespaces

# Check load balancers
aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].LoadBalancerName'

# Verify IAM roles
aws iam list-attached-role-policies \
    --role-name AmazonEKSLoadBalancerControllerRole
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name eks-ingress-controller-stack

# Wait for deletion
aws cloudformation wait stack-delete-complete \
    --stack-name eks-ingress-controller-stack
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
npx cdk destroy --all  # or: cdk destroy --all for Python
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy -auto-approve
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh

# Manually delete any remaining resources if needed
eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION
```

## Security Considerations

- **IAM Permissions**: Uses IRSA (IAM Roles for Service Accounts) for secure access
- **Network Security**: Implements proper VPC, subnet, and security group configurations
- **SSL/TLS**: Supports automatic certificate management via ACM
- **Access Control**: Ingress-level authentication and authorization options
- **Audit Logging**: CloudTrail integration for API call monitoring

## Cost Optimization

- **Spot Instances**: Use spot instances for worker nodes in non-production environments
- **Ingress Groups**: Share ALBs across multiple ingresses to reduce costs
- **Right-sizing**: Monitor and adjust instance types based on actual usage
- **Lifecycle Policies**: Implement S3 lifecycle policies for access logs
- **Reserved Instances**: Use reserved instances for predictable workloads

## Support and Documentation

- [AWS Load Balancer Controller Documentation](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Application Load Balancer Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Network Load Balancer Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)
- [AWS Certificate Manager Documentation](https://docs.aws.amazon.com/acm/)

For issues with this infrastructure code, refer to the original recipe documentation or the AWS documentation links above.