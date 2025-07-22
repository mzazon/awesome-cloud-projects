# Infrastructure as Code for Kubernetes Operators for AWS Resources

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Kubernetes Operators for AWS Resources".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- kubectl configured for EKS cluster access
- Helm 3.8+ installed for ACK controller deployment
- Go 1.21+ and Docker installed for custom operator development
- Operator SDK v1.32+ for scaffolding custom operators
- Appropriate AWS permissions for:
  - EKS cluster management
  - IAM role creation and policy attachment
  - S3, Lambda, and IAM service access
  - ECR registry access for controller images
- Estimated cost: $50-100 for EKS cluster, Lambda functions, and S3 storage during development

## Architecture Overview

This solution implements AWS Controllers for Kubernetes (ACK) to enable native AWS resource management through Kubernetes operators. The infrastructure includes:

- **EKS Cluster**: Kubernetes control plane for operator deployment
- **ACK Controllers**: S3, IAM, and Lambda service controllers
- **Custom Operator**: Platform-specific resource orchestration
- **OIDC Provider**: Service account authentication for AWS APIs
- **IAM Roles**: Least-privilege access for controller operations

## Quick Start

### Using CloudFormation

```bash
# Deploy EKS cluster and supporting infrastructure
aws cloudformation create-stack \
    --stack-name k8s-operators-infrastructure \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=ClusterName,ParameterValue=ack-operators-cluster \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-west-2

# Wait for stack creation
aws cloudformation wait stack-create-complete \
    --stack-name k8s-operators-infrastructure

# Update kubeconfig
aws eks update-kubeconfig \
    --name ack-operators-cluster \
    --region us-west-2

# Deploy ACK controllers using Helm (post-deployment step)
./scripts/deploy-ack-controllers.sh
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
npx cdk bootstrap

# Deploy infrastructure
npx cdk deploy --all

# The CDK deployment includes post-deployment scripts for ACK controllers
# Check deployment status
kubectl get pods -n ack-system
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy infrastructure
cdk deploy --all

# Verify ACK controllers
kubectl get pods -n ack-system
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply infrastructure
terraform apply

# Configure kubectl (output from Terraform)
aws eks update-kubeconfig \
    --name $(terraform output -raw cluster_name) \
    --region $(terraform output -raw aws_region)

# Verify deployment
kubectl get nodes
kubectl get pods -n ack-system
```

### Using Bash Scripts

```bash
# Set required environment variables
export AWS_REGION=us-west-2
export CLUSTER_NAME=ack-operators-cluster

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy complete solution
./scripts/deploy.sh

# Verify deployment
kubectl get applications -A
kubectl get pods -n ack-system
```

## Post-Deployment Configuration

### Install Custom Operator

After deploying the infrastructure, install the custom platform operator:

```bash
# Clone operator project (generated during recipe)
cd platform-operator/

# Build and deploy operator
make docker-build IMG=platform-operator:latest
kind load docker-image platform-operator:latest

# Deploy to cluster
make deploy IMG=platform-operator:latest

# Verify operator deployment
kubectl get pods -n platform-operator-system
```

### Create Sample Application

```bash
# Create test application using custom operator
cat > sample-app.yaml << 'EOF'
apiVersion: platform.example.com/v1
kind: Application
metadata:
  name: sample-app
  namespace: default
spec:
  name: sample-app
  environment: dev
  storageClass: STANDARD
  lambdaRuntime: python3.9
  enableLogging: true
EOF

kubectl apply -f sample-app.yaml

# Monitor application provisioning
kubectl get applications sample-app -w
```

## Validation and Testing

### Verify ACK Controllers

```bash
# Check ACK controller status
kubectl get pods -n ack-system
kubectl get crd | grep -E "(s3|iam|lambda).services.k8s.aws"

# Test S3 bucket creation
cat > test-bucket.yaml << 'EOF'
apiVersion: s3.services.k8s.aws/v1alpha1
kind: Bucket
metadata:
  name: test-bucket-ack
spec:
  name: test-bucket-ack-$(date +%s)
EOF

kubectl apply -f test-bucket.yaml
kubectl get buckets
```

### Verify Custom Operator

```bash
# Check operator webhook validation
cat > invalid-app.yaml << 'EOF'
apiVersion: platform.example.com/v1
kind: Application
metadata:
  name: Invalid_Name
spec:
  name: Invalid_Name
  environment: invalid
EOF

kubectl apply -f invalid-app.yaml
# Should return validation error
```

### Monitor Operator Metrics

```bash
# Port forward to metrics endpoint
kubectl port-forward -n platform-operator-system \
    svc/platform-operator-metrics 8080:8080 &

# Check metrics
curl http://localhost:8080/metrics | grep controller_runtime
```

## Cleanup

### Using CloudFormation

```bash
# Delete any created applications first
kubectl delete applications --all --all-namespaces

# Delete custom operator
cd platform-operator/
make undeploy

# Delete ACK controllers
helm uninstall ack-s3-controller -n ack-system
helm uninstall ack-iam-controller -n ack-system
helm uninstall ack-lambda-controller -n ack-system

# Delete CloudFormation stack
aws cloudformation delete-stack \
    --stack-name k8s-operators-infrastructure

# Wait for deletion
aws cloudformation wait stack-delete-complete \
    --stack-name k8s-operators-infrastructure
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Clean up applications and operators first
kubectl delete applications --all --all-namespaces

# Destroy CDK stack
npx cdk destroy --all  # or: cdk destroy --all for Python
```

### Using Terraform

```bash
cd terraform/

# Clean up Kubernetes resources first
kubectl delete applications --all --all-namespaces

# Destroy infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
aws eks list-clusters --region $AWS_REGION
```

## Customization

### Environment Variables

Key variables for customization:

```bash
# Infrastructure sizing
export CLUSTER_NAME="your-cluster-name"
export AWS_REGION="your-preferred-region"
export NODE_INSTANCE_TYPE="t3.medium"  # Adjust based on workload

# Operator configuration
export OPERATOR_NAMESPACE="platform-operator-system"
export ACK_SYSTEM_NAMESPACE="ack-system"

# Application defaults
export DEFAULT_LAMBDA_RUNTIME="python3.9"
export DEFAULT_STORAGE_CLASS="STANDARD"
```

### Terraform Variables

Customize the deployment by modifying `terraform/terraform.tfvars`:

```hcl
cluster_name         = "my-ack-cluster"
cluster_version      = "1.28"
node_group_min_size  = 1
node_group_max_size  = 5
node_group_desired_size = 2
node_instance_types  = ["t3.medium"]
enable_cluster_encryption = true

# Custom operator configuration
operator_image = "my-registry/platform-operator:v1.0"
enable_webhooks = true
enable_monitoring = true
```

### CDK Configuration

Modify stack parameters in `cdk-typescript/lib/k8s-operators-stack.ts` or `cdk-python/k8s_operators/k8s_operators_stack.py`:

```typescript
// TypeScript example
const cluster = new eks.Cluster(this, 'ACKCluster', {
  version: eks.KubernetesVersion.V1_28,
  defaultCapacity: 2,
  defaultCapacityInstance: ec2.InstanceType.of(
    ec2.InstanceClass.T3, 
    ec2.InstanceSize.MEDIUM
  ),
  // Additional configurations...
});
```

## Advanced Features

### Multi-Environment Setup

Deploy operators across multiple environments:

```bash
# Development environment
export ENVIRONMENT=dev
terraform workspace new dev
terraform apply -var="environment=dev"

# Production environment
export ENVIRONMENT=prod
terraform workspace new prod
terraform apply -var="environment=prod"
```

### Custom Resource Policies

Implement additional validation with OPA Gatekeeper:

```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: applicationnaming
spec:
  crd:
    spec:
      names:
        kind: ApplicationNaming
      validation:
        properties:
          pattern:
            type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package applicationnaming
        violation[{"msg": msg}] {
          input.review.object.kind == "Application"
          not regex.match(input.parameters.pattern, input.review.object.spec.name)
          msg := "Application name must follow naming convention"
        }
```

### Monitoring and Alerting

Configure Prometheus alerts for operator health:

```yaml
groups:
- name: platform-operator-alerts
  rules:
  - alert: OperatorReconciliationErrors
    expr: increase(controller_runtime_reconcile_errors_total[5m]) > 5
    for: 2m
    annotations:
      summary: "High reconciliation error rate detected"
  
  - alert: OperatorDown
    expr: up{job="platform-operator-metrics"} == 0
    for: 1m
    annotations:
      summary: "Platform operator is down"
```

## Troubleshooting

### Common Issues

1. **OIDC Provider Not Found**
   ```bash
   # Check OIDC provider exists
   aws iam list-open-id-connect-providers
   
   # If missing, recreate:
   eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve
   ```

2. **ACK Controller Authentication Errors**
   ```bash
   # Verify service account annotations
   kubectl get sa ack-controller -n ack-system -o yaml
   
   # Check IAM role trust policy
   aws iam get-role --role-name ACK-Controller-Role
   ```

3. **Custom Operator Image Pull Errors**
   ```bash
   # Check image exists and is accessible
   docker pull platform-operator:latest
   
   # For kind clusters, ensure image is loaded
   kind load docker-image platform-operator:latest
   ```

4. **Webhook Certificate Issues**
   ```bash
   # Regenerate webhook certificates
   kubectl delete secret webhook-server-certs -n platform-operator-system
   kubectl rollout restart deployment platform-operator-controller-manager -n platform-operator-system
   ```

### Debug Commands

```bash
# Check operator logs
kubectl logs -n platform-operator-system deployment/platform-operator-controller-manager

# Check ACK controller logs
kubectl logs -n ack-system deployment/ack-s3-controller

# Describe failed resources
kubectl describe application sample-app
kubectl describe bucket test-bucket-ack

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp
```

## Security Considerations

- **RBAC**: All operators use least-privilege RBAC policies
- **Network Policies**: Pod-to-pod communication is restricted
- **Image Security**: Use signed container images in production
- **Secret Management**: Avoid storing credentials in manifests
- **Audit Logging**: Enable EKS audit logging for compliance

## Performance Tuning

- **Resource Requests/Limits**: Set appropriate CPU/memory limits for operators
- **Controller Concurrency**: Tune reconciliation worker counts for scale
- **Watch Optimization**: Use field selectors to reduce API server load
- **Caching**: Configure efficient controller-runtime caching strategies

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS ACK project documentation: https://aws-controllers-k8s.github.io/
3. Consult Kubernetes Operator development guides
4. Review provider-specific troubleshooting guides

## Contributing

When modifying this infrastructure:

1. Update all IaC implementations consistently
2. Test deployments in multiple environments
3. Validate security configurations
4. Update documentation for any changes
5. Follow semantic versioning for operator releases