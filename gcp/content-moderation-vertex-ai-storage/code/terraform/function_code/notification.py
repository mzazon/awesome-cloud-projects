import json
import smtplib
from email.mime.text import MimeText
from email.mime.multipart import MimeMultipart
from google.cloud import storage
import functions_framework
import os
import logging

logger = logging.getLogger(__name__)

QUARANTINE_BUCKET = "${quarantine_bucket}"

@functions_framework.cloud_event
def notify_quarantine(cloud_event):
    """Notify moderators of quarantined content."""
    try:
        data = cloud_event.data
        bucket_name = data['bucket']
        file_name = data['name']
        
        # Only process quarantine bucket events
        if bucket_name != QUARANTINE_BUCKET:
            return
        
        logger.info(f"Quarantined content detected: {file_name}")
        
        # Get file metadata
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        metadata = blob.metadata or {}
        moderation_result = json.loads(metadata.get('moderation_result', '{}'))
        
        # Log the quarantine event (in production, send email/Slack notification)
        logger.warning(f"""
        CONTENT QUARANTINED:
        File: {file_name}
        Bucket: {bucket_name}
        Categories: {moderation_result.get('categories', [])}
        Confidence: {moderation_result.get('confidence', 0)}
        Reasoning: {moderation_result.get('reasoning', 'No reason provided')}
        """)
        
        print(f"🚨 ALERT: Content quarantined - {file_name}")
        
    except Exception as e:
        logger.error(f"Error processing quarantine notification: {str(e)}")