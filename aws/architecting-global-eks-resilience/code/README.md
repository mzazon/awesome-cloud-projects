# Infrastructure as Code for Architecting Global EKS Resilience with Cross-Region Networking

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Architecting Global EKS Resilience with Cross-Region Networking".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a multi-cluster Amazon EKS architecture spanning multiple AWS regions, connected through AWS Transit Gateway with cross-region peering and AWS VPC Lattice for service mesh federation. The architecture includes:

- Primary EKS cluster in us-east-1
- Secondary EKS cluster in us-west-2
- Cross-region Transit Gateway peering
- VPC Lattice service mesh federation
- Route 53 health checks for global load balancing
- Multi-AZ deployment for high availability

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl version 1.28+ installed locally
- eksctl version 0.140+ installed locally
- Helm v3.12+ installed locally
- Appropriate AWS permissions for:
  - Amazon EKS (full access)
  - AWS Transit Gateway (full access)
  - VPC Lattice (full access)
  - Route 53 (health checks and DNS management)
  - IAM (role creation and policy attachment)
  - EC2 (VPC, subnet, and security group management)
- Expert understanding of Kubernetes networking, AWS Transit Gateway, and service mesh concepts
- Estimated cost: $250-350/month for EKS clusters, Transit Gateway, VPC Lattice, Load Balancers, and associated resources

> **Note**: This recipe creates resources across multiple regions including Transit Gateway cross-region peering, which may incur additional data transfer costs and hourly charges for cross-region communication.

## Quick Start

### Using CloudFormation
```bash
# Deploy the primary region stack
aws cloudformation create-stack \
    --stack-name multi-cluster-eks-primary \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DeploymentRegion,ParameterValue=us-east-1 \
               ParameterKey=PeerRegion,ParameterValue=us-west-2 \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Deploy the secondary region stack
aws cloudformation create-stack \
    --stack-name multi-cluster-eks-secondary \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=DeploymentRegion,ParameterValue=us-west-2 \
               ParameterKey=PeerRegion,ParameterValue=us-east-1 \
    --capabilities CAPABILITY_IAM \
    --region us-west-2

# Wait for both stacks to complete
aws cloudformation wait stack-create-complete --stack-name multi-cluster-eks-primary --region us-east-1
aws cloudformation wait stack-create-complete --stack-name multi-cluster-eks-secondary --region us-west-2
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Deploy to primary region
export CDK_DEFAULT_REGION=us-east-1
cdk bootstrap
cdk deploy MultiClusterEksStack --parameters primaryRegion=us-east-1 --parameters secondaryRegion=us-west-2

# Deploy to secondary region
export CDK_DEFAULT_REGION=us-west-2
cdk bootstrap
cdk deploy MultiClusterEksStack --parameters primaryRegion=us-west-2 --parameters secondaryRegion=us-east-1
```

### Using CDK Python
```bash
cd cdk-python/
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Deploy to primary region
export CDK_DEFAULT_REGION=us-east-1
cdk bootstrap
cdk deploy MultiClusterEksStack --parameters primary-region=us-east-1 --parameters secondary-region=us-west-2

# Deploy to secondary region
export CDK_DEFAULT_REGION=us-west-2
cdk bootstrap
cdk deploy MultiClusterEksStack --parameters primary-region=us-west-2 --parameters secondary-region=us-east-1
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2"

# Deploy the infrastructure
terraform apply \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2"
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# The script will prompt for confirmation before creating resources
# Follow the prompts to configure regions and cluster names
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| DeploymentRegion | Primary AWS region for deployment | us-east-1 | Yes |
| PeerRegion | Secondary AWS region for peering | us-west-2 | Yes |
| ClusterName | EKS cluster name suffix | multi-cluster | No |
| NodeInstanceType | EC2 instance type for worker nodes | m5.large | No |
| MinNodes | Minimum number of worker nodes | 2 | No |
| MaxNodes | Maximum number of worker nodes | 6 | No |
| DesiredNodes | Desired number of worker nodes | 3 | No |

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| primary_region | Primary AWS region | string | "us-east-1" |
| secondary_region | Secondary AWS region | string | "us-west-2" |
| cluster_name_prefix | Prefix for EKS cluster names | string | "multi-cluster" |
| node_instance_type | EC2 instance type for worker nodes | string | "m5.large" |
| min_nodes | Minimum nodes per cluster | number | 2 |
| max_nodes | Maximum nodes per cluster | number | 6 |
| desired_nodes | Desired nodes per cluster | number | 3 |
| vpc_cidr_primary | CIDR block for primary VPC | string | "10.1.0.0/16" |
| vpc_cidr_secondary | CIDR block for secondary VPC | string | "10.2.0.0/16" |

### CDK Configuration

Both CDK implementations support the same configuration through context variables or environment variables:

```json
{
  "primaryRegion": "us-east-1",
  "secondaryRegion": "us-west-2",
  "clusterNamePrefix": "multi-cluster",
  "nodeInstanceType": "m5.large",
  "minNodes": 2,
  "maxNodes": 6,
  "desiredNodes": 3
}
```

## Post-Deployment Configuration

After deploying the infrastructure, additional configuration is required to complete the setup:

### 1. Configure kubectl Access

```bash
# Update kubeconfig for primary cluster
aws eks update-kubeconfig \
    --name <primary-cluster-name> \
    --region us-east-1 \
    --alias primary-cluster

# Update kubeconfig for secondary cluster
aws eks update-kubeconfig \
    --name <secondary-cluster-name> \
    --region us-west-2 \
    --alias secondary-cluster
```

### 2. Install VPC Lattice Gateway API Controller

```bash
# Install in primary cluster
kubectl --context=primary-cluster apply -f \
    https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/deploy/deploy-v1.0.0.yaml

# Install in secondary cluster
kubectl --context=secondary-cluster apply -f \
    https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/deploy/deploy-v1.0.0.yaml
```

### 3. Deploy Sample Applications

```bash
# Deploy nginx applications with VPC Lattice integration
kubectl --context=primary-cluster apply -f sample-apps/nginx-primary.yaml
kubectl --context=secondary-cluster apply -f sample-apps/nginx-secondary.yaml
```

## Validation and Testing

### 1. Verify Cluster Status

```bash
# Check cluster status
kubectl --context=primary-cluster get nodes
kubectl --context=secondary-cluster get nodes

# Verify VPC Lattice controllers
kubectl --context=primary-cluster get pods -n aws-application-networking-system
kubectl --context=secondary-cluster get pods -n aws-application-networking-system
```

### 2. Test Cross-Region Connectivity

```bash
# Test Transit Gateway peering
aws ec2 describe-transit-gateway-peering-attachments --region us-east-1

# Test VPC Lattice service discovery
kubectl --context=primary-cluster get gateway,httproute
kubectl --context=secondary-cluster get gateway,httproute
```

### 3. Verify Route 53 Health Checks

```bash
# Check health check status
aws route53 get-health-check --health-check-id <health-check-id>
```

## Monitoring and Observability

The deployed infrastructure includes monitoring capabilities:

- **CloudWatch Logs**: EKS control plane logs
- **VPC Flow Logs**: Network traffic monitoring
- **Transit Gateway Metrics**: Cross-region traffic analysis
- **VPC Lattice Metrics**: Service mesh performance
- **Route 53 Health Check Metrics**: Global load balancing status

Access these through the AWS Console or configure additional monitoring tools like Prometheus and Grafana.

## Troubleshooting

### Common Issues

1. **EKS Cluster Creation Fails**
   - Verify IAM permissions for EKS service
   - Check subnet configuration and availability zones
   - Ensure VPC has DNS resolution enabled

2. **Transit Gateway Peering Issues**
   - Verify both regions support Transit Gateway
   - Check route table configurations
   - Ensure security groups allow cross-region traffic

3. **VPC Lattice Controller Issues**
   - Verify IAM permissions for VPC Lattice
   - Check controller pod logs
   - Ensure Gateway API CRDs are properly installed

4. **Cross-Region Communication Fails**
   - Verify Transit Gateway routes
   - Check VPC Lattice service network associations
   - Review security group and NACL rules

### Debugging Commands

```bash
# Check EKS cluster status
aws eks describe-cluster --name <cluster-name> --region <region>

# View Transit Gateway route tables
aws ec2 describe-transit-gateway-route-tables --region <region>

# Check VPC Lattice service networks
aws vpc-lattice list-service-networks --region <region>

# View controller logs
kubectl --context=<context> logs -n aws-application-networking-system deployment/gateway-api-controller
```

## Security Considerations

The infrastructure implements several security best practices:

- **IAM Roles**: Least privilege access for EKS clusters and nodes
- **Private Subnets**: Worker nodes deployed in private subnets
- **Security Groups**: Restrictive network access controls
- **VPC Lattice Auth**: IAM-based service authentication
- **Transit Gateway**: Private cross-region communication
- **Encryption**: EKS secrets encryption and EBS volume encryption

## Cost Optimization

To optimize costs:

1. **Use Spot Instances**: Configure node groups with spot instances for non-production workloads
2. **Cluster Autoscaling**: Enable cluster autoscaler to adjust capacity based on demand
3. **Reserved Instances**: Use Reserved Instances for predictable workloads
4. **Monitor Data Transfer**: Track cross-region data transfer costs
5. **Resource Cleanup**: Regularly clean up unused resources

## Cleanup

### Using CloudFormation
```bash
# Delete secondary region stack first
aws cloudformation delete-stack --stack-name multi-cluster-eks-secondary --region us-west-2

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name multi-cluster-eks-secondary --region us-west-2

# Delete primary region stack
aws cloudformation delete-stack --stack-name multi-cluster-eks-primary --region us-east-1

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name multi-cluster-eks-primary --region us-east-1
```

### Using CDK
```bash
# Destroy secondary region deployment
export CDK_DEFAULT_REGION=us-west-2
cdk destroy MultiClusterEksStack

# Destroy primary region deployment
export CDK_DEFAULT_REGION=us-east-1
cdk destroy MultiClusterEksStack
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="primary_region=us-east-1" \
    -var="secondary_region=us-west-2"
```

### Using Bash Scripts
```bash
# Run the destruction script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
# Follow the prompts carefully to avoid accidental deletions
```

> **Warning**: Cleanup operations are irreversible. Ensure you have backed up any important data before proceeding with resource deletion.

## Support and Documentation

- **Original Recipe**: Refer to the complete recipe documentation for detailed implementation steps
- **AWS EKS Documentation**: [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/)
- **AWS Transit Gateway Documentation**: [Transit Gateway User Guide](https://docs.aws.amazon.com/vpc/latest/tgw/)
- **VPC Lattice Documentation**: [VPC Lattice User Guide](https://docs.aws.amazon.com/vpc-lattice/)
- **Kubernetes Documentation**: [Kubernetes.io](https://kubernetes.io/docs/)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's policies and AWS best practices before using in production environments.