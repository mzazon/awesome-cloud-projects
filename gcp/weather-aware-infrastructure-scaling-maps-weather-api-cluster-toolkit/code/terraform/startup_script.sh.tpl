#!/bin/bash
#
# HPC Cluster Node Startup Script
# This script configures cluster nodes for weather-aware HPC workloads
#

set -e

# Configuration from template variables
FILESTORE_IP="${filestore_ip}"
FILESTORE_SHARE="${filestore_share}"
MOUNT_POINT="/mnt/shared"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/hpc-startup.log
}

log "Starting HPC cluster node initialization"

# Update system packages
log "Updating system packages"
apt-get update -y
apt-get upgrade -y

# Install required packages for HPC and monitoring
log "Installing required packages"
apt-get install -y \
    nfs-common \
    python3 \
    python3-pip \
    htop \
    iotop \
    sysstat \
    nvidia-utils-470 \
    cuda-toolkit-11-8 \
    slurm-client \
    munge \
    build-essential \
    git \
    wget \
    curl \
    jq \
    google-cloud-ops-agent

# Install Python packages for weather workloads
log "Installing Python packages for weather workloads"
pip3 install \
    numpy \
    scipy \
    pandas \
    matplotlib \
    xarray \
    netCDF4 \
    google-cloud-pubsub \
    google-cloud-storage \
    google-cloud-monitoring

# Configure NFS mount for shared storage
log "Configuring NFS mount for shared storage"
mkdir -p $MOUNT_POINT

# Add NFS mount to fstab
echo "$FILESTORE_IP:/$FILESTORE_SHARE $MOUNT_POINT nfs rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0" >> /etc/fstab

# Mount the shared filesystem
mount $MOUNT_POINT

# Set appropriate permissions
chmod 755 $MOUNT_POINT

log "NFS mount configured successfully at $MOUNT_POINT"

# Configure Slurm client
log "Configuring Slurm client"
mkdir -p /etc/slurm
cat > /etc/slurm/slurm.conf << 'EOF'
# Slurm configuration for weather-aware HPC cluster
ClusterName=weather-hpc
ControlMachine=weather-hpc-controller
ControlAddr=weather-hpc-controller
SlurmUser=slurm
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
CryptoType=crypto/munge
StateSaveLocation=/var/spool/slurm/ctld
SlurmdSpoolDir=/var/spool/slurm/d
SwitchType=switch/none
MpiDefault=none
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmdPidFile=/var/run/slurm/slurmd.pid
ProctrackType=proctrack/pgid
TaskPlugin=task/affinity
InactiveLimit=0
MinJobAge=300
KillWait=30
Waittime=0
SchedulerType=sched/backfill
FastSchedule=1
DefaultStorageType=accounting_storage/none
AccountingStorageType=accounting_storage/none
JobAcctGatherFrequency=30
JobAcctGatherType=jobacct_gather/linux
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
SlurmctldDebug=3
SlurmdDebug=3

# Node configuration (will be updated by cluster management)
NodeName=DEFAULT CPUs=60 RealMemory=240000 Sockets=1 CoresPerSocket=60 ThreadsPerCore=1 State=UNKNOWN
PartitionName=weather-compute Nodes=ALL Default=YES MaxTime=INFINITE State=UP

# Weather-aware scaling configuration
DefMemPerCPU=4000
MaxMemPerCPU=8000
SelectType=select/cons_res
SelectTypeParameters=CR_Core_Memory
GresTypes=gpu
EOF

# Configure Munge for authentication
log "Configuring Munge authentication"
systemctl enable munge
systemctl start munge

# Configure Slurm daemon
log "Configuring Slurm daemon"
mkdir -p /var/spool/slurm/d
mkdir -p /var/log/slurm
chown slurm:slurm /var/spool/slurm/d
chown slurm:slurm /var/log/slurm

# Create slurm user if it doesn't exist
if ! id -u slurm >/dev/null 2>&1; then
    useradd -r -s /bin/false slurm
fi

# Enable and start Slurm daemon
systemctl enable slurmd
systemctl start slurmd

log "Slurm client configuration completed"

# Configure Google Cloud Ops Agent for monitoring
log "Configuring Google Cloud Ops Agent"
cat > /etc/google-cloud-ops-agent/config.yaml << 'EOF'
logging:
  receivers:
    syslog:
      type: files
      include_paths:
        - /var/log/messages
        - /var/log/syslog
    slurm_logs:
      type: files
      include_paths:
        - /var/log/slurm/*.log
    hpc_startup:
      type: files
      include_paths:
        - /var/log/hpc-startup.log
  service:
    pipelines:
      default_pipeline:
        receivers: [syslog, slurm_logs, hpc_startup]

metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
    processes:
      type: processes
      collection_interval: 60s
  processors:
    resourcedetection:
      type: resourcedetection
      resource_attributes:
        - gce.instance.id
        - gce.instance.name
        - gce.zone
        - gce.project_id
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics, processes]
        processors: [resourcedetection]
EOF

# Restart Ops Agent with new configuration
systemctl restart google-cloud-ops-agent

log "Google Cloud Ops Agent configured successfully"

# Create sample weather workload scripts
log "Creating sample weather workload scripts"
mkdir -p $MOUNT_POINT/scripts
mkdir -p $MOUNT_POINT/data

# Climate modeling script
cat > $MOUNT_POINT/scripts/climate_model.py << 'EOF'
#!/usr/bin/env python3
"""
Climate modeling workload for weather-aware HPC cluster
"""
import time
import math
import random
import os
import sys
from datetime import datetime

def run_climate_simulation(scaling_factor=1.0, duration_minutes=30):
    """Run climate modeling simulation with weather-based scaling"""
    print(f"🌦️  Starting climate modeling simulation")
    print(f"Weather scaling factor: {scaling_factor}")
    print(f"Duration: {duration_minutes} minutes")
    
    simulation_time = int(duration_minutes * 60 * scaling_factor)
    
    for iteration in range(0, simulation_time, 30):
        # Simulate atmospheric pressure calculations
        pressure_computation = sum(math.sin(i * scaling_factor) for i in range(10000))
        
        # Simulate temperature gradient modeling
        temp_gradient = sum(math.cos(i / scaling_factor) for i in range(8000))
        
        # Simulate precipitation modeling
        precip_model = sum(random.random() * scaling_factor for _ in range(5000))
        
        progress = iteration + 30
        remaining_time = simulation_time - progress
        
        print(f"Progress: {progress}s/{simulation_time}s - Remaining: {remaining_time}s")
        print(f"  Pressure: {pressure_computation:.2f}")
        print(f"  Temperature: {temp_gradient:.2f}")
        print(f"  Precipitation: {precip_model:.2f}")
        
        time.sleep(30)
    
    print("✅ Climate modeling simulation completed")

if __name__ == "__main__":
    scaling_factor = float(os.environ.get('WEATHER_SCALING_FACTOR', '1.0'))
    duration = int(os.environ.get('SIMULATION_DURATION_MINUTES', '30'))
    
    run_climate_simulation(scaling_factor, duration)
EOF

# Energy forecasting script
cat > $MOUNT_POINT/scripts/energy_forecast.py << 'EOF'
#!/usr/bin/env python3
"""
Renewable energy forecasting workload for weather-aware HPC cluster
"""
import time
import math
import random
import os
from datetime import datetime

def run_energy_forecast(wind_factor=1.0, solar_factor=1.0, hours=24):
    """Run renewable energy forecasting with weather-based scaling"""
    print(f"⚡ Starting renewable energy forecasting")
    print(f"Wind scaling factor: {wind_factor}")
    print(f"Solar scaling factor: {solar_factor}")
    print(f"Forecast hours: {hours}")
    
    total_wind_output = 0
    total_solar_output = 0
    
    for hour in range(hours):
        # Wind energy calculation
        base_wind = 100  # MW base capacity
        wind_variability = 0.5 + 0.5 * math.sin(hour / 4)
        wind_output = base_wind * wind_factor * wind_variability
        
        # Solar energy calculation
        base_solar = 150  # MW base capacity
        solar_variability = max(0, math.sin(math.pi * hour / 12))
        solar_output = base_solar * solar_factor * solar_variability
        
        total_renewable = wind_output + solar_output
        total_wind_output += wind_output
        total_solar_output += solar_output
        
        print(f"Hour {hour:2d}: Wind {wind_output:6.1f}MW | Solar {solar_output:6.1f}MW | Total {total_renewable:6.1f}MW")
        
        # Simulate computation time
        time.sleep(5)
    
    print(f"✅ Energy forecasting completed")
    print(f"Total wind generation: {total_wind_output:.1f}MW")
    print(f"Total solar generation: {total_solar_output:.1f}MW")

if __name__ == "__main__":
    wind_factor = float(os.environ.get('WIND_SCALING_FACTOR', '1.0'))
    solar_factor = float(os.environ.get('SOLAR_SCALING_FACTOR', '1.0'))
    forecast_hours = int(os.environ.get('FORECAST_HOURS', '24'))
    
    run_energy_forecast(wind_factor, solar_factor, forecast_hours)
EOF

# Make scripts executable
chmod +x $MOUNT_POINT/scripts/*.py

# Create sample Slurm job scripts
cat > $MOUNT_POINT/scripts/submit_climate_job.sh << 'EOF'
#!/bin/bash
#SBATCH --job-name=weather-climate-model
#SBATCH --partition=weather-compute
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --time=02:00:00
#SBATCH --output=climate-model-%j.out
#SBATCH --error=climate-model-%j.err

# Set weather scaling factor from environment or default
export WEATHER_SCALING_FACTOR=${WEATHER_SCALING_FACTOR:-1.0}
export SIMULATION_DURATION_MINUTES=${SIMULATION_DURATION_MINUTES:-30}

echo "Starting climate modeling job with scaling factor: $WEATHER_SCALING_FACTOR"
python3 /mnt/shared/scripts/climate_model.py
EOF

cat > $MOUNT_POINT/scripts/submit_energy_job.sh << 'EOF'
#!/bin/bash
#SBATCH --job-name=weather-energy-forecast
#SBATCH --partition=weather-compute
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --time=01:00:00
#SBATCH --output=energy-forecast-%j.out
#SBATCH --error=energy-forecast-%j.err

# Set weather scaling factors from environment or defaults
export WIND_SCALING_FACTOR=${WIND_SCALING_FACTOR:-1.0}
export SOLAR_SCALING_FACTOR=${SOLAR_SCALING_FACTOR:-1.0}
export FORECAST_HOURS=${FORECAST_HOURS:-24}

echo "Starting energy forecasting job"
echo "Wind factor: $WIND_SCALING_FACTOR, Solar factor: $SOLAR_SCALING_FACTOR"
python3 /mnt/shared/scripts/energy_forecast.py
EOF

chmod +x $MOUNT_POINT/scripts/*.sh

log "Sample workload scripts created successfully"

# Create system performance monitoring script
cat > /usr/local/bin/weather-hpc-monitor.sh << 'EOF'
#!/bin/bash
#
# Weather HPC Node Monitoring Script
#

# Function to get CPU usage
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//'
}

# Function to get memory usage
get_memory_usage() {
    free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}'
}

# Function to get disk usage
get_disk_usage() {
    df -h /mnt/shared | tail -1 | awk '{print $5}' | sed 's/%//'
}

# Function to get network statistics
get_network_stats() {
    cat /proc/net/dev | grep eth0 | awk '{print "RX:" $2 " TX:" $10}'
}

# Function to get Slurm job status
get_slurm_status() {
    if command -v squeue &> /dev/null; then
        squeue -u $(whoami) | tail -n +2 | wc -l
    else
        echo "0"
    fi
}

# Main monitoring loop
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    cpu_usage=$(get_cpu_usage)
    memory_usage=$(get_memory_usage)
    disk_usage=$(get_disk_usage)
    network_stats=$(get_network_stats)
    active_jobs=$(get_slurm_status)
    
    echo "[$timestamp] CPU: ${cpu_usage}% | Memory: ${memory_usage}% | Disk: ${disk_usage}% | Network: $network_stats | Jobs: $active_jobs"
    
    sleep 60
done
EOF

chmod +x /usr/local/bin/weather-hpc-monitor.sh

# Create systemd service for monitoring
cat > /etc/systemd/system/weather-hpc-monitor.service << 'EOF'
[Unit]
Description=Weather HPC Node Monitoring Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/weather-hpc-monitor.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start monitoring service
systemctl daemon-reload
systemctl enable weather-hpc-monitor.service
systemctl start weather-hpc-monitor.service

log "Weather HPC monitoring service configured and started"

# Final system configuration
log "Performing final system configuration"

# Set system timezone
timedatectl set-timezone UTC

# Configure system limits for HPC workloads
cat >> /etc/security/limits.conf << 'EOF'
# HPC workload limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
* soft memlock unlimited
* hard memlock unlimited
EOF

# Update kernel parameters for HPC
cat >> /etc/sysctl.conf << 'EOF'
# HPC kernel parameters
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
vm.swappiness = 1
EOF

# Apply kernel parameters
sysctl -p

log "System configuration completed successfully"

# Create node readiness indicator
touch /var/log/hpc-node-ready

log "HPC cluster node initialization completed successfully"
log "Node is ready for weather-aware HPC workloads"

# Send completion notification to Cloud Logging
echo "HPC node startup completed at $(date)" | logger -t "weather-hpc-startup"