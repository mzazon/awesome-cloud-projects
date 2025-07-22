#!/bin/bash
# GPU Setup Script for ML Training Instances
# This script configures GPU drivers, Docker, and ML frameworks

set -e

# Update system packages
apt-get update

# Install NVIDIA drivers and CUDA toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install -y nvidia-container-toolkit

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi

# Configure Docker for GPU support
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Install Google Cloud SDK if not already installed
if ! command -v gcloud &> /dev/null; then
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    apt-get update && apt-get install -y google-cloud-sdk
fi

# Configure Docker authentication for Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev --quiet

# Install Python ML packages
pip3 install --upgrade pip
pip3 install tensorflow torch transformers datasets accelerate scikit-learn pandas numpy matplotlib seaborn jupyter

# Create ML workspace directory
mkdir -p /opt/ml-workspace
chmod 755 /opt/ml-workspace

# Create startup script for ML environment
cat > /opt/ml-workspace/setup_env.sh << 'EOF'
#!/bin/bash
# Set environment variables for ML development
export CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
export TOKENIZERS_PARALLELISM=false
export TRANSFORMERS_CACHE=/opt/ml-workspace/.cache/transformers
export HF_HOME=/opt/ml-workspace/.cache/huggingface

# Create cache directories
mkdir -p /opt/ml-workspace/.cache/transformers
mkdir -p /opt/ml-workspace/.cache/huggingface

echo "ML environment setup completed"
EOF

chmod +x /opt/ml-workspace/setup_env.sh

# Install additional ML tools
pip3 install wandb mlflow tensorboard nvidia-ml-py3

# Verify GPU setup
nvidia-smi

echo "GPU setup completed successfully"