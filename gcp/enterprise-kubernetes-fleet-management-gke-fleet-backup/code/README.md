# Infrastructure as Code for Enterprise Kubernetes Fleet Management with GKE Fleet and Backup for GKE

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Kubernetes Fleet Management with GKE Fleet and Backup for GKE".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud account with billing enabled
- gcloud CLI v2 or later installed and configured
- kubectl command-line tool installed
- Appropriate Google Cloud permissions for:
  - Project creation and management
  - GKE cluster management
  - Fleet operations
  - Backup for GKE administration
  - IAM policy management

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Terraform >= 1.0
- Google Cloud Infrastructure Manager API enabled
- `roles/config.admin` IAM permission

#### Terraform
- Terraform >= 1.0
- Google Cloud provider >= 4.0
- `roles/editor` or equivalent permissions

#### Bash Scripts
- bash shell environment
- jq for JSON parsing (optional but recommended)
- openssl for random string generation

### Estimated Costs
- **Development Setup**: $50-100/month
- **Production Fleet**: $200-500/month
- **Backup Storage**: $10-50/month

> **Note**: Costs vary based on cluster size, backup frequency, and retention policies. Use the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for accurate estimates.

## Quick Start

### Using Infrastructure Manager

1. **Enable Infrastructure Manager API**:
   ```bash
   gcloud services enable config.googleapis.com
   ```

2. **Deploy the infrastructure**:
   ```bash
   cd infrastructure-manager/
   
   # Create deployment
   gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/fleet-deployment \
       --service-account="projects/PROJECT_ID/serviceAccounts/SERVICE_ACCOUNT_EMAIL" \
       --local-source="." \
       --inputs-file="terraform.tfvars.example"
   ```

3. **Monitor deployment**:
   ```bash
   gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/fleet-deployment
   ```

### Using Terraform

1. **Initialize Terraform**:
   ```bash
   cd terraform/
   terraform init
   ```

2. **Configure variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Plan and apply**:
   ```bash
   terraform plan
   terraform apply
   ```

4. **Verify deployment**:
   ```bash
   terraform output
   ```

### Using Bash Scripts

1. **Set environment variables**:
   ```bash
   export FLEET_HOST_PROJECT_ID="your-fleet-host-project"
   export WORKLOAD_PROJECT_1="your-prod-project"
   export WORKLOAD_PROJECT_2="your-staging-project"
   export REGION="us-central1"
   ```

2. **Deploy infrastructure**:
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

3. **Verify deployment**:
   ```bash
   # Check fleet status
   gcloud container fleet memberships list
   
   # Check backup plans
   gcloud backup-dr backup-plans list --location=$REGION
   ```

## Architecture Overview

The infrastructure creates:

- **Fleet Host Project**: Central management plane for fleet operations
- **Workload Projects**: Separate projects for production and staging clusters
- **GKE Clusters**: Kubernetes clusters with fleet registration
- **Backup for GKE**: Automated backup plans with scheduling
- **Config Connector**: GitOps-enabled infrastructure management
- **IAM Configuration**: Cross-project permissions and service accounts

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `fleet_host_project_id` | Fleet host project ID | - | Yes |
| `workload_project_1` | Production workload project | - | Yes |
| `workload_project_2` | Staging workload project | - | Yes |
| `region` | Google Cloud region | `us-central1` | No |
| `zone` | Google Cloud zone | `us-central1-a` | No |
| `fleet_name` | Name for the fleet | `enterprise-fleet` | No |

### Cluster Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `prod_cluster_node_count` | Production cluster initial node count | 2 |
| `prod_cluster_machine_type` | Production cluster machine type | `e2-standard-4` |
| `staging_cluster_node_count` | Staging cluster initial node count | 1 |
| `staging_cluster_machine_type` | Staging cluster machine type | `e2-standard-2` |

### Backup Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `backup_schedule_prod` | Production backup schedule (cron) | `0 2 * * *` |
| `backup_schedule_staging` | Staging backup schedule (cron) | `0 3 * * 0` |
| `backup_retain_days_prod` | Production backup retention days | 30 |
| `backup_retain_days_staging` | Staging backup retention days | 14 |

## Validation and Testing

### Post-Deployment Validation

1. **Verify Fleet Registration**:
   ```bash
   gcloud container fleet memberships list
   ```

2. **Check Cluster Status**:
   ```bash
   gcloud container clusters list --format="table(name,status,location)"
   ```

3. **Validate Backup Plans**:
   ```bash
   gcloud backup-dr backup-plans list --location=$REGION
   ```

4. **Test Config Connector**:
   ```bash
   kubectl get configconnector -n cnrm-system
   ```

### Sample Application Deployment

Deploy test applications to validate fleet functionality:

```bash
# Get cluster credentials
gcloud container clusters get-credentials prod-cluster --region=$REGION --project=$WORKLOAD_PROJECT_1

# Deploy sample application
kubectl create namespace test-app
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: test-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
EOF
```

### Backup Testing

Test backup functionality:

```bash
# Trigger manual backup
gcloud backup-dr backups create test-backup-$(date +%s) \
    --location=$REGION \
    --backup-plan=fleet-backup-plan-prod \
    --description="Manual test backup"

# Monitor backup progress
gcloud backup-dr backups list --location=$REGION
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/fleet-deployment
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup Verification

Verify all resources are removed:

```bash
# Check for remaining clusters
gcloud container clusters list

# Check for backup plans
gcloud backup-dr backup-plans list --location=$REGION

# Check for fleet memberships
gcloud container fleet memberships list

# List projects (if created by automation)
gcloud projects list --filter="name:fleet-* OR name:workload-*"
```

## Troubleshooting

### Common Issues

1. **Project Creation Failures**:
   - Verify billing account is attached
   - Check organization policies for project creation
   - Ensure sufficient quota for projects

2. **Cluster Creation Timeout**:
   - Verify compute quotas in target regions
   - Check for conflicting firewall rules
   - Ensure VPC networks have sufficient IP ranges

3. **Fleet Registration Issues**:
   - Verify cross-project IAM permissions
   - Check GKE Hub API enablement
   - Confirm Workload Identity configuration

4. **Backup Plan Failures**:
   - Verify Backup for GKE API is enabled
   - Check service account permissions
   - Confirm cluster has persistent volumes

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:container.googleapis.com OR name:gkehub.googleapis.com OR name:gkebackup.googleapis.com"

# Verify IAM permissions
gcloud projects get-iam-policy $PROJECT_ID

# Check cluster connectivity
kubectl cluster-info

# Debug Config Connector
kubectl logs -n cnrm-system deployment/cnrm-controller-manager
```

### Resource Quotas

Monitor quotas to prevent deployment failures:

```bash
# Check compute quotas
gcloud compute project-info describe --project=$PROJECT_ID

# Check GKE quotas
gcloud container operations list --region=$REGION
```

## Security Considerations

### IAM Best Practices

- **Least Privilege**: Service accounts have minimal required permissions
- **Cross-Project Access**: Limited to fleet management and backup operations
- **Workload Identity**: Enabled for secure pod-to-service authentication
- **Service Account Keys**: Not used; relies on automatic key rotation

### Network Security

- **Private Clusters**: Consider enabling private cluster mode for production
- **Authorized Networks**: Restrict cluster API server access
- **Pod Security**: Implement Pod Security Standards
- **Network Policies**: Configure Kubernetes network policies

### Backup Security

- **Encryption**: Backups encrypted at rest with Google-managed keys
- **Access Control**: Backup access restricted to authorized service accounts
- **Retention**: Automated cleanup based on retention policies
- **Cross-Region**: Consider cross-region backup replication for DR

## Advanced Configurations

### Multi-Region Deployment

Extend the setup for multi-region clusters:

```bash
# Additional regions for cluster deployment
export SECONDARY_REGION="us-west1"
export TERTIARY_REGION="europe-west1"
```

### Custom Backup Policies

Configure environment-specific backup strategies:

```yaml
# Production: Daily backups with 30-day retention
prod_backup_config:
  schedule: "0 2 * * *"
  retention_days: 30
  include_volume_data: true
  include_secrets: true

# Staging: Weekly backups with 14-day retention  
staging_backup_config:
  schedule: "0 3 * * 0"
  retention_days: 14
  include_volume_data: true
  include_secrets: false
```

### Fleet-Wide Policies

Implement organization-wide Kubernetes policies:

```bash
# Enable Policy Controller for all clusters
gcloud container fleet config-management apply \
    --membership=ALL_CLUSTER_MEMBERSHIPS \
    --config=policy-controller-config.yaml
```

## Monitoring and Observability

### Cloud Monitoring Integration

Monitor fleet health and performance:

```bash
# Fleet-wide cluster health dashboard
gcloud monitoring dashboards list --filter="displayName:Fleet"

# Backup success rate metrics
gcloud logging read "resource.type=gke_cluster AND jsonPayload.message=~backup"
```

### Alerting Setup

Configure alerts for critical fleet events:

- Cluster unavailability
- Backup plan failures
- Config drift detection
- Resource quota exhaustion

## Support and Resources

### Documentation
- [GKE Fleet Management](https://cloud.google.com/kubernetes-engine/fleet-management/docs)
- [Backup for GKE](https://cloud.google.com/kubernetes-engine/docs/add-on/backup-for-gke)
- [Config Connector](https://cloud.google.com/config-connector/docs)

### Community
- [Google Cloud Community](https://cloud.google.com/community)
- [Kubernetes Slack](https://kubernetes.slack.com)
- [GKE GitHub](https://github.com/kubernetes/kubernetes)

### Professional Support
For production deployments, consider [Google Cloud Support](https://cloud.google.com/support) for guaranteed response times and expert assistance.

---

**Note**: This infrastructure code implements the complete solution described in the original recipe. For detailed explanations of the architecture and implementation decisions, refer to the recipe documentation.