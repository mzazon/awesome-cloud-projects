# Infrastructure as Code for Multi-Cluster Service Mesh Governance with Anthos Service Mesh and Config Management

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Establishing Multi-Cluster Service Mesh Governance with Anthos Service Mesh and Config Management".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using the Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for complete automation

## Prerequisites

- Google Cloud account with appropriate permissions for:
  - Google Kubernetes Engine (GKE)
  - Anthos Service Mesh
  - Anthos Config Management
  - Fleet Management
  - Binary Authorization
  - Artifact Registry
  - Cloud Monitoring and Logging
- Google Cloud CLI (gcloud) installed and configured
- kubectl CLI tool installed (version 1.24 or later)
- Terraform CLI installed (version 1.5 or later) - for Terraform implementation
- Git repository access for configuration management
- Basic understanding of Kubernetes, Istio, and GitOps principles
- Estimated cost: $150-300/month for 3 GKE clusters with Anthos Service Mesh and monitoring

> **Note**: This solution uses Google Cloud's managed Anthos Service Mesh, which provides enterprise-grade service mesh capabilities without the operational overhead of managing Istio control planes manually.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native IaC solution that provides state management and deployment orchestration.

```bash
# Authenticate and set project
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Deploy the infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/service-mesh-governance \
    --service-account projects/YOUR_PROJECT_ID/serviceAccounts/infra-manager@YOUR_PROJECT_ID.iam.gserviceaccount.com \
    --local-source="."

# Monitor deployment status
gcloud infra-manager deployments describe projects/YOUR_PROJECT_ID/locations/us-central1/deployments/service-mesh-governance
```

### Using Terraform

Terraform provides declarative infrastructure management with comprehensive state tracking and resource lifecycle management.

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud auth application-default login

# Initialize and deploy
cd terraform/
terraform init
terraform plan -var="project_id=YOUR_PROJECT_ID"
terraform apply -var="project_id=YOUR_PROJECT_ID"
```

### Using Bash Scripts

The bash scripts provide a complete automated deployment with error handling and validation checks.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy the complete solution
./scripts/deploy.sh

# Verify deployment
./scripts/validate.sh
```

## Architecture Overview

This implementation creates a comprehensive multi-cluster service mesh governance solution:

### Core Components

- **3 GKE Clusters**: Production, staging, and development environments
- **Anthos Service Mesh**: Managed Istio service mesh across all clusters
- **Fleet Management**: Centralized cluster management and policy enforcement
- **Anthos Config Management**: GitOps-driven configuration synchronization
- **Binary Authorization**: Container image security validation
- **Cross-cluster Service Discovery**: Secure inter-cluster communication

### Security Features

- **Strict mTLS**: Enforced mutual TLS for all service communications
- **Authorization Policies**: Environment-based access controls
- **Network Policies**: Kubernetes-level traffic restrictions
- **Binary Authorization**: Image signing and verification
- **Workload Identity**: Secure pod-to-GCP service authentication

### Observability

- **Cloud Monitoring**: Service mesh metrics and dashboards
- **Cloud Logging**: Centralized log aggregation
- **Cloud Trace**: Distributed tracing across services
- **Service mesh telemetry**: Request rates, latency, and error rates

## Configuration

### Infrastructure Manager Configuration

The Infrastructure Manager implementation uses YAML configuration files:

```yaml
# infrastructure-manager/main.yaml
imports:
  - path: modules/gke-clusters.yaml
  - path: modules/service-mesh.yaml
  - path: modules/config-management.yaml
  - path: modules/security-policies.yaml

resources:
  # GKE clusters with Anthos Service Mesh
  # Fleet registration and management
  # Config Management setup
  # Security and monitoring configuration
```

### Terraform Variables

Key variables for customization:

```hcl
# terraform/variables.tf
variable "project_id" {
  description = "Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "Default region for resources"
  type        = string
  default     = "us-central1"
}

variable "cluster_environments" {
  description = "Configuration for each cluster environment"
  type = map(object({
    node_count   = number
    machine_type = string
    labels       = map(string)
  }))
  default = {
    production = {
      node_count   = 3
      machine_type = "e2-standard-4"
      labels = {
        env = "production"
        tier = "critical"
      }
    }
    staging = {
      node_count   = 2
      machine_type = "e2-standard-2"
      labels = {
        env = "staging"
        tier = "testing"
      }
    }
    development = {
      node_count   = 2
      machine_type = "e2-standard-2"
      labels = {
        env = "development"
        tier = "experimental"
      }
    }
  }
}
```

### Environment Variables

Set these environment variables before deployment:

```bash
# Required variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export CLUSTER_PREFIX="mesh-gov"
export GIT_REPO_NAME="anthos-config-management"
export MONITORING_RETENTION_DAYS="30"
```

## Post-Deployment Configuration

### 1. Configure Git Repository

After deployment, set up your GitOps repository:

```bash
# Clone the created configuration repository
gcloud source repos clone ${GIT_REPO_NAME} --project=${PROJECT_ID}
cd ${GIT_REPO_NAME}

# Set up initial configuration structure
mkdir -p config-root/{namespaces,cluster,system}
mkdir -p config-root/namespaces/{production,staging,development}

# Create initial policies and commit
git add .
git commit -m "Initial Anthos Config Management setup"
git push origin master
```

### 2. Deploy Sample Applications

Deploy test applications to validate the service mesh:

```bash
# Apply sample application manifests
kubectl apply -f examples/sample-apps/ --context=gke_${PROJECT_ID}_${ZONE}_prod-cluster

# Verify service mesh injection
kubectl get pods -n production -o jsonpath='{.items[*].spec.containers[*].name}' | grep istio-proxy
```

### 3. Configure Monitoring Dashboards

Set up monitoring dashboards for service mesh observability:

```bash
# Import predefined dashboards
gcloud monitoring dashboards create --config-from-file=monitoring/service-mesh-dashboard.json

# Set up alerting policies
gcloud alpha monitoring policies create --policy-from-file=monitoring/alert-policies.yaml
```

## Validation and Testing

### Verify Cluster Fleet Registration

```bash
# Check fleet membership status
gcloud container fleet memberships list

# Verify service mesh status
gcloud container fleet mesh describe
```

### Test Service Mesh Policies

```bash
# Verify mutual TLS enforcement
kubectl get peerauthentication -A --context=gke_${PROJECT_ID}_${ZONE}_prod-cluster

# Check authorization policies
kubectl get authorizationpolicy -A --context=gke_${PROJECT_ID}_${ZONE}_prod-cluster
```

### Validate Config Management Sync

```bash
# Check sync status
kubectl get configmanagement --context=gke_${PROJECT_ID}_${ZONE}_prod-cluster

# Verify policy enforcement
kubectl get constrainttemplates --context=gke_${PROJECT_ID}_${ZONE}_prod-cluster
```

### Test Binary Authorization

```bash
# Attempt to deploy unsigned image (should fail)
kubectl run test-pod --image=nginx --context=gke_${PROJECT_ID}_${ZONE}_prod-cluster

# Verify policy enforcement in logs
gcloud logging read "resource.type=gke_cluster AND severity=ERROR AND protoPayload.methodName=io.k8s.core.v1.Pod"
```

## Troubleshooting

### Common Issues and Solutions

1. **Service Mesh Installation Failures**
   ```bash
   # Check service mesh status
   gcloud container fleet mesh describe
   
   # Verify cluster registration
   gcloud container fleet memberships list
   ```

2. **Config Management Sync Issues**
   ```bash
   # Check sync errors
   kubectl describe configmanagement config-management
   
   # View sync status
   kubectl get reposyncs -A
   ```

3. **Cross-cluster Communication Problems**
   ```bash
   # Verify network connectivity
   kubectl get endpoints istio-eastwestgateway -n istio-system
   
   # Check DNS resolution
   kubectl exec -it test-pod -- nslookup service-name.namespace.svc.cluster.local
   ```

4. **Binary Authorization Blocks Valid Images**
   ```bash
   # Check attestor status
   gcloud container binauthz attestors list
   
   # Verify policy configuration
   gcloud container binauthz policy export
   ```

### Debug Commands

```bash
# Service mesh debugging
kubectl logs -l app=istiod -n istio-system
kubectl get destinationrules,virtualservices,serviceentries -A

# Config management debugging
kubectl logs -l app=config-management-operator -n config-management-system
kubectl get gitconfigs,reposyncs,rootsyncs -A

# Binary authorization debugging
gcloud logging read "protoPayload.serviceName=binaryauthorization.googleapis.com"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/service-mesh-governance
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```

### Using Bash Scripts

```bash
# Complete cleanup
./scripts/destroy.sh

# Verify resource deletion
gcloud container clusters list
gcloud container fleet memberships list
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud container clusters delete prod-cluster staging-cluster dev-cluster --zone=${ZONE}
gcloud artifacts repositories delete secure-apps --location=${REGION}
gcloud source repos delete ${GIT_REPO_NAME}

# Clean up IAM bindings
gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:service-mesh-admin@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/gkehub.serviceAgent"
```

## Customization

### Adding Additional Clusters

To add more clusters to the fleet:

1. **Infrastructure Manager**: Update the `infrastructure-manager/modules/gke-clusters.yaml` file
2. **Terraform**: Add cluster configuration to `terraform/main.tf`
3. **Scripts**: Modify the cluster creation loop in `scripts/deploy.sh`

### Custom Security Policies

Create custom authorization and network policies:

```yaml
# config-root/cluster/custom-authz-policy.yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: custom-policy
  namespace: production
spec:
  selector:
    matchLabels:
      app: frontend
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/production/sa/authorized-sa"]
  - to:
    - operation:
        methods: ["GET", "POST"]
```

### Environment-Specific Configuration

Customize policies per environment by modifying the GitOps repository structure:

```
config-root/
├── cluster/           # Cluster-wide policies
├── system/           # System configuration
└── namespaces/
    ├── production/   # Production-specific policies
    ├── staging/      # Staging-specific policies
    └── development/  # Development-specific policies
```

## Security Considerations

- **Least Privilege**: All service accounts follow principle of least privilege
- **Network Segmentation**: Network policies enforce traffic isolation
- **Image Security**: Binary Authorization validates container image integrity
- **Audit Logging**: Comprehensive audit trails for all operations
- **Secrets Management**: Use Google Secret Manager for sensitive data
- **Regular Updates**: Keep service mesh and cluster versions current

## Performance Optimization

- **Resource Allocation**: Tune cluster node sizes based on workload requirements
- **Service Mesh Configuration**: Optimize Istio resource limits and requests
- **Monitoring Retention**: Configure appropriate log and metric retention periods
- **Network Policies**: Use efficient network policy rules to minimize overhead

## Support and Documentation

For additional information and troubleshooting:

- [Google Cloud Service Mesh Documentation](https://cloud.google.com/service-mesh/docs)
- [Anthos Config Management Documentation](https://cloud.google.com/anthos-config-management/docs)
- [Binary Authorization Documentation](https://cloud.google.com/binary-authorization/docs)
- [GKE Fleet Management Documentation](https://cloud.google.com/kubernetes-engine/fleet-management/docs)
- [Terraform Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or submit issues to the project repository.