# Infrastructure as Code for EKS Workload Auto Scaling

This directory contains Infrastructure as Code (IaC) implementations for the recipe "EKS Workload Auto Scaling".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This comprehensive EKS autoscaling solution includes:

- **EKS Cluster** with OIDC identity provider
- **Multiple Node Groups** (general-purpose and compute-optimized)
- **Horizontal Pod Autoscaler (HPA)** for pod-level scaling
- **Cluster Autoscaler** for node-level scaling
- **KEDA** for custom metrics scaling
- **Metrics Server** for resource metrics collection
- **Prometheus & Grafana** for monitoring and visualization
- **Demo Applications** for testing autoscaling functionality
- **Pod Disruption Budgets** for high availability
- **VPA** (optional) for vertical pod autoscaling

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl client installed and configured
- eksctl CLI tool installed (version 0.147.0 or later)
- Helm v3 installed (version 3.10.0 or later)
- Docker installed (for building custom images if needed)
- jq installed for JSON processing
- Appropriate AWS IAM permissions for:
  - Amazon EKS (full access)
  - Amazon EC2 (full access)
  - Amazon IAM (full access)
  - Amazon CloudWatch (full access)
  - AWS Auto Scaling (full access)
  - Amazon ECR (read access)
- Estimated cost: $150-300/month for cluster resources during operation

## Quick Start

### Using CloudFormation

```bash
# Deploy the EKS cluster and supporting infrastructure
aws cloudformation create-stack \
    --stack-name eks-autoscaling-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=eks-autoscaling-demo \
                 ParameterKey=NodeGroupName,ParameterValue=autoscaling-nodes \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-west-2

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name eks-autoscaling-stack \
    --region us-west-2

# Update kubeconfig
aws eks update-kubeconfig \
    --region us-west-2 \
    --name eks-autoscaling-demo

# Deploy Kubernetes resources
kubectl apply -f k8s-resources/
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy EksAutoscalingStack

# Update kubeconfig
aws eks update-kubeconfig \
    --region us-west-2 \
    --name $(cdk output EksAutoscalingStack.ClusterName)

# Deploy Kubernetes resources
kubectl apply -f ../k8s-resources/
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the infrastructure
cdk deploy EksAutoscalingStack

# Update kubeconfig
aws eks update-kubeconfig \
    --region us-west-2 \
    --name $(cdk output EksAutoscalingStack.ClusterName)

# Deploy Kubernetes resources
kubectl apply -f ../k8s-resources/
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

# Update kubeconfig
aws eks update-kubeconfig \
    --region us-west-2 \
    --name $(terraform output -raw cluster_name)

# Deploy Kubernetes resources
kubectl apply -f ../k8s-resources/
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# The script will:
# 1. Create EKS cluster with node groups
# 2. Install Metrics Server
# 3. Deploy Cluster Autoscaler
# 4. Install KEDA
# 5. Deploy sample applications with HPA
# 6. Set up monitoring stack
# 7. Configure load testing
```

## Post-Deployment Configuration

After infrastructure deployment, additional configuration is required:

### 1. Verify Cluster Status

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Verify Metrics Server
kubectl top nodes
kubectl top pods --all-namespaces
```

### 2. Configure Monitoring Access

```bash
# Get Grafana admin password
kubectl get secret --namespace monitoring grafana \
    -o jsonpath="{.data.admin-password}" | base64 --decode

# Port forward to access Grafana
kubectl port-forward --namespace monitoring svc/grafana 3000:80

# Access Grafana at http://localhost:3000
# Username: admin
# Password: (from previous command)
```

### 3. Test Autoscaling

```bash
# Generate load to test HPA
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh

# Inside the pod, run:
while true; do wget -q -O- http://cpu-demo-service.demo-apps.svc.cluster.local/; done

# In another terminal, watch scaling
kubectl get hpa -n demo-apps --watch
kubectl get pods -n demo-apps --watch
```

## Validation and Testing

### 1. Verify HPA Functionality

```bash
# Check HPA status
kubectl get hpa -n demo-apps

# Describe HPA for detailed information
kubectl describe hpa cpu-demo-hpa -n demo-apps

# Monitor scaling events
kubectl get events --sort-by=.metadata.creationTimestamp -n demo-apps
```

### 2. Test Cluster Autoscaler

```bash
# Create resource-intensive deployment
kubectl create deployment resource-test --image=nginx --replicas=50
kubectl patch deployment resource-test -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","resources":{"requests":{"cpu":"500m","memory":"1Gi"}}}]}}}}'

# Watch for new nodes being added
kubectl get nodes --watch
```

### 3. Verify KEDA Scaling

```bash
# Check KEDA scaling objects
kubectl get scaledobjects -n demo-apps

# Describe KEDA scaler
kubectl describe scaledobject custom-metrics-scaler -n demo-apps
```

### 4. Monitor Metrics

```bash
# Check Prometheus metrics
kubectl port-forward --namespace monitoring svc/prometheus-server 9090:80

# Access Prometheus at http://localhost:9090
# Query examples:
# - kube_deployment_status_replicas{namespace="demo-apps"}
# - cluster_autoscaler_nodes_count
# - keda_scaler_active
```

## Customization

### Environment Variables

Each implementation supports customization through variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `cluster_name` | `eks-autoscaling-demo` | Name of the EKS cluster |
| `node_group_name` | `autoscaling-nodes` | Name of the managed node group |
| `region` | `us-west-2` | AWS region for deployment |
| `min_size` | `1` | Minimum number of nodes |
| `max_size` | `10` | Maximum number of nodes |
| `desired_size` | `2` | Desired number of nodes |
| `instance_types` | `["m5.large", "m5.xlarge"]` | Instance types for node group |

### Scaling Configuration

#### HPA Configuration
```yaml
# Modify HPA target utilization
spec:
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # Change from 50 to 70
```

#### Cluster Autoscaler Configuration
```yaml
# Modify cluster autoscaler settings
--scale-down-delay-after-add=10m
--scale-down-unneeded-time=10m
--scale-down-utilization-threshold=0.5
```

#### KEDA Configuration
```yaml
# Modify KEDA scaling triggers
triggers:
- type: prometheus
  metadata:
    threshold: '50'  # Change from 30 to 50
    query: rate(http_requests_total[1m])
```

### Adding Custom Applications

1. Create application deployment with resource requests
2. Configure HPA for the application
3. Add Pod Disruption Budget
4. Configure monitoring and alerting

Example:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

## Troubleshooting

### Common Issues

1. **HPA not scaling**: Check if Metrics Server is running and resource requests are defined
2. **Cluster Autoscaler not adding nodes**: Verify IAM permissions and node group tags
3. **KEDA not scaling**: Check if ScaledObject is configured correctly and metrics are available
4. **Pods in pending state**: Check resource requests and node capacity

### Debugging Commands

```bash
# Check HPA status
kubectl describe hpa <hpa-name> -n <namespace>

# Check Cluster Autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler

# Check KEDA logs
kubectl logs -n keda-system -l app=keda-operator

# Check Metrics Server logs
kubectl logs -n kube-system -l k8s-app=metrics-server

# View node capacity and allocation
kubectl describe nodes
```

### Performance Optimization

1. **Right-size resource requests**: Set appropriate CPU and memory requests
2. **Configure node affinity**: Place workloads on appropriate node types
3. **Use Pod Disruption Budgets**: Ensure application availability during scaling
4. **Monitor scaling patterns**: Analyze metrics to optimize scaling policies
5. **Implement custom metrics**: Use business-relevant metrics for scaling decisions

## Testing Autoscaling

### 1. Check Initial State

```bash
# View nodes
kubectl get nodes

# Check HPA status
kubectl get hpa -n demo-apps

# View demo applications
kubectl get pods -n demo-apps
```

### 2. Test Horizontal Pod Autoscaling

```bash
# Generate CPU load
kubectl run load-generator --rm -i --tty --image=busybox --restart=Never -n demo-apps -- /bin/sh -c "while true; do wget -q -O- http://cpu-demo-service/; done"

# Watch HPA scaling in another terminal
kubectl get hpa -n demo-apps -w

# Monitor pod scaling
kubectl get pods -n demo-apps -w
```

### 3. Test Cluster Autoscaler

```bash
# Scale the node-scale-test deployment to trigger node scaling
kubectl scale deployment node-scale-test --replicas=10 -n demo-apps

# Watch nodes being added
kubectl get nodes -w

# Check cluster autoscaler logs
kubectl logs -n kube-system -l app=cluster-autoscaler
```

### 4. Monitor Resource Usage

```bash
# Check node resource usage
kubectl top nodes

# Check pod resource usage
kubectl top pods -n demo-apps

# View scaling events
kubectl get events --sort-by=.metadata.creationTimestamp -n demo-apps
```

## Monitoring and Observability

### Access Grafana Dashboard

```bash
# Port-forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80

# Access at http://localhost:3000
# Username: admin
# Password: (value from grafana_admin_password variable)
```

### Access Prometheus

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80

# Access at http://localhost:9090
```

### Key Metrics to Monitor

- **Cluster Autoscaler**: Node scaling events and decisions
- **HPA**: Pod scaling based on CPU/memory utilization
- **KEDA**: Custom metrics-based scaling
- **Node Utilization**: CPU, memory, and disk usage
- **Pod Resource Consumption**: Requests vs limits

## Troubleshooting

### Common Issues

1. **Cluster Autoscaler Not Scaling**
   ```bash
   # Check autoscaler logs
   kubectl logs -n kube-system -l app=cluster-autoscaler
   
   # Verify node group tags
   aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[*].Tags[?Key=='k8s.io/cluster-autoscaler/enabled']"
   ```

2. **HPA Not Scaling**
   ```bash
   # Check metrics server
   kubectl get pods -n kube-system -l k8s-app=metrics-server
   
   # Verify resource requests are set
   kubectl describe hpa -n demo-apps
   ```

3. **KEDA Not Working**
   ```bash
   # Check KEDA pods
   kubectl get pods -n keda-system
   
   # Verify ScaledObject configuration
   kubectl describe scaledobject -n demo-apps
   ```

### Useful Commands

```bash
# Cluster information
terraform output kubectl_config_command
terraform output cluster_autoscaler_logs_command
terraform output hpa_status_command

# Resource usage
terraform output top_nodes_command
terraform output top_pods_command

# Load testing
terraform output load_test_cpu_command
terraform output load_test_memory_command
```

## Cost Optimization

### Estimated Costs

- **EKS Cluster**: ~$73/month
- **Worker Nodes**: ~$30-150/month (depends on usage)
- **Load Balancer**: ~$16/month
- **Storage**: ~$10/month
- **Total**: ~$130-250/month

### Cost Optimization Tips

1. **Use Spot Instances** for non-critical workloads
2. **Configure appropriate scale-down delays** to prevent node churn
3. **Monitor and optimize resource requests/limits**
4. **Use cluster autoscaler expander policies** for cost-effective scaling
5. **Regular review of scaling patterns** and threshold adjustments

## Customization

### Adding Custom Applications

1. Create deployment with resource requests/limits
2. Add HPA configuration with appropriate metrics
3. Configure Pod Disruption Budgets
4. Add monitoring and alerting

### Modifying Scaling Behavior

1. **HPA Behavior**: Adjust stabilization windows and scaling policies
2. **Cluster Autoscaler**: Modify scale-down delays and thresholds
3. **KEDA**: Add custom metrics scalers for specific needs

### Production Considerations

1. **Enable VPA** for resource right-sizing
2. **Configure proper network policies**
3. **Set up proper RBAC policies**
4. **Enable audit logging**
5. **Configure backup and disaster recovery**

## Cleanup

### Using CloudFormation

```bash
# Delete Kubernetes resources first
kubectl delete -f k8s-resources/

# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name eks-autoscaling-stack \
    --region us-west-2

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name eks-autoscaling-stack \
    --region us-west-2
```

### Using CDK

```bash
# Delete Kubernetes resources
kubectl delete -f ../k8s-resources/

# Destroy the CDK stack
cd cdk-typescript/  # or cdk-python/
cdk destroy EksAutoscalingStack

# Clean up local CDK context
rm -rf cdk.out/
```

### Using Terraform

```bash
# Delete Kubernetes resources
kubectl delete -f ../k8s-resources/

# Destroy Terraform infrastructure
cd terraform/
terraform destroy

# Clean up Terraform state
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Kubernetes resources
# 2. Uninstall Helm charts
# 3. Delete EKS cluster
# 4. Clean up IAM roles and policies
# 5. Remove local configuration files
```

## Security Considerations

### IAM Permissions

- Use least privilege principle for all IAM roles
- Implement IRSA (IAM Roles for Service Accounts) for pod-level permissions
- Regularly audit and rotate access keys
- Enable AWS CloudTrail for API logging

### Network Security

- Use private subnets for worker nodes
- Configure security groups with minimal required access
- Enable VPC Flow Logs for network monitoring
- Consider using AWS Load Balancer Controller for ingress

### Cluster Security

- Enable cluster logging for audit trails
- Use Pod Security Standards for workload security
- Implement Network Policies for pod-to-pod communication
- Regular security updates for node groups

## Cost Optimization

### Resource Management

- Use Spot Instances for non-critical workloads
- Implement proper resource requests and limits
- Monitor and adjust scaling policies based on usage patterns
- Use node groups with different instance types

### Monitoring and Alerting

- Set up CloudWatch alarms for cost thresholds
- Monitor resource utilization and right-size instances
- Use AWS Cost Explorer for cost analysis
- Implement automated resource cleanup for test environments

## Support and Documentation

- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Kubernetes Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Cluster Autoscaler Documentation](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/README.md)
- [KEDA Documentation](https://keda.sh/docs/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

For issues with this infrastructure code, refer to the original recipe documentation or the respective tool documentation.

## License

This code is provided as-is for educational and demonstration purposes. Please review and modify according to your organization's requirements and security policies.