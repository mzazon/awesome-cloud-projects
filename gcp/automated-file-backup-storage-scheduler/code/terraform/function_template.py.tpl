import os
from google.cloud import storage, logging
from datetime import datetime
import json
import functions_framework

@functions_framework.http
def backup_files(request):
    """Cloud Function to backup files from primary to backup bucket."""
    
    # Initialize clients
    storage_client = storage.Client()
    logging_client = logging.Client()
    logger = logging_client.logger('backup-function')
    
    # Get bucket names from environment variables
    primary_bucket_name = os.environ.get('PRIMARY_BUCKET')
    backup_bucket_name = os.environ.get('BACKUP_BUCKET')
    environment = os.environ.get('ENVIRONMENT', 'unknown')
    
    if not primary_bucket_name or not backup_bucket_name:
        error_msg = "Missing required environment variables"
        logger.log_text(error_msg, severity='ERROR')
        return {'error': error_msg}, 400
    
    try:
        # Get bucket references
        primary_bucket = storage_client.bucket(primary_bucket_name)
        backup_bucket = storage_client.bucket(backup_bucket_name)
        
        # List and copy all files from primary to backup
        blobs = primary_bucket.list_blobs()
        copied_count = 0
        total_size = 0
        
        for blob in blobs:
            # Create backup file name with timestamp
            backup_name = f"backup-{datetime.now().strftime('%Y%m%d')}/{blob.name}"
            
            # Skip if backup already exists (avoid duplicates)
            if backup_bucket.blob(backup_name).exists():
                logger.log_text(f"Backup already exists for {blob.name}, skipping")
                continue
            
            # Copy blob to backup bucket
            backup_bucket.copy_blob(blob, backup_bucket, backup_name)
            copied_count += 1
            total_size += blob.size or 0
            
            logger.log_text(f"Copied {blob.name} to {backup_name} ({blob.size} bytes)")
        
        success_msg = f"Backup completed successfully. {copied_count} files copied, {total_size} bytes total."
        logger.log_text(success_msg, severity='INFO')
        
        return {
            'status': 'success',
            'files_copied': copied_count,
            'total_size_bytes': total_size,
            'primary_bucket': primary_bucket_name,
            'backup_bucket': backup_bucket_name,
            'environment': environment,
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        error_msg = f"Backup failed: {str(e)}"
        logger.log_text(error_msg, severity='ERROR', 
                      labels={'error_type': type(e).__name__})
        return {'error': error_msg, 'error_type': type(e).__name__}, 500