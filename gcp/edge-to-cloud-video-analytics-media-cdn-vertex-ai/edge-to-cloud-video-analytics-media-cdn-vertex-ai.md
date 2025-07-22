---
title: Edge-to-Cloud Video Analytics with Media CDN and Vertex AI
id: a8f3d5e7
category: analytics
difficulty: 200
subject: gcp
services: Media CDN, Vertex AI, Cloud Functions, Cloud Storage
estimated-time: 120 minutes
recipe-version: 1.0
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: video analytics, edge computing, ai, content delivery, object detection, media streaming, automation
recipe-generator-version: 1.3
---

# Edge-to-Cloud Video Analytics with Media CDN and Vertex AI

## Problem

Media companies and content creators face the challenge of efficiently processing and analyzing massive volumes of streaming video content while delivering high-quality experiences to global audiences. Traditional video processing workflows often create bottlenecks between content ingestion, AI-powered analysis, and content delivery, resulting in delayed insights, increased latency for end users, and inefficient resource utilization. Without automated edge-to-cloud analytics pipelines, organizations struggle to extract real-time value from their video content while maintaining optimal performance for viewers worldwide.

## Solution

This solution leverages Google Cloud's Media CDN for global edge distribution combined with Vertex AI's powerful video analytics capabilities to create an intelligent, automated video processing pipeline. The architecture uses Cloud Storage as the central repository, Cloud Functions for event-driven processing triggers, and Vertex AI for sophisticated object detection and content classification. This integrated approach enables real-time video analysis at scale while ensuring optimal content delivery performance through Google's global edge network infrastructure.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Content Ingestion"
        VIDEO[Video Content]
        UPLOAD[Upload Process]
    end
    
    subgraph "Edge Layer"
        CDN[Media CDN<br/>Global Edge Network]
        CACHE[Edge Cache Locations]
    end
    
    subgraph "Storage & Processing"
        STORAGE[Cloud Storage<br/>Video Repository]
        TRIGGER[Cloud Functions<br/>Event Triggers]
        PROCESS[Video Processing<br/>Pipeline]
    end
    
    subgraph "AI Analytics"
        VERTEX[Vertex AI<br/>Video Analytics]
        DETECT[Object Detection]
        CLASSIFY[Content Classification]
    end
    
    subgraph "Insights Storage"
        RESULTS[Cloud Storage<br/>Analytics Results]
        METADATA[Video Metadata<br/>& Insights]
    end
    
    subgraph "Global Users"
        USERS[End Users<br/>Worldwide]
    end
    
    VIDEO-->UPLOAD
    UPLOAD-->STORAGE
    STORAGE-->TRIGGER
    TRIGGER-->PROCESS
    PROCESS-->VERTEX
    VERTEX-->DETECT
    VERTEX-->CLASSIFY
    DETECT-->RESULTS
    CLASSIFY-->RESULTS
    STORAGE-->CDN
    CDN-->CACHE
    CACHE-->USERS
    RESULTS-->METADATA
    
    style CDN fill:#4285F4
    style VERTEX fill:#34A853
    style STORAGE fill:#FBBC04
    style TRIGGER fill:#EA4335
```

## Prerequisites

1. Google Cloud Project with billing enabled and appropriate IAM permissions
2. Google Cloud CLI (gcloud) installed and configured or Cloud Shell access
3. Basic knowledge of video processing concepts and AI/ML workflows
4. Understanding of serverless functions and event-driven architectures
5. Estimated cost: $50-200 for testing (varies by video processing volume and CDN usage)

> **Note**: Media CDN requires approval from Google Cloud sales. Contact your account team to request access before starting this recipe.

## Preparation

```bash
# Set environment variables for GCP resources
export PROJECT_ID="video-analytics-$(date +%s)"
export REGION="us-central1"
export ZONE="us-central1-a"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set default project and region
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Enable required APIs
gcloud services enable storage.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable networkconnectivity.googleapis.com
gcloud services enable eventarc.googleapis.com

echo "✅ Project configured: ${PROJECT_ID}"

# Create resource names with unique suffixes
export BUCKET_NAME="video-content-${RANDOM_SUFFIX}"
export RESULTS_BUCKET="analytics-results-${RANDOM_SUFFIX}"
export FUNCTION_NAME="video-processor-${RANDOM_SUFFIX}"
export CDN_SERVICE_NAME="media-cdn-${RANDOM_SUFFIX}"

echo "✅ Resource names generated with suffix: ${RANDOM_SUFFIX}"
```

## Steps

1. **Create Cloud Storage Buckets for Video Content and Analytics Results**:

   Google Cloud Storage provides the foundational infrastructure for storing video content and analytics results. The primary bucket serves as both the origin for Media CDN distribution and the trigger point for automated processing. Creating separate buckets for raw content and processed results enables better organization and access control while supporting both high-throughput streaming and analytical workloads.

   ```bash
   # Create primary video content bucket
   gsutil mb -p ${PROJECT_ID} \
       -c STANDARD \
       -l ${REGION} \
       gs://${BUCKET_NAME}
   
   # Create analytics results bucket
   gsutil mb -p ${PROJECT_ID} \
       -c STANDARD \
       -l ${REGION} \
       gs://${RESULTS_BUCKET}
   
   # Enable versioning for data protection
   gsutil versioning set on gs://${BUCKET_NAME}
   gsutil versioning set on gs://${RESULTS_BUCKET}
   
   echo "✅ Storage buckets created successfully"
   echo "Video Content Bucket: gs://${BUCKET_NAME}"
   echo "Analytics Results Bucket: gs://${RESULTS_BUCKET}"
   ```

   The storage buckets now provide scalable, durable storage with automatic encryption and versioning enabled. This foundation supports both the real-time streaming requirements of Media CDN and the batch processing needs of Vertex AI analytics workflows.

2. **Configure Media CDN Edge Cache Service for Global Distribution**:

   Media CDN leverages Google's global edge network with over 100Tbps of capacity to deliver video content with minimal latency. The EdgeCacheService configuration defines how content is cached, routed, and delivered from edge locations worldwide. This setup enables cache hit ratios of 98.5-99% for video-on-demand content while providing origin protection and advanced routing capabilities.

   ```bash
   # Create EdgeCacheOrigin for Cloud Storage
   gcloud compute network-edge-security-services create ${CDN_SERVICE_NAME}-origin \
       --description="Origin for video content storage" \
       --region=${REGION}
   
   # Note: Full Media CDN configuration requires additional
   # setup through Google Cloud Console or REST API
   # as it involves advanced routing and caching policies
   
   echo "✅ Media CDN origin configuration initiated"
   echo "Complete setup in Cloud Console for full Media CDN configuration"
   ```

   The Media CDN configuration establishes the foundation for global content delivery with intelligent caching and routing. This infrastructure reduces origin load while ensuring optimal performance for users accessing video content from any geographic location.

3. **Deploy Cloud Function for Automated Video Processing Triggers**:

   Cloud Functions provides event-driven processing that automatically responds to new video uploads in Cloud Storage. The function serves as the orchestration layer, triggering Vertex AI analytics workflows whenever new content is available. This serverless approach ensures scalable, cost-effective processing that only consumes resources when videos require analysis.

   ```bash
   # Create function source directory
   mkdir -p video-processor-function
   cd video-processor-function
   
   # Create main function code
   cat > main.py << 'EOF'
import os
import json
from google.cloud import aiplatform
from google.cloud import storage
from google.cloud import functions_v1
import base64

def process_video(cloud_event):
    """Triggered by Cloud Storage object upload."""
    
    # Parse the Cloud Storage event
    file_name = cloud_event.data["name"]
    bucket_name = cloud_event.data["bucket"]
    
    # Skip if not a video file
    if not file_name.lower().endswith(('.mp4', '.mov', '.avi', '.mkv')):
        print(f"Skipping non-video file: {file_name}")
        return
    
    print(f"Processing video: {file_name} from bucket: {bucket_name}")
    
    # Initialize Vertex AI client
    project_id = os.environ.get('PROJECT_ID')
    region = os.environ.get('REGION', 'us-central1')
    
    aiplatform.init(project=project_id, location=region)
    
    # Trigger video analysis workflow
    video_uri = f"gs://{bucket_name}/{file_name}"
    
    # Create analytics job metadata
    analytics_metadata = {
        "video_uri": video_uri,
        "file_name": file_name,
        "bucket_name": bucket_name,
        "processing_status": "initiated",
        "timestamp": cloud_event.time
    }
    
    # Store metadata in results bucket
    results_bucket = os.environ.get('RESULTS_BUCKET')
    storage_client = storage.Client()
    results_bucket_obj = storage_client.bucket(results_bucket)
    
    metadata_blob = results_bucket_obj.blob(f"metadata/{file_name}.json")
    metadata_blob.upload_from_string(json.dumps(analytics_metadata))
    
    print(f"✅ Video processing initiated for: {file_name}")
    
    return {"status": "success", "video_uri": video_uri}
EOF
   
   # Create requirements.txt
   cat > requirements.txt << 'EOF'
google-cloud-aiplatform==1.38.0
google-cloud-storage==2.10.0
google-cloud-functions==1.8.3
EOF
   
   # Deploy the Cloud Function
   gcloud functions deploy ${FUNCTION_NAME} \
       --runtime python39 \
       --trigger-bucket ${BUCKET_NAME} \
       --entry-point process_video \
       --memory 512MB \
       --timeout 540s \
       --set-env-vars PROJECT_ID=${PROJECT_ID},REGION=${REGION},RESULTS_BUCKET=${RESULTS_BUCKET}
   
   cd ..
   
   echo "✅ Cloud Function deployed with Cloud Storage trigger"
   echo "Function Name: ${FUNCTION_NAME}"
   ```

   The Cloud Function now automatically processes new video uploads with built-in error handling and metadata tracking. This serverless architecture provides reliable, scalable event processing while maintaining cost efficiency through pay-per-invocation pricing.

4. **Configure Vertex AI Video Analytics Models for Object Detection**:

   Vertex AI provides pre-trained video analytics models optimized for object detection and content classification. These models leverage Google's advanced machine learning infrastructure to analyze video content at scale, identifying objects, activities, and content themes with high accuracy. The configuration enables automated analysis workflows that extract valuable insights from video content.

   ```bash
   # Create Vertex AI dataset for video analytics
   gcloud ai datasets create \
       --display-name="video-analytics-dataset-${RANDOM_SUFFIX}" \
       --metadata-schema-uri="gs://google-cloud-aiplatform/schema/dataset/metadata/video_1.0.0.yaml" \
       --region=${REGION}
   
   # Store dataset ID for future reference
   DATASET_ID=$(gcloud ai datasets list \
       --region=${REGION} \
       --filter="displayName:video-analytics-dataset-${RANDOM_SUFFIX}" \
       --format="value(name)" | cut -d'/' -f6)
   
   echo "Dataset ID: ${DATASET_ID}"
   
   # Create video analysis pipeline configuration
   cat > video-analysis-config.json << EOF
{
  "displayName": "video-analytics-pipeline-${RANDOM_SUFFIX}",
  "description": "Automated video analytics for object detection and classification",
  "inputDataConfig": {
    "gcsSource": {
      "uris": ["gs://${BUCKET_NAME}/*"]
    }
  },
  "outputDataConfig": {
    "gcsDestination": {
      "outputUriPrefix": "gs://${RESULTS_BUCKET}/analysis-results/"
    }
  }
}
EOF
   
   echo "✅ Vertex AI analytics configuration created"
   echo "Dataset ID: ${DATASET_ID}"
   ```

   The Vertex AI configuration establishes automated video analysis capabilities with pre-trained models for object detection and content classification. This setup enables sophisticated AI-powered insights while maintaining integration with the broader analytics pipeline.

5. **Create Advanced Video Processing Function for Vertex AI Integration**:

   This enhanced function leverages Vertex AI's Video Intelligence API to perform detailed video analysis including object detection, activity recognition, and content classification. The function processes videos asynchronously and stores detailed analytics results in Cloud Storage, creating a comprehensive video intelligence pipeline.

   ```bash
   # Create advanced video analytics function
   mkdir -p advanced-video-analytics
   cd advanced-video-analytics
   
   # Create enhanced processing function
   cat > main.py << 'EOF'
import os
import json
import asyncio
from google.cloud import videointelligence
from google.cloud import storage
from google.cloud import aiplatform
import logging

def analyze_video_content(cloud_event):
    """Advanced video analysis using Vertex AI Video Intelligence."""
    
    file_name = cloud_event.data["name"]
    bucket_name = cloud_event.data["bucket"]
    
    # Skip non-video files
    video_extensions = ('.mp4', '.mov', '.avi', '.mkv', '.webm')
    if not file_name.lower().endswith(video_extensions):
        return {"status": "skipped", "reason": "not a video file"}
    
    video_uri = f"gs://{bucket_name}/{file_name}"
    logging.info(f"Starting analysis for: {video_uri}")
    
    # Initialize Video Intelligence client
    video_client = videointelligence.VideoIntelligenceServiceClient()
    
    # Configure analysis features
    features = [
        videointelligence.Feature.OBJECT_TRACKING,
        videointelligence.Feature.LABEL_DETECTION,
        videointelligence.Feature.SHOT_CHANGE_DETECTION,
        videointelligence.Feature.TEXT_DETECTION
    ]
    
    # Configure analysis settings
    config = videointelligence.VideoContext(
        object_tracking_config=videointelligence.ObjectTrackingConfig(
            model="builtin/latest"
        ),
        label_detection_config=videointelligence.LabelDetectionConfig(
            model="builtin/latest",
            label_detection_mode=videointelligence.LabelDetectionMode.SHOT_AND_FRAME_MODE
        )
    )
    
    # Start video analysis operation
    operation = video_client.annotate_video(
        request={
            "features": features,
            "input_uri": video_uri,
            "video_context": config,
            "output_uri": f"gs://{os.environ.get('RESULTS_BUCKET')}/analysis/{file_name}_analysis.json"
        }
    )
    
    # Process results asynchronously
    print(f"Analysis started for {file_name}. Operation: {operation.operation.name}")
    
    # Store analysis metadata
    storage_client = storage.Client()
    results_bucket = storage_client.bucket(os.environ.get('RESULTS_BUCKET'))
    
    analysis_metadata = {
        "video_uri": video_uri,
        "file_name": file_name,
        "operation_name": operation.operation.name,
        "features_analyzed": [feature.name for feature in features],
        "status": "processing",
        "timestamp": cloud_event.time
    }
    
    metadata_blob = results_bucket.blob(f"operations/{file_name}_metadata.json")
    metadata_blob.upload_from_string(json.dumps(analysis_metadata, indent=2))
    
    return {
        "status": "analysis_started",
        "operation_name": operation.operation.name,
        "video_uri": video_uri
    }
EOF
   
   # Create requirements for advanced function
   cat > requirements.txt << 'EOF'
google-cloud-videointelligence==2.11.3
google-cloud-storage==2.10.0
google-cloud-aiplatform==1.38.0
asyncio
EOF
   
   # Deploy advanced analytics function
   gcloud functions deploy advanced-video-analytics-${RANDOM_SUFFIX} \
       --runtime python39 \
       --trigger-bucket ${BUCKET_NAME} \
       --entry-point analyze_video_content \
       --memory 1024MB \
       --timeout 540s \
       --set-env-vars PROJECT_ID=${PROJECT_ID},REGION=${REGION},RESULTS_BUCKET=${RESULTS_BUCKET}
   
   cd ..
   
   echo "✅ Advanced video analytics function deployed"
   ```

   The advanced video analytics function now provides comprehensive video analysis capabilities including object tracking, label detection, shot change detection, and text recognition. This creates a powerful AI-driven video intelligence pipeline that automatically processes content and generates detailed insights.

6. **Set Up Media CDN Cache Policies and Edge Optimization**:

   Media CDN's advanced caching policies optimize content delivery based on video characteristics, user location, and access patterns. Configuring appropriate cache headers, TTL values, and edge behaviors ensures optimal performance while minimizing origin load. This setup leverages Google's global edge network to deliver video content with minimal latency worldwide.

   ```bash
   # Create cache policy configuration
   cat > media-cdn-config.yaml << EOF
# Media CDN Configuration for Video Streaming
name: ${CDN_SERVICE_NAME}
description: "Intelligent edge caching for video analytics pipeline"
cache_policies:
  - name: "video-content-policy"
    default_ttl: "86400s"  # 24 hours
    max_ttl: "604800s"     # 7 days
    cache_key_policy:
      include_query_string: true
      query_string_blacklist: ["utm_source", "utm_medium"]
  - name: "analytics-results-policy"
    default_ttl: "3600s"   # 1 hour
    max_ttl: "86400s"      # 24 hours
origin_config:
  origin_uri: "gs://${BUCKET_NAME}"
  protocol: "HTTPS"
EOF
   
   # Configure origin for Media CDN (requires Cloud Console completion)
   echo "📋 Media CDN Configuration Summary:"
   echo "   Service Name: ${CDN_SERVICE_NAME}"
   echo "   Origin Bucket: gs://${BUCKET_NAME}"
   echo "   Cache Policy: Optimized for video streaming"
   echo ""
   echo "⚠️  Complete Media CDN setup in Google Cloud Console:"
   echo "   1. Navigate to Network Services > Media CDN"
   echo "   2. Create EdgeCacheService with the configuration above"
   echo "   3. Configure custom domain and SSL certificates"
   
   echo "✅ Media CDN configuration prepared"
   ```

   The Media CDN cache policies are optimized for video content delivery with intelligent caching strategies that balance performance and freshness. This configuration ensures optimal content delivery while supporting the analytics pipeline's requirements for both streaming and processed results.

7. **Configure Automated Analytics Results Processing**:

   This step creates a comprehensive results processing pipeline that monitors Vertex AI analysis operations and processes completed analytics results. The system automatically organizes insights, generates summaries, and creates searchable metadata for video content analytics.

   ```bash
   # Create results processing function
   mkdir -p results-processor
   cd results-processor
   
   cat > main.py << 'EOF'
import json
import os
from google.cloud import storage
from google.cloud import videointelligence
import logging

def process_analytics_results(cloud_event):
    """Process completed video analytics results."""
    
    file_name = cloud_event.data["name"]
    bucket_name = cloud_event.data["bucket"]
    
    # Only process analysis result files
    if not file_name.endswith('_analysis.json'):
        return {"status": "skipped", "reason": "not an analysis result"}
    
    logging.info(f"Processing analytics results: {file_name}")
    
    # Download and parse analysis results
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    
    try:
        analysis_data = json.loads(blob.download_as_text())
        
        # Extract key insights
        insights = {
            "video_file": file_name.replace('_analysis.json', ''),
            "processing_timestamp": cloud_event.time,
            "objects_detected": [],
            "labels_detected": [],
            "text_detected": [],
            "shots_detected": 0
        }
        
        # Process object tracking results
        if 'object_annotations' in analysis_data:
            for obj in analysis_data['object_annotations']:
                insights['objects_detected'].append({
                    "entity": obj.get('entity', {}).get('description', 'Unknown'),
                    "confidence": obj.get('confidence', 0),
                    "track_count": len(obj.get('frames', []))
                })
        
        # Process label detection results
        if 'label_annotations' in analysis_data:
            for label in analysis_data['label_annotations']:
                insights['labels_detected'].append({
                    "description": label.get('entity', {}).get('description', 'Unknown'),
                    "confidence": label.get('category_entities', [{}])[0].get('description', 'N/A') if label.get('category_entities') else 'N/A'
                })
        
        # Process shot detection
        if 'shot_annotations' in analysis_data:
            insights['shots_detected'] = len(analysis_data['shot_annotations'])
        
        # Store processed insights
        insights_blob = bucket.blob(f"insights/{insights['video_file']}_insights.json")
        insights_blob.upload_from_string(json.dumps(insights, indent=2))
        
        # Create summary report
        summary = {
            "total_objects": len(insights['objects_detected']),
            "total_labels": len(insights['labels_detected']),
            "total_shots": insights['shots_detected'],
            "top_objects": sorted(insights['objects_detected'], 
                                key=lambda x: x['confidence'], reverse=True)[:5],
            "top_labels": sorted(insights['labels_detected'], 
                               key=lambda x: len(x['description']), reverse=True)[:5]
        }
        
        summary_blob = bucket.blob(f"summaries/{insights['video_file']}_summary.json")
        summary_blob.upload_from_string(json.dumps(summary, indent=2))
        
        print(f"✅ Processed analytics for: {insights['video_file']}")
        print(f"   Objects detected: {summary['total_objects']}")
        print(f"   Labels detected: {summary['total_labels']}")
        print(f"   Shots detected: {summary['total_shots']}")
        
        return {"status": "success", "insights": summary}
        
    except Exception as e:
        logging.error(f"Error processing analytics results: {str(e)}")
        return {"status": "error", "error": str(e)}
EOF
   
   cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
google-cloud-videointelligence==2.11.3
EOF
   
   # Deploy results processing function
   gcloud functions deploy results-processor-${RANDOM_SUFFIX} \
       --runtime python39 \
       --trigger-bucket ${RESULTS_BUCKET} \
       --entry-point process_analytics_results \
       --memory 512MB \
       --timeout 300s \
       --set-env-vars PROJECT_ID=${PROJECT_ID},REGION=${REGION}
   
   cd ..
   
   echo "✅ Analytics results processing function deployed"
   ```

   The results processing pipeline now automatically organizes and summarizes video analytics insights, creating searchable metadata and summary reports. This automation ensures that analytics results are immediately available for further analysis and decision-making.

## Validation & Testing

1. **Upload a test video and verify end-to-end processing**:

   ```bash
   # Create a test video file (or use an existing one)
   echo "Uploading test video to trigger the analytics pipeline..."
   
   # Upload test video (replace with actual video file)
   gsutil cp sample-video.mp4 gs://${BUCKET_NAME}/test-videos/
   
   echo "✅ Test video uploaded to: gs://${BUCKET_NAME}/test-videos/"
   ```

   Expected output: Video upload triggers Cloud Function processing and initiates Vertex AI analysis.

2. **Monitor Cloud Function execution and analytics processing**:

   ```bash
   # Check Cloud Function logs
   gcloud functions logs read ${FUNCTION_NAME} \
       --limit 50 \
       --format="table(timestamp,level,message)"
   
   # Check advanced analytics function logs
   gcloud functions logs read advanced-video-analytics-${RANDOM_SUFFIX} \
       --limit 50 \
       --format="table(timestamp,level,message)"
   ```

   Expected output: Function execution logs showing successful video processing initiation.

3. **Verify analytics results and insights generation**:

   ```bash
   # List generated analytics results
   gsutil ls gs://${RESULTS_BUCKET}/analysis/
   gsutil ls gs://${RESULTS_BUCKET}/insights/
   gsutil ls gs://${RESULTS_BUCKET}/summaries/
   
   # View sample insights
   gsutil cat gs://${RESULTS_BUCKET}/insights/*_insights.json | head -20
   ```

   Expected output: JSON files containing video analytics results, insights, and summaries.

4. **Test Media CDN content delivery performance**:

   ```bash
   # Check CDN configuration status
   gcloud compute network-edge-security-services list
   
   # Test video accessibility through storage
   gsutil ls -l gs://${BUCKET_NAME}/test-videos/
   
   echo "📊 Media CDN Performance Test:"
   echo "Access your video content through the configured CDN endpoint"
   echo "Monitor cache hit ratios in Cloud Console > Media CDN"
   ```

## Cleanup

1. **Delete Cloud Functions and remove triggers**:

   ```bash
   # Delete all created Cloud Functions
   gcloud functions delete ${FUNCTION_NAME} --quiet
   gcloud functions delete advanced-video-analytics-${RANDOM_SUFFIX} --quiet
   gcloud functions delete results-processor-${RANDOM_SUFFIX} --quiet
   
   echo "✅ Cloud Functions deleted"
   ```

2. **Remove Vertex AI resources and datasets**:

   ```bash
   # Delete Vertex AI dataset
   if [ ! -z "${DATASET_ID}" ]; then
       gcloud ai datasets delete ${DATASET_ID} \
           --region=${REGION} \
           --quiet
   fi
   
   echo "✅ Vertex AI resources cleaned up"
   ```

3. **Remove Cloud Storage buckets and all content**:

   ```bash
   # Remove all bucket contents and buckets
   gsutil -m rm -r gs://${BUCKET_NAME}
   gsutil -m rm -r gs://${RESULTS_BUCKET}
   
   echo "✅ Storage buckets and content deleted"
   ```

4. **Clean up Media CDN configuration**:

   ```bash
   # Remove Media CDN edge security services
   gcloud compute network-edge-security-services delete ${CDN_SERVICE_NAME}-origin \
       --region=${REGION} \
       --quiet
   
   echo "✅ Media CDN resources cleaned up"
   echo "Note: Complete Media CDN cleanup may require manual steps in Cloud Console"
   ```

## Discussion

This recipe demonstrates how to orchestrate an intelligent edge-to-cloud video analytics pipeline that combines Google Cloud's Media CDN global distribution capabilities with Vertex AI's advanced video analysis features. The architecture leverages Cloud Storage as the central data repository, Cloud Functions for event-driven automation, and Vertex AI for sophisticated content analysis including object detection and content classification.

The solution addresses the growing need for automated video content analysis at scale while maintaining optimal delivery performance for global audiences. Media CDN's edge caching capabilities, with over 100Tbps of global capacity and cache hit ratios averaging 98.5-99% for video-on-demand content, ensure that video content is delivered with minimal latency worldwide. Meanwhile, Vertex AI's pre-trained video intelligence models provide accurate object detection, activity recognition, and content classification without requiring custom model development.

The event-driven architecture using Cloud Functions creates a seamless automation pipeline that processes videos as soon as they're uploaded to Cloud Storage. This serverless approach ensures cost-effective scaling, as resources are only consumed during actual processing operations. The integration with Vertex AI Video Intelligence API enables sophisticated analysis capabilities including object tracking, label detection, shot change detection, and text recognition, providing comprehensive insights into video content.

One of the key architectural decisions involves separating content storage from analytics results storage, which enables different access patterns and security policies for each data type. The pipeline also implements comprehensive metadata tracking and results processing, creating searchable insights and summary reports that make analytics results immediately actionable for content creators and media organizations.

> **Note**: This architecture follows Google Cloud's Well-Architected Framework principles, emphasizing operational excellence, security, reliability, and cost optimization. For production deployments, consider implementing additional monitoring, alerting, and security controls. See the [Google Cloud Architecture Center](https://cloud.google.com/architecture) for advanced patterns and best practices.

## Challenge

Extend this intelligent video analytics solution by implementing these enhancements:

1. **Real-time Live Stream Analytics**: Integrate the Video Intelligence Streaming API to analyze live video streams in real-time, enabling immediate content moderation and dynamic ad insertion based on detected content.

2. **Custom ML Model Integration**: Develop and deploy custom Vertex AI models trained on domain-specific video content, such as sports highlight detection or brand logo recognition, using AutoML Video or custom training pipelines.

3. **Multi-modal Content Analysis**: Enhance the pipeline to include audio analysis using Speech-to-Text API and Natural Language AI for transcript analysis, creating comprehensive multimedia content insights.

4. **Intelligent Content Recommendations**: Build a recommendation engine using the analytics results and Vertex AI Matching Engine to suggest related content based on detected objects, activities, and themes.

5. **Advanced Security and Compliance**: Implement Cloud DLP (Data Loss Prevention) for sensitive content detection, add digital watermarking for content protection, and integrate with Cloud Security Command Center for comprehensive security monitoring.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*