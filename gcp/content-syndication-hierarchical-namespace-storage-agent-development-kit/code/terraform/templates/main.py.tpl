# Content Processing Cloud Function
# This function integrates with the Agent Development Kit to process uploaded content
# and route it through the intelligent syndication pipeline

import functions_framework
import json
import os
import logging
from typing import Dict, Any, List
from google.cloud import storage
from google.cloud import aiplatform
from google.cloud import workflows_v1
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
PROJECT_ID = "${project_id}"
BUCKET_NAME = "${bucket_name}"
VERTEX_AI_LOCATION = os.getenv('VERTEX_AI_LOCATION', 'us-central1')
QUALITY_THRESHOLD = float(os.getenv('QUALITY_THRESHOLD', '0.75'))
ENABLE_AUTO_APPROVAL = os.getenv('ENABLE_AUTO_APPROVAL', 'true').lower() == 'true'

class ContentProcessor:
    """Content processing class that handles analysis, routing, and quality assessment"""
    
    def __init__(self):
        self.storage_client = storage.Client()
        self.bucket = self.storage_client.bucket(BUCKET_NAME)
        
        # Content categorization rules
        self.content_categories = {
            'video/': 'video',
            'image/': 'image', 
            'audio/': 'audio',
            'text/': 'document',
            'application/pdf': 'document',
            'application/msword': 'document',
            'application/vnd.openxmlformats-officedocument': 'document'
        }
        
        # Routing rules for distribution channels
        self.routing_rules = {
            'video': ['youtube', 'tiktok', 'instagram', 'facebook'],
            'image': ['instagram', 'pinterest', 'twitter', 'facebook'],
            'audio': ['spotify', 'apple_music', 'podcast', 'youtube'],
            'document': ['medium', 'linkedin', 'blog', 'website']
        }
    
    def analyze_content(self, blob_name: str) -> Dict[str, Any]:
        """Analyze content and extract metadata"""
        try:
            blob = self.bucket.blob(blob_name)
            blob.reload()
            
            # Extract basic metadata
            metadata = {
                'name': blob.name,
                'size': blob.size,
                'content_type': blob.content_type or 'application/octet-stream',
                'created': blob.time_created.isoformat() if blob.time_created else None,
                'md5_hash': blob.md5_hash,
                'etag': blob.etag
            }
            
            # Determine content category
            content_type = metadata['content_type'].lower()
            category = 'document'  # default
            
            for type_prefix, cat in self.content_categories.items():
                if content_type.startswith(type_prefix):
                    category = cat
                    break
            
            metadata['category'] = category
            
            # Add file size analysis
            file_size_mb = metadata['size'] / (1024 * 1024) if metadata['size'] else 0
            metadata['size_mb'] = round(file_size_mb, 2)
            metadata['size_category'] = self._categorize_file_size(file_size_mb)
            
            logger.info(f"Content analyzed: {blob_name}, Category: {category}, Size: {file_size_mb}MB")
            return metadata
            
        except Exception as e:
            logger.error(f"Error analyzing content {blob_name}: {str(e)}")
            raise
    
    def _categorize_file_size(self, size_mb: float) -> str:
        """Categorize file size for processing optimization"""
        if size_mb < 1:
            return 'small'
        elif size_mb < 50:
            return 'medium'
        elif size_mb < 200:
            return 'large'
        else:
            return 'xlarge'
    
    def route_content(self, metadata: Dict[str, Any]) -> Dict[str, Any]:
        """Route content based on analysis results"""
        category = metadata.get('category', 'document')
        file_size_mb = metadata.get('size_mb', 0)
        
        # Get base distribution channels for category
        platforms = self.routing_rules.get(category, ['website'])
        
        # Filter platforms based on size constraints
        if file_size_mb > 100:  # 100MB limit
            platforms = [p for p in platforms if p not in ['twitter', 'instagram']]
        
        if file_size_mb > 500:  # 500MB limit for most platforms
            platforms = [p for p in platforms if p in ['youtube', 'website', 'blog']]
        
        # Determine processing priority
        priority = 'high' if file_size_mb < 10 else 'normal'
        if file_size_mb > 200:
            priority = 'low'
        
        routing_decision = {
            'source_file': metadata['name'],
            'category': category,
            'target_platforms': platforms,
            'priority': priority,
            'processing_required': category in ['video', 'image'],
            'estimated_processing_time': self._estimate_processing_time(category, file_size_mb),
            'size_optimizations_needed': file_size_mb > 50
        }
        
        logger.info(f"Content routed: {metadata['name']} -> {platforms} (Priority: {priority})")
        return routing_decision
    
    def _estimate_processing_time(self, category: str, size_mb: float) -> int:
        """Estimate processing time in seconds"""
        base_times = {
            'video': 30,    # seconds per MB
            'image': 2,     # seconds per MB
            'audio': 5,     # seconds per MB
            'document': 1   # seconds per MB
        }
        
        base_time = base_times.get(category, 1)
        return max(10, int(base_time * size_mb))
    
    def assess_quality(self, metadata: Dict[str, Any], routing_info: Dict[str, Any]) -> Dict[str, Any]:
        """Assess content quality for distribution approval"""
        category = metadata.get('category', 'document')
        file_size_mb = metadata.get('size_mb', 0)
        
        # Simulate quality assessment (in production, would use actual AI models)
        quality_factors = []
        
        # File size assessment
        if 1 <= file_size_mb <= 100:
            quality_factors.append(0.9)
        elif file_size_mb > 100:
            quality_factors.append(0.7)
        else:
            quality_factors.append(0.8)
        
        # Content type assessment
        content_type_scores = {
            'video': 0.85,
            'image': 0.9,
            'audio': 0.8,
            'document': 0.75
        }
        quality_factors.append(content_type_scores.get(category, 0.7))
        
        # Calculate overall quality score
        quality_score = sum(quality_factors) / len(quality_factors)
        
        # Apply some randomness to simulate real AI assessment
        import random
        quality_score += random.uniform(-0.1, 0.1)
        quality_score = max(0.0, min(1.0, quality_score))
        
        # Determine approval status
        passes_quality = quality_score >= QUALITY_THRESHOLD
        
        # Generate recommendations
        recommendations = []
        if not passes_quality:
            recommendations.append("Content quality below threshold - consider enhancement")
        
        if file_size_mb > 100:
            recommendations.append("Consider file compression for better distribution")
        
        if len(routing_info.get('target_platforms', [])) == 1:
            recommendations.append("Limited distribution channels - content may need optimization")
        
        assessment = {
            'quality_score': round(quality_score, 3),
            'passes_quality_check': passes_quality,
            'category': category,
            'recommendations': recommendations,
            'approved_for_distribution': passes_quality and ENABLE_AUTO_APPROVAL,
            'target_platforms': routing_info.get('target_platforms', []),
            'assessment_timestamp': time.time(),
            'threshold_used': QUALITY_THRESHOLD
        }
        
        logger.info(f"Quality assessed: {metadata['name']}, Score: {quality_score:.3f}, Approved: {assessment['approved_for_distribution']}")
        return assessment
    
    def move_content(self, source_path: str, target_folder: str) -> str:
        """Move content between folders in hierarchical storage"""
        try:
            source_blob = self.bucket.blob(source_path)
            
            # Extract filename from source path
            filename = source_path.split('/')[-1]
            target_path = f"{target_folder}/{filename}"
            
            # Copy to new location (hierarchical namespace supports atomic moves)
            self.bucket.copy_blob(source_blob, self.bucket, target_path)
            
            # Delete original (completes the move operation)
            source_blob.delete()
            
            logger.info(f"Content moved: {source_path} -> {target_path}")
            return target_path
            
        except Exception as e:
            logger.error(f"Error moving content {source_path}: {str(e)}")
            raise
    
    def process_pipeline(self, file_path: str) -> Dict[str, Any]:
        """Process content through the complete syndication pipeline"""
        try:
            # Step 1: Analyze content
            logger.info(f"Starting pipeline processing for: {file_path}")
            analysis_result = self.analyze_content(file_path)
            
            # Step 2: Route content
            routing_result = self.route_content(analysis_result)
            
            # Step 3: Assess quality
            quality_result = self.assess_quality(analysis_result, routing_result)
            
            # Step 4: Move content based on results
            if quality_result.get('approved_for_distribution', False):
                category = quality_result.get('category', 'document')
                new_path = self.move_content(file_path, f"categorized/{category}")
                status = "approved_and_categorized"
            else:
                new_path = self.move_content(file_path, "processing")
                status = "requires_improvement"
            
            # Compile pipeline result
            pipeline_result = {
                'original_path': file_path,
                'new_path': new_path,
                'status': status,
                'analysis': analysis_result,
                'routing': routing_result,
                'quality': quality_result,
                'processing_timestamp': time.time(),
                'pipeline_version': '1.0'
            }
            
            logger.info(f"Pipeline completed for {file_path}: {status}")
            return pipeline_result
            
        except Exception as e:
            logger.error(f"Pipeline processing failed for {file_path}: {str(e)}")
            # Move to rejected folder on error
            try:
                error_path = self.move_content(file_path, "rejected")
                return {
                    'original_path': file_path,
                    'new_path': error_path,
                    'status': 'error',
                    'error': str(e),
                    'processing_timestamp': time.time()
                }
            except:
                raise e

# Initialize processor
processor = ContentProcessor()

@functions_framework.http
def process_content(request):
    """HTTP Cloud Function entry point for content processing"""
    
    # Handle CORS for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'No JSON body provided'}, 400, headers
        
        # Extract parameters
        bucket_name = request_json.get('bucket')
        object_name = request_json.get('object')
        
        if not bucket_name or not object_name:
            return {'error': 'Missing bucket or object name'}, 400, headers
        
        # Validate bucket name
        if bucket_name != BUCKET_NAME:
            return {'error': f'Invalid bucket name. Expected: {BUCKET_NAME}'}, 400, headers
        
        # Process content through pipeline
        result = processor.process_pipeline(object_name)
        
        return {
            'success': True,
            'result': result,
            'message': f'Content processed successfully: {result["status"]}'
        }, 200, headers
        
    except Exception as e:
        logger.error(f"Function execution error: {str(e)}")
        return {
            'success': False,
            'error': str(e),
            'message': 'Content processing failed'
        }, 500, headers

@functions_framework.cloud_event
def process_content_event(cloud_event):
    """Cloud Event entry point for storage trigger processing"""
    
    try:
        # Extract event data
        data = cloud_event.data
        bucket_name = data.get('bucket')
        object_name = data.get('name')
        
        logger.info(f"Processing storage event: {bucket_name}/{object_name}")
        
        # Validate bucket and path
        if bucket_name != BUCKET_NAME:
            logger.warning(f"Ignoring event from different bucket: {bucket_name}")
            return
        
        if not object_name.startswith('incoming/'):
            logger.info(f"Ignoring object outside incoming folder: {object_name}")
            return
        
        # Process content through pipeline
        result = processor.process_pipeline(object_name)
        
        logger.info(f"Event processing completed: {result['status']}")
        return result
        
    except Exception as e:
        logger.error(f"Event processing error: {str(e)}")
        raise