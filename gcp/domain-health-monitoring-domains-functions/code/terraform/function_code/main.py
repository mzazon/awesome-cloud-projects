#!/usr/bin/env python3
"""
GCP Domain Health Monitoring Cloud Function
Performs comprehensive domain health checks including SSL certificate validation,
DNS resolution verification, and HTTP response checking.
"""

import ssl
import socket
import requests
import dns.resolver
import json
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from google.cloud import monitoring_v3
from google.cloud import domains_v1
from google.cloud import storage
from google.cloud import pubsub_v1
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Default domains to monitor (can be overridden by environment variables)
DEFAULT_DOMAINS = ${jsonencode(domains_to_monitor)}
SSL_EXPIRY_WARNING_DAYS = ${ssl_expiry_warning_days}

class DomainHealthMonitor:
    """Domain health monitoring class with comprehensive checking capabilities."""
    
    def __init__(self):
        """Initialize the domain health monitor with Google Cloud clients."""
        self.project_id = os.environ.get('GCP_PROJECT')
        self.topic_name = os.environ.get('TOPIC_NAME')
        self.bucket_name = os.environ.get('BUCKET_NAME')
        self.region = os.environ.get('REGION', 'us-central1')
        
        # Parse domains from environment or use defaults
        domains_env = os.environ.get('DOMAINS_TO_MONITOR', '${jsonencode(domains_to_monitor)}')
        try:
            self.domains_to_monitor = json.loads(domains_env)
        except json.JSONDecodeError:
            logger.warning(f"Failed to parse domains from environment, using defaults: {DEFAULT_DOMAINS}")
            self.domains_to_monitor = DEFAULT_DOMAINS
        
        # SSL expiry warning threshold
        self.ssl_warning_days = int(os.environ.get('SSL_EXPIRY_WARNING_DAYS', SSL_EXPIRY_WARNING_DAYS))
        
        # Initialize Google Cloud clients
        try:
            self.monitoring_client = monitoring_v3.MetricServiceClient()
            self.storage_client = storage.Client()
            self.publisher = pubsub_v1.PublisherClient()
            
            if self.topic_name and self.project_id:
                self.topic_path = self.publisher.topic_path(self.project_id, self.topic_name)
            else:
                self.topic_path = None
                logger.warning("Pub/Sub topic not configured, alerts will not be sent")
                
        except Exception as e:
            logger.error(f"Failed to initialize Google Cloud clients: {e}")
            raise

    def check_ssl_certificate(self, domain: str) -> Dict[str, Any]:
        """
        Check SSL certificate validity and expiration for a domain.
        
        Args:
            domain: The domain name to check
            
        Returns:
            Dictionary containing SSL certificate status and expiration info
        """
        try:
            logger.info(f"Checking SSL certificate for {domain}")
            
            # Create SSL context and connect to domain
            context = ssl.create_default_context()
            with socket.create_connection((domain, 443), timeout=10) as sock:
                with context.wrap_socket(sock, server_hostname=domain) as ssock:
                    cert = ssock.getpeercert()
                    
                    # Parse certificate expiration date
                    expire_date = datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z')
                    days_until_expiry = (expire_date - datetime.utcnow()).days
                    
                    result = {
                        'valid': True,
                        'expires': expire_date.isoformat(),
                        'days_until_expiry': days_until_expiry,
                        'issuer': cert.get('issuer', 'Unknown'),
                        'subject': cert.get('subject', 'Unknown')
                    }
                    
                    logger.info(f"SSL certificate for {domain} expires in {days_until_expiry} days")
                    return result
                    
        except socket.timeout:
            logger.warning(f"SSL check timeout for {domain}")
            return {
                'valid': False,
                'expires': None,
                'days_until_expiry': 0,
                'error': 'Connection timeout'
            }
        except ssl.SSLError as e:
            logger.warning(f"SSL error for {domain}: {e}")
            return {
                'valid': False,
                'expires': None,
                'days_until_expiry': 0,
                'error': f'SSL error: {str(e)}'
            }
        except Exception as e:
            logger.error(f"Unexpected error checking SSL for {domain}: {e}")
            return {
                'valid': False,
                'expires': None,
                'days_until_expiry': 0,
                'error': f'Unexpected error: {str(e)}'
            }

    def check_dns_resolution(self, domain: str) -> Dict[str, Any]:
        """
        Check if domain resolves correctly via DNS.
        
        Args:
            domain: The domain name to check
            
        Returns:
            Dictionary containing DNS resolution status and results
        """
        try:
            logger.info(f"Checking DNS resolution for {domain}")
            
            # Check A record resolution
            a_records = dns.resolver.resolve(domain, 'A')
            a_ips = [str(record) for record in a_records]
            
            # Check if we can also resolve AAAA (IPv6) records
            aaaa_ips = []
            try:
                aaaa_records = dns.resolver.resolve(domain, 'AAAA')
                aaaa_ips = [str(record) for record in aaaa_records]
            except (dns.resolver.NoAnswer, dns.resolver.NXDOMAIN):
                # IPv6 not available, which is fine
                pass
            
            result = {
                'resolves': True,
                'a_records': a_ips,
                'aaaa_records': aaaa_ips,
                'record_count': len(a_ips) + len(aaaa_ips)
            }
            
            logger.info(f"DNS resolution successful for {domain}: {len(a_ips)} A records, {len(aaaa_ips)} AAAA records")
            return result
            
        except dns.resolver.NXDOMAIN:
            logger.warning(f"DNS NXDOMAIN for {domain}")
            return {
                'resolves': False,
                'error': 'Domain does not exist (NXDOMAIN)',
                'a_records': [],
                'aaaa_records': [],
                'record_count': 0
            }
        except dns.resolver.NoAnswer:
            logger.warning(f"DNS NoAnswer for {domain}")
            return {
                'resolves': False,
                'error': 'No DNS records found',
                'a_records': [],
                'aaaa_records': [],
                'record_count': 0
            }
        except Exception as e:
            logger.error(f"DNS resolution error for {domain}: {e}")
            return {
                'resolves': False,
                'error': f'DNS resolution error: {str(e)}',
                'a_records': [],
                'aaaa_records': [],
                'record_count': 0
            }

    def check_http_response(self, domain: str) -> Dict[str, Any]:
        """
        Check if domain responds to HTTP/HTTPS requests.
        
        Args:
            domain: The domain name to check
            
        Returns:
            Dictionary containing HTTP response status and timing
        """
        try:
            logger.info(f"Checking HTTP response for {domain}")
            
            # Try HTTPS first, then HTTP
            for protocol in ['https', 'http']:
                try:
                    url = f"{protocol}://{domain}"
                    start_time = datetime.utcnow()
                    
                    response = requests.get(
                        url,
                        timeout=10,
                        allow_redirects=True,
                        verify=True if protocol == 'https' else False
                    )
                    
                    end_time = datetime.utcnow()
                    response_time = (end_time - start_time).total_seconds() * 1000  # Convert to milliseconds
                    
                    result = {
                        'responds': True,
                        'status_code': response.status_code,
                        'protocol': protocol,
                        'response_time_ms': round(response_time, 2),
                        'final_url': response.url,
                        'headers': dict(response.headers)
                    }
                    
                    logger.info(f"HTTP check successful for {domain}: {response.status_code} via {protocol} in {response_time:.2f}ms")
                    return result
                    
                except requests.exceptions.SSLError:
                    if protocol == 'https':
                        logger.warning(f"HTTPS SSL error for {domain}, trying HTTP")
                        continue
                    else:
                        raise
                        
        except requests.exceptions.Timeout:
            logger.warning(f"HTTP timeout for {domain}")
            return {
                'responds': False,
                'error': 'Request timeout',
                'status_code': None,
                'protocol': None,
                'response_time_ms': None
            }
        except requests.exceptions.ConnectionError:
            logger.warning(f"HTTP connection error for {domain}")
            return {
                'responds': False,
                'error': 'Connection error',
                'status_code': None,
                'protocol': None,
                'response_time_ms': None
            }
        except Exception as e:
            logger.error(f"HTTP check error for {domain}: {e}")
            return {
                'responds': False,
                'error': f'HTTP error: {str(e)}',
                'status_code': None,
                'protocol': None,
                'response_time_ms': None
            }

    def send_metrics(self, domain: str, result: Dict[str, Any]) -> None:
        """
        Send domain health metrics to Cloud Monitoring.
        
        Args:
            domain: The domain name
            result: Health check results dictionary
        """
        try:
            if not self.project_id:
                logger.warning("Project ID not configured, skipping metrics")
                return
                
            project_name = f"projects/{self.project_id}"
            
            # Create time series data
            interval = monitoring_v3.TimeInterval()
            now = datetime.utcnow()
            interval.end_time.seconds = int(now.timestamp())
            
            # SSL validity metric
            if 'ssl_valid' in result:
                series = monitoring_v3.TimeSeries()
                series.metric.type = "custom.googleapis.com/domain/ssl_valid"
                series.resource.type = "global"
                series.metric.labels["domain"] = domain
                
                point = monitoring_v3.Point()
                point.value.double_value = 1.0 if result['ssl_valid'] else 0.0
                point.interval.CopyFrom(interval)
                series.points = [point]
                
                self.monitoring_client.create_time_series(name=project_name, time_series=[series])
            
            # DNS resolution metric
            if 'dns_resolves' in result:
                series = monitoring_v3.TimeSeries()
                series.metric.type = "custom.googleapis.com/domain/dns_resolves"
                series.resource.type = "global"
                series.metric.labels["domain"] = domain
                
                point = monitoring_v3.Point()
                point.value.double_value = 1.0 if result['dns_resolves'] else 0.0
                point.interval.CopyFrom(interval)
                series.points = [point]
                
                self.monitoring_client.create_time_series(name=project_name, time_series=[series])
            
            # HTTP response metric
            if 'http_responds' in result:
                series = monitoring_v3.TimeSeries()
                series.metric.type = "custom.googleapis.com/domain/http_responds"
                series.resource.type = "global"
                series.metric.labels["domain"] = domain
                
                point = monitoring_v3.Point()
                point.value.double_value = 1.0 if result['http_responds'] else 0.0
                point.interval.CopyFrom(interval)
                series.points = [point]
                
                self.monitoring_client.create_time_series(name=project_name, time_series=[series])
            
            logger.info(f"Metrics sent successfully for {domain}")
            
        except Exception as e:
            logger.error(f"Failed to send metrics for {domain}: {e}")

    def send_alert(self, message: str, severity: str = "warning") -> None:
        """
        Send alert message to Pub/Sub topic.
        
        Args:
            message: Alert message content
            severity: Alert severity level
        """
        try:
            if not self.topic_path:
                logger.warning(f"Pub/Sub not configured, skipping alert: {message}")
                return
                
            alert_data = {
                'message': message,
                'timestamp': datetime.utcnow().isoformat(),
                'severity': severity,
                'source': 'domain-health-monitor'
            }
            
            # Publish message to Pub/Sub
            future = self.publisher.publish(
                self.topic_path, 
                json.dumps(alert_data).encode('utf-8')
            )
            
            # Wait for publish to complete
            future.result()
            logger.info(f"Alert sent: {message}")
            
        except Exception as e:
            logger.error(f"Failed to send alert: {e}")

    def store_results(self, results: List[Dict[str, Any]]) -> None:
        """
        Store monitoring results in Cloud Storage.
        
        Args:
            results: List of domain health check results
        """
        try:
            if not self.bucket_name:
                logger.warning("Storage bucket not configured, skipping results storage")
                return
                
            bucket = self.storage_client.bucket(self.bucket_name)
            
            # Create timestamped filename
            timestamp = datetime.utcnow().strftime('%Y-%m-%d-%H-%M-%S')
            blob_name = f"monitoring-results/{timestamp}.json"
            
            # Upload results as JSON
            blob = bucket.blob(blob_name)
            blob.upload_from_string(
                json.dumps(results, indent=2),
                content_type='application/json'
            )
            
            logger.info(f"Results stored in gs://{self.bucket_name}/{blob_name}")
            
        except Exception as e:
            logger.error(f"Failed to store results: {e}")

    def monitor_domain(self, domain: str) -> Dict[str, Any]:
        """
        Perform comprehensive health monitoring for a single domain.
        
        Args:
            domain: The domain name to monitor
            
        Returns:
            Dictionary containing all health check results
        """
        logger.info(f"Starting health check for domain: {domain}")
        
        result = {
            'domain': domain,
            'timestamp': datetime.utcnow().isoformat(),
            'ssl_valid': False,
            'ssl_expires': None,
            'dns_resolves': False,
            'http_responds': False,
            'alerts': [],
            'details': {}
        }
        
        try:
            # Check SSL certificate
            ssl_info = self.check_ssl_certificate(domain)
            result['ssl_valid'] = ssl_info['valid']
            result['ssl_expires'] = ssl_info.get('expires')
            result['details']['ssl'] = ssl_info
            
            # Check for SSL expiry warnings
            if ssl_info['valid'] and ssl_info.get('days_until_expiry', 0) < self.ssl_warning_days:
                alert_msg = f"SSL certificate for {domain} expires in {ssl_info['days_until_expiry']} days"
                result['alerts'].append(alert_msg)
                self.send_alert(alert_msg, 'warning')
            elif not ssl_info['valid']:
                alert_msg = f"SSL certificate check failed for {domain}: {ssl_info.get('error', 'Unknown error')}"
                result['alerts'].append(alert_msg)
                self.send_alert(alert_msg, 'error')
            
            # Check DNS resolution
            dns_info = self.check_dns_resolution(domain)
            result['dns_resolves'] = dns_info['resolves']
            result['details']['dns'] = dns_info
            
            if not dns_info['resolves']:
                alert_msg = f"DNS resolution failed for {domain}: {dns_info.get('error', 'Unknown error')}"
                result['alerts'].append(alert_msg)
                self.send_alert(alert_msg, 'error')
            
            # Check HTTP response
            http_info = self.check_http_response(domain)
            result['http_responds'] = http_info['responds']
            result['details']['http'] = http_info
            
            if not http_info['responds']:
                alert_msg = f"HTTP response check failed for {domain}: {http_info.get('error', 'Unknown error')}"
                result['alerts'].append(alert_msg)
                self.send_alert(alert_msg, 'error')
            
            # Send metrics to Cloud Monitoring
            self.send_metrics(domain, result)
            
            logger.info(f"Health check completed for {domain}: SSL={result['ssl_valid']}, DNS={result['dns_resolves']}, HTTP={result['http_responds']}")
            
        except Exception as e:
            error_msg = f"Error during health check for {domain}: {str(e)}"
            result['alerts'].append(error_msg)
            self.send_alert(error_msg, 'error')
            logger.error(error_msg)
        
        return result

    def monitor_all_domains(self) -> List[Dict[str, Any]]:
        """
        Monitor health for all configured domains.
        
        Returns:
            List of health check results for all domains
        """
        logger.info(f"Starting health monitoring for {len(self.domains_to_monitor)} domains")
        
        results = []
        for domain in self.domains_to_monitor:
            try:
                result = self.monitor_domain(domain)
                results.append(result)
            except Exception as e:
                logger.error(f"Failed to monitor domain {domain}: {e}")
                # Add error result
                results.append({
                    'domain': domain,
                    'timestamp': datetime.utcnow().isoformat(),
                    'ssl_valid': False,
                    'ssl_expires': None,
                    'dns_resolves': False,
                    'http_responds': False,
                    'alerts': [f"Monitoring failed: {str(e)}"],
                    'details': {'error': str(e)}
                })
        
        # Store results in Cloud Storage
        self.store_results(results)
        
        logger.info(f"Health monitoring completed for {len(results)} domains")
        return results


@functions_framework.http
def domain_health_check(request):
    """
    Cloud Function entry point for domain health monitoring.
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with monitoring results
    """
    try:
        # Log request information
        logger.info(f"Domain health check triggered via {request.method}")
        
        # Initialize monitor
        monitor = DomainHealthMonitor()
        
        # Perform monitoring
        results = monitor.monitor_all_domains()
        
        # Prepare response
        response = {
            'status': 'completed',
            'timestamp': datetime.utcnow().isoformat(),
            'domains_checked': len(results),
            'domains_healthy': sum(1 for r in results if r['ssl_valid'] and r['dns_resolves'] and r['http_responds']),
            'total_alerts': sum(len(r['alerts']) for r in results),
            'results': results
        }
        
        logger.info(f"Monitoring completed: {response['domains_healthy']}/{response['domains_checked']} domains healthy")
        
        return response
        
    except Exception as e:
        error_msg = f"Domain health check failed: {str(e)}"
        logger.error(error_msg)
        
        return {
            'status': 'error',
            'timestamp': datetime.utcnow().isoformat(),
            'error': error_msg
        }, 500


# For local testing
if __name__ == "__main__":
    # Set up test environment
    os.environ['GCP_PROJECT'] = 'test-project'
    os.environ['TOPIC_NAME'] = 'test-topic'
    os.environ['BUCKET_NAME'] = 'test-bucket'
    
    # Run monitoring
    monitor = DomainHealthMonitor()
    results = monitor.monitor_all_domains()
    
    print(json.dumps(results, indent=2))