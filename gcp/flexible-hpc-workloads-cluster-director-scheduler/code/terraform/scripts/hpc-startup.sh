#!/bin/bash
# HPC Compute Node Startup Script
# This script configures HPC compute instances with optimized settings

set -euo pipefail

# Variables passed from Terraform
BUCKET_NAME="${bucket_name}"
PROJECT_ID="${project_id}"

# Logging setup
LOG_FILE="/var/log/hpc-startup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "Starting HPC compute node configuration at $(date)"

# Update system packages
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install essential HPC tools
echo "Installing HPC development tools..."
apt-get install -y \
    build-essential \
    gfortran \
    cmake \
    git \
    wget \
    curl \
    vim \
    htop \
    iotop \
    stress-ng \
    sysstat \
    numactl \
    hwloc \
    python3 \
    python3-pip \
    python3-dev \
    libblas-dev \
    liblapack-dev \
    libhdf5-dev \
    libnetcdf-dev \
    openmpi-bin \
    openmpi-common \
    libopenmpi-dev \
    nfs-common

# Install Python scientific packages
echo "Installing Python scientific computing packages..."
pip3 install --upgrade \
    numpy \
    scipy \
    matplotlib \
    pandas \
    scikit-learn \
    h5py \
    netcdf4 \
    mpi4py \
    dask \
    xarray

# Configure Cloud Storage access
echo "Configuring Cloud Storage access..."
# Mount bucket using gcsfuse
apt-get install -y gcsfuse
mkdir -p /mnt/hpc-data
echo "$BUCKET_NAME /mnt/hpc-data gcsfuse rw,user,allow_other" >> /etc/fstab

# Create gcsfuse mount with proper permissions
gcsfuse --implicit-dirs "$BUCKET_NAME" /mnt/hpc-data

# Set up environment variables for HPC
echo "Configuring HPC environment..."
cat >> /etc/environment << EOF
# HPC Environment Variables
export OMP_NUM_THREADS=\$(nproc)
export MKL_NUM_THREADS=\$(nproc)
export OPENBLAS_NUM_THREADS=\$(nproc)
export HPC_DATA_PATH=/mnt/hpc-data
export PROJECT_ID=$PROJECT_ID
export BUCKET_NAME=$BUCKET_NAME
EOF

# Configure system optimization for HPC workloads
echo "Applying HPC system optimizations..."

# Disable swap for better performance
swapoff -a
sed -i '/swap/d' /etc/fstab

# Configure kernel parameters for HPC
cat >> /etc/sysctl.conf << EOF
# HPC Kernel Optimizations
vm.swappiness=1
vm.dirty_ratio=15
vm.dirty_background_ratio=5
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.netdev_max_backlog=5000
EOF

sysctl -p

# Configure CPU governor for performance
echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Disable CPU frequency scaling for consistent performance
systemctl disable ondemand
systemctl disable cpufrequtils

# Configure hugepages for better memory performance
echo 'vm.nr_hugepages=1024' >> /etc/sysctl.conf
echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag

# Set up monitoring agents
echo "Installing monitoring agents..."

# Install Google Cloud Ops Agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install

# Configure custom metrics collection
cat > /etc/google-cloud-ops-agent/config.yaml << EOF
metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
  processors:
    batch:
      timeout: 1s
      send_batch_size: 50
  exporters:
    google_cloud_monitoring:
      type: google_cloud_monitoring
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
        processors: [batch]
        exporters: [google_cloud_monitoring]

logging:
  receivers:
    files:
      type: files
      include_paths:
        - /var/log/hpc-startup.log
        - /var/log/hpc-workload.log
      exclude_paths:
        - /var/log/google-cloud-ops-agent*
  exporters:
    google_cloud_logging:
      type: google_cloud_logging
  service:
    pipelines:
      default_pipeline:
        receivers: [files]
        exporters: [google_cloud_logging]
EOF

systemctl restart google-cloud-ops-agent

# Create working directories
echo "Setting up working directories..."
mkdir -p /home/shared/workspace
mkdir -p /home/shared/data
mkdir -p /home/shared/results
chmod 755 /home/shared/workspace
chmod 755 /home/shared/data
chmod 755 /home/shared/results

# Set up symbolic links to mounted storage
ln -sf /mnt/hpc-data /home/shared/data/hpc-data

# Install Intel MKL for optimized mathematical operations
echo "Installing Intel Math Kernel Library..."
wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | apt-key add -
echo "deb https://apt.repos.intel.com/mkl all main" > /etc/apt/sources.list.d/intel-mkl.list
apt-get update
apt-get install -y intel-mkl-64bit-2020.4-912

# Set up MKL environment
echo "source /opt/intel/mkl/bin/mklvars.sh intel64" >> /etc/bash.bashrc

# Configure automatic cleanup of temporary files
echo "Setting up automatic cleanup..."
cat > /etc/cron.daily/hpc-cleanup << 'EOF'
#!/bin/bash
# Clean up temporary files and logs older than 7 days
find /tmp -type f -mtime +7 -delete 2>/dev/null || true
find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null || true
find /home/shared/workspace -name "*.tmp" -mtime +3 -delete 2>/dev/null || true
EOF

chmod +x /etc/cron.daily/hpc-cleanup

# Create HPC utility scripts
echo "Creating HPC utility scripts..."
cat > /usr/local/bin/hpc-info << 'EOF'
#!/bin/bash
# Display HPC node information
echo "=== HPC Node Information ==="
echo "Hostname: $(hostname)"
echo "CPU Info: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "CPU Cores: $(nproc)"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "Storage Mount: $(df -h /mnt/hpc-data | tail -1 | awk '{print $2, $3, $4, $5}')"
echo "Network Interfaces:"
ip -o -4 addr show | awk '{print $2, $4}'
echo "=== System Load ==="
uptime
echo "=== Memory Usage ==="
free -h
echo "=== Disk Usage ==="
df -h
EOF

chmod +x /usr/local/bin/hpc-info

cat > /usr/local/bin/hpc-benchmark << 'EOF'
#!/bin/bash
# Simple HPC benchmark script
echo "Running HPC benchmarks..."
echo "=== CPU Benchmark ==="
stress-ng --cpu $(nproc) --timeout 30s --metrics-brief
echo "=== Memory Bandwidth Test ==="
stress-ng --stream $(nproc) --timeout 30s --metrics-brief
echo "=== Disk I/O Test ==="
stress-ng --hdd 1 --hdd-bytes 1G --timeout 30s --metrics-brief
EOF

chmod +x /usr/local/bin/hpc-benchmark

# Configure SSH for passwordless communication between nodes
echo "Configuring SSH for cluster communication..."
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config
systemctl restart sshd

# Set up firewall rules for HPC communication
echo "Configuring firewall for HPC communication..."
ufw allow ssh
ufw allow from 10.0.0.0/8
ufw --force enable

# Create startup complete marker
echo "HPC compute node configuration completed at $(date)" | tee /tmp/hpc-startup-complete

# Send startup notification to Cloud Logging
gcloud logging write hpc-startup \
  '{"message": "HPC compute node startup completed", "instance": "'$(hostname)'", "timestamp": "'$(date -Is)'"}' \
  --severity=INFO

echo "HPC compute node startup script completed successfully"