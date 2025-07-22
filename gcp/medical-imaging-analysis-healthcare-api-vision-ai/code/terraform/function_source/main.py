"""
Medical Imaging Analysis Cloud Function

This Cloud Function processes medical images using Google Cloud Healthcare API
and Vision AI to provide automated analysis and anomaly detection.

Author: Google Cloud Recipes
Version: 1.0
"""

import os
import json
import base64
import logging
from datetime import datetime
from typing import Dict, List, Optional, Any
import io

# Google Cloud imports
from google.cloud import healthcare_v1
from google.cloud import vision
from google.cloud import storage
from google.cloud import pubsub_v1
import google.cloud.logging

# Medical imaging imports
import pydicom
from PIL import Image
import numpy as np

# Functions Framework
import functions_framework

# Configure Cloud Logging
client = google.cloud.logging.Client()
client.setup_logging()
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID')
DATASET_ID = os.environ.get('DATASET_ID')
DICOM_STORE_ID = os.environ.get('DICOM_STORE_ID')
FHIR_STORE_ID = os.environ.get('FHIR_STORE_ID')
REGION = os.environ.get('REGION', 'us-central1')
BUCKET_NAME = os.environ.get('BUCKET_NAME')

# Initialize clients (global for performance)
healthcare_client = healthcare_v1.HealthcareServiceClient()
vision_client = vision.ImageAnnotatorClient()
storage_client = storage.Client()


@functions_framework.cloud_event
def process_medical_image(cloud_event):
    """
    Main entry point for processing medical images.
    
    This function is triggered by Pub/Sub messages from the Healthcare API
    when new DICOM instances are stored.
    
    Args:
        cloud_event: CloudEvent containing the Pub/Sub message
        
    Returns:
        Dict containing processing results
    """
    try:
        logger.info(f"Processing medical image event: {cloud_event}")
        
        # Extract event data
        event_data = _extract_event_data(cloud_event)
        if not event_data:
            logger.error("Failed to extract event data")
            return {"status": "error", "message": "Invalid event data"}
        
        logger.info(f"Processing DICOM instance: {event_data.get('name', 'unknown')}")
        
        # Process the DICOM image
        analysis_results = _process_dicom_image(event_data)
        
        if analysis_results:
            # Store results in FHIR store
            _store_analysis_results(analysis_results, event_data)
            
            # Move processed image to appropriate folder
            _move_processed_image(event_data, analysis_results)
            
            logger.info(f"Successfully processed image: {event_data.get('name', 'unknown')}")
            return {"status": "success", "results": analysis_results}
        else:
            logger.error(f"Failed to process image: {event_data.get('name', 'unknown')}")
            return {"status": "error", "message": "Image processing failed"}
            
    except Exception as e:
        logger.error(f"Error processing medical image: {str(e)}", exc_info=True)
        return {"status": "error", "message": str(e)}


def _extract_event_data(cloud_event) -> Optional[Dict[str, Any]]:
    """
    Extract and validate event data from the Pub/Sub message.
    
    Args:
        cloud_event: CloudEvent containing the Pub/Sub message
        
    Returns:
        Dict containing event data or None if invalid
    """
    try:
        # Decode the Pub/Sub message
        message_data = base64.b64decode(cloud_event.data['message']['data']).decode('utf-8')
        event_data = json.loads(message_data)
        
        # Validate required fields
        if 'name' not in event_data:
            logger.error("Event data missing 'name' field")
            return None
            
        return event_data
        
    except Exception as e:
        logger.error(f"Failed to extract event data: {str(e)}")
        return None


def _process_dicom_image(event_data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Process a DICOM image with Vision AI analysis.
    
    Args:
        event_data: Event data containing DICOM instance information
        
    Returns:
        Dict containing analysis results or None if processing failed
    """
    try:
        # Retrieve DICOM instance from Healthcare API
        dicom_instance = _retrieve_dicom_instance(event_data['name'])
        if not dicom_instance:
            return None
        
        # Convert DICOM to PIL Image for Vision AI
        pil_image, dicom_metadata = _convert_dicom_to_image(dicom_instance)
        if not pil_image:
            return None
        
        # Perform Vision AI analysis
        vision_results = _analyze_image_with_vision_ai(pil_image)
        if not vision_results:
            return None
        
        # Combine results with metadata
        analysis_results = _combine_analysis_results(dicom_metadata, vision_results)
        
        return analysis_results
        
    except Exception as e:
        logger.error(f"Failed to process DICOM image: {str(e)}")
        return None


def _retrieve_dicom_instance(instance_name: str) -> Optional[bytes]:
    """
    Retrieve DICOM instance data from Healthcare API.
    
    Args:
        instance_name: Full name/path of the DICOM instance
        
    Returns:
        DICOM instance data as bytes or None if retrieval failed
    """
    try:
        # Get the DICOM instance
        request = healthcare_v1.GetInstanceRequest(name=instance_name)
        response = healthcare_client.get_instance(request=request)
        
        return response.data
        
    except Exception as e:
        logger.error(f"Failed to retrieve DICOM instance {instance_name}: {str(e)}")
        return None


def _convert_dicom_to_image(dicom_data: bytes) -> tuple[Optional[Image.Image], Optional[Dict[str, Any]]]:
    """
    Convert DICOM data to PIL Image and extract metadata.
    
    Args:
        dicom_data: Raw DICOM data as bytes
        
    Returns:
        Tuple of (PIL Image, metadata dict) or (None, None) if conversion failed
    """
    try:
        # Parse DICOM data
        dicom_dataset = pydicom.dcmread(io.BytesIO(dicom_data))
        
        # Extract pixel data
        if not hasattr(dicom_dataset, 'pixel_array'):
            logger.error("DICOM file has no pixel data")
            return None, None
        
        pixel_array = dicom_dataset.pixel_array
        
        # Normalize pixel values for Vision AI (0-255 range)
        if pixel_array.dtype != np.uint8:
            # Normalize to 0-255 range
            normalized_pixels = ((pixel_array - pixel_array.min()) / 
                               (pixel_array.max() - pixel_array.min()) * 255).astype(np.uint8)
        else:
            normalized_pixels = pixel_array
        
        # Convert to PIL Image
        pil_image = Image.fromarray(normalized_pixels)
        
        # Extract DICOM metadata
        metadata = {
            'patient_id': str(dicom_dataset.get('PatientID', 'Unknown')),
            'study_date': str(dicom_dataset.get('StudyDate', 'Unknown')),
            'study_time': str(dicom_dataset.get('StudyTime', 'Unknown')),
            'modality': str(dicom_dataset.get('Modality', 'Unknown')),
            'study_description': str(dicom_dataset.get('StudyDescription', 'Unknown')),
            'series_description': str(dicom_dataset.get('SeriesDescription', 'Unknown')),
            'institution_name': str(dicom_dataset.get('InstitutionName', 'Unknown')),
            'manufacturer': str(dicom_dataset.get('Manufacturer', 'Unknown')),
            'manufacturer_model': str(dicom_dataset.get('ManufacturerModelName', 'Unknown')),
            'image_dimensions': {
                'width': int(normalized_pixels.shape[1]),
                'height': int(normalized_pixels.shape[0])
            }
        }
        
        return pil_image, metadata
        
    except Exception as e:
        logger.error(f"Failed to convert DICOM to image: {str(e)}")
        return None, None


def _analyze_image_with_vision_ai(pil_image: Image.Image) -> Optional[Dict[str, Any]]:
    """
    Analyze the image using Google Cloud Vision AI.
    
    Args:
        pil_image: PIL Image to analyze
        
    Returns:
        Dict containing Vision AI analysis results or None if analysis failed
    """
    try:
        # Convert PIL Image to bytes for Vision AI
        img_byte_arr = io.BytesIO()
        pil_image.save(img_byte_arr, format='PNG')
        img_byte_arr = img_byte_arr.getvalue()
        
        # Create Vision AI image object
        image = vision.Image(content=img_byte_arr)
        
        # Perform multiple types of analysis
        results = {}
        
        # Object detection
        try:
            objects_response = vision_client.object_localization(image=image)
            results['objects'] = [
                {
                    'name': obj.name,
                    'confidence': float(obj.score),
                    'bounding_box': {
                        'vertices': [
                            {'x': vertex.x, 'y': vertex.y} 
                            for vertex in obj.bounding_poly.normalized_vertices
                        ]
                    }
                }
                for obj in objects_response.localized_object_annotations
            ]
        except Exception as e:
            logger.warning(f"Object detection failed: {str(e)}")
            results['objects'] = []
        
        # Label detection
        try:
            labels_response = vision_client.label_detection(image=image)
            results['labels'] = [
                {
                    'description': label.description,
                    'confidence': float(label.score),
                    'topicality': float(label.topicality)
                }
                for label in labels_response.label_annotations
            ]
        except Exception as e:
            logger.warning(f"Label detection failed: {str(e)}")
            results['labels'] = []
        
        # Safe search detection (for content filtering)
        try:
            safe_search_response = vision_client.safe_search_detection(image=image)
            safe_search = safe_search_response.safe_search_annotation
            results['safe_search'] = {
                'adult': safe_search.adult.name,
                'spoof': safe_search.spoof.name,
                'medical': safe_search.medical.name,
                'violence': safe_search.violence.name,
                'racy': safe_search.racy.name
            }
        except Exception as e:
            logger.warning(f"Safe search detection failed: {str(e)}")
            results['safe_search'] = {}
        
        # Check for potential anomalies based on confidence scores
        results['anomaly_detected'] = _detect_anomalies(results)
        
        return results
        
    except Exception as e:
        logger.error(f"Vision AI analysis failed: {str(e)}")
        return None


def _detect_anomalies(vision_results: Dict[str, Any]) -> Dict[str, Any]:
    """
    Detect potential anomalies based on Vision AI results.
    
    Args:
        vision_results: Results from Vision AI analysis
        
    Returns:
        Dict containing anomaly detection results
    """
    anomaly_info = {
        'detected': False,
        'confidence': 0.0,
        'reasons': []
    }
    
    try:
        # Check for high-confidence object detections
        objects = vision_results.get('objects', [])
        high_confidence_objects = [obj for obj in objects if obj['confidence'] > 0.8]
        
        if high_confidence_objects:
            anomaly_info['detected'] = True
            anomaly_info['confidence'] = max(obj['confidence'] for obj in high_confidence_objects)
            anomaly_info['reasons'].append(f"High confidence objects detected: {len(high_confidence_objects)}")
        
        # Check for medical-related labels
        labels = vision_results.get('labels', [])
        medical_labels = [
            label for label in labels 
            if any(term in label['description'].lower() for term in 
                  ['medical', 'anatomy', 'organ', 'bone', 'tissue', 'pathology'])
            and label['confidence'] > 0.7
        ]
        
        if medical_labels:
            if not anomaly_info['detected']:
                anomaly_info['detected'] = True
                anomaly_info['confidence'] = max(label['confidence'] for label in medical_labels)
            anomaly_info['reasons'].append(f"Medical content detected: {len(medical_labels)} labels")
        
        # Check safe search results for medical content
        safe_search = vision_results.get('safe_search', {})
        if safe_search.get('medical') in ['LIKELY', 'VERY_LIKELY']:
            anomaly_info['detected'] = True
            anomaly_info['reasons'].append("Medical content flagged by safe search")
        
    except Exception as e:
        logger.error(f"Anomaly detection failed: {str(e)}")
    
    return anomaly_info


def _combine_analysis_results(dicom_metadata: Dict[str, Any], 
                            vision_results: Dict[str, Any]) -> Dict[str, Any]:
    """
    Combine DICOM metadata with Vision AI analysis results.
    
    Args:
        dicom_metadata: Metadata extracted from DICOM file
        vision_results: Results from Vision AI analysis
        
    Returns:
        Combined analysis results
    """
    return {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'processing_version': '1.0',
        'dicom_metadata': dicom_metadata,
        'vision_analysis': vision_results,
        'summary': {
            'objects_detected': len(vision_results.get('objects', [])),
            'labels_detected': len(vision_results.get('labels', [])),
            'anomaly_detected': vision_results.get('anomaly_detected', {}).get('detected', False),
            'anomaly_confidence': vision_results.get('anomaly_detected', {}).get('confidence', 0.0),
            'processing_successful': True
        }
    }


def _store_analysis_results(analysis_results: Dict[str, Any], event_data: Dict[str, Any]) -> bool:
    """
    Store analysis results in the FHIR store as a DiagnosticReport.
    
    Args:
        analysis_results: Combined analysis results
        event_data: Original event data
        
    Returns:
        True if storage was successful, False otherwise
    """
    try:
        # Create FHIR DiagnosticReport resource
        diagnostic_report = _create_fhir_diagnostic_report(analysis_results, event_data)
        
        # Store in FHIR store
        fhir_store_path = f"projects/{PROJECT_ID}/locations/{REGION}/datasets/{DATASET_ID}/fhirStores/{FHIR_STORE_ID}"
        
        request = healthcare_v1.CreateResourceRequest(
            parent=fhir_store_path,
            type_="DiagnosticReport",
            body=json.dumps(diagnostic_report).encode()
        )
        
        response = healthcare_client.create_resource(request=request)
        logger.info(f"Stored analysis results in FHIR store: {response.name}")
        
        return True
        
    except Exception as e:
        logger.error(f"Failed to store analysis results: {str(e)}")
        return False


def _create_fhir_diagnostic_report(analysis_results: Dict[str, Any], 
                                 event_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create a FHIR DiagnosticReport resource from analysis results.
    
    Args:
        analysis_results: Combined analysis results
        event_data: Original event data
        
    Returns:
        FHIR DiagnosticReport resource as dict
    """
    return {
        "resourceType": "DiagnosticReport",
        "status": "final",
        "category": [
            {
                "coding": [
                    {
                        "system": "http://terminology.hl7.org/CodeSystem/v2-0074",
                        "code": "RAD",
                        "display": "Radiology"
                    }
                ]
            }
        ],
        "code": {
            "coding": [
                {
                    "system": "http://loinc.org",
                    "code": "18748-4",
                    "display": "Diagnostic imaging study"
                }
            ]
        },
        "subject": {
            "reference": f"Patient/{analysis_results['dicom_metadata']['patient_id']}"
        },
        "effectiveDateTime": analysis_results['timestamp'],
        "issued": analysis_results['timestamp'],
        "conclusion": f"AI Analysis: {analysis_results['summary']['objects_detected']} objects detected, "
                     f"{analysis_results['summary']['labels_detected']} labels identified. "
                     f"Anomaly detected: {analysis_results['summary']['anomaly_detected']}",
        "conclusionCode": [
            {
                "coding": [
                    {
                        "system": "http://snomed.info/sct",
                        "code": "365854008" if analysis_results['summary']['anomaly_detected'] else "365855009",
                        "display": "Abnormal finding" if analysis_results['summary']['anomaly_detected'] else "Normal finding"
                    }
                ]
            }
        ],
        "presentedForm": [
            {
                "contentType": "application/json",
                "data": base64.b64encode(json.dumps(analysis_results).encode()).decode()
            }
        ]
    }


def _move_processed_image(event_data: Dict[str, Any], analysis_results: Dict[str, Any]) -> bool:
    """
    Move processed image to appropriate folder based on results.
    
    Args:
        event_data: Original event data
        analysis_results: Analysis results
        
    Returns:
        True if move was successful, False otherwise
    """
    try:
        # This is a placeholder for moving images between folders
        # In a real implementation, you would move the source images
        # from incoming/ to processed/ or failed/ folders
        
        bucket = storage_client.bucket(BUCKET_NAME)
        
        # Create a processing log entry
        log_content = {
            'event': event_data,
            'results': analysis_results,
            'status': 'processed' if analysis_results['summary']['processing_successful'] else 'failed'
        }
        
        log_filename = f"logs/processing_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
        blob = bucket.blob(log_filename)
        blob.upload_from_string(json.dumps(log_content, indent=2))
        
        logger.info(f"Created processing log: {log_filename}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to move processed image: {str(e)}")
        return False