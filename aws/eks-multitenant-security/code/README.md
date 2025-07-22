# Infrastructure as Code for EKS Multi-Tenant Security with Namespaces

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EKS Multi-Tenant Security with Namespaces".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl command-line tool installed
- Appropriate AWS permissions for EKS, IAM, and VPC management
- An existing EKS cluster (or ability to create one)
- Basic understanding of Kubernetes concepts (pods, namespaces, services)
- Familiarity with RBAC and IAM principles

### Tool-Specific Prerequisites

#### CloudFormation
- AWS CLI with CloudFormation permissions
- IAM permissions for stack creation and resource management

#### CDK TypeScript
- Node.js (version 14 or later)
- npm or yarn package manager
- AWS CDK CLI (`npm install -g aws-cdk`)

#### CDK Python
- Python 3.7 or later
- pip package manager
- AWS CDK CLI (`pip install aws-cdk-lib`)

#### Terraform
- Terraform (version 1.0 or later)
- AWS provider for Terraform

#### Bash Scripts
- Bash shell environment
- jq for JSON processing
- AWS CLI and kubectl configured

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the multi-tenant security infrastructure
aws cloudformation create-stack \
    --stack-name eks-multi-tenant-security \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=my-multi-tenant-cluster \
                 ParameterKey=TenantAName,ParameterValue=tenant-alpha \
                 ParameterKey=TenantBName,ParameterValue=tenant-beta \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name eks-multi-tenant-security

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name eks-multi-tenant-security \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters clusterName=my-multi-tenant-cluster \
           --parameters tenantAName=tenant-alpha \
           --parameters tenantBName=tenant-beta

# List deployed resources
cdk ls
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --parameters clusterName=my-multi-tenant-cluster \
           --parameters tenantAName=tenant-alpha \
           --parameters tenantBName=tenant-beta

# List deployed resources
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="cluster_name=my-multi-tenant-cluster" \
    -var="tenant_a_name=tenant-alpha" \
    -var="tenant_b_name=tenant-beta"

# Apply the infrastructure
terraform apply \
    -var="cluster_name=my-multi-tenant-cluster" \
    -var="tenant_a_name=tenant-alpha" \
    -var="tenant_b_name=tenant-beta"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export CLUSTER_NAME="my-multi-tenant-cluster"
export TENANT_A_NAME="tenant-alpha"
export TENANT_B_NAME="tenant-beta"

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment
kubectl get namespaces --show-labels | grep -E "(tenant-alpha|tenant-beta)"
```

## Configuration Options

### Environment Variables

The following environment variables can be set to customize the deployment:

- `CLUSTER_NAME`: Name of the existing EKS cluster (default: "my-multi-tenant-cluster")
- `TENANT_A_NAME`: Name for the first tenant (default: "tenant-alpha")
- `TENANT_B_NAME`: Name for the second tenant (default: "tenant-beta")
- `AWS_REGION`: AWS region for deployment (default: from AWS CLI configuration)

### Customizable Parameters

#### CloudFormation Parameters
- `ClusterName`: EKS cluster name
- `TenantAName`: First tenant identifier
- `TenantBName`: Second tenant identifier
- `ResourceQuotaCPU`: CPU quota per tenant (default: "2")
- `ResourceQuotaMemory`: Memory quota per tenant (default: "4Gi")

#### CDK Parameters
- `clusterName`: EKS cluster name
- `tenantAName`: First tenant identifier
- `tenantBName`: Second tenant identifier
- `resourceQuotaCpu`: CPU quota per tenant
- `resourceQuotaMemory`: Memory quota per tenant

#### Terraform Variables
- `cluster_name`: EKS cluster name
- `tenant_a_name`: First tenant identifier
- `tenant_b_name`: Second tenant identifier
- `resource_quota_cpu`: CPU quota per tenant
- `resource_quota_memory`: Memory quota per tenant
- `enable_network_policies`: Enable network policy enforcement (default: true)

## Validation and Testing

After deployment, validate the multi-tenant security configuration:

### Verify Namespace Isolation

```bash
# Check namespace creation and labels
kubectl get namespaces --show-labels | grep -E "(tenant-alpha|tenant-beta)"

# Verify pods are isolated in correct namespaces
kubectl get pods -n tenant-alpha
kubectl get pods -n tenant-beta
```

### Test RBAC Permissions

```bash
# Test cross-namespace access restrictions (should fail)
kubectl auth can-i get pods --as=tenant-alpha-user -n tenant-beta
kubectl auth can-i get pods --as=tenant-beta-user -n tenant-alpha

# Test allowed namespace access (should succeed)
kubectl auth can-i get pods --as=tenant-alpha-user -n tenant-alpha
```

### Validate Network Policies

```bash
# Test network connectivity between tenants (should fail)
kubectl exec -n tenant-alpha \
    $(kubectl get pods -n tenant-alpha -o jsonpath='{.items[0].metadata.name}') \
    -- curl -m 5 tenant-beta-service.tenant-beta.svc.cluster.local

# Test internal connectivity (should succeed)
kubectl exec -n tenant-alpha \
    $(kubectl get pods -n tenant-alpha -o jsonpath='{.items[0].metadata.name}') \
    -- curl -m 5 tenant-alpha-service.tenant-alpha.svc.cluster.local
```

### Verify Resource Quotas

```bash
# Check resource quota usage
kubectl describe quota tenant-alpha-quota -n tenant-alpha
kubectl describe quota tenant-beta-quota -n tenant-beta

# Check limit ranges
kubectl describe limitrange tenant-alpha-limits -n tenant-alpha
kubectl describe limitrange tenant-beta-limits -n tenant-beta
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name eks-multi-tenant-security

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name eks-multi-tenant-security
```

### Using CDK (AWS)

```bash
# For TypeScript
cd cdk-typescript/
cdk destroy

# For Python
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="cluster_name=my-multi-tenant-cluster" \
    -var="tenant_a_name=tenant-alpha" \
    -var="tenant_b_name=tenant-beta"

# Clean up Terraform state
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify cleanup
kubectl get namespaces | grep -E "(tenant-alpha|tenant-beta)"
```

## Security Considerations

### Network Policy Requirements

> **Warning**: Network policies require a compatible CNI plugin such as Calico, Cilium, or the AWS VPC CNI with network policy support. Ensure your EKS cluster has network policy enforcement enabled before implementing these policies.

### IAM Best Practices

- The infrastructure creates IAM roles with minimal required permissions
- Access entries map IAM roles to Kubernetes RBAC permissions
- Regular review and rotation of IAM credentials is recommended

### Resource Isolation

- Resource quotas prevent resource exhaustion attacks
- Network policies enforce traffic isolation between tenants
- RBAC ensures API-level access control

## Troubleshooting

### Common Issues

1. **Network policies not enforcing**: Verify your CNI plugin supports network policies
2. **RBAC permissions denied**: Check access entry configuration and role bindings
3. **Resource quota exceeded**: Adjust quota limits or optimize resource requests
4. **Pod scheduling failures**: Verify node capacity and resource availability

### Debug Commands

```bash
# Check EKS cluster status
aws eks describe-cluster --name ${CLUSTER_NAME}

# Verify access entries
aws eks list-access-entries --cluster-name ${CLUSTER_NAME}

# Check network policy support
kubectl get networkpolicies --all-namespaces

# View resource quota details
kubectl describe quota --all-namespaces
```

## Cost Optimization

### Resource Recommendations

- Adjust resource quotas based on actual tenant needs
- Use node affinity to optimize pod placement
- Consider using spot instances for non-critical workloads
- Monitor resource utilization and adjust limits accordingly

### Estimated Costs

- EKS cluster: ~$0.10/hour
- Worker nodes: ~$0.05-0.20/hour per node (depending on instance type)
- Network data transfer: Variable based on usage
- IAM operations: Minimal charges

## Advanced Configuration

### Adding Additional Tenants

To add more tenants, modify the infrastructure code to include:

1. Additional namespace definitions
2. Extended IAM role creation
3. Additional RBAC configurations
4. Extended network policy rules
5. Additional resource quota definitions

### Enhanced Security Features

Consider implementing:

1. **Pod Security Standards**: Enforce security policies at pod level
2. **OPA Gatekeeper**: Policy-based governance and compliance
3. **Falco**: Runtime security monitoring
4. **External Secrets Operator**: Secure secret management
5. **Istio Service Mesh**: Advanced traffic management and security

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check AWS EKS documentation for service-specific issues
3. Review Kubernetes documentation for RBAC and network policy issues
4. Consult tool-specific documentation (CloudFormation, CDK, Terraform)

## References

- [AWS EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [AWS EKS Security Best Practices](https://docs.aws.amazon.com/eks/latest/best-practices/security.html)
- [Kubernetes RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)