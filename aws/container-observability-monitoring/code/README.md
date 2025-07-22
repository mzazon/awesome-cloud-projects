# Infrastructure as Code for Container Observability and Performance Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container Observability and Performance Monitoring".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (version 2.0.38 or later)
- kubectl and eksctl installed for EKS management
- Helm v3 installed for Kubernetes package management
- Docker installed for container image management
- Appropriate AWS permissions for:
  - Amazon EKS (create/manage clusters)
  - Amazon ECS (create/manage clusters and services)
  - Amazon CloudWatch (create/manage alarms, dashboards, logs)
  - AWS X-Ray (create/manage traces)
  - Amazon OpenSearch Service (create/manage domains)
  - AWS Lambda (create/manage functions)
  - Amazon EventBridge (create/manage rules)
  - Amazon SNS (create/manage topics)
  - IAM (create/manage roles and policies)

## Architecture Overview

This solution deploys a comprehensive container observability platform that includes:

- **Container Infrastructure**: EKS cluster with enhanced monitoring and ECS cluster with Container Insights
- **Metrics Collection**: CloudWatch Container Insights, Prometheus server, and ADOT collectors
- **Distributed Tracing**: AWS X-Ray with OpenTelemetry integration
- **Log Aggregation**: CloudWatch Logs with OpenSearch analytics
- **Visualization**: Grafana dashboards and CloudWatch dashboards
- **Alerting**: CloudWatch alarms with anomaly detection and SNS notifications
- **Performance Optimization**: Lambda-based automated optimization recommendations

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete observability stack
aws cloudformation create-stack \
    --stack-name container-observability-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=my-observability-cluster \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-west-2

# Wait for stack completion
aws cloudformation wait stack-create-complete \
    --stack-name container-observability-stack
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy ContainerObservabilityStack

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy ContainerObservabilityStack

# View outputs
cdk outputs
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

# Deploy the complete solution
./scripts/deploy.sh

# Follow the deployment progress
# The script will output progress and important information
```

## Configuration Parameters

### CloudFormation Parameters
- `ClusterName`: Name for the EKS cluster (default: observability-cluster)
- `ECSClusterName`: Name for the ECS cluster (default: observability-ecs-cluster)
- `MonitoringNamespace`: Kubernetes namespace for monitoring tools (default: monitoring)
- `OpenSearchDomain`: Name for OpenSearch domain (default: container-logs)
- `NotificationEmail`: Email address for alerts (required)
- `EnableAnomalyDetection`: Enable CloudWatch anomaly detection (default: true)
- `GrafanaPassword`: Password for Grafana admin user (default: auto-generated)

### Terraform Variables
- `aws_region`: AWS region for deployment
- `cluster_name`: EKS cluster name
- `ecs_cluster_name`: ECS cluster name
- `monitoring_namespace`: Kubernetes namespace for monitoring
- `opensearch_domain`: OpenSearch domain name
- `notification_email`: Email for alerts
- `enable_anomaly_detection`: Enable anomaly detection
- `grafana_admin_password`: Grafana admin password

### CDK Configuration
Both CDK implementations support the same parameters through environment variables or stack properties:
- `CLUSTER_NAME`: EKS cluster name
- `ECS_CLUSTER_NAME`: ECS cluster name
- `MONITORING_NAMESPACE`: Kubernetes monitoring namespace
- `OPENSEARCH_DOMAIN`: OpenSearch domain name
- `NOTIFICATION_EMAIL`: Email for alerts

## Post-Deployment Steps

After successful deployment, perform these steps:

1. **Configure kubectl for EKS**:
   ```bash
   aws eks update-kubeconfig --region <region> --name <cluster-name>
   ```

2. **Access Grafana Dashboard**:
   ```bash
   # Get Grafana URL from outputs
   kubectl get svc -n monitoring grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   
   # Default credentials: admin / [password from outputs]
   ```

3. **Deploy Sample Applications** (optional):
   ```bash
   # Deploy demo applications to generate metrics
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/examples/master/guestbook/all-in-one/guestbook-all-in-one.yaml
   ```

4. **Verify Monitoring Stack**:
   ```bash
   # Check Container Insights metrics
   aws cloudwatch list-metrics --namespace "AWS/ContainerInsights"
   
   # Check Prometheus metrics
   kubectl port-forward -n monitoring svc/prometheus-server 9090:80
   ```

## Monitoring and Alerting

### CloudWatch Dashboards
- **Container Observability Dashboard**: Comprehensive view of EKS and ECS metrics
- **Performance Insights**: Application performance and resource utilization
- **Cost Optimization**: Resource usage and cost analysis

### Grafana Dashboards
- **Kubernetes Cluster Overview**: Cluster-wide metrics and health
- **Pod Performance**: Individual pod metrics and troubleshooting
- **ECS Service Monitoring**: ECS task and service performance

### Alerting Rules
- High CPU/Memory utilization alerts
- Container restart alerts
- Service unavailability alerts
- Anomaly detection alerts
- Performance degradation alerts

## Cost Considerations

This solution deploys multiple AWS services that incur costs:

- **EKS Cluster**: $0.10 per hour for control plane + EC2 instances
- **ECS Cluster**: Fargate pricing for running tasks
- **CloudWatch**: Metrics, logs, and dashboard charges
- **OpenSearch**: Domain hosting and storage costs
- **Lambda**: Function execution costs
- **Data Transfer**: Cross-AZ and internet egress charges

**Estimated Monthly Cost**: $300-500 for moderate usage (development/testing)

For production workloads, costs will scale with:
- Number of containers and metrics
- Log volume and retention
- OpenSearch domain size
- Alert notification frequency

## Customization

### Adding Custom Metrics
Modify the Prometheus configuration to scrape additional endpoints:

```yaml
# In prometheus-values.yaml
scrape_configs:
  - job_name: 'my-app'
    static_configs:
      - targets: ['my-app:8080']
```

### Custom Dashboards
Add custom Grafana dashboards by placing JSON files in:
- CloudFormation: Custom resource for dashboard creation
- CDK: Use Grafana dashboard construct
- Terraform: Use grafana_dashboard resource

### Alert Customization
Modify alert thresholds and notifications:

```bash
# CloudWatch alarms
aws cloudwatch put-metric-alarm \
    --alarm-name "Custom-Alert" \
    --threshold 90 \
    --comparison-operator GreaterThanThreshold
```

## Troubleshooting

### Common Issues

1. **EKS Cluster Creation Fails**:
   - Check IAM permissions for EKS service
   - Verify VPC and subnet configuration
   - Ensure adequate IP addresses in subnets

2. **Container Insights Not Showing Data**:
   - Verify CloudWatch agent is running: `kubectl get pods -n amazon-cloudwatch`
   - Check IAM permissions for CloudWatch
   - Ensure proper service account annotations

3. **Grafana Dashboard Empty**:
   - Check Prometheus data source connection
   - Verify Prometheus is scraping targets
   - Review network policies blocking access

4. **High Costs**:
   - Review log retention policies
   - Optimize metric collection frequency
   - Consider using CloudWatch Logs Insights instead of OpenSearch

### Debug Commands

```bash
# Check EKS cluster status
aws eks describe-cluster --name <cluster-name>

# Verify Container Insights
kubectl get pods -n amazon-cloudwatch
kubectl logs -n amazon-cloudwatch <pod-name>

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# Visit http://localhost:9090/targets

# Test X-Ray tracing
aws xray get-service-map --start-time <timestamp> --end-time <timestamp>
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name container-observability-stack

# Wait for deletion
aws cloudformation wait stack-delete-complete \
    --stack-name container-observability-stack
```

### Using CDK
```bash
# From the respective CDK directory
cdk destroy ContainerObservabilityStack

# Confirm deletion when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup (if needed)
```bash
# Delete EKS cluster
eksctl delete cluster --name <cluster-name>

# Delete ECS cluster
aws ecs delete-cluster --cluster <cluster-name>

# Delete OpenSearch domain
aws opensearch delete-domain --domain-name <domain-name>

# Delete CloudWatch log groups
aws logs delete-log-group --log-group-name "/aws/eks/<cluster-name>/application"
```

## Security Best Practices

This implementation follows AWS security best practices:

- **IAM Roles**: Least privilege access for all services
- **VPC Security**: Private subnets for worker nodes
- **Encryption**: At-rest and in-transit encryption enabled
- **Network Security**: Security groups restrict access
- **Secrets Management**: Passwords stored in AWS Secrets Manager
- **Audit Logging**: CloudTrail integration for API calls

## Support and Maintenance

### Regular Maintenance Tasks

1. **Update Kubernetes Version**: Regularly update EKS cluster version
2. **Rotate Secrets**: Rotate Grafana and other service passwords
3. **Review Costs**: Monitor and optimize CloudWatch usage
4. **Update Dashboards**: Keep Grafana dashboards current
5. **Security Updates**: Apply security patches to container images

### Monitoring Health

- Set up CloudWatch alarms for infrastructure health
- Monitor OpenSearch cluster health
- Track Prometheus target health
- Review Lambda function execution logs

### Backup and Recovery

- EKS cluster configuration is backed up in IaC
- Grafana dashboards can be exported/imported
- CloudWatch logs have configurable retention
- OpenSearch supports automated snapshots

## Additional Resources

- [AWS Container Insights Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/container-insights-detailed-metrics.html)
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [AWS X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [OpenSearch Service Documentation](https://docs.aws.amazon.com/opensearch-service/)

For issues with this infrastructure code, refer to the original recipe documentation or the AWS service documentation.