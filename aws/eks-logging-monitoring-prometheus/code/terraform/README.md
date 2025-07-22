# EKS Cluster Logging and Monitoring with CloudWatch and Prometheus

This Terraform configuration creates a comprehensive observability stack for Amazon EKS that combines AWS CloudWatch for centralized logging and Container Insights for infrastructure monitoring with Prometheus for application metrics collection.

## Architecture Overview

This solution deploys:
- **Amazon EKS Cluster** with comprehensive control plane logging
- **VPC with public and private subnets** for secure networking
- **EKS managed node group** with auto-scaling capabilities
- **CloudWatch Container Insights** for infrastructure monitoring
- **Fluent Bit** for log collection and forwarding
- **Amazon Managed Service for Prometheus** for metrics collection
- **CloudWatch dashboards and alarms** for visualization and alerting
- **Sample application** with Prometheus metrics (optional)

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0
- kubectl installed for cluster management
- Appropriate AWS permissions for EKS, CloudWatch, and Prometheus services

## Quick Start

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Review and customize variables** (optional):
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your desired values
   ```

3. **Plan the deployment**:
   ```bash
   terraform plan
   ```

4. **Apply the configuration**:
   ```bash
   terraform apply
   ```

5. **Configure kubectl**:
   ```bash
   aws eks update-kubeconfig --region <region> --name <cluster-name>
   ```

## Configuration Variables

### Required Variables

- `aws_region`: AWS region for resources (default: "us-west-2")
- `cluster_name`: Name of the EKS cluster (default: "eks-observability-cluster")

### Optional Variables

- `cluster_version`: Kubernetes version (default: "1.28")
- `environment`: Environment name (default: "dev")
- `enable_prometheus`: Enable Prometheus workspace (default: true)
- `enable_cloudwatch_alarms`: Enable CloudWatch alarms (default: true)
- `deploy_sample_app`: Deploy sample app with metrics (default: true)
- `sns_endpoint`: Email for SNS notifications (default: "")

### Node Group Configuration

```hcl
node_group_config = {
  instance_types = ["t3.medium"]
  scaling_config = {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }
  disk_size = 30
  ami_type  = "AL2_x86_64"
}
```

### Network Configuration

```hcl
vpc_cidr = "10.0.0.0/16"
private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnets  = ["10.0.3.0/24", "10.0.4.0/24"]
availability_zones = ["us-west-2a", "us-west-2b"]
```

## Features

### Control Plane Logging
- API server logs
- Audit logs
- Authenticator logs
- Controller manager logs
- Scheduler logs

### Container Insights
- Node-level metrics (CPU, memory, disk, network)
- Pod-level metrics and logs
- Container-level resource utilization
- Performance monitoring dashboards

### Prometheus Integration
- Automatic service discovery
- Kubernetes API server metrics
- Node and pod metrics via cAdvisor
- Custom application metrics
- Managed Prometheus workspace

### CloudWatch Features
- Centralized log aggregation
- Real-time dashboards
- Automated alerting
- Log Insights queries
- Metric-based alarms

## Monitoring Components

### Fluent Bit DaemonSet
- Collects container logs from all nodes
- Forwards logs to CloudWatch Logs
- Kubernetes metadata enrichment
- Automatic log parsing

### CloudWatch Agent
- Collects system and container metrics
- Sends metrics to Container Insights
- Node and pod performance monitoring
- Resource utilization tracking

### Prometheus Scraper
- Managed scraper configuration
- Automatic target discovery
- Metrics collection from Kubernetes APIs
- Integration with Amazon Managed Service for Prometheus

## Outputs

After successful deployment, Terraform provides:

- `cluster_name`: EKS cluster name
- `cluster_endpoint`: Kubernetes API endpoint
- `kubectl_config_command`: Command to configure kubectl
- `cloudwatch_dashboard_url`: CloudWatch dashboard URL
- `prometheus_workspace_id`: Prometheus workspace ID
- `monitoring_setup_complete`: Status of monitoring components

## Cost Estimation

Approximate monthly costs (varies by usage):

- **EKS Control Plane**: ~$73/month
- **EC2 Instances**: ~$30-60/month (t3.medium)
- **CloudWatch Logs**: ~$10-50/month (depends on volume)
- **Container Insights**: ~$10-30/month
- **Prometheus**: ~$20-40/month
- **Total**: ~$143-253/month

## Security Considerations

- All IAM roles follow least privilege principle
- IRSA (IAM Roles for Service Accounts) enabled
- VPC with private subnets for worker nodes
- Security groups restrict access appropriately
- Encryption at rest and in transit

## Troubleshooting

### Common Issues

1. **EKS cluster creation fails**:
   - Check IAM permissions
   - Verify VPC and subnet configuration
   - Ensure availability zones are correct

2. **Monitoring pods not starting**:
   - Check node group status
   - Verify IRSA configuration
   - Review CloudWatch permissions

3. **Prometheus metrics not appearing**:
   - Check scraper configuration
   - Verify network connectivity
   - Review Prometheus workspace status

### Verification Commands

```bash
# Check cluster status
kubectl get nodes

# Verify monitoring pods
kubectl get pods -n amazon-cloudwatch

# Check Fluent Bit logs
kubectl logs -n amazon-cloudwatch -l name=fluent-bit

# Check CloudWatch Agent logs
kubectl logs -n amazon-cloudwatch -l name=cloudwatch-agent
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all resources including logs and metrics data. Ensure you have backups if needed.

## Advanced Configuration

### Custom Fluent Bit Configuration

Modify the `fluent_bit_config` variable to customize log collection:

```hcl
fluent_bit_config = {
  image_tag      = "2.31.0"
  log_level      = "debug"
  mem_buf_limit  = "100MB"
  read_from_head = true
}
```

### CloudWatch Alarms

Configure custom thresholds:

```hcl
cpu_utilization_threshold    = 85
memory_utilization_threshold = 90
failed_pods_threshold       = 3
```

### SNS Notifications

Enable email notifications:

```hcl
enable_sns_alerts = true
sns_endpoint      = "your-email@example.com"
```

## Support

For issues and questions:

1. Check the [EKS documentation](https://docs.aws.amazon.com/eks/)
2. Review [CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
3. Consult [Amazon Managed Service for Prometheus](https://docs.aws.amazon.com/prometheus/)
4. Review Terraform AWS provider documentation

## Contributing

When making changes:

1. Update variable descriptions
2. Test with `terraform plan`
3. Update documentation
4. Validate with different configurations
5. Check cost implications

## License

This code is provided as-is for educational and demonstration purposes. Use at your own risk in production environments.