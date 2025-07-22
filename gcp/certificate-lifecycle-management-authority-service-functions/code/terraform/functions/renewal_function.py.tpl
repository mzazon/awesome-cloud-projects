"""
Certificate Renewal Cloud Function

This function automates certificate renewal using Google Cloud Certificate
Authority Service and stores renewed certificates in Secret Manager.

Environment Variables:
- PROJECT_ID: Google Cloud project ID
- CA_POOL_NAME: Certificate Authority pool name
- SUB_CA_NAME: Subordinate CA name for certificate issuance
- REGION: Google Cloud region
"""

import json
import datetime
import logging
import os
from typing import Dict, Any, Optional, List
from google.cloud import secretmanager
from google.cloud import privateca_v1
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import rsa, ec
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
PROJECT_ID = "${project_id}"
CA_POOL_NAME = "${ca_pool_name}"
SUB_CA_NAME = "${sub_ca_name}"
REGION = "${region}"

@functions_framework.http
def certificate_renewal(request) -> Dict[str, Any]:
    """
    Renew certificates using Certificate Authority Service.
    
    This function generates new private keys, creates certificate signing
    requests, issues certificates via the subordinate CA, and stores the
    results securely in Secret Manager.
    
    Args:
        request: HTTP request containing certificate renewal parameters
        
    Returns:
        Dict containing renewal results and certificate information
    """
    
    try:
        # Initialize Google Cloud clients
        secret_client = secretmanager.SecretManagerServiceClient()
        ca_client = privateca_v1.CertificateAuthorityServiceClient()
        
        logger.info(f"Starting certificate renewal for project: {PROJECT_ID}")
        
        # Parse and validate request
        request_json = request.get_json(silent=True)
        if not request_json:
            raise ValueError("Request body must contain JSON data")
        
        renewal_params = _validate_renewal_request(request_json)
        
        logger.info(f"Renewing certificate for: {renewal_params['common_name']}")
        
        # Generate new cryptographic key pair
        private_key = _generate_private_key(renewal_params.get('key_algorithm', 'RSA_2048'))
        
        # Create certificate signing request
        csr = _create_certificate_request(private_key, renewal_params)
        
        # Issue certificate using Certificate Authority Service
        certificate_response = _issue_certificate(ca_client, csr, renewal_params)
        
        # Store certificate and private key in Secret Manager
        storage_result = _store_certificate_bundle(
            secret_client, 
            certificate_response, 
            private_key, 
            renewal_params
        )
        
        # Prepare success response
        response = {
            'status': 'success',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'certificate_info': {
                'common_name': renewal_params['common_name'],
                'certificate_name': certificate_response.name,
                'serial_number': _extract_serial_number(certificate_response.pem_certificate),
                'validity_period': {
                    'not_before': _extract_not_before(certificate_response.pem_certificate),
                    'not_after': _extract_not_after(certificate_response.pem_certificate)
                },
                'subject_alt_names': renewal_params.get('dns_sans', []),
                'key_algorithm': renewal_params.get('key_algorithm', 'RSA_2048')
            },
            'storage_info': storage_result,
            'ca_info': {
                'ca_pool': CA_POOL_NAME,
                'issuing_ca': SUB_CA_NAME,
                'region': REGION
            }
        }
        
        logger.info(f"Certificate renewal completed successfully for: {renewal_params['common_name']}")
        return response
        
    except Exception as e:
        logger.error(f"Certificate renewal failed: {str(e)}")
        return {
            'status': 'error',
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'error': str(e),
            'error_type': type(e).__name__
        }


def _validate_renewal_request(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate and normalize certificate renewal request parameters.
    
    Args:
        request_data: Raw request data from HTTP request
        
    Returns:
        Validated and normalized renewal parameters
        
    Raises:
        ValueError: If required parameters are missing or invalid
    """
    
    # Required parameters
    if 'common_name' not in request_data:
        raise ValueError("Missing required parameter: common_name")
    
    common_name = request_data['common_name'].strip()
    if not common_name:
        raise ValueError("common_name cannot be empty")
    
    # Validate common name format (basic DNS validation)
    if len(common_name) > 253:
        raise ValueError("common_name too long (max 253 characters)")
    
    # Optional parameters with defaults
    validity_days = request_data.get('validity_days', 365)
    if not isinstance(validity_days, int) or validity_days < 1 or validity_days > 1095:
        raise ValueError("validity_days must be between 1 and 1095 days")
    
    # Subject Alternative Names
    dns_sans = request_data.get('dns_sans', [common_name])
    if isinstance(dns_sans, str):
        dns_sans = [dns_sans]
    elif not isinstance(dns_sans, list):
        raise ValueError("dns_sans must be a string or list of strings")
    
    # Ensure common name is in SANs
    if common_name not in dns_sans:
        dns_sans.insert(0, common_name)
    
    # Organization information
    organization = request_data.get('organization', 'Organization')
    organizational_unit = request_data.get('organizational_unit', 'IT')
    country_code = request_data.get('country_code', 'US')
    
    # Key algorithm
    key_algorithm = request_data.get('key_algorithm', 'RSA_2048')
    valid_algorithms = ['RSA_2048', 'RSA_4096', 'ECDSA_P256', 'ECDSA_P384']
    if key_algorithm not in valid_algorithms:
        raise ValueError(f"key_algorithm must be one of: {valid_algorithms}")
    
    return {
        'common_name': common_name,
        'validity_days': validity_days,
        'dns_sans': dns_sans,
        'organization': organization,
        'organizational_unit': organizational_unit,
        'country_code': country_code,
        'key_algorithm': key_algorithm
    }


def _generate_private_key(key_algorithm: str):
    """
    Generate a new private key for certificate renewal.
    
    Args:
        key_algorithm: Type of key to generate (RSA_2048, RSA_4096, ECDSA_P256, ECDSA_P384)
        
    Returns:
        Generated private key object
    """
    
    if key_algorithm == 'RSA_2048':
        return rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )
    elif key_algorithm == 'RSA_4096':
        return rsa.generate_private_key(
            public_exponent=65537,
            key_size=4096
        )
    elif key_algorithm == 'ECDSA_P256':
        return ec.generate_private_key(ec.SECP256R1())
    elif key_algorithm == 'ECDSA_P384':
        return ec.generate_private_key(ec.SECP384R1())
    else:
        raise ValueError(f"Unsupported key algorithm: {key_algorithm}")


def _create_certificate_request(private_key, renewal_params: Dict[str, Any]):
    """
    Create a certificate signing request (CSR) for the new certificate.
    
    Args:
        private_key: Private key for the certificate
        renewal_params: Certificate parameters
        
    Returns:
        Certificate signing request object
    """
    
    # Build subject distinguished name
    subject = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, renewal_params['country_code']),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, renewal_params['organization']),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, renewal_params['organizational_unit']),
        x509.NameAttribute(NameOID.COMMON_NAME, renewal_params['common_name']),
    ])
    
    # Create certificate signing request builder
    csr_builder = x509.CertificateSigningRequestBuilder().subject_name(subject)
    
    # Add Subject Alternative Names
    san_list = [x509.DNSName(dns_name) for dns_name in renewal_params['dns_sans']]
    if san_list:
        csr_builder = csr_builder.add_extension(
            x509.SubjectAlternativeName(san_list),
            critical=False
        )
    
    # Add Key Usage extension
    csr_builder = csr_builder.add_extension(
        x509.KeyUsage(
            digital_signature=True,
            key_encipherment=True,
            content_commitment=False,
            data_encipherment=False,
            key_agreement=False,
            key_cert_sign=False,
            crl_sign=False,
            encipher_only=False,
            decipher_only=False
        ),
        critical=True
    )
    
    # Add Extended Key Usage extension
    csr_builder = csr_builder.add_extension(
        x509.ExtendedKeyUsage([
            ExtendedKeyUsageOID.SERVER_AUTH,
            ExtendedKeyUsageOID.CLIENT_AUTH
        ]),
        critical=True
    )
    
    # Sign the CSR
    csr = csr_builder.sign(private_key, hashes.SHA256())
    
    return csr


def _issue_certificate(ca_client: privateca_v1.CertificateAuthorityServiceClient,
                      csr, renewal_params: Dict[str, Any]):
    """
    Issue a certificate using Google Cloud Certificate Authority Service.
    
    Args:
        ca_client: Certificate Authority Service client
        csr: Certificate signing request
        renewal_params: Certificate parameters
        
    Returns:
        Certificate response from Certificate Authority Service
    """
    
    # Convert CSR to PEM format
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode('utf-8')
    
    # Create certificate request
    certificate = privateca_v1.Certificate(
        pem_csr=csr_pem,
        lifetime=datetime.timedelta(days=renewal_params['validity_days'])
    )
    
    # Build CA path
    ca_parent = f"projects/{PROJECT_ID}/locations/{REGION}/caPools/{CA_POOL_NAME}"
    
    # Generate unique certificate ID
    timestamp = int(datetime.datetime.now().timestamp())
    cert_id = f"{renewal_params['common_name'].replace('.', '-')}-{timestamp}"
    
    # Create certificate request
    request = privateca_v1.CreateCertificateRequest(
        parent=ca_parent,
        certificate=certificate,
        certificate_id=cert_id
    )
    
    # Issue the certificate
    logger.info(f"Issuing certificate via CA: {SUB_CA_NAME}")
    operation = ca_client.create_certificate(request=request)
    certificate_response = operation.result(timeout=300)
    
    logger.info(f"Certificate issued successfully: {certificate_response.name}")
    
    return certificate_response


def _store_certificate_bundle(secret_client: secretmanager.SecretManagerServiceClient,
                            certificate_response, private_key, 
                            renewal_params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Store the certificate bundle in Secret Manager.
    
    Args:
        secret_client: Secret Manager client
        certificate_response: Certificate response from CA Service
        private_key: Private key for the certificate
        renewal_params: Certificate parameters
        
    Returns:
        Dictionary with storage information
    """
    
    # Prepare certificate bundle
    private_key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    ).decode('utf-8')
    
    certificate_bundle = {
        'certificate': certificate_response.pem_certificate,
        'private_key': private_key_pem,
        'certificate_chain': certificate_response.pem_certificate_chain,
        'common_name': renewal_params['common_name'],
        'subject_alt_names': renewal_params['dns_sans'],
        'issued_date': datetime.datetime.utcnow().isoformat(),
        'expiry_date': (datetime.datetime.utcnow() + 
                       datetime.timedelta(days=renewal_params['validity_days'])).isoformat(),
        'key_algorithm': renewal_params['key_algorithm'],
        'ca_pool': CA_POOL_NAME,
        'issuing_ca': SUB_CA_NAME,
        'certificate_name': certificate_response.name
    }
    
    # Convert to JSON
    bundle_json = json.dumps(certificate_bundle, indent=2)
    
    # Create secret name
    secret_name = f"cert-{renewal_params['common_name'].replace('.', '-')}"
    secret_id = f"projects/{PROJECT_ID}/secrets/{secret_name}"
    
    try:
        # Try to create the secret (will fail if it already exists)
        secret_client.create_secret(
            request={
                "parent": f"projects/{PROJECT_ID}",
                "secret_id": secret_name,
                "secret": {
                    "replication": {"automatic": {}},
                    "labels": {
                        "certificate-cn": renewal_params['common_name'].replace('.', '-'),
                        "ca-pool": CA_POOL_NAME,
                        "managed-by": "certificate-lifecycle-automation"
                    }
                }
            }
        )
        logger.info(f"Created new secret: {secret_name}")
    except Exception as e:
        # Secret already exists, which is fine for renewals
        logger.info(f"Secret {secret_name} already exists, adding new version")
    
    # Add new secret version
    response = secret_client.add_secret_version(
        request={
            "parent": secret_id,
            "payload": {"data": bundle_json.encode('utf-8')}
        }
    )
    
    logger.info(f"Stored certificate bundle in Secret Manager: {response.name}")
    
    return {
        'secret_name': secret_name,
        'secret_version': response.name,
        'bundle_size_bytes': len(bundle_json.encode('utf-8')),
        'stored_timestamp': datetime.datetime.utcnow().isoformat()
    }


def _extract_serial_number(cert_pem: str) -> str:
    """Extract serial number from PEM certificate."""
    try:
        cert = x509.load_pem_x509_certificate(cert_pem.encode(), default_backend())
        return str(cert.serial_number)
    except Exception:
        return "unknown"


def _extract_not_before(cert_pem: str) -> str:
    """Extract not_before date from PEM certificate."""
    try:
        cert = x509.load_pem_x509_certificate(cert_pem.encode(), default_backend())
        return cert.not_valid_before.isoformat()
    except Exception:
        return "unknown"


def _extract_not_after(cert_pem: str) -> str:
    """Extract not_after date from PEM certificate."""
    try:
        cert = x509.load_pem_x509_certificate(cert_pem.encode(), default_backend())
        return cert.not_valid_after.isoformat()
    except Exception:
        return "unknown"