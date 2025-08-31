import functions_framework
from google.cloud import webrisk_v1
from google.cloud import storage
import json
import hashlib
import urllib.parse
from datetime import datetime, timezone
import logging
import os

# Initialize clients
webrisk_client = webrisk_v1.WebRiskServiceClient()
storage_client = storage.Client()

def get_url_hash(url):
    """Generate SHA256 hash for URL caching"""
    return hashlib.sha256(url.encode('utf-8')).hexdigest()

def check_cache(url_hash, cache_bucket):
    """Check if URL validation result exists in cache"""
    try:
        bucket = storage_client.bucket(cache_bucket)
        blob = bucket.blob(f"cache/{url_hash}.json")
        if blob.exists():
            cache_data = json.loads(blob.download_as_text())
            # Check if cache is still valid (24 hours)
            cache_time = datetime.fromisoformat(
                cache_data['timestamp'].replace('Z', '+00:00')
            )
            now = datetime.now(timezone.utc)
            if (now - cache_time).total_seconds() < 86400:  # 24 hours
                return cache_data['result']
    except Exception as e:
        logging.warning(f"Cache check failed: {e}")
    return None

def store_cache(url_hash, result, cache_bucket):
    """Store validation result in cache"""
    try:
        bucket = storage_client.bucket(cache_bucket)
        blob = bucket.blob(f"cache/{url_hash}.json")
        cache_data = {
            'result': result,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        blob.upload_from_string(json.dumps(cache_data))
    except Exception as e:
        logging.error(f"Cache storage failed: {e}")

def log_validation(url, result, audit_bucket):
    """Log validation result for audit purposes"""
    try:
        bucket = storage_client.bucket(audit_bucket)
        timestamp = datetime.now(timezone.utc).isoformat()
        filename = f"audit/{datetime.now().strftime('%Y/%m/%d')}/{timestamp}-{get_url_hash(url)[:8]}.json"
        blob = bucket.blob(filename)
        
        audit_data = {
            'timestamp': timestamp,
            'url': url,
            'result': result,
            'source_ip': 'cloud-function',
            'user_agent': 'url-validator-function'
        }
        blob.upload_from_string(json.dumps(audit_data, indent=2))
    except Exception as e:
        logging.error(f"Audit logging failed: {e}")

@functions_framework.http
def validate_url(request):
    """Main Cloud Function entry point for URL validation"""
    
    # Handle CORS for web clients
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    if request.method != 'POST':
        return ({'error': 'Only POST method supported'}, 405, headers)
    
    try:
        # Parse request data
        request_json = request.get_json()
        if not request_json or 'url' not in request_json:
            return ({'error': 'URL parameter required'}, 400, headers)
        
        url = request_json['url']
        cache_enabled = request_json.get('cache', True)
        
        # Validate URL format
        try:
            parsed = urllib.parse.urlparse(url)
            if not parsed.scheme or not parsed.netloc:
                return ({'error': 'Invalid URL format'}, 400, headers)
        except Exception:
            return ({'error': 'Invalid URL format'}, 400, headers)
        
        url_hash = get_url_hash(url)
        project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
        cache_bucket = os.environ.get('CACHE_BUCKET_NAME', f"url-validation-cache-{project_id}")
        audit_bucket = os.environ.get('AUDIT_BUCKET_NAME', f"url-validation-logs-{project_id}")
        
        # Check cache first if enabled
        if cache_enabled:
            cached_result = check_cache(url_hash, cache_bucket)
            if cached_result:
                log_validation(url, {**cached_result, 'cached': True}, audit_bucket)
                return (cached_result, 200, headers)
        
        # Define threat types to check
        threat_types = [
            webrisk_v1.ThreatType.MALWARE,
            webrisk_v1.ThreatType.SOCIAL_ENGINEERING,
            webrisk_v1.ThreatType.UNWANTED_SOFTWARE
        ]
        
        # Check URL against Web Risk API
        request_obj = webrisk_v1.SearchUrisRequest(
            uri=url,
            threat_types=threat_types
        )
        
        response = webrisk_client.search_uris(request=request_obj)
        
        # Process results
        result = {
            'url': url,
            'safe': True,
            'threats': [],
            'checked_at': datetime.now(timezone.utc).isoformat(),
            'cached': False
        }
        
        if response.threat:
            result['safe'] = False
            for threat_type in response.threat.threat_types:
                result['threats'].append({
                    'type': threat_type.name,
                    'expires_at': response.threat.expire_time.isoformat() if response.threat.expire_time else None
                })
        
        # Store in cache and log
        if cache_enabled:
            store_cache(url_hash, result, cache_bucket)
        log_validation(url, result, audit_bucket)
        
        return (result, 200, headers)
        
    except Exception as e:
        logging.error(f"Validation error: {e}")
        error_result = {
            'error': 'Internal validation error',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        return (error_result, 500, headers)