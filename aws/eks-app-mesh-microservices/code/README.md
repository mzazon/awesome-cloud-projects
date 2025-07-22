# Infrastructure as Code for EKS Microservices with App Mesh Service Mesh

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EKS Microservices with App Mesh Service Mesh".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This IaC deploys a complete microservices architecture on Amazon EKS with AWS App Mesh service mesh, including:

- Amazon EKS cluster with managed node groups
- AWS App Mesh service mesh with virtual nodes, services, and routers
- Sample microservices (frontend, backend, database) with Envoy sidecars
- Application Load Balancer for external access
- Amazon ECR repositories for container images
- X-Ray distributed tracing integration
- Advanced traffic management with canary deployment capabilities

## Prerequisites

### General Requirements
- AWS account with appropriate permissions for EKS, App Mesh, ECR, and associated services
- AWS CLI v2 installed and configured (minimum version 2.0.38)
- kubectl client installed and configured
- Docker installed for container image building

### Tool-Specific Prerequisites

#### For CloudFormation
- AWS CLI with CloudFormation permissions
- Estimated deployment time: 25-30 minutes

#### For CDK TypeScript
- Node.js 18+ and npm installed
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript knowledge recommended

#### For CDK Python
- Python 3.8+ installed
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- Python development experience recommended

#### For Terraform
- Terraform 1.5+ installed
- kubectl CLI tool installed
- Helm v3 installed

#### For Bash Scripts
- eksctl CLI tool installed (version 0.100.0 or later)
- Helm v3 installed for App Mesh controller deployment
- jq utility for JSON processing

### Permissions Required

Your AWS credentials must have permissions for:
- EKS cluster creation and management
- EC2 instances and VPC management
- IAM role creation and policy attachment
- ECR repository creation and image management
- App Mesh resource management
- Application Load Balancer creation
- X-Ray service access

## Cost Considerations

Estimated costs for a 4-hour session:
- EKS cluster: ~$0.40/hour
- EC2 worker nodes (3x m5.large): ~$0.29/hour
- Application Load Balancer: ~$0.03/hour
- ECR storage: ~$0.10/GB/month
- **Total estimated cost: $50-100 for 4-hour testing session**

> **Warning**: Remember to clean up resources after testing to avoid ongoing charges.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name microservices-eks-appmesh-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=demo-mesh-cluster \
                 ParameterKey=MeshName,ParameterValue=demo-mesh \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-west-2

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name microservices-eks-appmesh-stack \
    --query 'Stacks[0].StackStatus'

# Get cluster info after deployment
aws cloudformation describe-stacks \
    --stack-name microservices-eks-appmesh-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --all

# Get outputs
cdk ls
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy --all

# Get outputs
cdk ls
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# 1. Create EKS cluster
# 2. Install App Mesh controller
# 3. Deploy sample microservices
# 4. Configure service mesh
# 5. Set up load balancer
# 6. Enable distributed tracing
```

## Post-Deployment Configuration

### Update kubectl Context
```bash
# Update kubeconfig for EKS cluster
aws eks update-kubeconfig \
    --region us-west-2 \
    --name your-cluster-name

# Verify connection
kubectl get nodes
```

### Verify App Mesh Installation
```bash
# Check App Mesh controller
kubectl get pods -n appmesh-system

# Verify mesh resources
kubectl get mesh,virtualnode,virtualservice,virtualrouter -n demo
```

### Test Application
```bash
# Get load balancer URL
ALB_URL=$(kubectl get ingress frontend-ingress -n demo \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test the application
curl http://${ALB_URL}

# Test multiple times to see traffic distribution
for i in {1..10}; do curl -s http://${ALB_URL} && echo; done
```

## Customization

### Environment Variables
Each implementation supports customization through variables:

#### CloudFormation Parameters
- `ClusterName`: EKS cluster name
- `MeshName`: App Mesh name
- `NodeInstanceType`: EC2 instance type for worker nodes
- `NodeGroupDesiredSize`: Number of worker nodes

#### CDK Context Variables
- `clusterName`: EKS cluster name
- `meshName`: App Mesh name
- `environment`: Deployment environment (dev/staging/prod)

#### Terraform Variables
- `cluster_name`: EKS cluster name
- `mesh_name`: App Mesh name
- `node_instance_type`: EC2 instance type
- `region`: AWS region

### Scaling Configuration

#### Horizontal Pod Autoscaler
```bash
# Enable HPA for backend service
kubectl autoscale deployment backend \
    --cpu-percent=70 \
    --min=2 \
    --max=10 \
    -n demo
```

#### Cluster Autoscaler
The Terraform implementation includes cluster autoscaler configuration that automatically adjusts node group size based on demand.

### Traffic Management

#### Canary Deployment
Update the virtual router to adjust traffic weights:

```bash
# Shift more traffic to v2 (20%)
kubectl patch virtualrouter backend-virtual-router -n demo \
    --type='merge' \
    -p='{"spec":{"routes":[{"name":"backend-route","httpRoute":{"action":{"weightedTargets":[{"virtualNodeRef":{"name":"backend-virtual-node"},"weight":80},{"virtualNodeRef":{"name":"backend-v2-virtual-node"},"weight":20}]}}}]}}'
```

## Monitoring and Observability

### CloudWatch Dashboards
Access pre-configured dashboards for:
- EKS cluster metrics
- App Mesh service metrics
- Application performance metrics

### X-Ray Tracing
```bash
# View traces in AWS Console or CLI
aws xray get-trace-summaries \
    --time-range-type TimeRangeByStartTime \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S)
```

### Application Logs
```bash
# View application logs
kubectl logs -f deployment/frontend -n demo
kubectl logs -f deployment/backend -n demo

# View Envoy proxy logs
kubectl logs -f deployment/frontend -c envoy -n demo
```

## Troubleshooting

### Common Issues

#### Pods Not Starting
```bash
# Check pod status
kubectl describe pods -n demo

# Check events
kubectl get events -n demo --sort-by='.lastTimestamp'
```

#### Sidecar Injection Issues
```bash
# Verify namespace labels
kubectl get namespace demo --show-labels

# Check App Mesh controller logs
kubectl logs -n appmesh-system deployment/appmesh-controller
```

#### Load Balancer Not Ready
```bash
# Check ingress status
kubectl describe ingress frontend-ingress -n demo

# Check AWS Load Balancer Controller
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

### Service Mesh Debugging

#### Check Virtual Node Health
```bash
# Describe virtual nodes
kubectl describe virtualnode -n demo

# Check Envoy configuration
kubectl exec -n demo deployment/frontend -c envoy -- \
    curl -s localhost:9901/config_dump
```

#### Traffic Flow Verification
```bash
# Check service endpoints
kubectl get endpoints -n demo

# Test service connectivity
kubectl exec -n demo deployment/frontend -- \
    nslookup backend.demo.svc.cluster.local
```

## Security Considerations

### Network Security
- All inter-service communication flows through Envoy proxies
- Network policies can be applied for additional isolation
- TLS encryption available for service-to-service communication

### IAM Security
- Least privilege IAM roles for all components
- Service accounts use IAM roles for AWS service access
- No hardcoded credentials in any configuration

### Image Security
- Container images use minimal base images
- ECR repositories support image scanning
- Pod security standards enforced

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name microservices-eks-appmesh-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name microservices-eks-appmesh-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# Destroy all stacks
cdk destroy --all

# Confirm destruction when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Remove applications and App Mesh resources
# 2. Delete EKS cluster
# 3. Clean up ECR repositories
# 4. Remove temporary files
```

### Manual Cleanup Verification
```bash
# Verify EKS cluster deletion
aws eks list-clusters

# Verify ECR repositories
aws ecr describe-repositories

# Check for remaining load balancers
aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[?contains(LoadBalancerName, `demo`) || contains(LoadBalancerName, `mesh`)]'
```

## Advanced Configuration

### Multi-Environment Setup
For production deployments, consider:
- Separate clusters per environment
- GitOps deployment pipelines
- Infrastructure as Code versioning
- Automated testing and validation

### High Availability
- Multi-AZ node group deployment
- Pod disruption budgets
- Resource quotas and limits
- Backup and disaster recovery

### Performance Optimization
- Cluster autoscaling configuration
- Horizontal pod autoscaling
- Vertical pod autoscaling
- Resource requests and limits tuning

## Migration from App Mesh

> **Important**: AWS App Mesh will reach end of support on September 30, 2026. Consider migrating to:
- Istio service mesh
- Linkerd service mesh  
- Amazon ECS Service Connect
- Native Kubernetes networking

## Support and Documentation

### Official Documentation
- [AWS App Mesh User Guide](https://docs.aws.amazon.com/app-mesh/latest/userguide/)
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/latest/guide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Community Resources
- [AWS Containers Roadmap](https://github.com/aws/containers-roadmap)
- [eksctl Documentation](https://eksctl.io/)
- [App Mesh Examples](https://github.com/aws/aws-app-mesh-examples)

### Getting Help
For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult AWS documentation for specific services
4. Submit issues to the recipe repository

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow AWS and tool-specific best practices
3. Update documentation for any configuration changes
4. Ensure all implementations remain functionally equivalent