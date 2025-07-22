# AWS EKS Ingress Controllers with AWS Load Balancer Controller - Terraform

This Terraform configuration deploys the AWS Load Balancer Controller on an existing Amazon EKS cluster, along with comprehensive ingress resources and sample applications to demonstrate various load balancing scenarios including Application Load Balancers (ALB) and Network Load Balancers (NLB).

## Architecture Overview

The solution creates:

- **AWS Load Balancer Controller**: Deployed via Helm chart with proper IAM permissions
- **IRSA Configuration**: IAM Roles for Service Accounts for secure AWS API access
- **Sample Applications**: Nginx-based applications with different versions for testing
- **Ingress Resources**: Various ingress configurations demonstrating different patterns
- **SSL/TLS Support**: Optional ACM certificate integration for HTTPS
- **Monitoring Setup**: Optional S3 access logs and CloudWatch integration

## Prerequisites

- **Existing EKS Cluster**: A running EKS cluster (version 1.21+)
- **AWS CLI**: Configured with appropriate permissions
- **kubectl**: Configured to access your EKS cluster
- **Terraform**: Version 1.5.0 or later
- **Helm**: Not required locally (managed by Terraform)

### Required IAM Permissions

Your Terraform execution role needs permissions for:

- EKS cluster management
- IAM role and policy creation
- ELB/ALB/NLB management
- ACM certificate operations
- S3 bucket operations (if access logs enabled)
- Route 53 operations (if using custom domains)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd terraform/
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

3. **Initialize and Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Verify Deployment**:
   ```bash
   # Configure kubectl
   aws eks update-kubeconfig --region <your-region> --name <your-cluster>
   
   # Check controller status
   kubectl get deployment -n kube-system aws-load-balancer-controller
   
   # View ingress resources
   kubectl get ingress -A
   ```

## Configuration Options

### Basic Configuration

```hcl
# Required variables
cluster_name = "your-eks-cluster"
aws_region   = "us-west-2"

# Optional: Enable sample resources
create_sample_ingresses = true
demo_namespace          = "ingress-demo"
```

### SSL/TLS Configuration

```hcl
# Enable HTTPS with ACM
domain_name        = "example.com"
enable_ssl_redirect = true
ssl_policy         = "ELBSecurityPolicy-TLS-1-2-2019-07"
```

### Advanced Features

```hcl
# Production features
enable_access_logs         = true
enable_deletion_protection = true
enable_waf                = true
enable_pod_readiness_gate  = true

# Performance tuning
idle_timeout_seconds           = 60
deregistration_delay_seconds   = 30
healthcheck_interval          = 10
```

## Deployment Modes

### Development Mode

```hcl
deployment_mode       = "development"
sample_app_replicas  = 2
enable_debug_logging = true
create_sample_ingresses = true
```

### Production Mode

```hcl
deployment_mode             = "production"
sample_app_replicas        = 5
enable_access_logs         = true
enable_deletion_protection = true
enable_waf                 = true
backup_retention_days      = 90
```

## Load Balancer Types

### Application Load Balancer (ALB)

- **Layer 7** HTTP/HTTPS load balancing
- **SSL termination** with ACM integration
- **Path-based routing** and host-based routing
- **WAF integration** for application security
- **Advanced routing** with weighted traffic distribution

### Network Load Balancer (NLB)

- **Layer 4** TCP/UDP load balancing
- **Ultra-low latency** and high throughput
- **Static IP addresses** and Elastic IP support
- **Cross-zone load balancing**
- **Health checks** with multiple protocols

## Ingress Patterns

### Basic Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

### Advanced Ingress with SSL

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
spec:
  ingressClassName: alb
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

### Weighted Traffic Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/actions.weighted-routing: |
      {
        "type": "forward",
        "forwardConfig": {
          "targetGroups": [
            {
              "serviceName": "app-v1",
              "servicePort": "80",
              "weight": 70
            },
            {
              "serviceName": "app-v2", 
              "servicePort": "80",
              "weight": 30
            }
          ]
        }
      }
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: weighted-routing
            port:
              name: use-annotation
```

## Security Features

### IAM Roles for Service Accounts (IRSA)

The controller uses IRSA for secure AWS API access:

```hcl
# OIDC provider configuration
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# IAM role with trust policy
resource "aws_iam_role" "aws_load_balancer_controller" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
    }]
  })
}
```

### WAF Integration

```hcl
# Enable WAF protection
enable_waf = true
waf_acl_arn = "arn:aws:wafv2:region:account:regional/webacl/name/id"
```

### Shield Advanced

```hcl
# Enable DDoS protection
enable_shield_advanced = true
```

## Monitoring and Observability

### Access Logs

```hcl
# Enable S3 access logs
enable_access_logs = true
access_logs_bucket = "my-alb-logs-bucket"
access_logs_prefix = "alb-logs"
```

### CloudWatch Integration

The controller automatically publishes metrics to CloudWatch:

- **Application Load Balancer**: `AWS/ApplicationELB` namespace
- **Network Load Balancer**: `AWS/NetworkELB` namespace
- **Target Groups**: Health check and request metrics

### Controller Logs

```bash
# View controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Enable debug logging
# Set enable_debug_logging = true in terraform.tfvars
```

## Testing and Validation

### Basic Connectivity

```bash
# Get ALB hostname
ALB_HOST=$(kubectl get ingress sample-app-basic-alb -n ingress-demo \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test HTTP access
curl -H "Host: basic.example.com" http://$ALB_HOST/

# Test HTTPS access (if SSL enabled)
curl https://basic.example.com/
```

### Path-Based Routing

```bash
# Test different service versions
curl https://advanced.example.com/v1  # Routes to app-v1
curl https://advanced.example.com/v2  # Routes to app-v2
```

### Network Load Balancer

```bash
# Get NLB hostname
NLB_HOST=$(kubectl get service sample-app-nlb -n ingress-demo \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test TCP connectivity
curl http://$NLB_HOST/
```

### Health Checks

```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>

# List all load balancers
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].{Name:LoadBalancerName,DNS:DNSName,Type:Type}' \
  --output table
```

## Troubleshooting

### Common Issues

1. **Controller Pod Not Starting**:
   ```bash
   kubectl describe pod -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   ```

2. **Ingress Not Creating Load Balancer**:
   ```bash
   kubectl describe ingress <ingress-name> -n <namespace>
   kubectl get events -n <namespace>
   ```

3. **IAM Permission Issues**:
   ```bash
   kubectl logs -n kube-system deployment/aws-load-balancer-controller
   ```

4. **SSL Certificate Issues**:
   ```bash
   aws acm describe-certificate --certificate-arn <cert-arn>
   ```

### Debug Commands

```bash
# Check controller status
kubectl get deployment -n kube-system aws-load-balancer-controller

# View controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Check ingress resources
kubectl get ingress -A

# List services with load balancers
kubectl get services -A --field-selector spec.type=LoadBalancer

# Check target groups
aws elbv2 describe-target-groups \
  --query 'TargetGroups[?contains(TargetGroupName, `k8s-`)].{Name:TargetGroupName,ARN:TargetGroupArn}' \
  --output table
```

## Resource Cleanup

### Terraform Cleanup

```bash
terraform destroy
```

### Manual Cleanup (if needed)

```bash
# Delete ingress resources first
kubectl delete ingress --all -A

# Delete LoadBalancer services
kubectl delete service --field-selector spec.type=LoadBalancer -A

# Wait for AWS resources to be cleaned up (2-3 minutes)
# Then run terraform destroy
```

## Advanced Configuration

### Custom IngressClass

```hcl
# Create custom ingress class with specific defaults
resource "kubernetes_manifest" "custom_ingress_class" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "IngressClass"
    metadata = {
      name = "custom-alb"
    }
    spec = {
      controller = "ingress.k8s.aws/alb"
      parameters = {
        apiVersion = "elbv2.k8s.aws/v1beta1"
        kind       = "IngressClassParams"
        name       = "custom-alb-params"
      }
    }
  }
}
```

### Multiple Ingress Groups

```yaml
# Share single ALB across multiple ingresses
metadata:
  annotations:
    alb.ingress.kubernetes.io/group.name: "shared-alb"
    alb.ingress.kubernetes.io/group.order: "1"
```

### Cross-Zone Load Balancing

```hcl
# Enable for better availability
nlb_cross_zone_enabled = true
```

## Production Considerations

### High Availability

- Deploy across multiple AZs
- Use multiple replicas for applications
- Configure proper health checks
- Enable cross-zone load balancing

### Security

- Use private subnets for worker nodes
- Enable WAF and Shield Advanced
- Implement proper security groups
- Use ACM for SSL certificates

### Cost Optimization

- Right-size instance types
- Use Spot instances where appropriate
- Monitor and optimize target group settings
- Implement proper tagging for cost allocation

### Monitoring

- Enable access logs for security analysis
- Set up CloudWatch alarms
- Monitor target group health
- Track application performance metrics

## Support and Documentation

- [AWS Load Balancer Controller Documentation](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Application Load Balancer Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Network Load Balancer Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)

## Contributing

To contribute improvements to this Terraform configuration:

1. Test changes in a development environment
2. Update documentation as needed
3. Ensure all variables have proper validation
4. Add appropriate tags and comments
5. Test cleanup procedures

## License

This configuration is provided as-is for educational and demonstration purposes. Please review and adapt security settings for production use.