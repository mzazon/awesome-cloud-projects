"""
Lambda function to process DICOM metadata from AWS HealthImaging image sets.

This function extracts and structures metadata from DICOM files that have been
imported into HealthImaging, making it available for clinical workflows and
downstream processing.
"""

import json
import boto3
import os
import logging
from typing import Dict, Any, Optional
from botocore.exceptions import ClientError
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for processing DICOM metadata.
    
    This function retrieves metadata from HealthImaging image sets and
    structures it for clinical use and downstream processing.
    
    Args:
        event: Event containing datastore and image set information
        context: Lambda context object
        
    Returns:
        Dict containing processed metadata and status
    """
    logger.info(f"Processing metadata event: {json.dumps(event, default=str)}")
    
    # Get environment variables
    output_bucket = os.environ.get('OUTPUT_BUCKET', '${output_bucket}')
    
    try:
        # Extract required parameters from event
        datastore_id = event.get('datastoreId') or event.get('dataStoreId')
        image_set_id = event.get('imageSetId')
        
        if not datastore_id or not image_set_id:
            raise ValueError("Missing required parameters: datastoreId and imageSetId")
        
        logger.info(f"Processing image set {image_set_id} in datastore {datastore_id}")
        
        # Get image set metadata from HealthImaging
        try:
            response = medical_imaging.get_image_set_metadata(
                datastoreId=datastore_id,
                imageSetId=image_set_id
            )
            
            # Parse the metadata blob
            metadata_blob = response['imageSetMetadataBlob'].read()
            metadata = json.loads(metadata_blob)
            
            logger.info("Successfully retrieved image set metadata")
            
        except ClientError as e:
            error_msg = f"Failed to retrieve metadata for image set {image_set_id}: {str(e)}"
            logger.error(error_msg)
            raise
        
        # Process and structure the metadata
        processed_metadata = process_dicom_metadata(metadata, image_set_id, context.aws_request_id)
        
        # Store processed metadata in S3
        output_key = f"metadata/{image_set_id}/metadata.json"
        store_metadata_in_s3(processed_metadata, output_bucket, output_key)
        
        # Create summary for clinical use
        clinical_summary = create_clinical_summary(processed_metadata)
        summary_key = f"metadata/{image_set_id}/clinical_summary.json"
        store_metadata_in_s3(clinical_summary, output_bucket, summary_key)
        
        logger.info(f"Successfully processed metadata for image set {image_set_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Metadata processed successfully',
                'imageSetId': image_set_id,
                'metadataLocation': f"s3://{output_bucket}/{output_key}",
                'summaryLocation': f"s3://{output_bucket}/{summary_key}",
                'processedMetadata': processed_metadata
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_msg = f"Error processing metadata: {str(e)}"
        logger.error(error_msg)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'requestId': context.aws_request_id
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }


def process_dicom_metadata(metadata: Dict[str, Any], image_set_id: str, request_id: str) -> Dict[str, Any]:
    """
    Process and structure DICOM metadata for clinical use.
    
    Args:
        metadata: Raw DICOM metadata from HealthImaging
        image_set_id: Image set identifier
        request_id: Lambda request ID for tracking
        
    Returns:
        Dictionary containing structured metadata
    """
    logger.info("Processing DICOM metadata structure")
    
    # Extract patient information
    patient_info = metadata.get('Patient', {}).get('DICOM', {})
    
    # Extract study information
    study_info = metadata.get('Study', {}).get('DICOM', {})
    
    # Extract series information (may be multiple series)
    series_list = []
    if 'Series' in metadata:
        if isinstance(metadata['Series'], list):
            series_list = metadata['Series']
        else:
            series_list = [metadata['Series']]
    
    # Process series information
    processed_series = []
    total_instances = 0
    
    for series in series_list:
        series_dicom = series.get('DICOM', {})
        instances = series.get('Instances', [])
        
        series_info = {
            'seriesInstanceUID': series_dicom.get('SeriesInstanceUID'),
            'seriesNumber': series_dicom.get('SeriesNumber'),
            'modality': series_dicom.get('Modality'),
            'seriesDescription': series_dicom.get('SeriesDescription'),
            'bodyPartExamined': series_dicom.get('BodyPartExamined'),
            'instanceCount': len(instances) if isinstance(instances, list) else 0,
            'instances': []
        }
        
        # Process instances within the series
        if isinstance(instances, list):
            for instance in instances:
                instance_dicom = instance.get('DICOM', {})
                instance_info = {
                    'sopInstanceUID': instance_dicom.get('SOPInstanceUID'),
                    'instanceNumber': instance_dicom.get('InstanceNumber'),
                    'sopClassUID': instance_dicom.get('SOPClassUID')
                }
                series_info['instances'].append(instance_info)
            
            total_instances += len(instances)
        
        processed_series.append(series_info)
    
    # Create structured metadata output
    processed_metadata = {
        'imageSetId': image_set_id,
        'processingTimestamp': datetime.utcnow().isoformat(),
        'requestId': request_id,
        
        # Patient Information
        'patient': {
            'patientId': patient_info.get('PatientID'),
            'patientName': patient_info.get('PatientName'),
            'patientBirthDate': patient_info.get('PatientBirthDate'),
            'patientSex': patient_info.get('PatientSex'),
            'patientAge': patient_info.get('PatientAge')
        },
        
        # Study Information
        'study': {
            'studyInstanceUID': study_info.get('StudyInstanceUID'),
            'studyId': study_info.get('StudyID'),
            'studyDate': study_info.get('StudyDate'),
            'studyTime': study_info.get('StudyTime'),
            'studyDescription': study_info.get('StudyDescription'),
            'accessionNumber': study_info.get('AccessionNumber'),
            'referringPhysicianName': study_info.get('ReferringPhysicianName'),
            'institutionName': study_info.get('InstitutionName')
        },
        
        # Series and Instance Information
        'series': processed_series,
        'totalSeries': len(processed_series),
        'totalInstances': total_instances,
        
        # Technical Information
        'technical': {
            'manufacturer': extract_manufacturer_info(metadata),
            'modalityTypes': list(set([s['modality'] for s in processed_series if s['modality']])),
            'bodyPartsExamined': list(set([s['bodyPartExamined'] for s in processed_series if s['bodyPartExamined']]))
        }
    }
    
    return processed_metadata


def create_clinical_summary(metadata: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create a clinical summary from processed metadata.
    
    Args:
        metadata: Processed DICOM metadata
        
    Returns:
        Dictionary containing clinical summary
    """
    return {
        'imageSetId': metadata['imageSetId'],
        'patientId': metadata['patient']['patientId'],
        'studyDate': metadata['study']['studyDate'],
        'modalities': metadata['technical']['modalityTypes'],
        'seriesCount': metadata['totalSeries'],
        'instanceCount': metadata['totalInstances'],
        'studyDescription': metadata['study']['studyDescription'],
        'bodyParts': metadata['technical']['bodyPartsExamined'],
        'summary': {
            'isMultiModality': len(metadata['technical']['modalityTypes']) > 1,
            'hasMultipleSeries': metadata['totalSeries'] > 1,
            'complexStudy': metadata['totalInstances'] > 100
        }
    }


def extract_manufacturer_info(metadata: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract manufacturer and equipment information from metadata.
    
    Args:
        metadata: Raw DICOM metadata
        
    Returns:
        Dictionary containing manufacturer information
    """
    # Look for manufacturer info in series or study level
    manufacturer_info = {}
    
    if 'Series' in metadata:
        series_list = metadata['Series'] if isinstance(metadata['Series'], list) else [metadata['Series']]
        for series in series_list:
            series_dicom = series.get('DICOM', {})
            if 'Manufacturer' in series_dicom:
                manufacturer_info['manufacturer'] = series_dicom['Manufacturer']
            if 'ManufacturerModelName' in series_dicom:
                manufacturer_info['modelName'] = series_dicom['ManufacturerModelName']
            if 'SoftwareVersions' in series_dicom:
                manufacturer_info['softwareVersions'] = series_dicom['SoftwareVersions']
            break  # Use first series with manufacturer info
    
    return manufacturer_info


def store_metadata_in_s3(metadata: Dict[str, Any], bucket: str, key: str) -> None:
    """
    Store processed metadata in S3.
    
    Args:
        metadata: Metadata to store
        bucket: S3 bucket name
        key: S3 object key
    """
    try:
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(metadata, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Successfully stored metadata at s3://{bucket}/{key}")
        
    except ClientError as e:
        error_msg = f"Failed to store metadata in S3: {str(e)}"
        logger.error(error_msg)
        raise