"""
Lambda function to perform medical image analysis on DICOM images.

This function retrieves image frames from AWS HealthImaging and performs
basic image analysis including quality checks, statistical analysis, and
preparation for AI/ML inference workflows.
"""

import json
import boto3
import os
import logging
from typing import Dict, Any, List, Optional, Tuple
from botocore.exceptions import ClientError
from datetime import datetime
import base64
import io

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
medical_imaging = boto3.client('medical-imaging')
s3 = boto3.client('s3')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for medical image analysis.
    
    This function performs basic image analysis on medical images stored
    in HealthImaging, providing quality metrics and preparing data for
    AI/ML workflows.
    
    Args:
        event: Event containing datastore and image set information
        context: Lambda context object
        
    Returns:
        Dict containing analysis results and status
    """
    logger.info(f"Starting image analysis: {json.dumps(event, default=str)}")
    
    # Get environment variables
    output_bucket = os.environ.get('OUTPUT_BUCKET', '${output_bucket}')
    
    try:
        # Extract required parameters from event
        datastore_id = event.get('datastoreId') or event.get('dataStoreId')
        image_set_id = event.get('imageSetId')
        
        if not datastore_id or not image_set_id:
            raise ValueError("Missing required parameters: datastoreId and imageSetId")
        
        logger.info(f"Analyzing image set {image_set_id} in datastore {datastore_id}")
        
        # Get image set metadata first
        metadata_response = medical_imaging.get_image_set_metadata(
            datastoreId=datastore_id,
            imageSetId=image_set_id
        )
        
        # Parse metadata to understand image structure
        metadata_blob = metadata_response['imageSetMetadataBlob'].read()
        metadata = json.loads(metadata_blob)
        
        # Perform analysis on the image set
        analysis_results = perform_image_analysis(
            datastore_id, 
            image_set_id, 
            metadata, 
            context.aws_request_id
        )
        
        # Store analysis results in S3
        output_key = f"analysis/{image_set_id}/analysis_results.json"
        store_analysis_results(analysis_results, output_bucket, output_key)
        
        # Create analysis summary
        summary = create_analysis_summary(analysis_results)
        summary_key = f"analysis/{image_set_id}/analysis_summary.json"
        store_analysis_results(summary, output_bucket, summary_key)
        
        logger.info(f"Successfully completed image analysis for {image_set_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Image analysis completed successfully',
                'imageSetId': image_set_id,
                'analysisLocation': f"s3://{output_bucket}/{output_key}",
                'summaryLocation': f"s3://{output_bucket}/{summary_key}",
                'analysisResults': summary
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_msg = f"Error analyzing image: {str(e)}"
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


def perform_image_analysis(
    datastore_id: str, 
    image_set_id: str, 
    metadata: Dict[str, Any], 
    request_id: str
) -> Dict[str, Any]:
    """
    Perform comprehensive image analysis on the image set.
    
    Args:
        datastore_id: HealthImaging datastore ID
        image_set_id: Image set ID
        metadata: DICOM metadata
        request_id: Request tracking ID
        
    Returns:
        Dictionary containing analysis results
    """
    logger.info("Starting comprehensive image analysis")
    
    # Initialize analysis results structure
    analysis_results = {
        'imageSetId': image_set_id,
        'datastoreId': datastore_id,
        'analysisTimestamp': datetime.utcnow().isoformat(),
        'requestId': request_id,
        'analysisType': 'ComprehensiveQualityAnalysis',
        'version': '1.0'
    }
    
    # Extract basic information from metadata
    basic_info = extract_basic_info(metadata)
    analysis_results['imageInfo'] = basic_info
    
    # Perform quality analysis
    quality_analysis = perform_quality_analysis(metadata, basic_info)
    analysis_results['qualityAnalysis'] = quality_analysis
    
    # Perform statistical analysis
    statistical_analysis = perform_statistical_analysis(metadata)
    analysis_results['statisticalAnalysis'] = statistical_analysis
    
    # Generate recommendations
    recommendations = generate_recommendations(quality_analysis, statistical_analysis, basic_info)
    analysis_results['recommendations'] = recommendations
    
    # Calculate overall assessment
    overall_assessment = calculate_overall_assessment(quality_analysis, statistical_analysis)
    analysis_results['overallAssessment'] = overall_assessment
    
    logger.info("Completed comprehensive image analysis")
    return analysis_results


def extract_basic_info(metadata: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract basic information about the image set.
    
    Args:
        metadata: DICOM metadata
        
    Returns:
        Dictionary containing basic image information
    """
    # Process series information
    series_list = []
    if 'Series' in metadata:
        if isinstance(metadata['Series'], list):
            series_list = metadata['Series']
        else:
            series_list = [metadata['Series']]
    
    # Extract modalities and instance counts
    modalities = []
    total_instances = 0
    series_info = []
    
    for series in series_list:
        series_dicom = series.get('DICOM', {})
        instances = series.get('Instances', [])
        instance_count = len(instances) if isinstance(instances, list) else 0
        
        modality = series_dicom.get('Modality', 'UNKNOWN')
        modalities.append(modality)
        total_instances += instance_count
        
        series_info.append({
            'seriesInstanceUID': series_dicom.get('SeriesInstanceUID'),
            'modality': modality,
            'instanceCount': instance_count,
            'seriesDescription': series_dicom.get('SeriesDescription', ''),
            'bodyPartExamined': series_dicom.get('BodyPartExamined', '')
        })
    
    return {
        'totalSeries': len(series_list),
        'totalInstances': total_instances,
        'modalities': list(set(modalities)),
        'seriesInfo': series_info,
        'isMultiModality': len(set(modalities)) > 1,
        'largeStudy': total_instances > 100
    }


def perform_quality_analysis(metadata: Dict[str, Any], basic_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Perform quality analysis on the image set.
    
    Args:
        metadata: DICOM metadata
        basic_info: Basic image information
        
    Returns:
        Dictionary containing quality analysis results
    """
    quality_score = 0.0
    quality_issues = []
    quality_details = {}
    
    # Check for missing critical metadata
    study_info = metadata.get('Study', {}).get('DICOM', {})
    patient_info = metadata.get('Patient', {}).get('DICOM', {})
    
    # Patient identification completeness
    if patient_info.get('PatientID'):
        quality_score += 0.2
    else:
        quality_issues.append("Missing Patient ID")
    
    if patient_info.get('PatientName'):
        quality_score += 0.1
    else:
        quality_issues.append("Missing Patient Name")
    
    # Study information completeness
    if study_info.get('StudyInstanceUID'):
        quality_score += 0.2
    else:
        quality_issues.append("Missing Study Instance UID")
    
    if study_info.get('StudyDate'):
        quality_score += 0.1
    else:
        quality_issues.append("Missing Study Date")
    
    if study_info.get('StudyDescription'):
        quality_score += 0.1
    else:
        quality_issues.append("Missing Study Description")
    
    # Series consistency checks
    modalities = basic_info['modalities']
    if len(modalities) == 1:
        quality_score += 0.1
    elif len(modalities) > 3:
        quality_issues.append("Too many different modalities in single study")
    
    # Instance count validation
    total_instances = basic_info['totalInstances']
    if total_instances > 0:
        quality_score += 0.2
        if total_instances < 10:
            quality_issues.append("Low instance count may indicate incomplete study")
        elif total_instances > 1000:
            quality_issues.append("Very high instance count may indicate data quality issues")
    else:
        quality_issues.append("No instances found in image set")
    
    # Calculate final quality score (0-1 scale)
    quality_score = min(1.0, quality_score)
    
    # Determine quality level
    if quality_score >= 0.8:
        quality_level = "EXCELLENT"
    elif quality_score >= 0.6:
        quality_level = "GOOD"
    elif quality_score >= 0.4:
        quality_level = "FAIR"
    else:
        quality_level = "POOR"
    
    quality_details = {
        'qualityScore': round(quality_score, 3),
        'qualityLevel': quality_level,
        'qualityIssues': quality_issues,
        'metadataCompleteness': {
            'hasPatientID': bool(patient_info.get('PatientID')),
            'hasStudyUID': bool(study_info.get('StudyInstanceUID')),
            'hasStudyDate': bool(study_info.get('StudyDate')),
            'hasStudyDescription': bool(study_info.get('StudyDescription'))
        },
        'structuralIntegrity': {
            'seriesCount': basic_info['totalSeries'],
            'instanceCount': basic_info['totalInstances'],
            'modalityConsistency': len(modalities) <= 2
        }
    }
    
    return quality_details


def perform_statistical_analysis(metadata: Dict[str, Any]) -> Dict[str, Any]:
    """
    Perform statistical analysis on the image metadata.
    
    Args:
        metadata: DICOM metadata
        
    Returns:
        Dictionary containing statistical analysis
    """
    stats = {
        'dataCharacteristics': {},
        'modalityDistribution': {},
        'temporalAnalysis': {},
        'technicalParameters': {}
    }
    
    # Analyze series distribution
    series_list = []
    if 'Series' in metadata:
        if isinstance(metadata['Series'], list):
            series_list = metadata['Series']
        else:
            series_list = [metadata['Series']]
    
    # Modality distribution
    modality_counts = {}
    instance_counts = []
    
    for series in series_list:
        series_dicom = series.get('DICOM', {})
        modality = series_dicom.get('Modality', 'UNKNOWN')
        
        if modality in modality_counts:
            modality_counts[modality] += 1
        else:
            modality_counts[modality] = 1
        
        instances = series.get('Instances', [])
        instance_count = len(instances) if isinstance(instances, list) else 0
        instance_counts.append(instance_count)
    
    stats['modalityDistribution'] = modality_counts
    
    # Instance count statistics
    if instance_counts:
        stats['dataCharacteristics'] = {
            'totalInstances': sum(instance_counts),
            'averageInstancesPerSeries': round(sum(instance_counts) / len(instance_counts), 2),
            'minInstancesPerSeries': min(instance_counts),
            'maxInstancesPerSeries': max(instance_counts),
            'seriesVariability': 'HIGH' if max(instance_counts) - min(instance_counts) > 50 else 'LOW'
        }
    
    # Extract temporal information
    study_info = metadata.get('Study', {}).get('DICOM', {})
    if study_info.get('StudyDate') and study_info.get('StudyTime'):
        stats['temporalAnalysis'] = {
            'studyDate': study_info['StudyDate'],
            'studyTime': study_info['StudyTime'],
            'hasTemporalData': True
        }
    else:
        stats['temporalAnalysis'] = {
            'hasTemporalData': False
        }
    
    return stats


def generate_recommendations(
    quality_analysis: Dict[str, Any], 
    statistical_analysis: Dict[str, Any], 
    basic_info: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """
    Generate recommendations based on analysis results.
    
    Args:
        quality_analysis: Quality analysis results
        statistical_analysis: Statistical analysis results
        basic_info: Basic image information
        
    Returns:
        List of recommendations
    """
    recommendations = []
    
    # Quality-based recommendations
    if quality_analysis['qualityScore'] < 0.6:
        recommendations.append({
            'type': 'QUALITY_IMPROVEMENT',
            'priority': 'HIGH',
            'description': 'Image set has quality issues that may affect clinical utility',
            'actions': quality_analysis['qualityIssues']
        })
    
    # Data volume recommendations
    total_instances = basic_info['totalInstances']
    if total_instances > 500:
        recommendations.append({
            'type': 'PROCESSING_OPTIMIZATION',
            'priority': 'MEDIUM',
            'description': 'Large image set detected - consider batch processing optimization',
            'actions': ['Use parallel processing', 'Implement chunked analysis']
        })
    
    # Multi-modality recommendations
    if basic_info['isMultiModality']:
        recommendations.append({
            'type': 'WORKFLOW_OPTIMIZATION',
            'priority': 'MEDIUM',
            'description': 'Multi-modality study detected - enable fusion workflows',
            'actions': ['Configure cross-modality analysis', 'Enable image registration']
        })
    
    # AI/ML readiness assessment
    if quality_analysis['qualityScore'] >= 0.8 and total_instances >= 10:
        recommendations.append({
            'type': 'AI_ML_READY',
            'priority': 'LOW',
            'description': 'Image set is suitable for AI/ML analysis',
            'actions': ['Enable AI inference', 'Run automated analysis models']
        })
    
    return recommendations


def calculate_overall_assessment(
    quality_analysis: Dict[str, Any], 
    statistical_analysis: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Calculate overall assessment of the image set.
    
    Args:
        quality_analysis: Quality analysis results
        statistical_analysis: Statistical analysis results
        
    Returns:
        Dictionary containing overall assessment
    """
    quality_score = quality_analysis['qualityScore']
    
    # Determine processing readiness
    if quality_score >= 0.8:
        processing_status = "READY_FOR_CLINICAL_USE"
        confidence_score = 0.95
    elif quality_score >= 0.6:
        processing_status = "READY_WITH_REVIEW"
        confidence_score = 0.80
    elif quality_score >= 0.4:
        processing_status = "REQUIRES_PREPROCESSING"
        confidence_score = 0.60
    else:
        processing_status = "NOT_RECOMMENDED"
        confidence_score = 0.30
    
    return {
        'processingStatus': processing_status,
        'confidenceScore': confidence_score,
        'overallQuality': quality_analysis['qualityLevel'],
        'clinicalReadiness': quality_score >= 0.7,
        'aiMlReadiness': quality_score >= 0.8,
        'recommendsManualReview': quality_score < 0.6,
        'summary': f"Image set shows {quality_analysis['qualityLevel'].lower()} quality with {processing_status.lower().replace('_', ' ')}"
    }


def create_analysis_summary(analysis_results: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create a concise summary of analysis results.
    
    Args:
        analysis_results: Full analysis results
        
    Returns:
        Dictionary containing analysis summary
    """
    return {
        'imageSetId': analysis_results['imageSetId'],
        'analysisTimestamp': analysis_results['analysisTimestamp'],
        'overallQuality': analysis_results['qualityAnalysis']['qualityLevel'],
        'qualityScore': analysis_results['qualityAnalysis']['qualityScore'],
        'processingStatus': analysis_results['overallAssessment']['processingStatus'],
        'clinicalReadiness': analysis_results['overallAssessment']['clinicalReadiness'],
        'totalInstances': analysis_results['imageInfo']['totalInstances'],
        'modalities': analysis_results['imageInfo']['modalities'],
        'recommendationCount': len(analysis_results['recommendations']),
        'keyRecommendations': [
            rec['description'] for rec in analysis_results['recommendations']
            if rec['priority'] in ['HIGH', 'MEDIUM']
        ][:3]  # Top 3 recommendations
    }


def store_analysis_results(results: Dict[str, Any], bucket: str, key: str) -> None:
    """
    Store analysis results in S3.
    
    Args:
        results: Analysis results to store
        bucket: S3 bucket name
        key: S3 object key
    """
    try:
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(results, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Successfully stored analysis results at s3://{bucket}/{key}")
        
    except ClientError as e:
        error_msg = f"Failed to store analysis results in S3: {str(e)}"
        logger.error(error_msg)
        raise