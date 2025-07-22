import boto3
import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize ECR client
ecr_client = boto3.client('ecr')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to perform automated ECR repository cleanup.
    
    This function cleans up old and unused container images based on:
    - Repository prefix filtering
    - Configurable retention periods
    - Untagged image cleanup
    
    Args:
        event: Lambda event object
        context: Lambda context object
        
    Returns:
        Dictionary with cleanup results
    """
    try:
        # Get configuration from environment variables
        repository_prefix = os.environ.get('REPOSITORY_PREFIX', '${repository_prefix}')
        cleanup_days = int(os.environ.get('CLEANUP_DAYS', '30'))
        
        logger.info(f"Starting ECR cleanup with prefix: {repository_prefix}")
        logger.info(f"Cleanup threshold: {cleanup_days} days")
        
        # Get all repositories with the specified prefix
        repositories = get_repositories_with_prefix(repository_prefix)
        logger.info(f"Found {len(repositories)} repositories matching prefix")
        
        cleanup_results = []
        
        for repo in repositories:
            repo_name = repo['repositoryName']
            logger.info(f"Processing repository: {repo_name}")
            
            # Get images for this repository
            images = get_repository_images(repo_name)
            logger.info(f"Found {len(images)} images in repository {repo_name}")
            
            # Identify old images for cleanup
            old_images = identify_old_images(images, cleanup_days)
            logger.info(f"Identified {len(old_images)} old images for cleanup")
            
            # Delete old images
            deleted_count = delete_old_images(repo_name, old_images)
            
            cleanup_results.append({
                'repository': repo_name,
                'total_images': len(images),
                'deleted_images': deleted_count,
                'cleanup_threshold_days': cleanup_days
            })
            
            logger.info(f"Cleanup completed for {repo_name}: {deleted_count} images deleted")
        
        # Log summary
        total_deleted = sum(result['deleted_images'] for result in cleanup_results)
        logger.info(f"ECR cleanup completed. Total images deleted: {total_deleted}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'ECR cleanup completed successfully',
                'results': cleanup_results,
                'total_deleted': total_deleted
            })
        }
        
    except Exception as e:
        logger.error(f"Error during ECR cleanup: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'ECR cleanup failed',
                'error': str(e)
            })
        }

def get_repositories_with_prefix(prefix: str) -> List[Dict[str, Any]]:
    """
    Get all ECR repositories that match the specified prefix.
    
    Args:
        prefix: Repository name prefix to filter by
        
    Returns:
        List of repository dictionaries
    """
    try:
        response = ecr_client.describe_repositories()
        repositories = response.get('repositories', [])
        
        # Filter repositories by prefix
        filtered_repos = [
            repo for repo in repositories
            if repo['repositoryName'].startswith(prefix)
        ]
        
        return filtered_repos
        
    except Exception as e:
        logger.error(f"Error getting repositories: {str(e)}")
        return []

def get_repository_images(repository_name: str) -> List[Dict[str, Any]]:
    """
    Get all images in a specific ECR repository.
    
    Args:
        repository_name: Name of the ECR repository
        
    Returns:
        List of image dictionaries
    """
    try:
        images = []
        paginator = ecr_client.get_paginator('describe_images')
        
        for page in paginator.paginate(repositoryName=repository_name):
            images.extend(page.get('imageDetails', []))
        
        return images
        
    except Exception as e:
        logger.error(f"Error getting images for repository {repository_name}: {str(e)}")
        return []

def identify_old_images(images: List[Dict[str, Any]], cleanup_days: int) -> List[Dict[str, str]]:
    """
    Identify images that are older than the specified cleanup threshold.
    
    Args:
        images: List of image dictionaries
        cleanup_days: Number of days threshold for cleanup
        
    Returns:
        List of image identifiers for deletion
    """
    cutoff_date = datetime.now(images[0]['imagePushedAt'].tzinfo) - timedelta(days=cleanup_days)
    old_images = []
    
    for image in images:
        # Check if image is old enough for cleanup
        if image['imagePushedAt'] < cutoff_date:
            # Prioritize untagged images for cleanup
            if 'imageTags' not in image or not image['imageTags']:
                old_images.append({
                    'imageDigest': image['imageDigest']
                })
            else:
                # For tagged images, be more conservative
                # Only delete if they're very old and don't have production tags
                tags = image.get('imageTags', [])
                has_prod_tag = any(tag.startswith(('prod', 'release', 'stable')) for tag in tags)
                
                if not has_prod_tag and image['imagePushedAt'] < cutoff_date:
                    old_images.append({
                        'imageDigest': image['imageDigest']
                    })
    
    return old_images

def delete_old_images(repository_name: str, old_images: List[Dict[str, str]]) -> int:
    """
    Delete old images from ECR repository.
    
    Args:
        repository_name: Name of the ECR repository
        old_images: List of image identifiers to delete
        
    Returns:
        Number of images successfully deleted
    """
    if not old_images:
        return 0
    
    try:
        # ECR batch delete has a limit of 100 images per call
        batch_size = 100
        deleted_count = 0
        
        for i in range(0, len(old_images), batch_size):
            batch = old_images[i:i + batch_size]
            
            response = ecr_client.batch_delete_image(
                repositoryName=repository_name,
                imageIds=batch
            )
            
            deleted_count += len(response.get('imageIds', []))
            
            # Log any failures
            failures = response.get('failures', [])
            if failures:
                logger.warning(f"Failed to delete {len(failures)} images from {repository_name}")
                for failure in failures:
                    logger.warning(f"Failure: {failure}")
        
        logger.info(f"Successfully deleted {deleted_count} images from {repository_name}")
        return deleted_count
        
    except Exception as e:
        logger.error(f"Error deleting images from repository {repository_name}: {str(e)}")
        return 0

def cleanup_untagged_images(repository_name: str, max_age_days: int = 1) -> int:
    """
    Clean up untagged images older than specified days.
    
    Args:
        repository_name: Name of the ECR repository
        max_age_days: Maximum age in days for untagged images
        
    Returns:
        Number of untagged images deleted
    """
    try:
        # Get untagged images
        response = ecr_client.describe_images(
            repositoryName=repository_name,
            filter={'tagStatus': 'UNTAGGED'}
        )
        
        untagged_images = response.get('imageDetails', [])
        cutoff_date = datetime.now(untagged_images[0]['imagePushedAt'].tzinfo) - timedelta(days=max_age_days)
        
        # Filter images older than cutoff date
        old_untagged = [
            {'imageDigest': img['imageDigest']}
            for img in untagged_images
            if img['imagePushedAt'] < cutoff_date
        ]
        
        if old_untagged:
            response = ecr_client.batch_delete_image(
                repositoryName=repository_name,
                imageIds=old_untagged
            )
            
            deleted_count = len(response.get('imageIds', []))
            logger.info(f"Deleted {deleted_count} untagged images from {repository_name}")
            return deleted_count
        
        return 0
        
    except Exception as e:
        logger.error(f"Error cleaning up untagged images: {str(e)}")
        return 0