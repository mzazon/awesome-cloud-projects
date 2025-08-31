#!/bin/bash
# GPU Compute Node Startup Script
# This script configures GPU compute instances with NVIDIA drivers and CUDA

set -euo pipefail

# Variables passed from Terraform
BUCKET_NAME="${bucket_name}"
PROJECT_ID="${project_id}"

# Logging setup
LOG_FILE="/var/log/gpu-startup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "Starting GPU compute node configuration at $(date)"

# Update system packages
echo "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install essential development tools
echo "Installing development tools and dependencies..."
apt-get install -y \
    build-essential \
    dkms \
    wget \
    curl \
    git \
    vim \
    htop \
    nvtop \
    stress-ng \
    python3 \
    python3-pip \
    python3-dev \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release

# Install NVIDIA drivers (if not already installed)
echo "Installing NVIDIA drivers..."
# Check if drivers are already installed
if ! nvidia-smi &> /dev/null; then
    echo "Installing NVIDIA driver..."
    # Add NVIDIA driver repository
    add-apt-repository ppa:graphics-drivers/ppa -y
    apt-get update
    
    # Install the latest NVIDIA driver
    apt-get install -y nvidia-driver-535
    
    # Verify installation will happen after reboot
    echo "NVIDIA driver installed, will be available after reboot"
else
    echo "NVIDIA drivers already installed"
    nvidia-smi
fi

# Install CUDA Toolkit
echo "Installing CUDA Toolkit..."
if ! nvcc --version &> /dev/null; then
    # Add NVIDIA CUDA repository
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
    dpkg -i cuda-keyring_1.0-1_all.deb
    apt-get update
    
    # Install CUDA toolkit
    apt-get install -y cuda-toolkit-12-3
    
    # Set up CUDA environment variables
    echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /etc/environment
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /etc/environment
    echo 'export CUDA_HOME=/usr/local/cuda' >> /etc/environment
    
    # Update current session
    export PATH=/usr/local/cuda/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH
    export CUDA_HOME=/usr/local/cuda
else
    echo "CUDA Toolkit already installed"
    nvcc --version
fi

# Install cuDNN
echo "Installing cuDNN..."
if [ ! -f /usr/local/cuda/include/cudnn.h ]; then
    # Install cuDNN (this requires manual download, so we'll use the package manager version)
    apt-get install -y libcudnn8 libcudnn8-dev
    echo "cuDNN installed from package manager"
else
    echo "cuDNN already installed"
fi

# Install Docker for containerized GPU workloads
echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Install NVIDIA Container Toolkit
echo "Installing NVIDIA Container Toolkit..."
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
apt-get update
apt-get install -y nvidia-container-toolkit

# Configure Docker to use NVIDIA runtime
systemctl restart docker
systemctl enable docker

# Add docker group for non-root access
groupadd -f docker
usermod -aG docker google-sudoers

# Install Python ML/AI packages
echo "Installing Python GPU computing packages..."
pip3 install --upgrade \
    numpy \
    scipy \
    matplotlib \
    pandas \
    scikit-learn \
    jupyter \
    jupyterlab \
    tensorflow \
    torch \
    torchvision \
    torchaudio \
    transformers \
    accelerate \
    datasets \
    evaluate \
    diffusers \
    xgboost \
    lightgbm \
    optuna \
    ray \
    dask \
    cupy-cuda12x \
    numba \
    pycuda

# Configure Cloud Storage access
echo "Configuring Cloud Storage access..."
apt-get install -y gcsfuse
mkdir -p /mnt/hpc-data
echo "$BUCKET_NAME /mnt/hpc-data gcsfuse rw,user,allow_other" >> /etc/fstab

# Create gcsfuse mount with proper permissions
gcsfuse --implicit-dirs "$BUCKET_NAME" /mnt/hpc-data

# Set up GPU-specific environment variables
echo "Configuring GPU environment..."
cat >> /etc/environment << EOF
# GPU Environment Variables
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:\$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,utility
export HPC_DATA_PATH=/mnt/hpc-data
export PROJECT_ID=$PROJECT_ID
export BUCKET_NAME=$BUCKET_NAME
# TensorFlow GPU memory growth
export TF_FORCE_GPU_ALLOW_GROWTH=true
# PyTorch CUDA memory management
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128
EOF

# Configure system optimization for GPU workloads
echo "Applying GPU system optimizations..."

# Disable swap for better performance
swapoff -a
sed -i '/swap/d' /etc/fstab

# Configure kernel parameters for GPU workloads
cat >> /etc/sysctl.conf << EOF
# GPU Workload Kernel Optimizations
vm.swappiness=1
vm.dirty_ratio=15
vm.dirty_background_ratio=5
# Increase shared memory for GPU applications
kernel.shmmax=68719476736
kernel.shmall=4294967296
EOF

sysctl -p

# Configure CPU governor for performance
echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Set up GPU monitoring
echo "Installing GPU monitoring tools..."

# Install Google Cloud Ops Agent with GPU metrics
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install

# Configure GPU metrics collection
cat > /etc/google-cloud-ops-agent/config.yaml << EOF
metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
    nvidia_gpu:
      type: nvidia_gpu
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
        receivers: [hostmetrics, nvidia_gpu]
        processors: [batch]
        exporters: [google_cloud_monitoring]

logging:
  receivers:
    files:
      type: files
      include_paths:
        - /var/log/gpu-startup.log
        - /var/log/gpu-workload.log
        - /var/log/nvidia-installer.log
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

# Create GPU-specific working directories
echo "Setting up GPU working directories..."
mkdir -p /home/shared/gpu-workspace
mkdir -p /home/shared/models
mkdir -p /home/shared/datasets
mkdir -p /home/shared/checkpoints
chmod 755 /home/shared/gpu-workspace
chmod 755 /home/shared/models
chmod 755 /home/shared/datasets
chmod 755 /home/shared/checkpoints

# Set up symbolic links to mounted storage
ln -sf /mnt/hpc-data /home/shared/datasets/hpc-data

# Create GPU utility scripts
echo "Creating GPU utility scripts..."
cat > /usr/local/bin/gpu-info << 'EOF'
#!/bin/bash
# Display GPU node information
echo "=== GPU Node Information ==="
echo "Hostname: $(hostname)"
echo "CPU Info: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "CPU Cores: $(nproc)"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "=== GPU Information ==="
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,temperature.gpu,utilization.gpu --format=csv,noheader,nounits
else
    echo "NVIDIA drivers not available or GPU not detected"
fi
echo "=== CUDA Version ==="
if command -v nvcc &> /dev/null; then
    nvcc --version | grep "release"
else
    echo "CUDA not installed or not in PATH"
fi
echo "=== System Load ==="
uptime
echo "=== Memory Usage ==="
free -h
echo "=== Disk Usage ==="
df -h
EOF

chmod +x /usr/local/bin/gpu-info

cat > /usr/local/bin/gpu-benchmark << 'EOF'
#!/bin/bash
# GPU benchmark script
echo "Running GPU benchmarks..."

if command -v nvidia-smi &> /dev/null; then
    echo "=== GPU Status ==="
    nvidia-smi
    
    echo "=== GPU Memory Test ==="
    python3 -c "
import torch
if torch.cuda.is_available():
    device = torch.cuda.get_device_name(0)
    memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
    print(f'GPU Device: {device}')
    print(f'GPU Memory: {memory:.2f} GB')
    
    # Simple tensor operations benchmark
    x = torch.randn(10000, 10000).cuda()
    y = torch.randn(10000, 10000).cuda()
    print('Running matrix multiplication benchmark...')
    import time
    start = time.time()
    for i in range(10):
        z = torch.mm(x, y)
    torch.cuda.synchronize()
    end = time.time()
    print(f'10 matrix multiplications took {end-start:.2f} seconds')
else:
    print('CUDA not available')
"
else
    echo "NVIDIA drivers not available"
fi

echo "=== CPU Benchmark ==="
stress-ng --cpu $(nproc) --timeout 30s --metrics-brief
EOF

chmod +x /usr/local/bin/gpu-benchmark

cat > /usr/local/bin/gpu-monitor << 'EOF'
#!/bin/bash
# Continuous GPU monitoring
if command -v nvidia-smi &> /dev/null; then
    watch -n 1 'nvidia-smi && echo && echo "=== GPU Memory Usage ===" && nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits'
else
    echo "NVIDIA drivers not available"
fi
EOF

chmod +x /usr/local/bin/gpu-monitor

# Configure Jupyter Lab for GPU development
echo "Setting up Jupyter Lab for GPU development..."
pip3 install jupyterlab-nvdashboard

# Create Jupyter config
mkdir -p /etc/jupyter
cat > /etc/jupyter/jupyter_notebook_config.py << EOF
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.token = ''
c.NotebookApp.password = ''
c.NotebookApp.allow_root = True
c.NotebookApp.notebook_dir = '/home/shared/gpu-workspace'
EOF

# Create systemd service for Jupyter Lab
cat > /etc/systemd/system/jupyterlab.service << EOF
[Unit]
Description=Jupyter Lab
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/shared/gpu-workspace
Environment="PATH=/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="LD_LIBRARY_PATH=/usr/local/cuda/lib64"
ExecStart=/usr/local/bin/jupyter-lab --config=/etc/jupyter/jupyter_notebook_config.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable but don't start Jupyter Lab (can be started manually)
systemctl daemon-reload
systemctl enable jupyterlab

# Set up automatic cleanup of GPU cache
echo "Setting up GPU cache cleanup..."
cat > /etc/cron.daily/gpu-cleanup << 'EOF'
#!/bin/bash
# Clean up GPU cache and temporary files
# Clear PyTorch cache
python3 -c "import torch; torch.cuda.empty_cache()" 2>/dev/null || true
# Clean up temporary files
find /tmp -type f -mtime +7 -delete 2>/dev/null || true
find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null || true
find /home/shared/gpu-workspace -name "*.tmp" -mtime +3 -delete 2>/dev/null || true
find /home/shared/checkpoints -name "*.tmp" -mtime +7 -delete 2>/dev/null || true
EOF

chmod +x /etc/cron.daily/gpu-cleanup

# Configure SSH for passwordless communication
echo "Configuring SSH for cluster communication..."
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#AuthorizedKeysFile/AuthorizedKeysFile/' /etc/ssh/sshd_config
systemctl restart sshd

# Set up firewall rules for GPU node communication
echo "Configuring firewall for GPU communication..."
ufw allow ssh
ufw allow 8888/tcp  # Jupyter Lab
ufw allow from 10.0.0.0/8
ufw --force enable

# Create GPU startup complete marker
echo "GPU compute node configuration completed at $(date)" | tee /tmp/gpu-startup-complete

# Send startup notification to Cloud Logging
gcloud logging write gpu-startup \
  '{"message": "GPU compute node startup completed", "instance": "'$(hostname)'", "timestamp": "'$(date -Is)'"}' \
  --severity=INFO

echo "GPU compute node startup script completed successfully"
echo "Note: If NVIDIA drivers were installed, a reboot may be required for full functionality"

# Test GPU availability after startup
echo "Testing GPU availability..."
if nvidia-smi &> /dev/null; then
    echo "GPU is available and functioning:"
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
else
    echo "GPU drivers may require a reboot to become fully functional"
fi