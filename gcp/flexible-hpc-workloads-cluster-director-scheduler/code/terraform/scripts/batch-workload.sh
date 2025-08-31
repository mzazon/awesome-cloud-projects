#!/bin/bash
# Cloud Batch HPC Workload Script
# This script runs HPC workloads in Cloud Batch with intelligent resource utilization

set -euo pipefail

# Variables passed from Terraform
BUCKET_NAME="${bucket_name}"
PROJECT_ID="${project_id}"

# Environment variables from Cloud Batch
JOB_INDEX=${BATCH_TASK_INDEX:-0}
TASK_COUNT=${BATCH_TASK_COUNT:-1}

# Logging setup
LOG_FILE="/var/log/batch-workload.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "Starting Cloud Batch HPC workload at $(date)"
echo "Job Index: $JOB_INDEX / Task Count: $TASK_COUNT"
echo "Project ID: $PROJECT_ID"
echo "Storage Bucket: $BUCKET_NAME"

# Get instance metadata
INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name 2>/dev/null || echo "unknown")
MACHINE_TYPE=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/machine-type 2>/dev/null | cut -d'/' -f4 || echo "unknown")
ZONE=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2>/dev/null | cut -d'/' -f4 || echo "unknown")

echo "Instance Name: $INSTANCE_NAME"
echo "Machine Type: $MACHINE_TYPE"
echo "Zone: $ZONE"

# Install required packages if not present
echo "Installing required packages..."
if ! command -v stress-ng &> /dev/null; then
    apt-get update -y
    apt-get install -y stress-ng sysstat htop curl python3 python3-pip
fi

if ! command -v gsutil &> /dev/null; then
    # Install Google Cloud SDK
    curl https://sdk.cloud.google.com | bash
    source /root/google-cloud-sdk/path.bash.inc
fi

# Install Python packages for scientific computing
pip3 install --quiet numpy scipy pandas matplotlib || true

# Display system information
echo "=== System Information ==="
echo "CPU: $(nproc) cores"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"

# Create working directory
WORK_DIR="/tmp/hpc-workload-$JOB_INDEX"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download input data from Cloud Storage (if exists)
echo "Checking for input data in Cloud Storage..."
INPUT_PREFIX="input/task-$JOB_INDEX"
if gsutil ls "gs://$BUCKET_NAME/$INPUT_PREFIX/" &> /dev/null; then
    echo "Downloading input data for task $JOB_INDEX..."
    gsutil -m cp -r "gs://$BUCKET_NAME/$INPUT_PREFIX/*" .
else
    echo "No input data found, generating synthetic workload..."
fi

# Simulate HPC workload based on task index
echo "Starting HPC computation simulation..."

case $((JOB_INDEX % 4)) in
    0)
        echo "Running CPU-intensive mathematical computation..."
        # Simulate mathematical computation
        python3 << EOF
import numpy as np
import time
import json

print("Computing matrix operations...")
start_time = time.time()

# Generate large matrices
size = 2000
a = np.random.random((size, size))
b = np.random.random((size, size))

# Perform computations
result1 = np.dot(a, b)
result2 = np.linalg.eigvals(result1[:100, :100])
result3 = np.fft.fft2(a[:512, :512])

computation_time = time.time() - start_time

# Save results
results = {
    "task_index": $JOB_INDEX,
    "computation_type": "matrix_operations",
    "matrix_size": size,
    "computation_time": computation_time,
    "eigenvalue_count": len(result2),
    "fft_shape": result3.shape,
    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
}

with open("results.json", "w") as f:
    json.dump(results, f, indent=2)

print(f"Matrix computation completed in {computation_time:.2f} seconds")
EOF
        ;;
    1)
        echo "Running Monte Carlo simulation..."
        # Simulate Monte Carlo computation
        python3 << EOF
import numpy as np
import time
import json

print("Running Monte Carlo simulation...")
start_time = time.time()

# Monte Carlo estimation of Pi
n_samples = 10000000
x = np.random.uniform(-1, 1, n_samples)
y = np.random.uniform(-1, 1, n_samples)
inside_circle = np.sum(x**2 + y**2 <= 1)
pi_estimate = 4 * inside_circle / n_samples

computation_time = time.time() - start_time

# Save results
results = {
    "task_index": $JOB_INDEX,
    "computation_type": "monte_carlo",
    "samples": n_samples,
    "pi_estimate": pi_estimate,
    "error": abs(pi_estimate - np.pi),
    "computation_time": computation_time,
    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
}

with open("results.json", "w") as f:
    json.dump(results, f, indent=2)

print(f"Monte Carlo simulation completed in {computation_time:.2f} seconds")
print(f"Pi estimate: {pi_estimate:.6f} (error: {abs(pi_estimate - np.pi):.6f})")
EOF
        ;;
    2)
        echo "Running data analysis workload..."
        # Simulate data analysis
        python3 << EOF
import numpy as np
import pandas as pd
import time
import json

print("Performing data analysis...")
start_time = time.time()

# Generate synthetic dataset
n_rows = 1000000
data = {
    "id": range(n_rows),
    "value1": np.random.normal(100, 15, n_rows),
    "value2": np.random.exponential(2, n_rows),
    "category": np.random.choice(["A", "B", "C", "D"], n_rows),
    "timestamp": pd.date_range("2024-01-01", periods=n_rows, freq="1min")
}

df = pd.DataFrame(data)

# Perform analysis
summary_stats = df.groupby("category").agg({
    "value1": ["mean", "std", "min", "max"],
    "value2": ["mean", "std", "min", "max"]
}).round(3)

# Time series analysis
df["hour"] = df["timestamp"].dt.hour
hourly_avg = df.groupby("hour")["value1"].mean().round(3)

computation_time = time.time() - start_time

# Save results
results = {
    "task_index": $JOB_INDEX,
    "computation_type": "data_analysis",
    "rows_processed": n_rows,
    "categories": len(df["category"].unique()),
    "computation_time": computation_time,
    "summary_stats": summary_stats.to_dict(),
    "hourly_patterns": hourly_avg.to_dict(),
    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
}

with open("results.json", "w") as f:
    json.dump(results, f, default=str, indent=2)

print(f"Data analysis completed in {computation_time:.2f} seconds")
print(f"Processed {n_rows:,} rows")
EOF
        ;;
    3)
        echo "Running stress test workload..."
        # CPU and memory stress test
        stress-ng --cpu $(nproc) --vm 2 --vm-bytes 80% --timeout 120s --metrics-brief > stress_results.txt 2>&1
        
        # Create results summary
        python3 << EOF
import json
import time
import subprocess

print("Analyzing stress test results...")

# Get system metrics
cpu_count = $(nproc)
memory_info = subprocess.run(["free", "-m"], capture_output=True, text=True)
memory_lines = memory_info.stdout.strip().split('\n')
memory_total = int(memory_lines[1].split()[1])

# Read stress test results
try:
    with open("stress_results.txt", "r") as f:
        stress_output = f.read()
except:
    stress_output = "Stress test completed"

results = {
    "task_index": $JOB_INDEX,
    "computation_type": "stress_test",
    "cpu_cores": cpu_count,
    "memory_mb": memory_total,
    "stress_duration": 120,
    "stress_output": stress_output[-500:],  # Last 500 chars
    "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
}

with open("results.json", "w") as f:
    json.dump(results, f, indent=2)

print("Stress test analysis completed")
EOF
        ;;
esac

# Create performance metrics
echo "Collecting performance metrics..."
cat > performance_metrics.json << EOF
{
  "task_index": $JOB_INDEX,
  "instance_name": "$INSTANCE_NAME",
  "machine_type": "$MACHINE_TYPE",
  "zone": "$ZONE",
  "cpu_cores": $(nproc),
  "memory_total_kb": $(grep MemTotal /proc/meminfo | awk '{print $2}'),
  "start_time": "$(date -Is)",
  "load_average": "$(uptime | awk -F'load average:' '{print $2}' | xargs)",
  "disk_usage": $(df / | tail -1 | awk '{print $5}' | sed 's/%//'),
  "network_interface": "$(ip route get 8.8.8.8 | awk '{print $5; exit}')"
}
EOF

# Upload results to Cloud Storage
echo "Uploading results to Cloud Storage..."
OUTPUT_PREFIX="results/task-$JOB_INDEX-$(date +%Y%m%d-%H%M%S)"

# Upload all result files
if [ -f "results.json" ]; then
    gsutil cp results.json "gs://$BUCKET_NAME/$OUTPUT_PREFIX/computation_results.json"
fi

gsutil cp performance_metrics.json "gs://$BUCKET_NAME/$OUTPUT_PREFIX/performance_metrics.json"

# Upload log file
if [ -f "$LOG_FILE" ]; then
    gsutil cp "$LOG_FILE" "gs://$BUCKET_NAME/$OUTPUT_PREFIX/workload.log"
fi

# Upload any additional output files
for file in *.txt *.csv *.png *.pdf; do
    if [ -f "$file" ]; then
        gsutil cp "$file" "gs://$BUCKET_NAME/$OUTPUT_PREFIX/"
    fi
done

echo "Results uploaded to gs://$BUCKET_NAME/$OUTPUT_PREFIX/"

# Clean up working directory
cd /
rm -rf "$WORK_DIR"

# Send completion notification
gcloud logging write hpc-batch-workload \
  "{\"message\": \"Batch workload completed\", \"task_index\": $JOB_INDEX, \"instance\": \"$INSTANCE_NAME\", \"machine_type\": \"$MACHINE_TYPE\", \"output_path\": \"gs://$BUCKET_NAME/$OUTPUT_PREFIX/\", \"timestamp\": \"$(date -Is)\"}" \
  --severity=INFO

echo "Cloud Batch HPC workload completed successfully at $(date)"
echo "Task $JOB_INDEX of $TASK_COUNT finished"
echo "Results available at: gs://$BUCKET_NAME/$OUTPUT_PREFIX/"

# Final system status
echo "=== Final System Status ==="
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)"
echo "Memory Usage: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"

exit 0