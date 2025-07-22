# Infrastructure as Code for EKS Microservices with App Mesh Integration

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EKS Microservices with App Mesh Integration".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a complete microservices architecture on Amazon EKS with AWS App Mesh service mesh, including:

- Amazon EKS cluster with managed node groups
- AWS App Mesh with Envoy proxy sidecars
- Three sample microservices (Service A, B, and C)
- Application Load Balancer for external access
- Amazon ECR repositories for container images
- CloudWatch Container Insights for observability
- AWS X-Ray for distributed tracing

## Prerequisites

- AWS CLI v2 installed and configured (minimum version 2.0.38)
- kubectl client installed and configured
- eksctl CLI tool installed (version 0.100.0 or later)
- Helm v3 installed (version 3.0 or later)
- Docker installed for building container images
- Appropriate AWS permissions for:
  - EKS cluster creation and management
  - App Mesh configuration
  - IAM role and policy management
  - ECR repository management
  - CloudWatch and X-Ray access
  - Application Load Balancer creation

> **Cost Estimate**: $150-200 for 4 hours of testing (EKS cluster $0.10/hour, EC2 instances $0.50-1.00/hour depending on instance types)

> **Important**: AWS App Mesh will reach end of support on September 30, 2026. Consider migration to Amazon ECS Service Connect or third-party solutions like Istio.

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name microservices-mesh-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ClusterName,ParameterValue=microservices-mesh-cluster \
                 ParameterKey=AppMeshName,ParameterValue=microservices-mesh

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name microservices-mesh-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name microservices-mesh-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --all

# Get outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --all

# Get outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will:
# 1. Create EKS cluster with App Mesh support
# 2. Install App Mesh controller and CRDs
# 3. Build and push sample microservices to ECR
# 4. Deploy microservices with service mesh integration
# 5. Configure Application Load Balancer
# 6. Set up CloudWatch and X-Ray observability
```

## Post-Deployment Steps

After the infrastructure is deployed, you may need to complete these additional steps:

### 1. Build and Push Container Images

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Navigate to microservices source code
cd microservices-demo/

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build and push images (these commands are included in the bash scripts)
# See scripts/deploy.sh for complete image building process
```

### 2. Verify Deployment

```bash
# Update kubeconfig
aws eks update-kubeconfig --region ${AWS_REGION} --name microservices-mesh-cluster

# Check App Mesh resources
kubectl get mesh
kubectl get virtualnodes -n production
kubectl get virtualservices -n production

# Verify pods are running with sidecars
kubectl get pods -n production

# Get Load Balancer URL
kubectl get ingress -n production
```

### 3. Test the Application

```bash
# Get the Load Balancer URL
LOAD_BALANCER_URL=$(kubectl get ingress service-a-ingress -n production \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test service endpoints
curl http://${LOAD_BALANCER_URL}/
curl http://${LOAD_BALANCER_URL}/call-b
```

## Customization

### Environment Variables

Each implementation supports customization through variables/parameters:

- `ClusterName`: Name of the EKS cluster (default: microservices-mesh-cluster)
- `AppMeshName`: Name of the App Mesh (default: microservices-mesh)
- `NodeInstanceType`: EC2 instance type for worker nodes (default: t3.medium)
- `NodeGroupDesiredCapacity`: Number of worker nodes (default: 3)
- `Namespace`: Kubernetes namespace for applications (default: production)

### CloudFormation Parameters

```bash
aws cloudformation create-stack \
    --stack-name microservices-mesh-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=ClusterName,ParameterValue=my-cluster \
                 ParameterKey=NodeInstanceType,ParameterValue=t3.large
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
cluster_name = "my-microservices-cluster"
node_instance_type = "t3.large"
node_group_desired_capacity = 5
app_mesh_name = "my-service-mesh"
```

### CDK Context

Modify `cdk.json` or pass context values:

```bash
cdk deploy -c clusterName=my-cluster -c nodeInstanceType=t3.large
```

## Monitoring and Observability

The infrastructure includes comprehensive observability:

### CloudWatch Container Insights

- Automatic collection of container metrics and logs
- Performance monitoring for pods, nodes, and services
- Resource utilization tracking

### AWS X-Ray Distributed Tracing

- End-to-end request tracing across microservices
- Performance bottleneck identification
- Service dependency mapping

### Access Monitoring

```bash
# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ContainerInsights \
    --metric-name pod_cpu_utilization \
    --dimensions Name=ClusterName,Value=microservices-mesh-cluster

# View X-Ray traces
aws xray get-trace-summaries \
    --time-range-type TimeRangeByStartTime \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```

## Security Considerations

### IAM Best Practices

- Principle of least privilege for all IAM roles
- Service accounts use IAM roles for Service Accounts (IRSA)
- No hardcoded credentials in configurations

### Network Security

- Private subnets for worker nodes
- Security groups restrict traffic to necessary ports
- App Mesh provides service-to-service encryption

### Container Security

- ECR image scanning enabled
- Private container repositories
- Security contexts configured for pods

## Troubleshooting

### Common Issues

1. **EKS Cluster Creation Fails**
   ```bash
   # Check IAM permissions
   aws sts get-caller-identity
   
   # Verify eksctl version
   eksctl version
   ```

2. **App Mesh Controller Not Ready**
   ```bash
   # Check controller logs
   kubectl logs -n appmesh-system deployment/appmesh-controller
   
   # Verify IRSA configuration
   kubectl describe serviceaccount appmesh-controller -n appmesh-system
   ```

3. **Sidecar Injection Not Working**
   ```bash
   # Check namespace labels
   kubectl describe namespace production
   
   # Verify webhook configuration
   kubectl get mutatingwebhookconfigurations
   ```

4. **Load Balancer Not Accessible**
   ```bash
   # Check ingress status
   kubectl describe ingress service-a-ingress -n production
   
   # Verify ALB controller
   kubectl logs -n kube-system deployment/aws-load-balancer-controller
   ```

### Debugging Commands

```bash
# Check all App Mesh resources
kubectl get virtualnodes,virtualservices,mesh --all-namespaces

# View Envoy proxy configuration
kubectl exec -it <pod-name> -c envoy -- curl localhost:9901/config_dump

# Check service mesh metrics
kubectl exec -it <pod-name> -c envoy -- curl localhost:9901/stats
```

## Cleanup

### Using CloudFormation

```bash
aws cloudformation delete-stack --stack-name microservices-mesh-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name microservices-mesh-stack
```

### Using CDK

```bash
# From the CDK directory
cdk destroy --all
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete ECR repositories
aws ecr delete-repository --repository-name microservices-demo-service-a --force
aws ecr delete-repository --repository-name microservices-demo-service-b --force
aws ecr delete-repository --repository-name microservices-demo-service-c --force

# Clean up any remaining IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `eksctl`)]'
```

## Advanced Configuration

### Multi-Region Deployment

For disaster recovery scenarios, consider deploying across multiple regions:

```bash
# Deploy primary region
terraform apply -var="region=us-east-1"

# Deploy secondary region
terraform apply -var="region=us-west-2" -var="is_secondary=true"
```

### Production Considerations

1. **High Availability**: Use multiple AZs and increase node group size
2. **Security**: Implement mTLS, network policies, and Pod Security Standards
3. **Monitoring**: Add custom metrics and alerting rules
4. **Backup**: Configure EBS snapshots and cluster state backups
5. **Updates**: Plan for regular updates of EKS, App Mesh, and container images

## Support and Documentation

- [AWS App Mesh Documentation](https://docs.aws.amazon.com/app-mesh/)
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [AWS App Mesh Migration Guide](https://docs.aws.amazon.com/app-mesh/latest/userguide/migrating-from-app-mesh.html)
- [Kubernetes Service Mesh Comparison](https://kubernetes.io/docs/concepts/services-networking/service/)

For issues with this infrastructure code, refer to the original recipe documentation or the AWS documentation for the specific services.

## Migration Path

Given App Mesh's end-of-support timeline, consider these migration options:

1. **Amazon ECS Service Connect**: For containerized workloads on ECS
2. **Istio on EKS**: Open-source service mesh solution
3. **AWS Gateway API**: For simpler service-to-service communication
4. **Application Load Balancer**: For basic load balancing without service mesh

Plan your migration strategy early to ensure smooth transition before the September 2026 deadline.