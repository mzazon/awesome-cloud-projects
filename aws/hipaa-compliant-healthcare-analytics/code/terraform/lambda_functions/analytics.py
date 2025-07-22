"""
AWS HealthLake Analytics Lambda Function

This Lambda function generates healthcare analytics reports from FHIR data
stored in AWS HealthLake. It performs patient cohort analysis, demographic
reporting, and clinical insights generation for population health management.

Environment Variables:
- OUTPUT_BUCKET: S3 bucket for storing analytics reports
- DATASTORE_ENDPOINT: HealthLake FHIR endpoint URL
- DATASTORE_ID: HealthLake data store ID
"""

import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
healthlake = boto3.client('healthlake')
cloudwatch = boto3.client('cloudwatch')

# Environment variables
OUTPUT_BUCKET = os.environ.get('OUTPUT_BUCKET', '')
DATASTORE_ENDPOINT = os.environ.get('DATASTORE_ENDPOINT', '')
DATASTORE_ID = os.environ.get('DATASTORE_ID', '')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for generating healthcare analytics.
    
    Args:
        event: Lambda event data (can be EventBridge event or direct invocation)
        context: Lambda context object
        
    Returns:
        Response dictionary with status code and message
    """
    try:
        logger.info(f"Starting healthcare analytics processing: {json.dumps(event, indent=2)}")
        
        # Generate comprehensive analytics report
        analytics_report = generate_comprehensive_analytics()
        
        # Save report to S3
        report_key = save_analytics_report(analytics_report)
        
        # Publish metrics for monitoring
        publish_analytics_metrics(analytics_report)
        
        # Generate alerts if necessary
        alerts = check_for_alerts(analytics_report)
        
        result = {
            "report_generated": True,
            "report_s3_key": report_key,
            "report_timestamp": analytics_report["metadata"]["generated_at"],
            "patient_count": analytics_report["summary"]["total_patients"],
            "alerts_generated": len(alerts),
            "alerts": alerts
        }
        
        logger.info(f"Analytics processing completed successfully: {result}")
        return create_response(200, "Analytics processing completed", result)
        
    except Exception as e:
        logger.error(f"Error in analytics processing: {str(e)}", exc_info=True)
        return create_response(500, f"Error processing analytics: {str(e)}")


def generate_comprehensive_analytics() -> Dict[str, Any]:
    """
    Generate a comprehensive healthcare analytics report.
    
    Returns:
        Dictionary containing analytics report data
    """
    try:
        logger.info("Generating comprehensive healthcare analytics report")
        
        # Initialize report structure
        report = {
            "metadata": {
                "report_id": str(uuid.uuid4()),
                "report_type": "healthcare_analytics",
                "generated_at": datetime.utcnow().isoformat(),
                "datastore_id": DATASTORE_ID,
                "datastore_endpoint": DATASTORE_ENDPOINT,
                "version": "1.0"
            },
            "summary": {},
            "demographics": {},
            "clinical_insights": {},
            "quality_metrics": {},
            "population_health": {},
            "recommendations": []
        }
        
        # Generate patient summary statistics
        report["summary"] = generate_patient_summary()
        
        # Generate demographic analysis
        report["demographics"] = generate_demographic_analysis()
        
        # Generate clinical insights
        report["clinical_insights"] = generate_clinical_insights()
        
        # Generate quality metrics
        report["quality_metrics"] = generate_quality_metrics()
        
        # Generate population health metrics
        report["population_health"] = generate_population_health_metrics()
        
        # Generate recommendations
        report["recommendations"] = generate_recommendations(report)
        
        logger.info("Comprehensive analytics report generated successfully")
        return report
        
    except Exception as e:
        logger.error(f"Error generating comprehensive analytics: {str(e)}")
        # Return a basic report with error information
        return {
            "metadata": {
                "report_id": str(uuid.uuid4()),
                "report_type": "healthcare_analytics_error",
                "generated_at": datetime.utcnow().isoformat(),
                "error": str(e)
            },
            "summary": generate_fallback_summary(),
            "demographics": {},
            "clinical_insights": {},
            "quality_metrics": {},
            "population_health": {},
            "recommendations": []
        }


def generate_patient_summary() -> Dict[str, Any]:
    """
    Generate summary statistics about patients in the data store.
    
    Returns:
        Dictionary containing patient summary data
    """
    try:
        # In a real implementation, you would query the HealthLake FHIR API
        # For this example, we'll generate realistic sample data
        
        logger.info("Generating patient summary statistics")
        
        # Simulate querying patient data
        # GET /Patient?_summary=count would give us total count
        # GET /Patient?active=true&_summary=count would give us active patients
        
        summary = {
            "total_patients": 1247,  # Sample data
            "active_patients": 1134,
            "inactive_patients": 113,
            "patients_added_last_30_days": 47,
            "patients_updated_last_7_days": 23,
            "average_age": 42.3,
            "age_distribution": {
                "0-17": 234,
                "18-64": 789,
                "65+": 224
            },
            "data_quality_score": 94.2,
            "last_updated": datetime.utcnow().isoformat()
        }
        
        logger.info(f"Patient summary generated: {summary['total_patients']} total patients")
        return summary
        
    except Exception as e:
        logger.error(f"Error generating patient summary: {str(e)}")
        return generate_fallback_summary()


def generate_demographic_analysis() -> Dict[str, Any]:
    """
    Generate demographic analysis of the patient population.
    
    Returns:
        Dictionary containing demographic data
    """
    try:
        logger.info("Generating demographic analysis")
        
        # In a real implementation, you would use FHIR search parameters:
        # GET /Patient?gender=male&_summary=count
        # GET /Patient?gender=female&_summary=count
        
        demographics = {
            "gender_distribution": {
                "male": 598,
                "female": 634,
                "other": 12,
                "unknown": 3
            },
            "age_statistics": {
                "mean_age": 42.3,
                "median_age": 39.5,
                "min_age": 0,
                "max_age": 97,
                "std_deviation": 22.8
            },
            "geographic_distribution": {
                "california": 456,
                "texas": 289,
                "florida": 178,
                "new_york": 156,
                "other_states": 168
            },
            "insurance_status": {
                "private": 734,
                "medicare": 198,
                "medicaid": 234,
                "uninsured": 67,
                "unknown": 14
            },
            "language_preferences": {
                "english": 1087,
                "spanish": 89,
                "chinese": 23,
                "other": 48
            }
        }
        
        logger.info("Demographic analysis completed")
        return demographics
        
    except Exception as e:
        logger.error(f"Error generating demographic analysis: {str(e)}")
        return {}


def generate_clinical_insights() -> Dict[str, Any]:
    """
    Generate clinical insights from patient data.
    
    Returns:
        Dictionary containing clinical insights
    """
    try:
        logger.info("Generating clinical insights")
        
        # In a real implementation, you would query various FHIR resources:
        # GET /Condition?_summary=count
        # GET /Medication?_summary=count
        # GET /Observation?category=vital-signs
        
        insights = {
            "common_conditions": [
                {"condition": "Hypertension", "patient_count": 278, "percentage": 22.3},
                {"condition": "Diabetes Type 2", "patient_count": 156, "percentage": 12.5},
                {"condition": "Hyperlipidemia", "patient_count": 134, "percentage": 10.7},
                {"condition": "Asthma", "patient_count": 89, "percentage": 7.1},
                {"condition": "Depression", "patient_count": 67, "percentage": 5.4}
            ],
            "medication_utilization": {
                "total_prescriptions": 3456,
                "unique_medications": 445,
                "most_prescribed": [
                    {"medication": "Metformin", "prescription_count": 178},
                    {"medication": "Lisinopril", "prescription_count": 156},
                    {"medication": "Atorvastatin", "prescription_count": 134},
                    {"medication": "Albuterol", "prescription_count": 89},
                    {"medication": "Sertraline", "prescription_count": 67}
                ]
            },
            "vital_signs_analysis": {
                "blood_pressure": {
                    "normal": 645,
                    "elevated": 234,
                    "high_stage_1": 189,
                    "high_stage_2": 67,
                    "crisis": 12
                },
                "bmi_distribution": {
                    "underweight": 45,
                    "normal": 523,
                    "overweight": 389,
                    "obese": 234,
                    "severely_obese": 56
                }
            },
            "care_gaps": {
                "overdue_screenings": 234,
                "missing_vaccinations": 156,
                "medication_adherence_issues": 89
            }
        }
        
        logger.info("Clinical insights generated")
        return insights
        
    except Exception as e:
        logger.error(f"Error generating clinical insights: {str(e)}")
        return {}


def generate_quality_metrics() -> Dict[str, Any]:
    """
    Generate healthcare quality metrics and performance indicators.
    
    Returns:
        Dictionary containing quality metrics
    """
    try:
        logger.info("Generating quality metrics")
        
        metrics = {
            "data_completeness": {
                "patient_demographics": 98.5,
                "contact_information": 89.2,
                "insurance_data": 76.4,
                "clinical_data": 92.1,
                "medication_history": 87.3
            },
            "care_quality_indicators": {
                "diabetes_hba1c_control": 78.5,  # Percentage with HbA1c < 7%
                "hypertension_control": 82.3,    # Percentage with BP < 140/90
                "cholesterol_management": 74.2,  # Percentage with LDL < 100
                "preventive_care_uptake": 68.9,  # Percentage up-to-date with screenings
                "medication_adherence": 79.4     # Percentage with good adherence
            },
            "readmission_rates": {
                "30_day_readmission": 8.7,
                "90_day_readmission": 15.2,
                "same_condition_readmission": 5.4
            },
            "patient_safety_indicators": {
                "medication_errors": 0.2,
                "adverse_drug_events": 1.4,
                "healthcare_associated_infections": 0.8
            }
        }
        
        logger.info("Quality metrics generated")
        return metrics
        
    except Exception as e:
        logger.error(f"Error generating quality metrics: {str(e)}")
        return {}


def generate_population_health_metrics() -> Dict[str, Any]:
    """
    Generate population health metrics and trends.
    
    Returns:
        Dictionary containing population health data
    """
    try:
        logger.info("Generating population health metrics")
        
        metrics = {
            "disease_prevalence": {
                "cardiovascular_disease": 23.4,
                "diabetes": 12.5,
                "mental_health_conditions": 18.7,
                "respiratory_conditions": 14.2,
                "cancer": 6.8
            },
            "risk_stratification": {
                "low_risk": 534,
                "moderate_risk": 456,
                "high_risk": 189,
                "very_high_risk": 68
            },
            "social_determinants": {
                "transportation_barriers": 23.4,
                "housing_instability": 12.7,
                "food_insecurity": 18.9,
                "language_barriers": 8.3,
                "technology_access_issues": 15.6
            },
            "utilization_patterns": {
                "primary_care_visits_per_year": 3.2,
                "emergency_department_visits": 0.8,
                "specialist_consultations": 1.4,
                "hospitalizations": 0.3,
                "telehealth_adoption": 34.7
            }
        }
        
        logger.info("Population health metrics generated")
        return metrics
        
    except Exception as e:
        logger.error(f"Error generating population health metrics: {str(e)}")
        return {}


def generate_recommendations(report: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Generate actionable recommendations based on analytics findings.
    
    Args:
        report: The complete analytics report
        
    Returns:
        List of recommendation dictionaries
    """
    try:
        logger.info("Generating recommendations")
        
        recommendations = []
        
        # Check data quality and suggest improvements
        data_quality = report.get("quality_metrics", {}).get("data_completeness", {})
        for field, completeness in data_quality.items():
            if completeness < 85:
                recommendations.append({
                    "type": "data_quality",
                    "priority": "high" if completeness < 75 else "medium",
                    "title": f"Improve {field.replace('_', ' ').title()} Data Completeness",
                    "description": f"Data completeness for {field} is {completeness}%. Consider implementing data collection improvements.",
                    "target_metric": field,
                    "current_value": completeness,
                    "target_value": 90.0
                })
        
        # Check care quality indicators
        quality_indicators = report.get("quality_metrics", {}).get("care_quality_indicators", {})
        for indicator, value in quality_indicators.items():
            if value < 75:
                recommendations.append({
                    "type": "clinical_quality",
                    "priority": "high",
                    "title": f"Improve {indicator.replace('_', ' ').title()}",
                    "description": f"Current {indicator} rate is {value}%. Implement targeted interventions to improve outcomes.",
                    "target_metric": indicator,
                    "current_value": value,
                    "target_value": 80.0
                })
        
        # Population health recommendations
        risk_stratification = report.get("population_health", {}).get("risk_stratification", {})
        high_risk_patients = risk_stratification.get("high_risk", 0) + risk_stratification.get("very_high_risk", 0)
        if high_risk_patients > 0:
            recommendations.append({
                "type": "population_health",
                "priority": "high",
                "title": "Implement Care Management Program",
                "description": f"{high_risk_patients} patients identified as high or very high risk. Consider implementing intensive care management.",
                "target_metric": "high_risk_patients",
                "current_value": high_risk_patients,
                "target_value": high_risk_patients * 0.8
            })
        
        # Social determinants recommendations
        social_barriers = report.get("population_health", {}).get("social_determinants", {})
        for barrier, percentage in social_barriers.items():
            if percentage > 15:
                recommendations.append({
                    "type": "social_determinants",
                    "priority": "medium",
                    "title": f"Address {barrier.replace('_', ' ').title()}",
                    "description": f"{percentage}% of patients experience {barrier}. Consider community partnerships to address this barrier.",
                    "target_metric": barrier,
                    "current_value": percentage,
                    "target_value": 10.0
                })
        
        logger.info(f"Generated {len(recommendations)} recommendations")
        return recommendations
        
    except Exception as e:
        logger.error(f"Error generating recommendations: {str(e)}")
        return []


def save_analytics_report(report: Dict[str, Any]) -> str:
    """
    Save the analytics report to S3.
    
    Args:
        report: The analytics report dictionary
        
    Returns:
        S3 key of the saved report
    """
    try:
        timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
        report_key = f"analytics/healthcare-analytics-{timestamp}.json"
        
        logger.info(f"Saving analytics report to S3: {report_key}")
        
        s3.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=report_key,
            Body=json.dumps(report, indent=2, default=str),
            ContentType='application/json',
            Metadata={
                'report-type': 'healthcare-analytics',
                'generated-at': report['metadata']['generated_at'],
                'patient-count': str(report['summary'].get('total_patients', 0))
            }
        )
        
        logger.info(f"Analytics report saved successfully to s3://{OUTPUT_BUCKET}/{report_key}")
        return report_key
        
    except Exception as e:
        logger.error(f"Error saving analytics report: {str(e)}")
        raise


def check_for_alerts(report: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Check analytics report for conditions that require alerts.
    
    Args:
        report: The analytics report dictionary
        
    Returns:
        List of alert dictionaries
    """
    try:
        alerts = []
        
        # Check for critical data quality issues
        data_quality = report.get("quality_metrics", {}).get("data_completeness", {})
        for field, completeness in data_quality.items():
            if completeness < 70:
                alerts.append({
                    "type": "data_quality_critical",
                    "severity": "high",
                    "message": f"Critical data quality issue: {field} completeness is {completeness}%",
                    "metric": field,
                    "value": completeness,
                    "threshold": 70
                })
        
        # Check for high readmission rates
        readmission_rate = report.get("quality_metrics", {}).get("readmission_rates", {}).get("30_day_readmission", 0)
        if readmission_rate > 12:
            alerts.append({
                "type": "clinical_quality",
                "severity": "medium",
                "message": f"30-day readmission rate is {readmission_rate}%, above target of 12%",
                "metric": "30_day_readmission",
                "value": readmission_rate,
                "threshold": 12
            })
        
        # Check for high-risk patient population
        risk_data = report.get("population_health", {}).get("risk_stratification", {})
        very_high_risk = risk_data.get("very_high_risk", 0)
        total_patients = report.get("summary", {}).get("total_patients", 1)
        very_high_risk_percentage = (very_high_risk / total_patients) * 100
        
        if very_high_risk_percentage > 8:
            alerts.append({
                "type": "population_health",
                "severity": "medium",
                "message": f"{very_high_risk_percentage:.1f}% of patients are very high risk, consider care management interventions",
                "metric": "very_high_risk_percentage",
                "value": very_high_risk_percentage,
                "threshold": 8
            })
        
        logger.info(f"Generated {len(alerts)} alerts")
        return alerts
        
    except Exception as e:
        logger.error(f"Error checking for alerts: {str(e)}")
        return []


def publish_analytics_metrics(report: Dict[str, Any]) -> None:
    """
    Publish analytics metrics to CloudWatch for monitoring.
    
    Args:
        report: The analytics report dictionary
    """
    try:
        namespace = "HealthLake/Analytics"
        timestamp = datetime.utcnow()
        
        # Publish patient metrics
        summary = report.get("summary", {})
        if summary:
            metrics = [
                {
                    'MetricName': 'TotalPatients',
                    'Value': summary.get('total_patients', 0),
                    'Unit': 'Count',
                    'Timestamp': timestamp
                },
                {
                    'MetricName': 'ActivePatients',
                    'Value': summary.get('active_patients', 0),
                    'Unit': 'Count',
                    'Timestamp': timestamp
                },
                {
                    'MetricName': 'DataQualityScore',
                    'Value': summary.get('data_quality_score', 0),
                    'Unit': 'Percent',
                    'Timestamp': timestamp
                }
            ]
            
            cloudwatch.put_metric_data(
                Namespace=namespace,
                MetricData=metrics
            )
        
        logger.info("Analytics metrics published to CloudWatch")
        
    except Exception as e:
        logger.error(f"Error publishing analytics metrics: {str(e)}")


def generate_fallback_summary() -> Dict[str, Any]:
    """
    Generate a fallback summary when normal processing fails.
    
    Returns:
        Basic summary dictionary
    """
    return {
        "total_patients": 0,
        "active_patients": 0,
        "inactive_patients": 0,
        "patients_added_last_30_days": 0,
        "patients_updated_last_7_days": 0,
        "average_age": 0,
        "age_distribution": {"0-17": 0, "18-64": 0, "65+": 0},
        "data_quality_score": 0,
        "last_updated": datetime.utcnow().isoformat(),
        "note": "Fallback data due to processing error"
    }


def create_response(status_code: int, message: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Create a standardized Lambda response.
    
    Args:
        status_code: HTTP status code
        message: Response message
        data: Optional additional data
        
    Returns:
        Response dictionary
    """
    response = {
        'statusCode': status_code,
        'body': json.dumps({
            'message': message,
            'timestamp': datetime.utcnow().isoformat(),
            'data': data or {}
        })
    }
    
    return response