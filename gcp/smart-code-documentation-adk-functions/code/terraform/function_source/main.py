import functions_framework
from google.cloud import storage
import tempfile
import os
import json
import zipfile
import logging
from typing import Dict, Any, Optional
from code_analysis_agent import CodeAnalysisAgent
from documentation_agent import DocumentationAgent
from review_agent import QualityReviewAgent

# Configure logging
logging.basicConfig(level=logging.${log_level})
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def process_code_repository(cloud_event):
    """
    Cloud Function triggered by Cloud Storage events to process code repositories
    and generate intelligent documentation using ADK multi-agent system.
    
    This function orchestrates the entire documentation generation workflow:
    1. Download and extract code repository from trigger bucket
    2. Initialize ADK agents for analysis, documentation, and review
    3. Analyze code structure and extract insights
    4. Generate comprehensive documentation
    5. Perform quality review and improvement
    6. Store results in output bucket
    """
    
    # Extract event data
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    logger.info(f"Processing repository: {file_name} from bucket: {bucket_name}")
    
    # Only process .zip files
    if not file_name.endswith('.zip'):
        logger.info(f"Skipping non-zip file: {file_name}")
        return
    
    # Get configuration from environment variables
    project_id = "${project_id}"
    output_bucket = "${output_bucket}"
    temp_bucket = "${temp_bucket}"
    debug_mode = os.environ.get('DEBUG_MODE', 'false').lower() == 'true'
    
    if debug_mode:
        logger.setLevel(logging.DEBUG)
        logger.debug("Debug mode enabled - enhanced logging active")
    
    storage_client = storage.Client()
    
    try:
        # Download and extract repository
        with tempfile.TemporaryDirectory() as temp_dir:
            logger.info("Downloading and extracting repository...")
            repo_path = download_and_extract_repo(
                storage_client, bucket_name, file_name, temp_dir
            )
            
            # Initialize ADK agents
            logger.info("Initializing ADK multi-agent system...")
            code_agent = CodeAnalysisAgent(project_id)
            doc_agent = DocumentationAgent(project_id)
            review_agent = QualityReviewAgent(project_id)
            
            # Step 1: Analyze code repository
            logger.info("Analyzing code repository structure and content...")
            analysis_results = code_agent.analyze_repository(repo_path)
            logger.info(f"Analysis completed. Found {len(analysis_results.get('file_analyses', []))} files")
            
            # Store intermediate results for debugging/monitoring
            if debug_mode:
                store_intermediate_results(
                    storage_client, temp_bucket, f"{file_name}/analysis.json", 
                    analysis_results
                )
            
            # Step 2: Generate documentation
            logger.info("Generating comprehensive documentation...")
            documentation = doc_agent.generate_documentation(analysis_results)
            markdown_docs = doc_agent.format_markdown_documentation(documentation)
            logger.info("Documentation generation completed")
            
            # Step 3: Quality review
            logger.info("Performing quality review and validation...")
            review_results = review_agent.review_documentation(
                markdown_docs, analysis_results
            )
            
            quality_score = review_results.get('quality_score', 0)
            logger.info(f"Quality review completed. Score: {quality_score}/10")
            
            # Step 4: Improve documentation if needed
            final_documentation = markdown_docs
            if not review_results.get('approved', False):
                logger.info("Improving documentation based on review feedback...")
                improved_docs = review_agent.suggest_improvements(
                    markdown_docs, review_results
                )
                final_documentation = improved_docs
                logger.info("Documentation improvement completed")
            else:
                logger.info("Documentation approved without modifications")
            
            # Step 5: Store final results
            logger.info("Storing final documentation and results...")
            output_data = {
                "repository": file_name,
                "analysis": analysis_results,
                "documentation": final_documentation,
                "review": review_results,
                "metadata": {
                    "processing_timestamp": cloud_event.timestamp,
                    "agent_versions": {
                        "adk_version": "1.0.0",
                        "model": "${gemini_model}",
                        "vertex_location": "${vertex_location}"
                    },
                    "function_config": {
                        "project_id": project_id,
                        "debug_mode": debug_mode,
                        "log_level": "${log_level}"
                    }
                }
            }
            
            store_final_documentation(
                storage_client, output_bucket, file_name, output_data
            )
            
            logger.info(f"✅ Successfully processed repository: {file_name}")
            logger.info(f"Quality Score: {quality_score}/10")
            logger.info(f"Total files analyzed: {len(analysis_results.get('file_analyses', []))}")
            logger.info(f"Complexity score: {analysis_results.get('overall_complexity', 0)}")
            
    except Exception as e:
        logger.error(f"Error processing repository {file_name}: {str(e)}")
        if debug_mode:
            logger.exception("Full exception traceback:")
        
        # Store error information for debugging
        error_data = {
            "repository": file_name,
            "error": str(e),
            "timestamp": cloud_event.timestamp,
            "debug_mode": debug_mode
        }
        
        try:
            store_error_information(storage_client, temp_bucket, file_name, error_data)
        except Exception as store_error:
            logger.error(f"Failed to store error information: {str(store_error)}")
        
        raise


def download_and_extract_repo(storage_client: storage.Client, bucket_name: str, 
                            file_name: str, temp_dir: str) -> str:
    """
    Download and extract repository zip file from Cloud Storage.
    
    Args:
        storage_client: Initialized Cloud Storage client
        bucket_name: Name of the source bucket
        file_name: Name of the zip file to download
        temp_dir: Temporary directory for extraction
        
    Returns:
        Path to the extracted repository directory
    """
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    
    # Download zip file
    zip_path = os.path.join(temp_dir, 'repo.zip')
    logger.debug(f"Downloading {file_name} to {zip_path}")
    blob.download_to_filename(zip_path)
    
    # Extract to subdirectory
    extract_path = os.path.join(temp_dir, 'extracted')
    os.makedirs(extract_path, exist_ok=True)
    
    logger.debug(f"Extracting repository to {extract_path}")
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(extract_path)
    
    return extract_path


def store_intermediate_results(storage_client: storage.Client, bucket_name: str, 
                             object_name: str, data: Dict[str, Any]) -> None:
    """
    Store intermediate processing results for debugging and monitoring.
    
    Args:
        storage_client: Initialized Cloud Storage client
        bucket_name: Name of the target bucket
        object_name: Name of the object to create
        data: Data to store as JSON
    """
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(object_name)
    
    json_data = json.dumps(data, indent=2, ensure_ascii=False, default=str)
    blob.upload_from_string(json_data, content_type='application/json')
    logger.debug(f"Stored intermediate results to gs://{bucket_name}/{object_name}")


def store_final_documentation(storage_client: storage.Client, bucket_name: str, 
                            repo_name: str, output_data: Dict[str, Any]) -> None:
    """
    Store final documentation results in multiple formats for easy access.
    
    Args:
        storage_client: Initialized Cloud Storage client
        bucket_name: Name of the output bucket
        repo_name: Name of the repository (used as folder name)
        output_data: Complete output data including documentation and metadata
    """
    bucket = storage_client.bucket(bucket_name)
    
    # Create folder structure for organized storage
    folder_prefix = f"{repo_name.replace('.zip', '')}"
    
    # Store complete results as JSON
    json_blob = bucket.blob(f"{folder_prefix}/complete_results.json")
    json_data = json.dumps(output_data, indent=2, ensure_ascii=False, default=str)
    json_blob.upload_from_string(json_data, content_type='application/json')
    logger.debug(f"Stored complete results to gs://{bucket_name}/{folder_prefix}/complete_results.json")
    
    # Store markdown documentation separately for easy reading
    docs_blob = bucket.blob(f"{folder_prefix}/README.md")
    docs_blob.upload_from_string(
        output_data['documentation'], 
        content_type='text/markdown'
    )
    logger.debug(f"Stored documentation to gs://{bucket_name}/{folder_prefix}/README.md")
    
    # Store analysis summary for quick insights
    summary_blob = bucket.blob(f"{folder_prefix}/analysis_summary.json")
    summary_data = {
        "repository_name": repo_name,
        "total_files_analyzed": len(output_data['analysis'].get('file_analyses', [])),
        "complexity_score": output_data['analysis'].get('overall_complexity', 0),
        "quality_score": output_data['review'].get('quality_score', 0),
        "documentation_approved": output_data['review'].get('approved', False),
        "processing_timestamp": output_data['metadata']['processing_timestamp'],
        "agent_metadata": output_data['metadata']['agent_versions']
    }
    summary_blob.upload_from_string(
        json.dumps(summary_data, indent=2, default=str), 
        content_type='application/json'
    )
    logger.debug(f"Stored summary to gs://{bucket_name}/{folder_prefix}/analysis_summary.json")
    
    # Store review feedback separately for improvement tracking
    if 'review' in output_data and not output_data['review'].get('approved', False):
        review_blob = bucket.blob(f"{folder_prefix}/review_feedback.json")
        review_data = {
            "quality_score": output_data['review'].get('quality_score', 0),
            "strengths": output_data['review'].get('strengths', []),
            "improvements": output_data['review'].get('improvements', []),
            "recommendations": output_data['review'].get('recommendations', []),
            "full_review": output_data['review'].get('review_summary', '')
        }
        review_blob.upload_from_string(
            json.dumps(review_data, indent=2, default=str),
            content_type='application/json'
        )
        logger.debug(f"Stored review feedback to gs://{bucket_name}/{folder_prefix}/review_feedback.json")


def store_error_information(storage_client: storage.Client, bucket_name: str, 
                          repo_name: str, error_data: Dict[str, Any]) -> None:
    """
    Store error information for debugging failed processing attempts.
    
    Args:
        storage_client: Initialized Cloud Storage client
        bucket_name: Name of the temporary bucket for error storage
        repo_name: Name of the repository that failed processing
        error_data: Error details and context
    """
    bucket = storage_client.bucket(bucket_name)
    error_blob = bucket.blob(f"errors/{repo_name}/error_details.json")
    
    json_data = json.dumps(error_data, indent=2, ensure_ascii=False, default=str)
    error_blob.upload_from_string(json_data, content_type='application/json')
    logger.info(f"Stored error details to gs://{bucket_name}/errors/{repo_name}/error_details.json")