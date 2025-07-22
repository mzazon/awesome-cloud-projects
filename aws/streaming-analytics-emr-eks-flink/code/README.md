# Infrastructure as Code for Analyzing Streaming Data with EMR on EKS and Flink

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Analyzing Streaming Data with EMR on EKS and Flink".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys a complete real-time streaming analytics platform featuring:

- Amazon EKS cluster with EMR-optimized node groups
- EMR on EKS virtual cluster for managed Flink job execution
- Apache Flink Kubernetes operator for job lifecycle management
- Kinesis Data Streams for real-time data ingestion
- S3 bucket with lifecycle policies for checkpoints and results
- IAM roles with OIDC integration for secure workload identity
- Monitoring stack with Prometheus and Grafana
- Sample Flink applications for fraud detection and risk analytics

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl, eksctl, and Helm installed locally
- Docker knowledge for custom image building
- Basic understanding of Apache Flink and stream processing concepts
- Terraform (if using Terraform deployment)
- Node.js 16+ and npm (if using CDK TypeScript)
- Python 3.8+ and pip (if using CDK Python)
- Appropriate AWS permissions for:
  - EKS cluster creation and management
  - EMR on EKS virtual cluster creation
  - IAM role creation and management
  - S3 bucket operations
  - Kinesis Data Streams operations
  - CloudWatch logs and metrics

## Estimated Costs

- **EKS Cluster**: ~$0.10/hour for control plane + EC2 costs for worker nodes
- **EMR on EKS**: ~$0.11/hour per vCPU for EMR charges
- **EC2 Instances**: ~$0.192/hour per m5.xlarge instance (4 instances typical)
- **Kinesis Data Streams**: ~$0.015/hour per shard (6 shards total)
- **S3 Storage**: Varies based on checkpoint and result data volume
- **Total Estimated Cost**: $150-300 for a 4-hour workshop

> **Warning**: Monitor costs and clean up resources when not needed to avoid unexpected charges.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the complete infrastructure
aws cloudformation create-stack \
    --stack-name flink-streaming-analytics \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=emr-flink-analytics \
                 ParameterKey=NodeInstanceType,ParameterValue=m5.xlarge \
    --capabilities CAPABILITY_IAM

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name flink-streaming-analytics

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name flink-streaming-analytics \
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
cdk deploy --all

# View stack outputs
cdk list
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy --all

# View stack outputs
cdk list
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete infrastructure
./scripts/deploy.sh

# Follow the on-screen instructions for post-deployment setup
```

## Post-Deployment Setup

After deploying the infrastructure, complete these steps:

### 1. Configure kubectl Access

```bash
# Update kubeconfig for EKS access
aws eks update-kubeconfig --region us-east-1 --name emr-flink-analytics

# Verify cluster access
kubectl get nodes
```

### 2. Install Flink Kubernetes Operator

```bash
# Add Flink operator Helm repository
helm repo add flink-operator-repo \
    https://downloads.apache.org/flink/flink-kubernetes-operator-1.7.0/
helm repo update

# Install the operator
helm install flink-kubernetes-operator \
    flink-operator-repo/flink-kubernetes-operator \
    --namespace emr-flink \
    --set image.repository=public.ecr.aws/emr-on-eks/flink/flink-kubernetes-operator \
    --set image.tag=1.7.0-emr-7.0.0
```

### 3. Deploy Sample Flink Applications

```bash
# Apply fraud detection job
kubectl apply -f examples/fraud-detection-job.yaml

# Apply risk analytics job
kubectl apply -f examples/risk-analytics-job.yaml

# Check job status
kubectl get flinkdeployments -n emr-flink
```

### 4. Access Monitoring Dashboards

```bash
# Port forward to Flink Web UI
kubectl port-forward -n emr-flink service/fraud-detection-rest 8081:8081 &

# Port forward to Grafana
kubectl port-forward -n monitoring service/prometheus-grafana 3000:80 &

echo "Flink UI: http://localhost:8081"
echo "Grafana: http://localhost:3000 (admin/prom-operator)"
```

## Configuration Options

### Key Parameters

| Parameter | Description | Default | CloudFormation | CDK | Terraform |
|-----------|-------------|---------|----------------|-----|-----------|
| ClusterName | EKS cluster name | emr-flink-analytics | ✅ | ✅ | ✅ |
| NodeInstanceType | EC2 instance type for worker nodes | m5.xlarge | ✅ | ✅ | ✅ |
| NodeGroupMinSize | Minimum nodes in group | 2 | ✅ | ✅ | ✅ |
| NodeGroupMaxSize | Maximum nodes in group | 10 | ✅ | ✅ | ✅ |
| NodeGroupDesiredSize | Desired nodes in group | 4 | ✅ | ✅ | ✅ |
| KinesisShardCount | Number of Kinesis shards | 4 | ✅ | ✅ | ✅ |
| EnableMonitoring | Install Prometheus/Grafana | true | ✅ | ✅ | ✅ |

### Environment Variables

```bash
# Core configuration
export AWS_REGION="us-east-1"
export CLUSTER_NAME="emr-flink-analytics"
export EMR_NAMESPACE="emr-flink"

# Resource naming
export BUCKET_NAME="emr-flink-analytics-${RANDOM_SUFFIX}"
export STREAM_NAME_TRADING="trading-events-${RANDOM_SUFFIX}"
export STREAM_NAME_MARKET="market-data-${RANDOM_SUFFIX}"
```

## Validation & Testing

### 1. Verify Infrastructure Deployment

```bash
# Check EKS cluster status
aws eks describe-cluster --name emr-flink-analytics \
    --query 'cluster.status'

# Check EMR virtual cluster
aws emr-containers list-virtual-clusters \
    --query 'virtualClusters[?name==`flink-analytics-cluster`]'

# Verify Kinesis streams
aws kinesis list-streams --query 'StreamNames'
```

### 2. Test Flink Job Deployment

```bash
# Check Flink deployments
kubectl get flinkdeployments -n emr-flink

# Monitor job manager logs
kubectl logs -n emr-flink \
    $(kubectl get pods -n emr-flink \
    -l app=fraud-detection,component=jobmanager -o name) \
    --tail=50
```

### 3. Generate Test Data

```bash
# Deploy data generator
kubectl apply -f examples/data-generator.yaml

# Scale for increased load testing
kubectl scale deployment trading-data-generator \
    -n emr-flink --replicas=3

# Monitor Kinesis metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Kinesis \
    --metric-name IncomingRecords \
    --dimensions Name=StreamName,Value=trading-events-* \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Troubleshooting

### Common Issues

1. **EKS Cluster Creation Fails**
   ```bash
   # Check CloudFormation events for detailed error messages
   aws cloudformation describe-stack-events \
       --stack-name flink-streaming-analytics
   ```

2. **Flink Jobs Not Starting**
   ```bash
   # Check operator logs
   kubectl logs -n emr-flink \
       $(kubectl get pods -n emr-flink \
       -l app.kubernetes.io/name=flink-kubernetes-operator -o name)
   
   # Verify service account annotations
   kubectl describe serviceaccount emr-containers-sa-flink-operator \
       -n emr-flink
   ```

3. **Kinesis Access Issues**
   ```bash
   # Verify IAM role permissions
   aws iam get-role --role-name EMRFlinkJobExecutionRole
   
   # Check attached policies
   aws iam list-attached-role-policies \
       --role-name EMRFlinkJobExecutionRole
   ```

### Debug Commands

```bash
# Check all pods in EMR namespace
kubectl get pods -n emr-flink -o wide

# Describe Flink deployment for detailed status
kubectl describe flinkdeployment fraud-detection -n emr-flink

# Check S3 bucket contents
aws s3 ls s3://emr-flink-analytics-* --recursive

# Monitor cluster autoscaler logs
kubectl logs -n kube-system \
    $(kubectl get pods -n kube-system \
    -l app=cluster-autoscaler -o name)
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name flink-streaming-analytics

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name flink-streaming-analytics
```

### Using CDK (AWS)

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy all stacks
cdk destroy --all

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (if needed)

```bash
# Remove Helm releases
helm uninstall flink-kubernetes-operator -n emr-flink
helm uninstall prometheus -n monitoring

# Delete persistent volumes
kubectl delete pv --all

# Empty S3 bucket before deletion
aws s3 rm s3://emr-flink-analytics-* --recursive
```

## Monitoring and Observability

### Key Metrics to Monitor

1. **Flink Job Metrics**
   - Job uptime and restart count
   - Checkpointing duration and success rate
   - Records processed per second
   - Latency percentiles

2. **Kubernetes Metrics**
   - Node CPU and memory utilization
   - Pod restart counts
   - Persistent volume usage

3. **AWS Service Metrics**
   - Kinesis incoming records and throttling
   - S3 request metrics and errors
   - EKS control plane health

### Grafana Dashboards

Pre-configured dashboards are available for:
- Flink job performance and health
- Kubernetes cluster overview
- AWS service metrics
- Cost tracking and optimization

### Alerts and Notifications

Recommended alert rules:
- Flink job failure or restart
- High checkpoint duration
- Kubernetes node resource exhaustion
- Kinesis throttling events

## Security Considerations

### IAM Best Practices

- Uses least privilege principle for all IAM roles
- Leverages OIDC federation for secure workload identity
- Separates service roles from job execution roles
- Implements proper trust relationships

### Network Security

- EKS cluster uses private networking for worker nodes
- Security groups restrict access to necessary ports only
- VPC endpoints used for AWS service communication
- TLS encryption enabled for all data in transit

### Data Protection

- S3 bucket encryption enabled by default
- Kinesis data encryption at rest and in transit
- Flink checkpoints encrypted in S3
- CloudWatch logs encrypted

## Performance Optimization

### Scaling Recommendations

1. **Horizontal Pod Autoscaler**: Configure based on CPU/memory usage
2. **Cluster Autoscaler**: Automatically scale worker nodes
3. **Flink Parallelism**: Match to Kinesis shard count
4. **Task Manager Resources**: Optimize based on workload characteristics

### Cost Optimization

1. **Spot Instances**: Use for non-critical task managers
2. **Reserved Instances**: For predictable workloads
3. **S3 Lifecycle Policies**: Automatically tier checkpoint data
4. **Right-sizing**: Monitor and adjust instance types

## Advanced Configuration

### Custom Flink Applications

To deploy custom Flink applications:

1. Build custom Docker image with your application JAR
2. Push to Amazon ECR
3. Update FlinkDeployment resource with new image
4. Configure application-specific parameters

### Multi-Region Deployment

For high availability across regions:

1. Deploy infrastructure in multiple AWS regions
2. Configure cross-region replication for S3 checkpoints
3. Set up Global Load Balancer for traffic distribution
4. Implement disaster recovery procedures

## Support and Resources

### Documentation Links

- [Amazon EMR on EKS User Guide](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/)
- [Apache Flink Documentation](https://flink.apache.org/docs/)
- [Flink Kubernetes Operator](https://flink.apache.org/docs/stable/docs/deployment/resource-providers/native_kubernetes/)
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)

### Community Resources

- [Apache Flink Community](https://flink.apache.org/community.html)
- [AWS Containers Blog](https://aws.amazon.com/blogs/containers/)
- [Kubernetes Community](https://kubernetes.io/community/)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS CloudFormation/EKS documentation
3. Consult the original recipe documentation
4. Reach out to AWS Support if needed

---

**Note**: This infrastructure code deploys production-ready resources that incur AWS charges. Always monitor your costs and clean up resources when they're no longer needed.