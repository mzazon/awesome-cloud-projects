#!/bin/bash

# CycleCloud Initialization Script for HPC Environment
# This script configures the CycleCloud server for Azure Managed Lustre integration

set -e

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/cyclecloud-init.log
}

log_message "Starting CycleCloud initialization for HPC environment"

# Update system packages
log_message "Updating system packages"
yum update -y

# Install required packages
log_message "Installing required packages"
yum install -y wget curl git vim jq

# Configure environment variables
export STORAGE_ACCOUNT_NAME="${storage_account_name}"
export STORAGE_ACCOUNT_KEY="${storage_account_key}"
export LUSTRE_MOUNT_IP="${lustre_mount_ip}"
export CLUSTER_NAME="${cluster_name}"

# Create directory for CycleCloud configuration
mkdir -p /opt/cyclecloud/config

# Create Lustre client mount script
log_message "Creating Lustre client mount script"
cat > /opt/cyclecloud/config/lustre-mount.sh << 'EOF'
#!/bin/bash
# Lustre client mount script for HPC nodes

# Install Lustre client packages
yum install -y lustre-client

# Create mount point
mkdir -p /mnt/lustre

# Mount Lustre file system
mount -t lustre ${LUSTRE_MOUNT_IP}@tcp:/lustrefs /mnt/lustre

# Add to fstab for persistent mounting
echo "${LUSTRE_MOUNT_IP}@tcp:/lustrefs /mnt/lustre lustre defaults,_netdev 0 0" >> /etc/fstab

# Set appropriate permissions
chmod 755 /mnt/lustre
chown root:root /mnt/lustre

# Install HPC-specific packages
yum groupinstall -y "Development Tools"
yum install -y openmpi openmpi-devel

# Configure environment for HPC
echo 'export PATH=/usr/lib64/openmpi/bin:$PATH' >> /etc/bashrc
echo 'export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:$LD_LIBRARY_PATH' >> /etc/bashrc

# Configure shared memory for HPC workloads
echo "kernel.shmmax = 68719476736" >> /etc/sysctl.conf
echo "kernel.shmall = 16777216" >> /etc/sysctl.conf
sysctl -p

# Install performance monitoring tools
yum install -y htop iotop sysstat
EOF

# Make the script executable
chmod +x /opt/cyclecloud/config/lustre-mount.sh

# Create cluster template configuration
log_message "Creating cluster template configuration"
cat > /opt/cyclecloud/config/cluster-template.json << EOF
{
  "cluster_name": "${CLUSTER_NAME}",
  "parameters": {
    "Region": "East US",
    "MachineType": "Standard_HB120rs_v3",
    "MaxCoreCount": 480,
    "UseLowPrio": false,
    "ProjectorientedQueues": true,
    "SubnetId": "compute-subnet",
    "InitScript": "/opt/cyclecloud/config/lustre-mount.sh",
    "AdditionalClusterInitSpecs": [
      {
        "Name": "hpc-optimizations",
        "Spec": "cluster-init/hpc-optimizations:1.0.0"
      }
    ]
  }
}
EOF

# Create HPC optimization cluster-init spec
log_message "Creating HPC optimization cluster-init spec"
mkdir -p /opt/cyclecloud/specs/hpc-optimizations/1.0.0
cat > /opt/cyclecloud/specs/hpc-optimizations/1.0.0/cluster-init.sh << 'EOF'
#!/bin/bash
# HPC optimization script for compute nodes

# Configure CPU governor for performance
echo performance > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Disable swap for HPC workloads
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Configure network optimizations
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 87380 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 134217728' >> /etc/sysctl.conf
sysctl -p

# Configure InfiniBand drivers (if available)
if lspci | grep -i infiniband; then
    yum install -y infiniband-diags perftest
    modprobe ib_uverbs
    modprobe rdma_ucm
fi

# Configure Intel MPI optimizations
export I_MPI_FABRICS=shm:tcp
export I_MPI_PIN_PROCESSOR_LIST=0-119
export I_MPI_DEBUG=5

# Install and configure monitoring agents
yum install -y collectd
systemctl enable collectd
systemctl start collectd
EOF

chmod +x /opt/cyclecloud/specs/hpc-optimizations/1.0.0/cluster-init.sh

# Create project.ini for the spec
cat > /opt/cyclecloud/specs/hpc-optimizations/1.0.0/project.ini << 'EOF'
[project]
name = hpc-optimizations
version = 1.0.0
type = application

[spec default]
run_list = recipe[hpc-optimizations::default]
EOF

# Create Chef recipe for HPC optimizations
mkdir -p /opt/cyclecloud/specs/hpc-optimizations/1.0.0/recipes
cat > /opt/cyclecloud/specs/hpc-optimizations/1.0.0/recipes/default.rb << 'EOF'
# HPC optimization Chef recipe

# Install HPC packages
package ['htop', 'iotop', 'sysstat', 'numactl', 'hwloc'] do
  action :install
end

# Configure CPU isolation for HPC workloads
execute 'configure_cpu_isolation' do
  command 'echo "isolcpus=1-119" >> /etc/default/grub'
  not_if 'grep -q "isolcpus" /etc/default/grub'
end

# Configure huge pages for memory optimization
execute 'configure_huge_pages' do
  command 'echo "vm.nr_hugepages = 1024" >> /etc/sysctl.conf'
  not_if 'grep -q "vm.nr_hugepages" /etc/sysctl.conf'
end

# Start and enable performance monitoring
service 'collectd' do
  action [:enable, :start]
end
EOF

# Configure CycleCloud storage account
log_message "Configuring CycleCloud storage account"
cat > /opt/cyclecloud/config/storage-config.json << EOF
{
  "storage_account_name": "${STORAGE_ACCOUNT_NAME}",
  "storage_account_key": "${STORAGE_ACCOUNT_KEY}",
  "container_name": "cyclecloud",
  "blob_endpoint": "https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/"
}
EOF

# Create Azure credentials file
log_message "Creating Azure credentials configuration"
cat > /opt/cyclecloud/config/azure-credentials.json << 'EOF'
{
  "subscription_id": "",
  "tenant_id": "",
  "application_id": "",
  "application_secret": "",
  "resource_group": "",
  "location": "East US"
}
EOF

# Create CycleCloud initialization script
log_message "Creating CycleCloud initialization script"
cat > /opt/cyclecloud/config/initialize-cyclecloud.sh << 'EOF'
#!/bin/bash
# Script to initialize CycleCloud after first boot

# Wait for CycleCloud service to be ready
while ! curl -k https://localhost/cyclecloud/api/account/user > /dev/null 2>&1; do
    echo "Waiting for CycleCloud service to start..."
    sleep 10
done

# Initialize CycleCloud
cyclecloud initialize --batch

# Import cluster template
cyclecloud import_cluster slurm --cluster-name ${CLUSTER_NAME}

# Apply cluster configuration
cyclecloud modify_cluster ${CLUSTER_NAME} --parameter-file /opt/cyclecloud/config/cluster-template.json

echo "CycleCloud initialization completed"
EOF

chmod +x /opt/cyclecloud/config/initialize-cyclecloud.sh

# Create systemd service for CycleCloud initialization
log_message "Creating systemd service for CycleCloud initialization"
cat > /etc/systemd/system/cyclecloud-init.service << 'EOF'
[Unit]
Description=CycleCloud Initialization Service
After=network.target cyclecloud.service
Requires=cyclecloud.service

[Service]
Type=oneshot
User=root
ExecStart=/opt/cyclecloud/config/initialize-cyclecloud.sh
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service (will run on first boot)
systemctl daemon-reload
systemctl enable cyclecloud-init.service

# Configure firewall for CycleCloud
log_message "Configuring firewall for CycleCloud"
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=443/tcp
    firewall-cmd --permanent --add-port=9443/tcp
    firewall-cmd --reload
fi

# Set up log rotation for CycleCloud logs
log_message "Setting up log rotation"
cat > /etc/logrotate.d/cyclecloud << 'EOF'
/var/log/cyclecloud-init.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

# Create motd with helpful information
log_message "Creating message of the day"
cat > /etc/motd << 'EOF'
================================================================================
                        Azure CycleCloud HPC Environment
================================================================================

Welcome to your CycleCloud HPC management server!

Quick Start Commands:
  - Initialize CycleCloud:     cyclecloud initialize --batch
  - Create cluster:           cyclecloud create_cluster slurm <cluster-name>
  - Start cluster:            cyclecloud start_cluster <cluster-name>
  - Monitor cluster:          cyclecloud show_cluster <cluster-name>

Web Interface:
  - Access at: https://<public-ip>
  - Default credentials will be set during initialization

Important Directories:
  - Configuration: /opt/cyclecloud/config/
  - Logs: /var/log/cyclecloud-init.log
  - Specs: /opt/cyclecloud/specs/

For support, refer to Azure CycleCloud documentation.
================================================================================
EOF

# Create helper script for cluster management
log_message "Creating helper script for cluster management"
cat > /usr/local/bin/hpc-cluster-helper << 'EOF'
#!/bin/bash
# Helper script for common HPC cluster operations

case "$1" in
    "status")
        echo "Cluster Status:"
        cyclecloud show_cluster ${CLUSTER_NAME}
        ;;
    "start")
        echo "Starting cluster: ${CLUSTER_NAME}"
        cyclecloud start_cluster ${CLUSTER_NAME}
        ;;
    "stop")
        echo "Stopping cluster: ${CLUSTER_NAME}"
        cyclecloud terminate_cluster ${CLUSTER_NAME}
        ;;
    "nodes")
        echo "Cluster Nodes:"
        cyclecloud show_nodes ${CLUSTER_NAME}
        ;;
    "queue")
        echo "Job Queue Status:"
        if command -v squeue >/dev/null 2>&1; then
            squeue
        else
            echo "Connect to head node to view queue status"
        fi
        ;;
    "lustre")
        echo "Lustre Mount Information:"
        echo "Mount IP: ${LUSTRE_MOUNT_IP}"
        echo "Mount command: sudo mount -t lustre ${LUSTRE_MOUNT_IP}@tcp:/lustrefs /mnt/lustre"
        ;;
    *)
        echo "Usage: $0 {status|start|stop|nodes|queue|lustre}"
        echo "  status  - Show cluster status"
        echo "  start   - Start the cluster"
        echo "  stop    - Stop the cluster"
        echo "  nodes   - Show cluster nodes"
        echo "  queue   - Show job queue status"
        echo "  lustre  - Show Lustre mount information"
        ;;
esac
EOF

chmod +x /usr/local/bin/hpc-cluster-helper

# Set permissions on configuration files
chown -R root:root /opt/cyclecloud/config/
chmod -R 755 /opt/cyclecloud/config/
chmod 600 /opt/cyclecloud/config/azure-credentials.json
chmod 600 /opt/cyclecloud/config/storage-config.json

log_message "CycleCloud initialization script completed successfully"

# Create completion marker
touch /var/log/cyclecloud-init-complete

log_message "CycleCloud server is ready for configuration"
echo "CycleCloud initialization completed at $(date)" >> /var/log/cyclecloud-init.log