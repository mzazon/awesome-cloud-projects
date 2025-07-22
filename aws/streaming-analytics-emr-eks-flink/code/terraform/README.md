# Real-time Streaming Analytics with EMR on EKS and Apache Flink

This Terraform configuration deploys a complete real-time streaming analytics platform using Amazon EMR on EKS with Apache Flink for financial services use cases.

## Architecture Overview

The infrastructure includes:

- **EKS Cluster**: Kubernetes platform for running Flink applications
- **EMR on EKS**: Virtual cluster for managed Flink job execution
- **VPC**: Secure networking with public/private subnets
- **Kinesis Data Streams**: Real-time data ingestion (trading events, market data)
- **S3 Storage**: Checkpoints, high-availability, and results storage
- **Flink Operator**: Kubernetes operator for Flink lifecycle management
- **Monitoring Stack**: Prometheus and Grafana for observability
- **IAM Roles**: Secure access with IRSA (IAM Roles for Service Accounts)

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** v2 installed and configured
2. **Terraform** >= 1.0 installed
3. **kubectl** installed for Kubernetes management
4. **Helm** installed for package management
5. Appropriate AWS permissions for creating:
   - EKS clusters and node groups
   - EMR virtual clusters
   - VPC and networking resources
   - S3 buckets
   - Kinesis streams
   - IAM roles and policies

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository and navigate to the Terraform directory
cd aws/real-time-streaming-analytics-emr-eks-flink/code/terraform/

# Copy the example variables file and customize
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure (takes 15-20 minutes)
terraform apply

# Save important outputs
terraform output > deployment-outputs.txt
```

### 3. Configure kubectl

```bash
# Configure kubectl to access the EKS cluster
aws eks update-kubeconfig --region <your-region> --name <cluster-name>

# Verify cluster access
kubectl get nodes
```

### 4. Verify Deployment

```bash
# Check Flink operator status
kubectl get pods -n emr-flink

# Check Flink deployments
kubectl get flinkdeployments -n emr-flink

# Check data generator (if enabled)
kubectl logs -n emr-flink deployment/trading-data-generator --tail=20
```

## Configuration Options

### Essential Variables

```hcl
# terraform.tfvars
aws_region      = "us-west-2"
cluster_name    = "emr-flink-analytics"
environment     = "production"
emr_namespace   = "emr-flink"

# Node group sizing
node_group_instance_types = ["m5.xlarge", "m5.2xlarge"]
node_group_desired_size   = 4

# Kinesis stream configuration
trading_stream_shard_count = 4
market_stream_shard_count  = 2
```

### Feature Flags

```hcl
enable_monitoring     = true   # Deploy Prometheus/Grafana
enable_data_generator = true   # Deploy test data generator
single_nat_gateway    = true   # Cost optimization for dev/test
```

### Advanced Configuration

```hcl
# Flink versions
flink_operator_version = "1.7.0"
flink_image_tag       = "1.17.1-emr-7.0.0"

# Storage lifecycle
s3_lifecycle_ia_days     = 30
s3_lifecycle_glacier_days = 90

# Monitoring
cloudwatch_log_retention_days = 7
```

## Accessing Services

### Flink Web UI

```bash
# Port forward to access Flink dashboard
kubectl port-forward -n emr-flink service/fraud-detection-rest 8081:8081

# Open browser to http://localhost:8081
```

### Grafana Dashboard (if monitoring enabled)

```bash
# Get Grafana admin password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode

# Port forward to Grafana
kubectl port-forward -n monitoring service/prometheus-grafana 3000:80

# Open browser to http://localhost:3000 (admin/password from above)
```

### Monitoring and Logs

```bash
# View Flink job logs
kubectl logs -n emr-flink <flink-pod-name>

# View CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix "/aws/emr-containers"

# Monitor Kinesis streams
aws kinesis describe-stream --stream-name <stream-name>
```

## Scaling and Performance

### Manual Scaling

```bash
# Scale Flink applications
kubectl patch flinkdeployment fraud-detection -n emr-flink \
  --type='merge' -p='{"spec":{"taskManager":{"replicas":5}}}'

# Scale node group
aws eks update-nodegroup-config \
  --cluster-name <cluster-name> \
  --nodegroup-name emr-flink-workers \
  --scaling-config minSize=3,maxSize=15,desiredSize=6
```

### Auto-scaling Configuration

The deployment includes:
- **Cluster Autoscaler**: Automatically scales EKS nodes based on demand
- **Horizontal Pod Autoscaler**: Scales Flink task managers based on CPU/memory
- **Kinesis Auto-scaling**: Automatic shard scaling based on throughput

## Cost Optimization

### Development/Testing

```hcl
# terraform.tfvars for cost optimization
single_nat_gateway         = true
node_group_instance_types  = ["t3.medium", "t3.large"]
node_group_desired_size    = 2
enable_monitoring         = false
trading_stream_shard_count = 1
market_stream_shard_count  = 1
```

### Production

```hcl
# terraform.tfvars for production
single_nat_gateway         = false  # Multi-AZ redundancy
node_group_instance_types  = ["m5.xlarge", "m5.2xlarge", "c5.xlarge"]
node_group_desired_size    = 6
enable_monitoring         = true
trading_stream_shard_count = 8
market_stream_shard_count  = 4
```

## Troubleshooting

### Common Issues

1. **Flink Jobs Not Starting**
   ```bash
   # Check operator logs
   kubectl logs -n emr-flink deployment/flink-kubernetes-operator
   
   # Check service account annotations
   kubectl describe sa emr-containers-sa-flink-operator -n emr-flink
   ```

2. **Data Not Flowing**
   ```bash
   # Check Kinesis stream status
   aws kinesis describe-stream --stream-name <stream-name>
   
   # Check data generator
   kubectl logs -n emr-flink deployment/trading-data-generator
   ```

3. **Permission Issues**
   ```bash
   # Verify IAM role trust relationship
   aws iam get-role --role-name EMRFlinkJobExecutionRole-<suffix>
   
   # Check OIDC provider
   aws eks describe-cluster --name <cluster-name> --query "cluster.identity.oidc"
   ```

### Resource Limits

Monitor resource usage:
```bash
# Pod resource usage
kubectl top pods -n emr-flink

# Node resource usage
kubectl top nodes

# Flink metrics
curl http://localhost:8081/jobs/<job-id>/metrics
```

## Security Considerations

### Network Security

- Private subnets for EKS nodes
- Security groups with minimal required access
- VPC Flow Logs for network monitoring
- NAT Gateway for outbound internet access

### Data Security

- Kinesis streams encrypted with AWS KMS
- S3 bucket encryption at rest
- In-transit encryption for all communications
- Network policies for pod-to-pod communication

### Access Control

- RBAC for Kubernetes access
- IAM roles with least privilege principle
- Service accounts with specific permissions
- EMR virtual cluster isolation

## Maintenance

### Regular Tasks

```bash
# Update cluster
eksctl upgrade cluster --name <cluster-name>

# Update Flink operator
helm upgrade flink-kubernetes-operator <chart> -n emr-flink

# Rotate secrets
kubectl delete secret <secret-name> -n emr-flink
```

### Backup Strategy

- S3 cross-region replication for checkpoints
- EKS cluster configuration backup
- Regular state snapshots using Flink savepoints

## Cleanup

### Destroy Infrastructure

```bash
# Delete Flink applications first
kubectl delete flinkdeployment --all -n emr-flink

# Wait for cleanup, then destroy infrastructure
terraform destroy

# Confirm all resources are deleted
aws emr-containers list-virtual-clusters
aws s3 ls | grep flink-analytics
```

### Selective Cleanup

```bash
# Remove monitoring only
terraform apply -var="enable_monitoring=false"

# Remove data generator only
terraform apply -var="enable_data_generator=false"
```

## Support and Resources

- [Apache Flink Documentation](https://flink.apache.org/docs/)
- [EMR on EKS User Guide](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/)
- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

To contribute improvements:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with detailed description

## Estimated Costs

Monthly cost breakdown (us-west-2):

| Component | Cost |
|-----------|------|
| EKS Control Plane | ~$73 |
| EC2 Instances (4x m5.xlarge) | ~$280 |
| NAT Gateway | ~$45 |
| Kinesis Streams (6 shards) | ~$50 |
| S3 Storage | ~$10-30 |
| CloudWatch | ~$10-20 |
| **Total** | **~$468-498/month** |

*Costs vary by usage patterns, region, and AWS pricing changes.*