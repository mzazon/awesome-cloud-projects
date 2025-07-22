#!/bin/bash

# High-Performance Analytics VM Startup Script
# This script configures Cloud Storage FUSE and Parallelstore mounts for optimal performance

set -e

# Log all output for debugging
exec > >(tee /var/log/startup-script.log) 2>&1
echo "Starting high-performance analytics VM configuration at $(date)"

# Update system packages
apt-get update -y

# Install Cloud Storage FUSE
echo "Installing Cloud Storage FUSE..."
export GCSFUSE_REPO=gcsfuse-$(lsb_release -c -s)
echo "deb https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | tee /etc/apt/sources.list.d/gcsfuse.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | tee /etc/apt/sources.list.d/gcsfuse.list
apt-get update -y
apt-get install -y gcsfuse

# Install NFS utilities for Parallelstore
echo "Installing NFS utilities for Parallelstore..."
apt-get install -y nfs-common

# Install performance monitoring tools
echo "Installing performance monitoring tools..."
apt-get install -y htop iotop sysstat

# Install Python and analytics tools
echo "Installing Python and analytics tools..."
apt-get install -y python3-pip python3-dev
pip3 install --upgrade pip
pip3 install pandas numpy scipy matplotlib seaborn jupyter

# Create mount points
echo "Creating mount points..."
mkdir -p /mnt/gcs-data
mkdir -p /mnt/parallel-store

# Configure Cloud Storage FUSE mount with performance optimizations
echo "Configuring Cloud Storage FUSE mount..."
# Mount with optimizations for large files and metadata operations
gcsfuse \
    --implicit-dirs \
    --stat-cache-ttl 1h \
    --type-cache-ttl 1h \
    --file-mode 755 \
    --dir-mode 755 \
    --gid 1000 \
    --uid 1000 \
    --max-conns-per-host 100 \
    --kernel-list-cache-ttl-secs 3600 \
    ${bucket_name} /mnt/gcs-data

# Configure Parallelstore NFS mount with performance optimizations
echo "Configuring Parallelstore NFS mount..."
# Mount with performance tuning for high-throughput workloads
mount -t nfs4 \
    -o nfsvers=4.1,proto=tcp,fsc,rsize=1048576,wsize=1048576,hard,intr,timeo=600 \
    ${parallelstore_ip}:/parallelstore /mnt/parallel-store

# Configure automatic remount on boot
echo "Configuring automatic remount on boot..."
cat >> /etc/fstab << EOF

# Cloud Storage FUSE mount for high-performance analytics
${bucket_name} /mnt/gcs-data gcsfuse rw,user,allow_other,implicit_dirs 0 0

# Parallelstore NFS mount for high-performance analytics
${parallelstore_ip}:/parallelstore /mnt/parallel-store nfs4 defaults,nfsvers=4.1,proto=tcp,fsc,rsize=1048576,wsize=1048576,hard,intr,timeo=600 0 0
EOF

# Set appropriate permissions
echo "Setting mount point permissions..."
chown -R 1000:1000 /mnt/gcs-data /mnt/parallel-store
chmod -R 755 /mnt/gcs-data /mnt/parallel-store

# Configure system for high-performance I/O
echo "Configuring system for high-performance I/O..."

# Optimize kernel parameters for high-throughput storage
cat >> /etc/sysctl.conf << EOF

# High-performance storage optimizations
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

# Apply sysctl settings
sysctl -p

# Configure I/O scheduler for SSDs
echo "Configuring I/O scheduler..."
echo 'ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="noop"' > /etc/udev/rules.d/60-ssd-scheduler.rules

# Create performance monitoring script
echo "Creating performance monitoring script..."
cat > /usr/local/bin/storage-performance-monitor.sh << 'EOF'
#!/bin/bash

# Storage Performance Monitoring Script
LOG_FILE="/var/log/storage-performance.log"

echo "$(date): Storage Performance Check" >> $LOG_FILE

# Check Cloud Storage FUSE mount
if mountpoint -q /mnt/gcs-data; then
    echo "$(date): Cloud Storage FUSE mount is active" >> $LOG_FILE
    ls /mnt/gcs-data > /dev/null 2>&1 && echo "$(date): Cloud Storage FUSE responsive" >> $LOG_FILE
else
    echo "$(date): ERROR - Cloud Storage FUSE mount not found" >> $LOG_FILE
fi

# Check Parallelstore mount
if mountpoint -q /mnt/parallel-store; then
    echo "$(date): Parallelstore mount is active" >> $LOG_FILE
    ls /mnt/parallel-store > /dev/null 2>&1 && echo "$(date): Parallelstore responsive" >> $LOG_FILE
else
    echo "$(date): ERROR - Parallelstore mount not found" >> $LOG_FILE
fi

# Test write performance to Parallelstore
if mountpoint -q /mnt/parallel-store; then
    WRITE_TEST=$(dd if=/dev/zero of=/mnt/parallel-store/perf_test bs=1M count=10 2>&1 | grep "MB/s" || echo "Write test failed")
    echo "$(date): Parallelstore write test: $WRITE_TEST" >> $LOG_FILE
    rm -f /mnt/parallel-store/perf_test
fi

echo "$(date): Performance check completed" >> $LOG_FILE
EOF

chmod +x /usr/local/bin/storage-performance-monitor.sh

# Set up cron job for performance monitoring
echo "Setting up performance monitoring cron job..."
echo "*/15 * * * * root /usr/local/bin/storage-performance-monitor.sh" >> /etc/crontab

# Create sample data generation script
echo "Creating sample data generation script..."
cat > /usr/local/bin/generate-sample-data.sh << 'EOF'
#!/bin/bash

# Sample Data Generation Script for Analytics Testing
SAMPLE_DIR="/mnt/gcs-data/sample_data/raw/2024/01"

echo "Generating sample analytics data..."

# Create directory structure if it doesn't exist
mkdir -p "$SAMPLE_DIR"

# Generate sample CSV files with sensor data
for i in {1..100}; do
    FILE="$SAMPLE_DIR/sensor_data_$i.csv"
    echo "timestamp,sensor_id,value,location" > "$FILE"
    
    # Generate 1000 data points per file
    for j in {1..1000}; do
        TIMESTAMP=$(date +%s)
        SENSOR_ID="sensor_$i"
        VALUE=$((RANDOM % 100))
        LOCATION="zone_$j"
        echo "$TIMESTAMP,$SENSOR_ID,$VALUE,$LOCATION" >> "$FILE"
    done
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "Generated $i files..."
    fi
done

echo "Sample data generation completed. Files created in $SAMPLE_DIR"
EOF

chmod +x /usr/local/bin/generate-sample-data.sh

# Create analytics pipeline script
echo "Creating analytics pipeline script..."
cat > /usr/local/bin/analytics-pipeline.py << 'EOF'
#!/usr/bin/env python3

"""
High-Performance Analytics Pipeline
Demonstrates data processing using Cloud Storage FUSE and Parallelstore
"""

import os
import time
import pandas as pd
import numpy as np
from pathlib import Path

def run_analytics_pipeline():
    """Run the high-performance analytics pipeline"""
    
    print("Starting high-performance analytics pipeline...")
    start_time = time.time()
    
    # Define paths
    gcs_data_path = Path("/mnt/gcs-data/sample_data/raw/2024/01")
    parallel_store_path = Path("/mnt/parallel-store/processed")
    
    # Create output directory
    parallel_store_path.mkdir(parents=True, exist_ok=True)
    
    # Read all CSV files from Cloud Storage FUSE
    print("Reading data from Cloud Storage FUSE...")
    read_start = time.time()
    
    all_data = []
    csv_files = list(gcs_data_path.glob("*.csv"))
    
    for csv_file in csv_files:
        try:
            df = pd.read_csv(csv_file)
            all_data.append(df)
        except Exception as e:
            print(f"Error reading {csv_file}: {e}")
    
    if not all_data:
        print("No data files found. Generate sample data first.")
        return
    
    # Combine all data
    combined_df = pd.concat(all_data, ignore_index=True)
    read_time = time.time() - read_start
    print(f"Data read completed in {read_time:.2f} seconds")
    print(f"Total records: {len(combined_df)}")
    
    # Perform analytics transformations
    print("Performing analytics transformations...")
    transform_start = time.time()
    
    # Convert timestamp to numeric
    combined_df['timestamp'] = pd.to_numeric(combined_df['timestamp'])
    combined_df['value'] = pd.to_numeric(combined_df['value'])
    
    # Group by sensor_id and calculate statistics
    analytics_df = combined_df.groupby('sensor_id').agg({
        'value': ['mean', 'max', 'min', 'std', 'count']
    }).round(2)
    
    # Flatten column names
    analytics_df.columns = ['avg_value', 'max_value', 'min_value', 'std_value', 'count']
    analytics_df = analytics_df.reset_index()
    
    transform_time = time.time() - transform_start
    print(f"Transformations completed in {transform_time:.2f} seconds")
    
    # Write results to Parallelstore for high-speed access
    print("Writing results to Parallelstore...")
    write_start = time.time()
    
    output_file = parallel_store_path / "analytics_results.parquet"
    analytics_df.to_parquet(output_file, compression='snappy')
    
    # Also write CSV for easy viewing
    csv_output = parallel_store_path / "analytics_results.csv"
    analytics_df.to_csv(csv_output, index=False)
    
    write_time = time.time() - write_start
    print(f"Results written in {write_time:.2f} seconds")
    
    # Copy results back to Cloud Storage for BigQuery access
    print("Copying results to Cloud Storage for BigQuery...")
    gcs_output_dir = Path("/mnt/gcs-data/sample_data/processed/analytics")
    gcs_output_dir.mkdir(parents=True, exist_ok=True)
    
    # Copy parquet file to Cloud Storage
    import shutil
    gcs_parquet = gcs_output_dir / "analytics_results.parquet"
    shutil.copy2(output_file, gcs_parquet)
    
    total_time = time.time() - start_time
    print(f"Pipeline completed successfully in {total_time:.2f} seconds")
    print(f"Results available at: {output_file}")
    print(f"Results also copied to: {gcs_parquet}")
    
    # Display sample results
    print("\nSample Analytics Results:")
    print(analytics_df.head(10))

if __name__ == "__main__":
    run_analytics_pipeline()
EOF

chmod +x /usr/local/bin/analytics-pipeline.py

# Install Google Cloud SDK (if not already installed)
if ! command -v gcloud &> /dev/null; then
    echo "Installing Google Cloud SDK..."
    curl https://sdk.cloud.google.com | bash
    exec -l $SHELL
fi

# Configure Google Cloud SDK if service account is provided
%{ if service_account != "" }
echo "Configuring Google Cloud SDK with service account..."
gcloud auth activate-service-account ${service_account} --key-file=/var/lib/google/google_application_credentials.json
gcloud config set account ${service_account}
%{ endif }

# Create status file to indicate successful completion
echo "Creating completion status file..."
cat > /tmp/startup-script-status.json << EOF
{
    "status": "completed",
    "timestamp": "$(date -Iseconds)",
    "cloud_storage_fuse_mount": "/mnt/gcs-data",
    "parallelstore_mount": "/mnt/parallel-store",
    "bucket_name": "${bucket_name}",
    "parallelstore_ip": "${parallelstore_ip}",
    "performance_tools": [
        "htop", "iotop", "sysstat", "storage-performance-monitor.sh"
    ],
    "analytics_tools": [
        "python3", "pandas", "numpy", "analytics-pipeline.py"
    ]
}
EOF

echo "High-performance analytics VM configuration completed successfully at $(date)"
echo "Storage mounts configured and performance optimizations applied"
echo "Analytics tools and monitoring scripts installed"

# Run initial performance check
/usr/local/bin/storage-performance-monitor.sh

# Generate sample data if requested
if [ -d "/mnt/gcs-data" ]; then
    echo "Generating initial sample data..."
    /usr/local/bin/generate-sample-data.sh
fi

echo "VM startup script completed successfully"