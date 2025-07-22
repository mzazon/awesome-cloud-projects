#!/bin/bash

# AWS Application Migration Service - Deployment Script
# This script deploys the infrastructure for large-scale server migration using AWS MGN

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DEPLOYMENT_NAME="mgn-migration-$(date +%Y%m%d-%H%M%S)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    cleanup_on_error
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Cleanup function for errors
cleanup_on_error() {
    warning "Deployment failed. Cleaning up partial resources..."
    # Add cleanup logic here if needed
}

# Prerequisites check function
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2.13.0 or later."
    fi
    
    # Check AWS CLI version
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: ${AWS_VERSION}"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not authenticated. Please run 'aws configure' or set appropriate credentials."
    fi
    
    # Check if required tools are available
    if ! command -v curl &> /dev/null; then
        error_exit "curl is not installed. Please install curl."
    fi
    
    # Check if python3 is available (needed for MGN agent)
    if ! command -v python3 &> /dev/null; then
        warning "python3 is not installed. This will be needed for MGN agent installation on source servers."
    fi
    
    success "Prerequisites check completed"
}

# Environment setup function
setup_environment() {
    info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    if [ -z "${AWS_REGION}" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured. Using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export MGN_SERVICE_ROLE_NAME="MGNServiceRole-${RANDOM_SUFFIX}"
    export MGN_REPLICATION_SETTINGS_TEMPLATE="MGNReplicationTemplate-${RANDOM_SUFFIX}"
    export MGN_LAUNCH_TEMPLATE="MGNLaunchTemplate-${RANDOM_SUFFIX}"
    
    # Create environment file for cleanup
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
MGN_SERVICE_ROLE_NAME=${MGN_SERVICE_ROLE_NAME}
MGN_REPLICATION_SETTINGS_TEMPLATE=${MGN_REPLICATION_SETTINGS_TEMPLATE}
MGN_LAUNCH_TEMPLATE=${MGN_LAUNCH_TEMPLATE}
DEPLOYMENT_NAME=${DEPLOYMENT_NAME}
EOF
    
    success "Environment setup completed"
    info "AWS Region: ${AWS_REGION}"
    info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "Deployment Name: ${DEPLOYMENT_NAME}"
}

# IAM role creation function
create_iam_role() {
    info "Creating IAM service role for MGN..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${MGN_SERVICE_ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${MGN_SERVICE_ROLE_NAME} already exists. Skipping creation."
        return 0
    fi
    
    # Create IAM service role
    aws iam create-role \
        --role-name "${MGN_SERVICE_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "mgn.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --tags Key=DeploymentName,Value="${DEPLOYMENT_NAME}" \
              Key=Purpose,Value="MGN-Service-Role" \
              Key=CreatedBy,Value="MGN-Deploy-Script" > /dev/null
    
    # Attach managed policy to service role
    aws iam attach-role-policy \
        --role-name "${MGN_SERVICE_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/AWSApplicationMigrationServiceRolePolicy"
    
    success "Created IAM service role: ${MGN_SERVICE_ROLE_NAME}"
}

# MGN service initialization function
initialize_mgn_service() {
    info "Initializing AWS Application Migration Service..."
    
    # Check if MGN is already initialized
    if aws mgn describe-replication-configuration-templates --region "${AWS_REGION}" &> /dev/null; then
        warning "MGN service appears to be already initialized in region ${AWS_REGION}"
        return 0
    fi
    
    # Initialize MGN service
    aws mgn initialize-service --region "${AWS_REGION}" > /dev/null || {
        warning "MGN service initialization may have already been completed"
    }
    
    # Wait for initialization to complete
    info "Waiting for MGN service initialization to complete..."
    local attempts=0
    local max_attempts=30
    
    while [ $attempts -lt $max_attempts ]; do
        if aws mgn describe-replication-configuration-templates --region "${AWS_REGION}" &> /dev/null; then
            success "MGN service initialized successfully"
            return 0
        fi
        
        attempts=$((attempts + 1))
        info "Waiting for initialization... (${attempts}/${max_attempts})"
        sleep 10
    done
    
    error_exit "MGN service initialization timed out after ${max_attempts} attempts"
}

# Replication configuration function
configure_replication() {
    info "Configuring replication settings..."
    
    # Get default VPC and subnet (or use existing ones)
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text --region "${AWS_REGION}" 2>/dev/null || echo "")
    
    if [ -z "${VPC_ID}" ] || [ "${VPC_ID}" == "None" ]; then
        warning "No default VPC found. Using empty subnet ID - MGN will use default configuration."
        SUBNET_ID=""
    else
        SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'Subnets[0].SubnetId' --output text --region "${AWS_REGION}" 2>/dev/null || echo "")
    fi
    
    # Create replication configuration template
    TEMPLATE_ID=$(aws mgn create-replication-configuration-template \
        --associate-default-security-group true \
        --bandwidth-throttling 0 \
        --create-public-ip false \
        --data-plane-routing "PRIVATE_IP" \
        --default-large-staging-disk-type "GP3" \
        --ebs-encryption "DEFAULT" \
        --replication-server-instance-type "t3.small" \
        --staging-area-subnet-id "${SUBNET_ID}" \
        --staging-area-tags Environment=Migration,Purpose=MGN-Staging,DeploymentName="${DEPLOYMENT_NAME}" \
        --use-dedicated-replication-server false \
        --tags DeploymentName="${DEPLOYMENT_NAME}",Purpose="MGN-Replication-Template" \
        --region "${AWS_REGION}" \
        --query 'replicationConfigurationTemplateID' --output text)
    
    if [ -z "${TEMPLATE_ID}" ] || [ "${TEMPLATE_ID}" == "None" ]; then
        error_exit "Failed to create replication configuration template"
    fi
    
    # Update environment file with template ID
    echo "MGN_REPLICATION_TEMPLATE_ID=${TEMPLATE_ID}" >> "${SCRIPT_DIR}/.env"
    
    success "Created replication configuration template: ${TEMPLATE_ID}"
}

# Download MGN agent function
download_mgn_agent() {
    info "Downloading MGN agent installation script..."
    
    local agent_dir="${SCRIPT_DIR}/mgn-agent"
    mkdir -p "${agent_dir}"
    
    # Download Linux agent
    if curl -s -o "${agent_dir}/aws-replication-installer-init.py" \
        "https://aws-application-migration-service-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/latest/linux/aws-replication-installer-init.py"; then
        success "Downloaded Linux MGN agent installer"
    else
        error_exit "Failed to download Linux MGN agent installer"
    fi
    
    # Create installation script for Linux servers
    cat > "${agent_dir}/install-mgn-agent.sh" << 'EOF'
#!/bin/bash

# MGN Agent Installation Script
# This script should be run on each source server to be migrated

set -e

# Check parameters
if [ $# -ne 3 ]; then
    echo "Usage: $0 <AWS_REGION> <ACCESS_KEY_ID> <SECRET_ACCESS_KEY>"
    exit 1
fi

AWS_REGION=$1
ACCESS_KEY_ID=$2
SECRET_ACCESS_KEY=$3

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    echo "python3 is not installed. Please install python3 first."
    exit 1
fi

# Install agent
echo "Installing MGN agent on $(hostname)..."
python3 aws-replication-installer-init.py \
    --region "${AWS_REGION}" \
    --aws-access-key-id "${ACCESS_KEY_ID}" \
    --aws-secret-access-key "${SECRET_ACCESS_KEY}" \
    --no-prompt

# Start and enable replication service
systemctl start aws-replication-agent
systemctl enable aws-replication-agent

echo "MGN agent installed and started on $(hostname)"
echo "Replication will begin automatically"
EOF
    
    chmod +x "${agent_dir}/install-mgn-agent.sh"
    
    # Create Windows installation instructions
    cat > "${agent_dir}/windows-installation.txt" << EOF
Windows MGN Agent Installation Instructions:

1. Download the Windows installer from:
   https://aws-application-migration-service-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/latest/windows/AwsReplicationWindowsInstaller.exe

2. Run the installer as Administrator with these parameters:
   AwsReplicationWindowsInstaller.exe --region ${AWS_REGION} --aws-access-key-id <YOUR_ACCESS_KEY> --aws-secret-access-key <YOUR_SECRET_KEY> --no-prompt

3. The service will start automatically after installation

Note: Replace <YOUR_ACCESS_KEY> and <YOUR_SECRET_KEY> with appropriate IAM credentials that have MGN permissions.
EOF
    
    success "Created MGN agent installation files in: ${agent_dir}"
    info "Agent installation files available at: ${agent_dir}"
}

# Create migration wave function
create_migration_wave() {
    info "Creating migration wave template..."
    
    # Create a sample migration wave
    WAVE_ID=$(aws mgn create-wave \
        --name "Production-Migration-Wave-1" \
        --description "First wave of production server migration" \
        --tags DeploymentName="${DEPLOYMENT_NAME}",Purpose="MGN-Migration-Wave" \
        --region "${AWS_REGION}" \
        --query 'waveID' --output text 2>/dev/null || echo "")
    
    if [ -n "${WAVE_ID}" ] && [ "${WAVE_ID}" != "None" ]; then
        echo "MGN_WAVE_ID=${WAVE_ID}" >> "${SCRIPT_DIR}/.env"
        success "Created migration wave: ${WAVE_ID}"
    else
        warning "Could not create migration wave (this is optional)"
    fi
}

# Generate post-deployment instructions
generate_instructions() {
    info "Generating post-deployment instructions..."
    
    cat > "${SCRIPT_DIR}/post-deployment-instructions.md" << EOF
# AWS Application Migration Service - Post-Deployment Instructions

## Deployment Summary
- **Deployment Name**: ${DEPLOYMENT_NAME}
- **AWS Region**: ${AWS_REGION}
- **AWS Account ID**: ${AWS_ACCOUNT_ID}
- **Service Role**: ${MGN_SERVICE_ROLE_NAME}

## Next Steps

### 1. Install MGN Agent on Source Servers

**For Linux Servers:**
1. Copy the agent installation files to your source servers:
   - \`mgn-agent/aws-replication-installer-init.py\`
   - \`mgn-agent/install-mgn-agent.sh\`

2. On each source server, run:
   \`\`\`bash
   sudo ./install-mgn-agent.sh ${AWS_REGION} <ACCESS_KEY> <SECRET_KEY>
   \`\`\`

**For Windows Servers:**
- Follow the instructions in \`mgn-agent/windows-installation.txt\`

### 2. Monitor Source Server Discovery

Check the MGN console or use AWS CLI to monitor server discovery:

\`\`\`bash
aws mgn describe-source-servers --region ${AWS_REGION} --query 'items[*].{ServerID:sourceServerID,Hostname:sourceProperties.identificationHints.hostname,Status:dataReplicationInfo.dataReplicationState}'
\`\`\`

### 3. Configure Launch Templates

For each discovered server, configure launch settings:

\`\`\`bash
# Get server ID from discovery
SERVER_ID="s-xxxxxxxxx"

# Configure launch template
aws mgn put-launch-configuration --source-server-id \$SERVER_ID --launch-configuration '{
    "bootMode": "BIOS",
    "copyPrivateIp": false,
    "copyTags": true,
    "launchDisposition": "STARTED",
    "licensing": {"osByol": true},
    "name": "MGN-Launch-Config",
    "targetInstanceTypeRightSizingMethod": "BASIC"
}'
\`\`\`

### 4. Test Migration

Launch test instances to validate applications:

\`\`\`bash
aws mgn start-test --source-server-ids \$SERVER_ID --region ${AWS_REGION}
\`\`\`

### 5. Production Cutover

After successful testing, perform production cutover:

\`\`\`bash
aws mgn start-cutover --source-server-ids \$SERVER_ID --region ${AWS_REGION}
\`\`\`

## Important Notes

- **Cost Management**: Monitor replication costs and server instance usage
- **Network Configuration**: Ensure proper security group and network ACL configuration
- **Backup Strategy**: Maintain backups of source servers during migration
- **Testing**: Thoroughly test all applications before production cutover
- **Documentation**: Document any custom configurations or dependencies

## Monitoring and Troubleshooting

### View Replication Status
\`\`\`bash
aws mgn describe-source-servers --region ${AWS_REGION}
\`\`\`

### View Migration Events
\`\`\`bash
aws mgn describe-job-log-items --job-id <JOB_ID> --region ${AWS_REGION}
\`\`\`

### MGN Console
Access the MGN console at: https://${AWS_REGION}.console.aws.amazon.com/mgn/home?region=${AWS_REGION}

## Cleanup
To clean up the deployment, run:
\`\`\`bash
./destroy.sh
\`\`\`

## Support Resources
- [AWS Application Migration Service User Guide](https://docs.aws.amazon.com/mgn/latest/ug/)
- [MGN Best Practices](https://docs.aws.amazon.com/mgn/latest/ug/best-practices.html)
- [AWS Migration Hub](https://aws.amazon.com/migration-hub/)
EOF
    
    success "Generated post-deployment instructions: ${SCRIPT_DIR}/post-deployment-instructions.md"
}

# Main deployment function
main() {
    # Initialize logging
    echo "Starting AWS Application Migration Service deployment at $(date)" > "${LOG_FILE}"
    
    info "Starting AWS Application Migration Service deployment..."
    info "Deployment name: ${DEPLOYMENT_NAME}"
    info "Log file: ${LOG_FILE}"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_iam_role
    initialize_mgn_service
    configure_replication
    download_mgn_agent
    create_migration_wave
    generate_instructions
    
    success "Deployment completed successfully!"
    info "View post-deployment instructions: ${SCRIPT_DIR}/post-deployment-instructions.md"
    info "MGN agent installation files: ${SCRIPT_DIR}/mgn-agent/"
    info "Environment configuration saved to: ${SCRIPT_DIR}/.env"
    
    warning "IMPORTANT: Install MGN agents on source servers to begin migration"
    warning "Estimated monthly cost: \$50-200 per server during migration"
    
    return 0
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi