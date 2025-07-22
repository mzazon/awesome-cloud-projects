# Terraform Infrastructure for EKS Hybrid Kubernetes Monitoring

This Terraform configuration deploys a complete hybrid Kubernetes monitoring solution using Amazon EKS with Hybrid Nodes support and CloudWatch observability.

## Architecture Overview

This infrastructure creates:

- **EKS Cluster** with Hybrid Nodes support for on-premises integration
- **VPC and Networking** with public/private subnets and NAT gateways
- **Fargate Profile** for serverless container execution
- **CloudWatch Observability** with Container Insights and custom metrics
- **Monitoring Infrastructure** including dashboards and alarms
- **Sample Applications** for testing and validation
- **Security Configuration** with IAM roles and encryption

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) v2 configured with appropriate permissions
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.28
- AWS account with permissions for EKS, VPC, IAM, CloudWatch, and related services

### Required AWS Permissions

Your AWS credentials must have permissions for:

- EKS cluster and addon management
- VPC, subnet, and security group management
- IAM role and policy management
- CloudWatch logs, metrics, and dashboard management
- KMS key management (if encryption is enabled)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   git clone <repository-url>
   cd aws/implementing-hybrid-kubernetes-monitoring-with-amazon-eks-hybrid-nodes-and-cloudwatch/code/terraform/
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific configuration
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan Deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

6. **Configure kubectl**:
   ```bash
   aws eks update-kubeconfig --region <your-region> --name <cluster-name>
   ```

## Configuration

### Essential Variables

Edit `terraform.tfvars` to customize these key settings:

```hcl
# Core Configuration
aws_region = "us-west-2"
environment = "dev"
project_name = "hybrid-monitoring"

# Hybrid Node Networks (customize for your on-premises environment)
remote_node_networks = ["10.100.0.0/16"]
remote_pod_networks = ["10.101.0.0/16"]

# VPC Configuration
vpc_cidr = "10.0.0.0/16"
public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# Monitoring Configuration
container_insights_enabled = true
cloudwatch_dashboard_enabled = true
cloudwatch_alarms_enabled = true
```

### Network Configuration for Hybrid Nodes

For hybrid nodes to work properly, ensure:

1. **Network Connectivity**: Your on-premises environment must have network connectivity to AWS via:
   - AWS Direct Connect (recommended for production)
   - Site-to-Site VPN
   - AWS PrivateLink (for specific use cases)

2. **CIDR Planning**: Configure non-overlapping CIDR blocks:
   - `vpc_cidr`: AWS VPC network (default: 10.0.0.0/16)
   - `remote_node_networks`: On-premises node networks (default: 10.100.0.0/16)
   - `remote_pod_networks`: On-premises pod networks (default: 10.101.0.0/16)

3. **Security Groups**: The EKS cluster security group must allow communication from your hybrid node networks.

## Deployment Options

### Standard Deployment

Default configuration suitable for development and testing:

```bash
terraform apply
```

### Production Deployment

For production environments, consider these modifications in `terraform.tfvars`:

```hcl
# High availability
single_nat_gateway = false
cluster_log_retention_days = 30

# Enhanced security
cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]  # Restrict to your networks
cluster_encryption_enabled = true

# Monitoring
sns_topic_arn = "arn:aws:sns:region:account:eks-alerts"
high_cpu_threshold = 70
high_memory_threshold = 70
```

### Cost-Optimized Deployment

For cost optimization:

```hcl
# Single NAT gateway
single_nat_gateway = true

# Shorter log retention
cluster_log_retention_days = 7

# Disable optional features
application_signals_enabled = false
install_efs_csi_driver = false
```

## Monitoring and Observability

### CloudWatch Dashboards

Access the automatically created dashboard:
- **URL Pattern**: `https://<region>.console.aws.amazon.com/cloudwatch/home?region=<region>#dashboards:name=EKS-Hybrid-Monitoring-<cluster-name>`
- **Widgets Include**:
  - Hybrid cluster capacity metrics
  - Pod resource utilization
  - Node and pod status distribution
  - Application logs
  - Per-namespace pod counts

### CloudWatch Alarms

Configured alarms monitor:
- High CPU utilization (default: 80%)
- High memory utilization (default: 80%)
- Low hybrid node count
- Failed pods
- Low cluster node count

### Custom Metrics

The infrastructure includes a custom metrics collection system that publishes:
- `HybridNodeCount`: Number of hybrid nodes
- `FargatePodCount`: Number of pods running on Fargate
- `TotalPodCount`: Total pods in the cluster
- `CloudAppsPodCount`: Pods in the cloud-apps namespace

## Hybrid Node Integration

### Prerequisites for Hybrid Nodes

1. **On-Premises Infrastructure**:
   - Linux servers (Ubuntu 20.04+ or Amazon Linux 2)
   - Container runtime (Docker or containerd)
   - Network connectivity to AWS
   - IAM permissions for node registration

2. **Network Requirements**:
   - Outbound HTTPS (443) access to AWS APIs
   - Access to EKS cluster endpoint
   - DNS resolution for AWS services

### Connecting Hybrid Nodes

After deploying this infrastructure, follow these steps to connect on-premises nodes:

1. **Install the Hybrid Node Agent** on your on-premises servers
2. **Configure IAM roles** for node authentication
3. **Register nodes** with the EKS cluster
4. **Verify connectivity** using the monitoring dashboards

Detailed instructions are available in the [Amazon EKS Hybrid Nodes documentation](https://docs.aws.amazon.com/eks/latest/userguide/hybrid-nodes.html).

## Validation and Testing

### Cluster Validation

```bash
# Verify cluster status
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A

# Check Fargate profile
aws eks describe-fargate-profile --cluster-name <cluster-name> --fargate-profile-name cloud-workloads

# Verify addons
aws eks list-addons --cluster-name <cluster-name>
```

### Monitoring Validation

```bash
# Check CloudWatch agent
kubectl get pods -n amazon-cloudwatch

# View custom metrics
aws cloudwatch list-metrics --namespace EKS/HybridMonitoring

# Test sample application
kubectl get pods -n cloud-apps
kubectl port-forward -n cloud-apps service/cloud-sample-service 8080:80
curl http://localhost:8080
```

### Log Validation

```bash
# View cluster logs
aws logs describe-log-groups --log-group-name-prefix /aws/eks/<cluster-name>

# Query application logs
aws logs start-query \
  --log-group-name "/aws/containerinsights/<cluster-name>/application" \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, kubernetes.pod_name, log | limit 20'
```

## Troubleshooting

### Common Issues

1. **Addon Installation Failures**:
   ```bash
   # Check addon status
   aws eks describe-addon --cluster-name <cluster-name> --addon-name amazon-cloudwatch-observability
   
   # View addon logs
   kubectl logs -n amazon-cloudwatch deployment/cloudwatch-agent
   ```

2. **Fargate Pod Scheduling Issues**:
   ```bash
   # Verify Fargate profile
   kubectl describe pod <pod-name> -n cloud-apps
   
   # Check events
   kubectl get events -n cloud-apps --sort-by='.lastTimestamp'
   ```

3. **Network Connectivity**:
   ```bash
   # Test cluster endpoint access
   kubectl get svc
   
   # Verify security groups
   aws ec2 describe-security-groups --group-ids <cluster-security-group-id>
   ```

### Logs and Debugging

- **Cluster Logs**: Available in CloudWatch at `/aws/eks/<cluster-name>/cluster`
- **Container Logs**: Available in CloudWatch at `/aws/containerinsights/<cluster-name>/`
- **Terraform State**: Use `terraform show` and `terraform state list` for resource inspection

## Cost Management

### Cost Optimization Features

This configuration includes several cost optimization features:

- **Single NAT Gateway**: Reduces NAT Gateway costs (configurable)
- **Fargate Only**: No EC2 instances to manage or pay for when idle
- **Log Retention**: Configurable CloudWatch log retention periods
- **Resource Tagging**: Comprehensive tagging for cost allocation

### Estimated Costs

Monthly cost estimates (us-west-2, as of 2024):

- **EKS Cluster**: ~$73/month
- **Fargate vCPU/Memory**: Variable based on usage
- **NAT Gateway**: ~$32-45/month (single/multi-AZ)
- **CloudWatch**: ~$10-20/month for logs and metrics
- **VPC**: ~$0 (no additional charges)

**Total Estimated Range**: $115-138/month + Fargate compute costs

Use the [AWS Pricing Calculator](https://calculator.aws/) for detailed estimates based on your usage patterns.

## Security Considerations

### Implemented Security Features

- **IAM Roles**: Least-privilege IAM roles for all components
- **Encryption**: Optional KMS encryption for cluster secrets
- **Network Security**: Private subnets for Fargate workloads
- **Access Control**: EKS access configuration with RBAC
- **Monitoring**: Comprehensive logging and monitoring

### Security Recommendations

1. **Network Access**:
   - Restrict `cluster_endpoint_public_access_cidrs` to your IP ranges
   - Use AWS PrivateLink for enhanced security
   - Implement network monitoring and anomaly detection

2. **IAM Security**:
   - Review and audit IAM roles regularly
   - Enable CloudTrail for API logging
   - Use IAM Access Analyzer for policy validation

3. **Cluster Security**:
   - Enable all control plane logging types
   - Implement Pod Security Standards
   - Regular security scanning with Amazon Inspector

## Advanced Configuration

### Adding Managed Node Groups

To add traditional EC2-based node groups alongside Fargate:

```hcl
# Add to terraform.tfvars
variable "enable_managed_node_groups" {
  description = "Enable managed node groups"
  type        = bool
  default     = false
}

# Add managed node group configuration in main.tf
resource "aws_eks_node_group" "managed" {
  count = var.enable_managed_node_groups ? 1 : 0
  # ... node group configuration
}
```

### Custom Networking

For complex networking requirements:

```hcl
# Custom subnet configuration
variable "custom_subnets" {
  description = "Use existing subnets instead of creating new ones"
  type = object({
    public_subnet_ids  = list(string)
    private_subnet_ids = list(string)
  })
  default = null
}
```

### Multi-Region Deployment

For multi-region hybrid monitoring:

1. Deploy this configuration in multiple regions
2. Configure cross-region VPC peering or Transit Gateway
3. Centralize monitoring in a primary region
4. Use AWS Config for cross-region compliance monitoring

## Cleanup

To destroy all resources:

```bash
# Delete sample applications first (if deployed)
kubectl delete namespace cloud-apps --ignore-not-found=true

# Wait for namespace deletion
kubectl wait --for=delete namespace cloud-apps --timeout=300s

# Destroy infrastructure
terraform destroy
```

**Warning**: This will delete all resources including data. Ensure you have backups of any important data before destroying.

## Support and Contributing

### Getting Help

1. **AWS Documentation**: [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
2. **Terraform Documentation**: [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
3. **Community Support**: [AWS re:Post](https://repost.aws/) for AWS-specific questions

### Known Limitations

- Hybrid nodes require manual setup on on-premises infrastructure
- Cross-region hybrid node connectivity requires additional network configuration
- Some monitoring features may require EKS cluster version 1.28+

### Version Compatibility

- **Terraform**: >= 1.0
- **AWS Provider**: >= 5.74.0
- **Kubernetes Provider**: >= 2.20
- **EKS**: >= 1.28 (for hybrid nodes support)

---

For detailed implementation guidance, refer to the [original recipe documentation](../README.md).