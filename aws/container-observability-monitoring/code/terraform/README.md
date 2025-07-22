# Infrastructure as Code for Comprehensive Container Observability and Performance Monitoring

This directory contains Terraform Infrastructure as Code (IaC) implementation for the recipe "Container Observability and Performance Monitoring" on AWS.

## Overview

This Terraform configuration deploys a complete container observability and performance monitoring solution that includes:

- **EKS Cluster** with Container Insights and enhanced observability
- **ECS Cluster** with Fargate tasks and monitoring
- **Prometheus and Grafana** monitoring stack
- **AWS Distro for OpenTelemetry (ADOT)** collector
- **CloudWatch** dashboards, alarms, and anomaly detection
- **OpenSearch** domain for log analytics (optional)
- **Performance optimization** Lambda function with automated analysis
- **SNS notifications** for critical alerts

## Architecture

The infrastructure creates a comprehensive observability platform that provides:

- **Multi-layer monitoring**: Infrastructure, platform, and application metrics
- **Distributed tracing**: AWS X-Ray integration for request tracing
- **Log analytics**: Centralized logging with OpenSearch
- **Automated alerting**: CloudWatch alarms with SNS notifications
- **Performance optimization**: ML-based recommendations for resource optimization
- **Cost optimization**: Automated analysis and recommendations

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- kubectl installed for EKS management
- Appropriate AWS permissions for creating EKS, ECS, CloudWatch, and other resources
- Estimated cost: $300-500 for 5 hours of operation

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize for your environment:

```bash
# Review variables.tf and customize as needed
# Key variables to consider:
# - aws_region: Your preferred AWS region
# - alert_email: Your email for notifications
# - enable_opensearch: Whether to deploy OpenSearch (adds cost)
# - enable_automated_optimization: Whether to enable performance optimization
```

### 3. Plan the Deployment

```bash
terraform plan -var="alert_email=your-email@example.com"
```

### 4. Deploy the Infrastructure

```bash
terraform apply -var="alert_email=your-email@example.com"
```

The deployment will take approximately 20-30 minutes to complete.

### 5. Configure kubectl

After deployment, configure kubectl to access your EKS cluster:

```bash
aws eks update-kubeconfig --region <your-region> --name <cluster-name>
```

## Accessing the Monitoring Stack

### Grafana Dashboard

If LoadBalancer is enabled (default):
```bash
# Get the LoadBalancer URL from Terraform output
terraform output grafana_url
```

If using port-forward:
```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
# Access at http://localhost:3000
# Username: admin
# Password: (from terraform output grafana_admin_password)
```

### Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
# Access at http://localhost:9090
```

### CloudWatch Dashboard

Access the CloudWatch dashboard using the URL from Terraform output:
```bash
terraform output cloudwatch_dashboard_url
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `aws_region` | AWS region for deployment | `us-west-2` | string |
| `alert_email` | Email for CloudWatch alerts | `admin@example.com` | string |
| `enable_opensearch` | Deploy OpenSearch domain | `true` | bool |
| `enable_automated_optimization` | Enable performance optimization | `true` | bool |
| `enable_grafana_lb` | Use LoadBalancer for Grafana | `true` | bool |
| `cpu_threshold` | CPU utilization alert threshold | `80` | number |
| `memory_threshold` | Memory utilization alert threshold | `80` | number |
| `log_retention_days` | CloudWatch log retention | `30` | number |

### Optional Features

- **OpenSearch**: Set `enable_opensearch = false` to disable and reduce costs
- **Performance Optimization**: Set `enable_automated_optimization = false` to disable Lambda-based optimization
- **Grafana LoadBalancer**: Set `enable_grafana_lb = false` to use port-forwarding instead

## Monitoring and Alerting

### CloudWatch Alarms

The deployment creates several CloudWatch alarms:

- **EKS High CPU Utilization**: Triggers when pod CPU > 80%
- **EKS High Memory Utilization**: Triggers when pod memory > 80%
- **ECS Unhealthy Tasks**: Triggers when running tasks < 1
- **CPU Anomaly Detection**: ML-based anomaly detection for CPU
- **Memory Anomaly Detection**: ML-based anomaly detection for memory

### SNS Notifications

Configure email notifications by setting the `alert_email` variable. You'll receive an email confirmation to subscribe to the SNS topic.

### Performance Optimization

The automated performance optimization Lambda function runs hourly and analyzes:

- CPU and memory utilization patterns
- Container restart patterns
- Cost optimization opportunities
- Scaling recommendations

## Verification Commands

After deployment, verify the infrastructure:

```bash
# Check EKS cluster
aws eks describe-cluster --name <cluster-name>

# Check ECS cluster
aws ecs describe-clusters --clusters <cluster-name>

# Check Container Insights metrics
aws cloudwatch list-metrics --namespace AWS/ContainerInsights

# Check Kubernetes pods
kubectl get pods -n monitoring
kubectl get pods -n amazon-cloudwatch

# Check CloudWatch alarms
aws cloudwatch describe-alarms
```

## Cost Optimization

### Estimated Monthly Costs

- **EKS Cluster**: ~$73 (control plane) + ~$90 (3 x t3.large nodes)
- **ECS Fargate**: ~$30 (2 tasks continuously running)
- **CloudWatch**: ~$35 (logs, metrics, and alarms)
- **OpenSearch**: ~$60 (3 x t3.small.search instances) - optional
- **Lambda**: ~$1 (hourly execution)
- **Total**: ~$299/month (with OpenSearch) or ~$239/month (without OpenSearch)

### Cost Reduction Strategies

1. **Disable OpenSearch**: Set `enable_opensearch = false`
2. **Use Spot Instances**: Modify node group configuration
3. **Reduce Log Retention**: Set `log_retention_days = 7`
4. **Scale Down Development**: Reduce node counts for dev environments
5. **Enable Automated Optimization**: Uses ML to optimize resource allocation

## Security Considerations

⚠️ **Important Security Notes**:

1. **EKS Endpoint**: Public endpoint enabled - consider private for production
2. **OpenSearch**: Basic auth enabled - implement fine-grained access control
3. **Grafana**: Default admin password - change immediately
4. **ECS Tasks**: Running in public subnets - move to private for production
5. **IAM Roles**: Review and apply least privilege principle

### Security Hardening

For production deployments:

1. Enable private EKS endpoint
2. Use AWS Secrets Manager for passwords
3. Implement network security groups
4. Enable AWS Config and GuardDuty
5. Use AWS Systems Manager Session Manager

## Troubleshooting

### Common Issues

1. **EKS Cluster Creation Fails**:
   - Check AWS service limits
   - Verify IAM permissions
   - Ensure sufficient IP addresses in subnets

2. **Container Insights Not Working**:
   - Verify IAM roles and permissions
   - Check CloudWatch agent logs
   - Ensure proper tagging

3. **Grafana Not Accessible**:
   - Check LoadBalancer creation
   - Verify security group rules
   - Try port-forwarding as alternative

4. **High Costs**:
   - Disable OpenSearch if not needed
   - Use smaller instance types
   - Enable automated optimization

### Debugging

```bash
# Check Terraform state
terraform show
terraform state list

# Check Kubernetes resources
kubectl get all -n monitoring
kubectl get all -n amazon-cloudwatch
kubectl describe pod <pod-name> -n monitoring

# Check CloudWatch logs
aws logs describe-log-groups
aws logs tail <log-group-name> --follow
```

## Cleanup

To destroy all resources:

```bash
terraform destroy -var="alert_email=your-email@example.com"
```

⚠️ **Warning**: This will destroy all resources and data. Make sure to backup any important data before running destroy.

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation
3. Check Terraform AWS provider documentation
4. Review CloudWatch Container Insights documentation

## Advanced Configuration

### Custom Metrics

Add custom metrics by modifying the ADOT collector configuration in `templates/adot-collector.yaml`.

### Additional Dashboards

Import additional Grafana dashboards by modifying the `grafana-values.yaml` template.

### Custom Alerts

Add custom CloudWatch alarms by extending the `main.tf` file.

### Multi-Region Deployment

For multi-region deployments, create separate Terraform configurations for each region.

## Contributing

When making changes to this infrastructure:

1. Test in a development environment first
2. Update documentation for any new variables or outputs
3. Validate with `terraform plan` before applying
4. Consider backwards compatibility for existing deployments