#!/bin/bash

# Scientific Video Analysis Workflows with Cluster Toolkit and Gemini Fine-tuning
# Deployment Script for GCP Infrastructure
# 
# This script deploys the complete infrastructure for scientific video analysis
# including HPC cluster, Vertex AI components, Cloud Dataflow, and monitoring

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="scientific-video-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Scientific Video Analysis Workflows infrastructure on GCP

OPTIONS:
    -p, --project       GCP Project ID (default: auto-generated)
    -r, --region        GCP Region (default: us-central1)
    -z, --zone          GCP Zone (default: us-central1-a)
    -c, --cluster-name  HPC Cluster name (default: video-analysis-cluster)
    -h, --help          Show this help message
    --dry-run           Show what would be deployed without executing
    --skip-cluster      Skip HPC cluster deployment (for testing)
    --skip-ai           Skip Vertex AI setup (for testing)

EXAMPLES:
    $0                                  # Deploy with defaults
    $0 -p my-project -r us-west1       # Deploy to specific project/region
    $0 --dry-run                       # Preview deployment without executing

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        error "git is not installed. Please install git."
        exit 1
    fi
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        warning "terraform is not installed. HPC cluster deployment may fail."
    fi
    
    # Check if python3 is installed
    if ! command -v python3 &> /dev/null; then
        error "python3 is not installed. Please install Python 3.8 or later."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to validate quotas
check_quotas() {
    log "Checking GCP quotas for deployment..."
    
    local current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -n "$current_project" ]]; then
        # Check compute quotas
        local cpu_quota=$(gcloud compute project-info describe \
            --format="value(quotas[metric=CPUS].limit)" 2>/dev/null || echo "0")
        
        if [[ "$cpu_quota" -lt 32 ]]; then
            warning "CPU quota ($cpu_quota) may be insufficient for HPC cluster. Recommended: 32+ vCPUs"
        fi
        
        # Check GPU quotas
        local gpu_quota=$(gcloud compute project-info describe \
            --format="value(quotas[metric=NVIDIA_T4_GPUS].limit)" 2>/dev/null || echo "0")
        
        if [[ "$gpu_quota" -lt 4 ]]; then
            warning "GPU quota ($gpu_quota) may be insufficient. Recommended: 4+ T4 GPUs"
        fi
    fi
    
    success "Quota validation completed"
}

# Function to setup project configuration
setup_project() {
    log "Setting up project configuration..."
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="scientific-video-data-${RANDOM_SUFFIX}"
    export DATASET_NAME="video_analysis_results"
    
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
    log "Cluster Name: ${CLUSTER_NAME}"
    log "Bucket Name: ${BUCKET_NAME}"
    
    success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "dataflow.googleapis.com"
        "bigquery.googleapis.com"
        "container.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "serviceusage.googleapis.com"
        "iam.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if ! gcloud services enable "${api}" --quiet; then
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create Cloud Storage infrastructure
setup_storage() {
    log "Setting up Cloud Storage infrastructure..."
    
    # Create main data bucket
    if ! gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log "Creating Cloud Storage bucket: ${BUCKET_NAME}"
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        
        # Enable versioning for data protection
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        # Create directory structure
        log "Creating bucket directory structure..."
        echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/raw-videos/.placeholder"
        echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/processed-results/.placeholder"
        echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/model-artifacts/.placeholder"
        echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/temp/.placeholder"
        echo "placeholder" | gsutil cp - "gs://${BUCKET_NAME}/staging/.placeholder"
        
        success "Cloud Storage bucket created and configured"
    else
        warning "Bucket ${BUCKET_NAME} already exists, skipping creation"
    fi
}

# Function to setup BigQuery
setup_bigquery() {
    log "Setting up BigQuery infrastructure..."
    
    # Create BigQuery dataset
    if ! bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log "Creating BigQuery dataset: ${DATASET_NAME}"
        bq mk --dataset \
            --location="${REGION}" \
            --description="Video analysis results dataset" \
            "${PROJECT_ID}:${DATASET_NAME}"
        
        # Create results table
        log "Creating video analysis results table..."
        bq mk --table \
            --description="Video analysis results and metadata" \
            "${PROJECT_ID}:${DATASET_NAME}.video_analysis_results" \
            "video_file:STRING,job_id:STRING,analysis_results:STRING,timestamp:TIMESTAMP,processing_duration:FLOAT,frame_count:INTEGER,confidence_score:FLOAT"
        
        success "BigQuery dataset and tables created"
    else
        warning "BigQuery dataset ${DATASET_NAME} already exists, skipping creation"
    fi
}

# Function to setup Vertex AI
setup_vertex_ai() {
    if [[ "$SKIP_AI" == "true" ]]; then
        warning "Skipping Vertex AI setup (--skip-ai flag provided)"
        return 0
    fi
    
    log "Setting up Vertex AI infrastructure..."
    
    # Create Vertex AI dataset
    log "Creating Vertex AI dataset for scientific video analysis..."
    if ! gcloud ai datasets list --region="${REGION}" --filter="displayName:scientific-video-dataset" --format="value(name)" | grep -q "scientific-video-dataset"; then
        gcloud ai datasets create \
            --display-name="scientific-video-dataset" \
            --metadata-schema-uri="gs://google-cloud-aiplatform/schema/dataset/metadata/text_1.0.0.yaml" \
            --region="${REGION}"
    else
        warning "Vertex AI dataset already exists, skipping creation"
    fi
    
    # Store dataset ID
    DATASET_ID=$(gcloud ai datasets list \
        --region="${REGION}" \
        --filter="displayName:scientific-video-dataset" \
        --format="value(name)" | cut -d'/' -f6)
    
    export DATASET_ID
    
    # Create training dataset for Gemini fine-tuning
    log "Creating training dataset for Gemini fine-tuning..."
    cat > "${SCRIPT_DIR}/scientific-video-training.jsonl" << 'EOF'
{"input_text": "Analyze this microscopy video for cellular division patterns", "output_text": "This video shows metaphase alignment of chromosomes during mitosis. The spindle apparatus is clearly visible, indicating normal cell division progression. Key features include: 1) Chromosome condensation and alignment at the metaphase plate, 2) Spindle fiber attachment to kinetochores, 3) Cell cycle checkpoint activation prior to anaphase onset."}
{"input_text": "Identify behavioral patterns in this wildlife tracking video", "output_text": "The video demonstrates foraging behavior in the subject species. Observable patterns include: 1) Systematic search patterns with 15-20 second intervals, 2) Preference for vegetation at 0.5-1.5m height, 3) Social coordination between individuals during resource discovery, 4) Territorial marking behaviors at feeding sites."}
{"input_text": "Evaluate protein crystal formation in this time-lapse sequence", "output_text": "Crystal nucleation occurs at 2:15 timestamp with initial formation of ordered lattice structures. Growth proceeds through: 1) Primary nucleation phase with spherical clusters, 2) Secondary nucleation creating dendritic branches, 3) Final stabilization showing tetragonal crystal system, 4) Estimated crystal quality grade A based on optical clarity."}
EOF
    
    # Upload training data to Cloud Storage
    gsutil cp "${SCRIPT_DIR}/scientific-video-training.jsonl" \
        "gs://${BUCKET_NAME}/model-artifacts/training-data/"
    
    log "Note: Gemini fine-tuning requires manual configuration through Vertex AI Console"
    log "Training data uploaded to: gs://${BUCKET_NAME}/model-artifacts/training-data/"
    
    success "Vertex AI infrastructure setup completed"
}

# Function to deploy HPC cluster
deploy_hpc_cluster() {
    if [[ "$SKIP_CLUSTER" == "true" ]]; then
        warning "Skipping HPC cluster deployment (--skip-cluster flag provided)"
        return 0
    fi
    
    log "Deploying HPC cluster with Cluster Toolkit..."
    
    # Clone Cluster Toolkit if not exists
    if [[ ! -d "${SCRIPT_DIR}/hpc-toolkit" ]]; then
        log "Cloning HPC Toolkit repository..."
        git clone https://github.com/GoogleCloudPlatform/hpc-toolkit.git "${SCRIPT_DIR}/hpc-toolkit"
    fi
    
    cd "${SCRIPT_DIR}/hpc-toolkit"
    
    # Create cluster configuration
    log "Creating HPC cluster configuration..."
    cat > "video-analysis-cluster.yaml" << EOF
blueprint_name: video-analysis-cluster

vars:
  project_id: ${PROJECT_ID}
  deployment_name: ${CLUSTER_NAME}
  region: ${REGION}
  zone: ${ZONE}

deployment_groups:
- group: primary
  modules:
  - id: network
    source: modules/network/vpc
    
  - id: filestore
    source: modules/file-system/filestore
    use: [network]
    settings:
      filestore_tier: HIGH_SCALE_SSD
      size_gb: 2560
      
  - id: compute_partition
    source: modules/compute/schedmd-slurm-gcp-v5-partition
    use: [network]
    settings:
      partition_name: compute
      machine_type: c2-standard-16
      max_node_count: 10
      
  - id: gpu_partition
    source: modules/compute/schedmd-slurm-gcp-v5-partition
    use: [network]
    settings:
      partition_name: gpu
      machine_type: n1-standard-4
      accelerator_type: nvidia-tesla-t4
      accelerator_count: 1
      max_node_count: 4
      
  - id: slurm_controller
    source: modules/scheduler/schedmd-slurm-gcp-v5-controller
    use: [network, filestore, compute_partition, gpu_partition]
    
  - id: slurm_login
    source: modules/scheduler/schedmd-slurm-gcp-v5-login
    use: [network, slurm_controller]
EOF
    
    # Build and deploy the cluster
    log "Building HPC cluster deployment..."
    if ./ghpc create video-analysis-cluster.yaml; then
        cd video-analysis-cluster
        
        log "Initializing Terraform..."
        terraform init
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "Dry run: showing Terraform plan..."
            terraform plan
        else
            log "Deploying HPC cluster infrastructure..."
            terraform apply -auto-approve
            
            # Wait for cluster to be ready
            log "Waiting for cluster to be fully operational..."
            sleep 60
            
            success "HPC cluster deployment completed"
        fi
    else
        error "Failed to create HPC cluster configuration"
        return 1
    fi
    
    cd "${SCRIPT_DIR}"
}

# Function to setup video analysis scripts
setup_analysis_scripts() {
    log "Setting up video analysis scripts..."
    
    # Create video analysis script
    cat > "${SCRIPT_DIR}/video-analysis-script.py" << 'EOF'
#!/usr/bin/env python3
"""
Scientific Video Analysis Script for HPC Cluster
Processes scientific videos using computer vision and AI analysis
"""

import argparse
import subprocess
import json
import cv2
import numpy as np
import tempfile
import logging
import os
import time
from datetime import datetime
from typing import List, Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def extract_frames(video_path: str, output_dir: str, frame_interval: int = 30) -> List[str]:
    """Extract frames from video at specified intervals"""
    logger.info(f"Extracting frames from {video_path}")
    
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Could not open video file: {video_path}")
    
    frame_count = 0
    extracted_frames = []
    
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            if frame_count % frame_interval == 0:
                frame_path = os.path.join(output_dir, f"frame_{frame_count:06d}.jpg")
                cv2.imwrite(frame_path, frame)
                extracted_frames.append(frame_path)
            
            frame_count += 1
    finally:
        cap.release()
    
    logger.info(f"Extracted {len(extracted_frames)} frames from {frame_count} total frames")
    return extracted_frames

def analyze_frame_basic(frame_path: str) -> Dict[str, Any]:
    """Perform basic computer vision analysis on frame"""
    try:
        # Load image
        image = cv2.imread(frame_path)
        if image is None:
            return {"error": "Could not load image"}
        
        # Basic image statistics
        height, width, channels = image.shape
        mean_brightness = np.mean(cv2.cvtColor(image, cv2.COLOR_BGR2GRAY))
        
        # Edge detection for content analysis
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        edges = cv2.Canny(gray, 50, 150)
        edge_density = np.sum(edges > 0) / (height * width)
        
        # Color analysis
        bgr_mean = np.mean(image, axis=(0, 1))
        
        return {
            "frame_path": frame_path,
            "dimensions": {"width": width, "height": height, "channels": channels},
            "brightness": float(mean_brightness),
            "edge_density": float(edge_density),
            "color_analysis": {
                "mean_blue": float(bgr_mean[0]),
                "mean_green": float(bgr_mean[1]),
                "mean_red": float(bgr_mean[2])
            },
            "quality_score": min(1.0, edge_density * 2 + (mean_brightness / 255) * 0.5)
        }
    except Exception as e:
        logger.error(f"Error analyzing frame {frame_path}: {e}")
        return {"error": str(e)}

def process_video_file(video_path: str, output_bucket: str) -> Dict[str, Any]:
    """Main video processing function"""
    start_time = time.time()
    logger.info(f"Processing video: {video_path}")
    
    try:
        # Create temporary directory for frame extraction
        with tempfile.TemporaryDirectory() as temp_dir:
            # Extract frames from video
            frames = extract_frames(video_path, temp_dir)
            
            if not frames:
                return {"error": "No frames extracted from video"}
            
            # Analyze each frame
            analysis_results = []
            for i, frame_path in enumerate(frames):
                logger.info(f"Analyzing frame {i+1}/{len(frames)}")
                analysis = analyze_frame_basic(frame_path)
                
                if "error" not in analysis:
                    analysis_results.append({
                        'frame_index': i,
                        'frame_path': os.path.basename(frame_path),
                        'analysis': analysis,
                        'timestamp': analysis.get('timestamp', i * 30)  # Assuming 30 frame intervals
                    })
            
            # Generate comprehensive video analysis report
            processing_time = time.time() - start_time
            
            report = {
                'video_file': video_path,
                'total_frames_analyzed': len(analysis_results),
                'processing_duration_seconds': processing_time,
                'analysis_results': analysis_results,
                'summary': generate_video_summary(analysis_results),
                'processing_timestamp': datetime.now().isoformat(),
                'metadata': {
                    'processor_version': '1.0',
                    'analysis_type': 'basic_computer_vision'
                }
            }
            
            # Save results locally first
            output_file = f"{os.path.basename(video_path)}_analysis.json"
            local_output_path = os.path.join(temp_dir, output_file)
            
            with open(local_output_path, 'w') as f:
                json.dump(report, f, indent=2)
            
            # Upload to Cloud Storage if gsutil is available
            try:
                gs_path = f"gs://{output_bucket}/processed-results/{output_file}"
                subprocess.run(['gsutil', 'cp', local_output_path, gs_path], 
                             check=True, capture_output=True)
                logger.info(f"Results uploaded to {gs_path}")
                report['output_location'] = gs_path
            except (subprocess.CalledProcessError, FileNotFoundError) as e:
                logger.warning(f"Could not upload to Cloud Storage: {e}")
                report['output_location'] = local_output_path
            
            logger.info(f"Analysis completed for {video_path}")
            return report
            
    except Exception as e:
        logger.error(f"Error processing video {video_path}: {e}")
        return {"error": str(e), "video_file": video_path}

def generate_video_summary(analysis_results: List[Dict]) -> Dict[str, Any]:
    """Generate summary using aggregated frame analyses"""
    if not analysis_results:
        return {"error": "No analysis results to summarize"}
    
    # Calculate aggregate statistics
    quality_scores = [r['analysis'].get('quality_score', 0) for r in analysis_results if 'analysis' in r]
    brightness_values = [r['analysis'].get('brightness', 0) for r in analysis_results if 'analysis' in r]
    edge_densities = [r['analysis'].get('edge_density', 0) for r in analysis_results if 'analysis' in r]
    
    summary = {
        'frame_count': len(analysis_results),
        'quality_metrics': {
            'average_quality_score': np.mean(quality_scores) if quality_scores else 0,
            'quality_consistency': 1.0 - np.std(quality_scores) if len(quality_scores) > 1 else 1.0,
            'min_quality': min(quality_scores) if quality_scores else 0,
            'max_quality': max(quality_scores) if quality_scores else 0
        },
        'visual_characteristics': {
            'average_brightness': np.mean(brightness_values) if brightness_values else 0,
            'brightness_variation': np.std(brightness_values) if len(brightness_values) > 1 else 0,
            'average_edge_density': np.mean(edge_densities) if edge_densities else 0,
            'content_complexity': 'high' if np.mean(edge_densities) > 0.1 else 'low'
        },
        'recommendations': generate_recommendations(quality_scores, brightness_values, edge_densities)
    }
    
    return summary

def generate_recommendations(quality_scores: List[float], brightness_values: List[float], edge_densities: List[float]) -> List[str]:
    """Generate analysis recommendations based on video characteristics"""
    recommendations = []
    
    if quality_scores:
        avg_quality = np.mean(quality_scores)
        if avg_quality < 0.3:
            recommendations.append("Video quality is low. Consider preprocessing for better analysis results.")
        elif avg_quality > 0.7:
            recommendations.append("High video quality detected. Suitable for detailed analysis.")
    
    if brightness_values:
        avg_brightness = np.mean(brightness_values)
        if avg_brightness < 50:
            recommendations.append("Video appears dark. Consider brightness enhancement.")
        elif avg_brightness > 200:
            recommendations.append("Video appears overexposed. Consider exposure correction.")
    
    if edge_densities:
        avg_edge_density = np.mean(edge_densities)
        if avg_edge_density > 0.15:
            recommendations.append("High content complexity. Suitable for detailed feature extraction.")
        elif avg_edge_density < 0.05:
            recommendations.append("Low content complexity. May require different analysis approaches.")
    
    if not recommendations:
        recommendations.append("Video characteristics are within normal ranges for analysis.")
    
    return recommendations

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Scientific Video Analysis')
    parser.add_argument('--input', required=True, help='Input video file path')
    parser.add_argument('--output', required=True, help='Output bucket name')
    parser.add_argument('--model-endpoint', help='Gemini model endpoint (optional)')
    parser.add_argument('--frame-interval', type=int, default=30, 
                       help='Frame extraction interval (default: 30)')
    
    args = parser.parse_args()
    
    # Validate input file
    if not os.path.exists(args.input):
        logger.error(f"Input video file not found: {args.input}")
        return 1
    
    # Process the video file
    try:
        result = process_video_file(args.input, args.output)
        
        if "error" in result:
            logger.error(f"Processing failed: {result['error']}")
            return 1
        
        # Print summary to stdout
        print(json.dumps(result, indent=2))
        return 0
        
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return 1

if __name__ == '__main__':
    exit(main())
EOF
    
    # Create job submission script
    cat > "${SCRIPT_DIR}/submit-video-analysis.sh" << 'EOF'
#!/bin/bash

# Video analysis job submission script for Slurm cluster
set -euo pipefail

VIDEO_INPUT_PATH="$1"
OUTPUT_BUCKET="$2"
MODEL_ENDPOINT="${3:-}"

# Validate inputs
if [[ -z "$VIDEO_INPUT_PATH" ]] || [[ -z "$OUTPUT_BUCKET" ]]; then
    echo "Usage: $0 <video_input_path> <output_bucket> [model_endpoint]"
    exit 1
fi

# Determine job parameters based on video size
if command -v gsutil &> /dev/null && [[ "$VIDEO_INPUT_PATH" =~ ^gs:// ]]; then
    VIDEO_SIZE=$(gsutil du "$VIDEO_INPUT_PATH" | cut -f1)
else
    VIDEO_SIZE=$(stat -c%s "$VIDEO_INPUT_PATH" 2>/dev/null || echo "1000000")
fi

# Configure job parameters based on video size
if [[ "$VIDEO_SIZE" -gt 1000000000 ]]; then  # > 1GB
    PARTITION="gpu"
    TIME_LIMIT="04:00:00"
    MEMORY="32GB"
    CPUS="8"
else
    PARTITION="compute"
    TIME_LIMIT="02:00:00"
    MEMORY="16GB"
    CPUS="4"
fi

# Create unique job ID
JOB_ID="video-analysis-$(date +%s)-$$"

# Create log directory if it doesn't exist
mkdir -p "/shared/logs"

# Create Slurm job script
cat > "/tmp/${JOB_ID}.sh" << SLURM_EOF
#!/bin/bash
#SBATCH --partition=${PARTITION}
#SBATCH --time=${TIME_LIMIT}
#SBATCH --mem=${MEMORY}
#SBATCH --cpus-per-task=${CPUS}
#SBATCH --job-name=${JOB_ID}
#SBATCH --output=/shared/logs/${JOB_ID}.out
#SBATCH --error=/shared/logs/${JOB_ID}.err

# Load required modules
module load python/3.8 || echo "Python module not available, using system python"
module load ffmpeg || echo "FFmpeg module not available"
module load opencv || echo "OpenCV module not available"

# Set up environment
export PYTHONPATH="/shared/python:$PYTHONPATH"
export PATH="/shared/bin:$PATH"

# Set up Google Cloud authentication if available
if [[ -f "/shared/credentials/service-account.json" ]]; then
    export GOOGLE_APPLICATION_CREDENTIALS="/shared/credentials/service-account.json"
fi

# Install required Python packages if not available
python3 -c "import cv2" 2>/dev/null || pip3 install --user opencv-python
python3 -c "import numpy" 2>/dev/null || pip3 install --user numpy

# Download video file if it's from Cloud Storage
if [[ "$VIDEO_INPUT_PATH" =~ ^gs:// ]]; then
    LOCAL_VIDEO="/tmp/$(basename $VIDEO_INPUT_PATH)"
    gsutil cp "$VIDEO_INPUT_PATH" "$LOCAL_VIDEO"
    INPUT_FILE="$LOCAL_VIDEO"
else
    INPUT_FILE="$VIDEO_INPUT_PATH"
fi

# Execute video analysis
echo "Starting video analysis: $VIDEO_INPUT_PATH"
echo "Job ID: $JOB_ID"
echo "Partition: $PARTITION"
echo "Allocated memory: $MEMORY"
echo "CPUs: $CPUS"

python3 /shared/video-analysis-script.py \
    --input="$INPUT_FILE" \
    --output="$OUTPUT_BUCKET" \
    ${MODEL_ENDPOINT:+--model-endpoint="$MODEL_ENDPOINT"}

EXIT_CODE=$?

# Clean up temporary files
if [[ "$VIDEO_INPUT_PATH" =~ ^gs:// ]] && [[ -f "$LOCAL_VIDEO" ]]; then
    rm -f "$LOCAL_VIDEO"
fi

# Log completion
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Video analysis completed successfully: $VIDEO_INPUT_PATH" >> /shared/logs/completed-jobs.log
else
    echo "Video analysis failed: $VIDEO_INPUT_PATH (exit code: $EXIT_CODE)" >> /shared/logs/failed-jobs.log
fi

exit $EXIT_CODE
SLURM_EOF

# Submit the job
echo "Submitting job: $JOB_ID"
if command -v sbatch &> /dev/null; then
    sbatch "/tmp/${JOB_ID}.sh"
    echo "Job submitted with ID: $JOB_ID"
    echo "Monitor with: squeue -j \$JOB_ID"
    echo "View output: tail -f /shared/logs/${JOB_ID}.out"
else
    echo "Slurm not available, running job directly..."
    bash "/tmp/${JOB_ID}.sh"
fi

# Clean up temporary script
rm -f "/tmp/${JOB_ID}.sh"
EOF
    
    # Make scripts executable
    chmod +x "${SCRIPT_DIR}/video-analysis-script.py"
    chmod +x "${SCRIPT_DIR}/submit-video-analysis.sh"
    
    success "Video analysis scripts created and configured"
}

# Function to create monitoring setup
setup_monitoring() {
    log "Setting up monitoring and logging..."
    
    # Create monitoring script
    cat > "${SCRIPT_DIR}/monitor-video-jobs.py" << 'EOF'
#!/usr/bin/env python3
"""
Video Analysis Job Monitoring Script
Monitors Slurm jobs and sends metrics to Cloud Monitoring
"""

import subprocess
import json
import time
import os
import sys
from datetime import datetime
from typing import List, Dict, Any

try:
    from google.cloud import monitoring_v3
    from google.cloud import logging as cloud_logging
    CLOUD_MONITORING_AVAILABLE = True
except ImportError:
    print("Google Cloud libraries not available, using local monitoring only")
    CLOUD_MONITORING_AVAILABLE = False

def get_slurm_job_status() -> List[Dict[str, Any]]:
    """Get current Slurm job status"""
    try:
        result = subprocess.run(['squeue', '-o', '%i,%j,%t,%M,%u'], 
                              capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            print(f"squeue command failed: {result.stderr}")
            return []
        
        jobs = []
        lines = result.stdout.strip().split('\n')
        
        # Skip header line
        for line in lines[1:] if len(lines) > 1 else []:
            try:
                job_id, job_name, status, time_used, user = line.split(',')
                if 'video-analysis' in job_name:
                    jobs.append({
                        'job_id': job_id.strip(),
                        'job_name': job_name.strip(),
                        'status': status.strip(),
                        'time_used': time_used.strip(),
                        'user': user.strip()
                    })
            except ValueError:
                continue  # Skip malformed lines
        
        return jobs
    except (subprocess.TimeoutExpired, FileNotFoundError):
        print("Slurm not available or command timed out")
        return []

def send_metrics_to_monitoring(jobs: List[Dict[str, Any]], project_id: str, zone: str):
    """Send job metrics to Cloud Monitoring"""
    if not CLOUD_MONITORING_AVAILABLE:
        return
    
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{project_id}"
        
        # Create time series for active jobs count
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/video_analysis/active_jobs"
        series.resource.type = "gce_instance"
        series.resource.labels["instance_id"] = "video-analysis-cluster"
        series.resource.labels["zone"] = zone
        series.resource.labels["project_id"] = project_id
        
        point = monitoring_v3.Point()
        point.value.int64_value = len(jobs)
        point.interval.end_time.seconds = int(time.time())
        series.points = [point]
        
        client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        # Create separate metrics for different job states
        status_counts = {}
        for job in jobs:
            status = job['status']
            status_counts[status] = status_counts.get(status, 0) + 1
        
        for status, count in status_counts.items():
            series = monitoring_v3.TimeSeries()
            series.metric.type = f"custom.googleapis.com/video_analysis/jobs_{status.lower()}"
            series.resource.type = "gce_instance"
            series.resource.labels["instance_id"] = "video-analysis-cluster"
            series.resource.labels["zone"] = zone
            series.resource.labels["project_id"] = project_id
            
            point = monitoring_v3.Point()
            point.value.int64_value = count
            point.interval.end_time.seconds = int(time.time())
            series.points = [point]
            
            client.create_time_series(
                name=project_name,
                time_series=[series]
            )
        
    except Exception as e:
        print(f"Error sending metrics to Cloud Monitoring: {e}")

def log_job_status(jobs: List[Dict[str, Any]]):
    """Log job status locally and to console"""
    timestamp = datetime.now().isoformat()
    
    # Console output
    print(f"\n[{timestamp}] Video Analysis Job Status")
    print("-" * 50)
    print(f"Active jobs: {len(jobs)}")
    
    if jobs:
        print(f"{'Job ID':<15} {'Status':<10} {'Runtime':<10} {'User':<10}")
        print("-" * 50)
        for job in jobs:
            print(f"{job['job_id']:<15} {job['status']:<10} {job['time_used']:<10} {job['user']:<10}")
    else:
        print("No active video analysis jobs")
    
    # Log to file
    try:
        os.makedirs("/shared/logs", exist_ok=True)
        with open("/shared/logs/monitoring.log", "a") as f:
            f.write(f"{timestamp}: {len(jobs)} active jobs\n")
            for job in jobs:
                f.write(f"  {job['job_id']}: {job['status']} ({job['time_used']})\n")
    except Exception as e:
        print(f"Error writing to log file: {e}")

def check_completed_jobs():
    """Check for recently completed jobs and log statistics"""
    try:
        # Check completed jobs log
        completed_log = "/shared/logs/completed-jobs.log"
        failed_log = "/shared/logs/failed-jobs.log"
        
        completed_count = 0
        failed_count = 0
        
        if os.path.exists(completed_log):
            with open(completed_log, "r") as f:
                completed_count = len(f.readlines())
        
        if os.path.exists(failed_log):
            with open(failed_log, "r") as f:
                failed_count = len(f.readlines())
        
        print(f"Job Statistics - Completed: {completed_count}, Failed: {failed_count}")
        
    except Exception as e:
        print(f"Error checking completed jobs: {e}")

def main():
    """Main monitoring loop"""
    # Get environment variables
    project_id = os.environ.get('PROJECT_ID', 'unknown-project')
    zone = os.environ.get('ZONE', 'unknown-zone')
    
    print(f"Starting video analysis job monitoring...")
    print(f"Project: {project_id}, Zone: {zone}")
    print(f"Cloud Monitoring available: {CLOUD_MONITORING_AVAILABLE}")
    print("Press Ctrl+C to stop monitoring")
    
    try:
        while True:
            jobs = get_slurm_job_status()
            log_job_status(jobs)
            
            if CLOUD_MONITORING_AVAILABLE:
                send_metrics_to_monitoring(jobs, project_id, zone)
            
            check_completed_jobs()
            
            # Wait before next check
            time.sleep(60)
            
    except KeyboardInterrupt:
        print("\nMonitoring stopped by user")
    except Exception as e:
        print(f"Monitoring error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF
    
    chmod +x "${SCRIPT_DIR}/monitor-video-jobs.py"
    
    success "Monitoring setup completed"
}

# Function to create sample test data
create_test_data() {
    log "Creating sample test data and metadata..."
    
    # Create sample video metadata
    cat > "${SCRIPT_DIR}/sample-video-metadata.json" << EOF
{
  "video_id": "test-microscopy-001",
  "video_type": "microscopy",
  "duration_seconds": 120,
  "resolution": "1920x1080",
  "frame_rate": 30,
  "subject": "cellular_division",
  "research_context": "mitosis_analysis",
  "analysis_requirements": [
    "chromosome_alignment",
    "spindle_formation",
    "cell_cycle_progression"
  ],
  "created_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "researcher": "automated-test",
  "institution": "sample-research-lab"
}
EOF
    
    # Upload test metadata
    gsutil cp "${SCRIPT_DIR}/sample-video-metadata.json" \
        "gs://${BUCKET_NAME}/raw-videos/metadata/"
    
    success "Test data and metadata created"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo "Cluster Name: ${CLUSTER_NAME}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "BigQuery Dataset: ${PROJECT_ID}:${DATASET_NAME}"
    echo ""
    echo "Resources Created:"
    echo "- HPC Cluster with Slurm scheduler"
    echo "- Cloud Storage bucket with organized structure"
    echo "- BigQuery dataset for analysis results"
    echo "- Vertex AI dataset for model training"
    echo "- Video analysis and monitoring scripts"
    echo ""
    echo "Next Steps:"
    echo "1. Upload scientific videos to gs://${BUCKET_NAME}/raw-videos/"
    echo "2. Configure Gemini fine-tuning in Vertex AI Console"
    echo "3. Submit analysis jobs using: /shared/scripts/submit-video-analysis.sh"
    echo "4. Monitor progress with: python3 /shared/scripts/monitor-video-jobs.py"
    echo ""
    echo "Estimated monthly cost: \$200-500 (depending on usage)"
    echo "Remember to run destroy.sh when finished to avoid ongoing charges"
    
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Scientific Video Analysis Workflows deployment..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -c|--cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --skip-cluster)
                SKIP_CLUSTER="true"
                shift
                ;;
            --skip-ai)
                SKIP_AI="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set defaults for unspecified parameters
    PROJECT_ID="${PROJECT_ID:-$PROJECT_NAME}"
    REGION="${REGION:-$DEFAULT_REGION}"
    ZONE="${ZONE:-$DEFAULT_ZONE}"
    CLUSTER_NAME="${CLUSTER_NAME:-video-analysis-cluster}"
    DRY_RUN="${DRY_RUN:-false}"
    SKIP_CLUSTER="${SKIP_CLUSTER:-false}"
    SKIP_AI="${SKIP_AI:-false}"
    
    # Export environment variables for use in scripts
    export PROJECT_ID REGION ZONE CLUSTER_NAME
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    check_quotas
    setup_project
    
    if [[ "$DRY_RUN" != "true" ]]; then
        enable_apis
        setup_storage
        setup_bigquery
        setup_vertex_ai
        deploy_hpc_cluster
        setup_analysis_scripts
        setup_monitoring
        create_test_data
        display_summary
    else
        log "Dry run completed - review the planned deployment above"
    fi
}

# Execute main function with all arguments
main "$@"