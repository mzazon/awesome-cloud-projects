# Infrastructure as Code for VMware Workload Migration and Modernization with Google Cloud VMware Engine and Migrate to Containers

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Orchestrating VMware Workload Migration and Modernization with Google Cloud VMware Engine and Migrate to Containers".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts for complete automation

## Architecture Overview

This solution implements a comprehensive VMware workload migration and modernization strategy that combines:

- **Google Cloud VMware Engine**: Native VMware environment in Google Cloud for lift-and-shift migrations
- **Migrate to Containers**: Automated containerization of selected workloads
- **Google Kubernetes Engine**: Container orchestration for modernized applications
- **Cloud Operations Suite**: Unified monitoring and logging across hybrid infrastructure

## Prerequisites

### Required Tools
- Google Cloud CLI (gcloud) installed and configured
- Terraform >= 1.0 (for Terraform implementation)
- kubectl for Kubernetes management
- Migrate to Containers CLI
- Docker (for container operations)

### Required Permissions
- VMware Engine Admin (`vmwareengine.admin`)
- Compute Admin (`compute.admin`)
- Container Admin (`container.admin`)
- Artifact Registry Admin (`artifactregistry.admin`)
- Monitoring Admin (`monitoring.admin`)
- Service Usage Admin (`serviceusage.serviceUsageAdmin`)

### Network Requirements
- Network connectivity between on-premises VMware environment and Google Cloud
- VPN or Cloud Interconnect for production deployments
- Firewall rules configured for VMware HCX traffic

### Cost Considerations
- VMware Engine requires minimum 3-node cluster: ~$2,000-5,000/month
- GKE cluster costs: ~$200-500/month depending on node configuration
- Additional costs for networking, storage, and data transfer
- Estimated total monthly cost: $2,500-6,000 for complete solution

## Quick Start

### Using Infrastructure Manager

```bash
# Set project and enable APIs
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable cloudbuild.googleapis.com
gcloud services enable config.googleapis.com

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/vmware-migration \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy complete solution
./scripts/deploy.sh
```

## Deployment Process

### Phase 1: Foundation Setup
1. **Network Infrastructure**: Creates VPC networks and subnets for VMware Engine connectivity
2. **API Enablement**: Enables all required Google Cloud APIs
3. **IAM Configuration**: Sets up service accounts and permissions
4. **Firewall Rules**: Configures security rules for VMware HCX traffic

### Phase 2: VMware Engine Deployment
1. **Private Cloud Creation**: Provisions VMware Engine private cloud with minimum 3-node cluster
2. **vCenter Configuration**: Sets up vCenter Server and NSX-T Data Center
3. **HCX Preparation**: Configures network connectivity for HCX migration
4. **Monitoring Setup**: Enables Cloud Operations monitoring for VMware resources

### Phase 3: Modernization Infrastructure
1. **GKE Cluster**: Creates container orchestration environment
2. **Artifact Registry**: Sets up container image repository
3. **Migrate to Containers**: Installs and configures M2C CLI tools
4. **Workload Analysis**: Prepares assessment framework for containerization

### Phase 4: Operations and Monitoring
1. **Cloud Operations**: Configures comprehensive monitoring dashboards
2. **Alerting Policies**: Sets up proactive alerting for infrastructure health
3. **Logging Integration**: Enables centralized logging across hybrid environment
4. **Cost Monitoring**: Implements cost tracking and optimization alerts

## Configuration Options

### VMware Engine Configuration
- **Node Type**: Standard-72 (default), can be customized based on workload requirements
- **Node Count**: Minimum 3 nodes, can be scaled up for larger workloads
- **Region**: Default us-central1, can be changed for data residency requirements
- **Network Range**: Customizable management network CIDR blocks

### GKE Configuration
- **Node Count**: Default 2 nodes with auto-scaling enabled (1-10 nodes)
- **Machine Type**: Default n1-standard-2, can be customized for workload requirements
- **Kubernetes Version**: Uses latest stable version, can be pinned for consistency
- **Network Policy**: Enabled for enhanced security

### Networking Configuration
- **VPC Network**: Custom VPC with regional subnets
- **Firewall Rules**: Configured for VMware HCX and Kubernetes traffic
- **VPN Gateway**: Optional for on-premises connectivity
- **Load Balancer**: Configured for modernized application access

## Post-Deployment Steps

### VMware Migration Setup
1. **Access vCenter**: Use provided IP address and credentials
2. **Configure HCX**: Set up HCX connector for on-premises connectivity
3. **Network Profiles**: Create network and compute profiles for migration
4. **Service Mesh**: Establish HCX service mesh between sites

### Container Modernization
1. **Install M2C CLI**: Download and configure Migrate to Containers CLI
2. **Workload Assessment**: Analyze VMs for containerization suitability
3. **Migration Plans**: Create migration plans for selected workloads
4. **Container Deployment**: Deploy modernized applications to GKE

### Monitoring Configuration
1. **Dashboard Access**: Navigate to Cloud Monitoring for infrastructure views
2. **Alert Configuration**: Customize alerting policies for your environment
3. **Log Analysis**: Use Cloud Logging for troubleshooting and analysis
4. **Cost Optimization**: Monitor usage and optimize resource allocation

## Validation and Testing

### Infrastructure Validation
```bash
# Check VMware Engine status
gcloud vmware private-clouds list --location=us-central1

# Verify GKE cluster
gcloud container clusters list --region=us-central1

# Test network connectivity
gcloud compute networks describe vmware-network-${RANDOM_SUFFIX}
```

### Application Testing
```bash
# Get GKE credentials
gcloud container clusters get-credentials modernized-apps-cluster --region=us-central1

# Check application deployment
kubectl get deployments,services,pods -n modernized-apps

# Test application connectivity
kubectl port-forward service/modernized-web-app-service 8080:80 -n modernized-apps
```

### Monitoring Validation
```bash
# List monitoring dashboards
gcloud monitoring dashboards list

# Check alerting policies
gcloud alpha monitoring policies list

# View recent logs
gcloud logging read "resource.type=\"vmware_vcenter\" OR resource.type=\"k8s_container\"" --limit=20
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/vmware-migration
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification
```bash
# Verify VMware Engine private cloud deletion
gcloud vmware private-clouds list --location=us-central1

# Verify GKE cluster deletion
gcloud container clusters list --region=us-central1

# Check for remaining resources
gcloud compute networks list --filter="name:vmware-network"
```

## Troubleshooting

### Common Issues

#### VMware Engine Creation Failures
- **Insufficient Quotas**: Check VMware Engine node quotas in your project
- **Network Conflicts**: Ensure IP ranges don't overlap with existing networks
- **Region Availability**: Verify VMware Engine availability in selected region

#### GKE Deployment Issues
- **API Enablement**: Ensure Container API is enabled
- **Service Account Permissions**: Verify GKE service account has required permissions
- **Network Configuration**: Check subnet and firewall rule configurations

#### Migration Connectivity Problems
- **HCX Configuration**: Verify HCX connector setup and network connectivity
- **Firewall Rules**: Check that all required ports are open for HCX traffic
- **DNS Resolution**: Ensure proper DNS configuration for vCenter access

#### Container Deployment Failures
- **Image Pull Errors**: Verify Artifact Registry permissions and authentication
- **Resource Limits**: Check GKE node capacity and pod resource requests
- **Network Policies**: Ensure network policies allow required traffic

### Monitoring and Debugging

#### Infrastructure Monitoring
```bash
# Check VMware Engine metrics
gcloud monitoring metrics list --filter="metric.type:vmware"

# View GKE cluster metrics
gcloud monitoring metrics list --filter="metric.type:kubernetes"

# Check resource utilization
gcloud monitoring metrics list --filter="resource.type:k8s_container"
```

#### Log Analysis
```bash
# VMware Engine logs
gcloud logging read "resource.type=\"vmware_vcenter\"" --limit=50

# GKE cluster logs
gcloud logging read "resource.type=\"k8s_cluster\"" --limit=50

# Application logs
kubectl logs -l app=modernized-web-app -n modernized-apps
```

### Performance Optimization

#### VMware Engine Optimization
- **Right-sizing**: Monitor CPU and memory utilization to optimize node sizing
- **Network Performance**: Configure high-performance networking for critical workloads
- **Storage Optimization**: Use appropriate storage policies for different workload types

#### GKE Optimization
- **Node Auto-scaling**: Configure appropriate min/max node counts
- **Pod Auto-scaling**: Implement HPA for application scaling
- **Resource Requests**: Set appropriate CPU and memory requests/limits

#### Cost Optimization
- **Scheduled Scaling**: Implement time-based scaling for dev/test environments
- **Preemptible Nodes**: Use preemptible instances for fault-tolerant workloads
- **Resource Monitoring**: Set up billing alerts and cost attribution

## Security Considerations

### Network Security
- **VPC Firewall**: Implement least-privilege firewall rules
- **Private Clusters**: Use private GKE clusters for enhanced security
- **VPN/Interconnect**: Secure connectivity for production workloads

### Identity and Access Management
- **Service Accounts**: Use dedicated service accounts with minimal permissions
- **Workload Identity**: Enable workload identity for secure pod authentication
- **RBAC**: Implement Kubernetes RBAC for fine-grained access control

### Data Protection
- **Encryption**: Enable encryption at rest and in transit
- **Backup Strategy**: Implement regular backups for critical data
- **Network Isolation**: Use network policies to isolate workloads

## Support and Documentation

### Additional Resources
- [Google Cloud VMware Engine Documentation](https://cloud.google.com/vmware-engine/docs)
- [Migrate to Containers Documentation](https://cloud.google.com/migrate/containers/docs)
- [Google Kubernetes Engine Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Cloud Operations Suite Documentation](https://cloud.google.com/monitoring/docs)

### Community Support
- [Google Cloud Community](https://cloud.google.com/community)
- [VMware Engine Community](https://cloud.google.com/vmware-engine/docs/community)
- [Kubernetes Community](https://kubernetes.io/community/)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.