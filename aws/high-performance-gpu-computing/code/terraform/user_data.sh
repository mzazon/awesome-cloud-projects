#!/bin/bash
# User data script for GPU-accelerated workloads on AWS EC2
# This script configures P4 and G4 instances with NVIDIA drivers, ML frameworks,
# and monitoring capabilities for production GPU computing workloads

set -e  # Exit on any error

# Variables passed from Terraform
REGION="${region}"
ENABLE_MONITORING="${enable_monitoring}"

# Log all output to a file for debugging
exec > >(tee /var/log/gpu-setup.log)
exec 2>&1

echo "==================================================="
echo "Starting GPU Instance Setup - $(date)"
echo "Region: $REGION"
echo "Monitoring Enabled: $ENABLE_MONITORING"
echo "==================================================="

# Update system packages
echo "Updating system packages..."
yum update -y
yum install -y wget curl unzip htop tree jq

# Install AWS CLI v2 if not present
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Configure AWS CLI region
aws configure set region $REGION

# Function to install NVIDIA drivers
install_nvidia_drivers() {
    echo "Installing NVIDIA drivers..."
    
    # Check if NVIDIA drivers are already installed
    if command -v nvidia-smi &> /dev/null; then
        echo "NVIDIA drivers already installed"
        nvidia-smi
        return 0
    fi
    
    # Download and install NVIDIA drivers from S3
    cd /tmp
    aws s3 cp --recursive s3://ec2-linux-nvidia-drivers/latest/ . --region us-east-1
    
    # Find the NVIDIA driver file
    NVIDIA_DRIVER=$(ls NVIDIA-Linux-x86_64*.run | head -1)
    
    if [ -n "$NVIDIA_DRIVER" ]; then
        echo "Installing NVIDIA driver: $NVIDIA_DRIVER"
        chmod +x "$NVIDIA_DRIVER"
        ./"$NVIDIA_DRIVER" --silent --dkms
        
        # Verify installation
        if nvidia-smi; then
            echo "NVIDIA drivers installed successfully"
        else
            echo "NVIDIA driver installation failed"
            exit 1
        fi
    else
        echo "No NVIDIA driver found"
        exit 1
    fi
}

# Function to install Docker with GPU support
install_docker_gpu() {
    echo "Installing Docker with GPU support..."
    
    # Install Docker
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    
    # Add ec2-user to docker group
    usermod -aG docker ec2-user
    
    # Install NVIDIA Container Toolkit
    distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | rpm --import -
    curl -s -L "https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo" | \
        tee /etc/yum.repos.d/nvidia-docker.repo
    
    yum clean expire-cache
    yum install -y nvidia-docker2
    
    # Restart Docker to load the new runtime
    systemctl restart docker
    
    # Test Docker GPU access
    echo "Testing Docker GPU access..."
    if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi; then
        echo "Docker GPU support verified"
    else
        echo "Docker GPU support test failed"
    fi
}

# Function to install Python ML frameworks
install_ml_frameworks() {
    echo "Installing Python ML frameworks..."
    
    # Install Python 3.8 and pip
    amazon-linux-extras install python3.8 -y
    
    # Create symbolic links for python3 and pip3
    ln -sf /usr/bin/python3.8 /usr/bin/python3
    ln -sf /usr/bin/pip3.8 /usr/bin/pip3
    
    # Upgrade pip
    python3 -m pip install --upgrade pip
    
    # Install common ML frameworks and tools
    echo "Installing PyTorch with CUDA support..."
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
    
    echo "Installing TensorFlow with GPU support..."
    pip3 install tensorflow[and-cuda]
    
    echo "Installing additional ML and data science packages..."
    pip3 install \
        jupyter \
        jupyterlab \
        matplotlib \
        pandas \
        numpy \
        scikit-learn \
        seaborn \
        plotly \
        transformers \
        accelerate \
        datasets \
        tensorboard \
        wandb \
        mlflow \
        nvidia-ml-py3
    
    # Install RAPIDS for GPU-accelerated data science (for supported instances)
    if [[ $(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1) -gt 16000 ]]; then
        echo "Installing RAPIDS for GPU-accelerated data science..."
        pip3 install cudf-cu11 cuml-cu11 cugraph-cu11 --extra-index-url=https://pypi.nvidia.com
    fi
    
    # Configure Jupyter for remote access
    echo "Configuring Jupyter for remote access..."
    mkdir -p /home/ec2-user/.jupyter
    
    cat > /home/ec2-user/.jupyter/jupyter_notebook_config.py << 'EOF'
import os
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
c.NotebookApp.token = ''
c.NotebookApp.password = ''
EOF

    chown -R ec2-user:ec2-user /home/ec2-user/.jupyter
}

# Function to install and configure CloudWatch monitoring
install_cloudwatch_monitoring() {
    if [ "$ENABLE_MONITORING" != "true" ]; then
        echo "CloudWatch monitoring disabled, skipping..."
        return 0
    fi
    
    echo "Installing CloudWatch agent and GPU monitoring..."
    
    # Download and install CloudWatch agent
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
    rpm -U ./amazon-cloudwatch-agent.rpm
    
    # Create CloudWatch agent configuration for GPU monitoring
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "GPU/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": [
                    "tcp_established",
                    "tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": [
                    "swap_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/gpu-setup.log",
                        "log_group_name": "gpu-workload-setup",
                        "log_stream_name": "{instance_id}-setup"
                    },
                    {
                        "file_path": "/var/log/gpu-metrics.log",
                        "log_group_name": "gpu-workload-metrics",
                        "log_stream_name": "{instance_id}-metrics"
                    }
                ]
            }
        }
    }
}
EOF
    
    # Start CloudWatch agent
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config -m ec2 \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
        -s
    
    # Create GPU monitoring script
    cat > /usr/local/bin/gpu-monitor.py << 'EOF'
#!/usr/bin/env python3
import subprocess
import json
import time
import boto3
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(
    filename='/var/log/gpu-metrics.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def get_instance_id():
    """Get EC2 instance ID from metadata"""
    try:
        result = subprocess.run([
            'curl', '-s', 
            'http://169.254.169.254/latest/meta-data/instance-id'
        ], capture_output=True, text=True, timeout=10)
        return result.stdout.strip()
    except Exception as e:
        logging.error(f"Failed to get instance ID: {e}")
        return "unknown"

def get_gpu_metrics():
    """Get GPU metrics using nvidia-smi"""
    try:
        # Get GPU utilization, memory, temperature, and power
        result = subprocess.run([
            'nvidia-smi', 
            '--query-gpu=utilization.gpu,utilization.memory,temperature.gpu,power.draw,memory.used,memory.total',
            '--format=csv,noheader,nounits'
        ], capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            gpu_metrics = []
            
            for i, line in enumerate(lines):
                if line.strip():
                    metrics = [float(x.strip()) for x in line.split(',')]
                    gpu_metrics.append({
                        'gpu_id': i,
                        'gpu_util': metrics[0],
                        'mem_util': metrics[1],
                        'temperature': metrics[2],
                        'power_draw': metrics[3],
                        'memory_used': metrics[4],
                        'memory_total': metrics[5]
                    })
            
            return gpu_metrics
    except Exception as e:
        logging.error(f"Error getting GPU metrics: {e}")
    return []

def send_cloudwatch_metrics(metrics, instance_id, region):
    """Send GPU metrics to CloudWatch"""
    try:
        cloudwatch = boto3.client('cloudwatch', region_name=region)
        
        metric_data = []
        
        for gpu in metrics:
            gpu_id = gpu['gpu_id']
            
            # Add metrics for each GPU
            metric_data.extend([
                {
                    'MetricName': 'utilization_gpu',
                    'Value': gpu['gpu_util'],
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': instance_id},
                        {'Name': 'GPUId', 'Value': str(gpu_id)}
                    ]
                },
                {
                    'MetricName': 'utilization_memory',
                    'Value': gpu['mem_util'],
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': instance_id},
                        {'Name': 'GPUId', 'Value': str(gpu_id)}
                    ]
                },
                {
                    'MetricName': 'temperature_gpu',
                    'Value': gpu['temperature'],
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': instance_id},
                        {'Name': 'GPUId', 'Value': str(gpu_id)}
                    ]
                },
                {
                    'MetricName': 'power_draw',
                    'Value': gpu['power_draw'],
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': instance_id},
                        {'Name': 'GPUId', 'Value': str(gpu_id)}
                    ]
                },
                {
                    'MetricName': 'memory_used',
                    'Value': gpu['memory_used'],
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'InstanceId', 'Value': instance_id},
                        {'Name': 'GPUId', 'Value': str(gpu_id)}
                    ]
                }
            ])
        
        # Send metrics in batches of 20 (CloudWatch limit)
        for i in range(0, len(metric_data), 20):
            batch = metric_data[i:i+20]
            cloudwatch.put_metric_data(
                Namespace='GPU/EC2',
                MetricData=batch
            )
        
        logging.info(f"Sent {len(metric_data)} metrics for {len(metrics)} GPUs")
        
    except Exception as e:
        logging.error(f"Error sending metrics to CloudWatch: {e}")

def main():
    instance_id = get_instance_id()
    region = "${region}"
    
    logging.info(f"Starting GPU monitoring for instance {instance_id} in region {region}")
    
    while True:
        try:
            metrics = get_gpu_metrics()
            if metrics:
                send_cloudwatch_metrics(metrics, instance_id, region)
                print(f"{datetime.now()}: Sent metrics for {len(metrics)} GPUs")
            else:
                logging.warning("No GPU metrics available")
            
            time.sleep(60)  # Send metrics every minute
            
        except KeyboardInterrupt:
            logging.info("GPU monitoring stopped by user")
            break
        except Exception as e:
            logging.error(f"Unexpected error in monitoring loop: {e}")
            time.sleep(60)

if __name__ == "__main__":
    main()
EOF
    
    chmod +x /usr/local/bin/gpu-monitor.py
    
    # Create systemd service for GPU monitoring
    cat > /etc/systemd/system/gpu-monitor.service << 'EOF'
[Unit]
Description=GPU Monitoring Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gpu-monitor.py
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable gpu-monitor.service
    systemctl start gpu-monitor.service
    
    echo "GPU monitoring service configured and started"
}

# Function to create helpful scripts and tools
create_helper_scripts() {
    echo "Creating helper scripts and tools..."
    
    # Create GPU status script
    cat > /usr/local/bin/gpu-status << 'EOF'
#!/bin/bash
echo "=== GPU Status ==="
nvidia-smi
echo ""
echo "=== GPU Processes ==="
nvidia-smi pmon -c 1
echo ""
echo "=== CUDA Version ==="
nvcc --version 2>/dev/null || echo "NVCC not found"
echo ""
echo "=== Python GPU Test ==="
python3 -c "
import torch
print(f'PyTorch CUDA available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'CUDA device count: {torch.cuda.device_count()}')
    for i in range(torch.cuda.device_count()):
        print(f'Device {i}: {torch.cuda.get_device_name(i)}')
"
EOF
    
    chmod +x /usr/local/bin/gpu-status
    
    # Create GPU benchmark script
    cat > /usr/local/bin/gpu-benchmark << 'EOF'
#!/usr/bin/env python3
import torch
import time
import argparse

def run_benchmark(device, size=5000, iterations=100):
    """Run a simple GPU benchmark"""
    print(f"Running benchmark on {device}")
    print(f"Matrix size: {size}x{size}, Iterations: {iterations}")
    
    # Create random matrices
    a = torch.randn(size, size, device=device)
    b = torch.randn(size, size, device=device)
    
    # Warm up
    for _ in range(10):
        c = torch.matmul(a, b)
    
    # Benchmark
    torch.cuda.synchronize() if device.type == 'cuda' else None
    start_time = time.time()
    
    for _ in range(iterations):
        c = torch.matmul(a, b)
    
    torch.cuda.synchronize() if device.type == 'cuda' else None
    end_time = time.time()
    
    total_time = end_time - start_time
    ops_per_sec = iterations / total_time
    
    print(f"Total time: {total_time:.2f} seconds")
    print(f"Operations per second: {ops_per_sec:.2f}")
    print(f"Average time per operation: {total_time/iterations*1000:.2f} ms")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='GPU Benchmark')
    parser.add_argument('--size', type=int, default=5000, help='Matrix size')
    parser.add_argument('--iterations', type=int, default=100, help='Number of iterations')
    args = parser.parse_args()
    
    if torch.cuda.is_available():
        for i in range(torch.cuda.device_count()):
            device = torch.device(f'cuda:{i}')
            print(f"\n=== GPU {i}: {torch.cuda.get_device_name(i)} ===")
            run_benchmark(device, args.size, args.iterations)
    else:
        print("CUDA not available")
EOF
    
    chmod +x /usr/local/bin/gpu-benchmark
    
    # Create Jupyter startup script
    cat > /home/ec2-user/start-jupyter.sh << 'EOF'
#!/bin/bash
# Start Jupyter Lab with GPU support
echo "Starting Jupyter Lab..."
cd /home/ec2-user
nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root > jupyter.log 2>&1 &
echo "Jupyter Lab started. Access it at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8888"
echo "Check jupyter.log for any issues"
EOF
    
    chmod +x /home/ec2-user/start-jupyter.sh
    chown ec2-user:ec2-user /home/ec2-user/start-jupyter.sh
    
    # Create sample GPU test notebook
    cat > /home/ec2-user/gpu-test.ipynb << 'EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# GPU Testing and Validation\n",
    "\n",
    "This notebook contains tests to validate GPU functionality and performance."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import torch\n",
    "import tensorflow as tf\n",
    "import time\n",
    "import numpy as np\n",
    "\n",
    "print(\"PyTorch version:\", torch.__version__)\n",
    "print(\"TensorFlow version:\", tf.__version__)\n",
    "print(\"CUDA available (PyTorch):\", torch.cuda.is_available())\n",
    "print(\"GPU available (TensorFlow):\", len(tf.config.experimental.list_physical_devices('GPU')) > 0)\n",
    "\n",
    "if torch.cuda.is_available():\n",
    "    print(f\"Number of GPUs: {torch.cuda.device_count()}\")\n",
    "    for i in range(torch.cuda.device_count()):\n",
    "        print(f\"GPU {i}: {torch.cuda.get_device_name(i)}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# PyTorch GPU Performance Test\n",
    "if torch.cuda.is_available():\n",
    "    device = torch.device('cuda')\n",
    "    \n",
    "    # Create large tensors\n",
    "    size = 5000\n",
    "    a = torch.randn(size, size, device=device)\n",
    "    b = torch.randn(size, size, device=device)\n",
    "    \n",
    "    # Measure performance\n",
    "    start_time = time.time()\n",
    "    for _ in range(10):\n",
    "        c = torch.matmul(a, b)\n",
    "    torch.cuda.synchronize()\n",
    "    end_time = time.time()\n",
    "    \n",
    "    print(f\"PyTorch GPU computation time: {end_time - start_time:.2f} seconds\")\n",
    "    print(f\"Result tensor shape: {c.shape}\")\n",
    "else:\n",
    "    print(\"CUDA not available for PyTorch\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# TensorFlow GPU Performance Test\n",
    "if len(tf.config.experimental.list_physical_devices('GPU')) > 0:\n",
    "    with tf.device('/GPU:0'):\n",
    "        # Create large tensors\n",
    "        size = 5000\n",
    "        a = tf.random.normal([size, size])\n",
    "        b = tf.random.normal([size, size])\n",
    "        \n",
    "        # Measure performance\n",
    "        start_time = time.time()\n",
    "        for _ in range(10):\n",
    "            c = tf.matmul(a, b)\n",
    "        end_time = time.time()\n",
    "        \n",
    "        print(f\"TensorFlow GPU computation time: {end_time - start_time:.2f} seconds\")\n",
    "        print(f\"Result tensor shape: {c.shape}\")\n",
    "else:\n",
    "    print(\"GPU not available for TensorFlow\")"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.8.0"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF
    
    chown ec2-user:ec2-user /home/ec2-user/gpu-test.ipynb
}

# Main execution flow
main() {
    echo "Starting GPU instance configuration..."
    
    # Install NVIDIA drivers
    install_nvidia_drivers
    
    # Install Docker with GPU support
    install_docker_gpu
    
    # Install ML frameworks
    install_ml_frameworks
    
    # Install CloudWatch monitoring
    install_cloudwatch_monitoring
    
    # Create helper scripts
    create_helper_scripts
    
    # Final verification
    echo "==================================================="
    echo "GPU Setup Complete - $(date)"
    echo "==================================================="
    
    # Display GPU information
    if command -v nvidia-smi &> /dev/null; then
        echo "GPU Information:"
        nvidia-smi
    else
        echo "WARNING: nvidia-smi not available"
    fi
    
    # Test PyTorch CUDA
    echo ""
    echo "Testing PyTorch CUDA availability:"
    python3 -c "import torch; print('CUDA available:', torch.cuda.is_available()); print('GPU count:', torch.cuda.device_count() if torch.cuda.is_available() else 0)"
    
    # Create completion marker
    echo "GPU setup completed successfully at $(date)" > /tmp/gpu-setup-complete
    
    echo ""
    echo "Setup completed! You can now:"
    echo "1. Run 'gpu-status' to check GPU status"
    echo "2. Run 'gpu-benchmark' to test GPU performance"
    echo "3. Start Jupyter with './start-jupyter.sh'"
    echo "4. Check logs at /var/log/gpu-setup.log"
}

# Execute main function
main