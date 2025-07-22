"""
Quality Monitoring Lambda Function

This function provides comprehensive quality monitoring and metrics collection
for the serverless data lake pipeline. It consumes validation events from
EventBridge, aggregates quality metrics, and publishes monitoring data.

Features:
- Real-time quality metrics aggregation
- CloudWatch custom metrics publishing
- Quality trend analysis and alerting
- Pipeline health monitoring
- Historical quality score tracking
- Integration with shared utilities layer
"""

import json
import os
import boto3
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
from data_utils import DataProcessor, MetricsCollector, EventPublisher
from decimal import Decimal


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for quality monitoring processing.
    
    Processes EventBridge events from the validation stage, aggregates
    quality metrics, and publishes monitoring data to CloudWatch.
    
    Args:
        event: EventBridge event payload
        context: Lambda context object
        
    Returns:
        Response dictionary with monitoring status
    """
    # Initialize processors and clients
    processor = DataProcessor()
    metrics_collector = MetricsCollector()
    event_publisher = EventPublisher(os.environ['CUSTOM_EVENT_BUS'])
    
    # Extract environment variables
    metadata_table = os.environ['METADATA_TABLE']
    project_name = os.environ['PROJECT_NAME']
    
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        process_id = detail.get('processId')
        validation_passed = detail.get('validationPassed', False)
        quality_score = float(detail.get('qualityScore', 0.0))
        validation_errors = detail.get('validationErrors', [])
        
        if not process_id:
            raise ValueError("Missing processId in event detail")
        
        print(f"Monitoring quality for process: {process_id}")
        print(f"Validation passed: {validation_passed}, Quality score: {quality_score}")
        
        # Calculate aggregate quality metrics
        aggregate_metrics = calculate_aggregate_metrics(
            processor, metadata_table, project_name
        )
        
        # Publish CloudWatch metrics
        publish_cloudwatch_metrics(
            metrics_collector, project_name, aggregate_metrics, quality_score
        )
        
        # Store quality monitoring metadata
        store_quality_metadata(
            processor, metadata_table, process_id, quality_score,
            validation_passed, validation_errors, aggregate_metrics
        )
        
        # Check for quality alerts
        quality_alerts = check_quality_alerts(aggregate_metrics, quality_score)
        
        if quality_alerts:
            publish_quality_alerts(
                event_publisher, process_id, quality_alerts, aggregate_metrics
            )
        
        print(f"✅ Quality monitoring completed for {process_id}")
        print(f"Aggregate success rate: {aggregate_metrics['success_rate']:.2f}%")
        print(f"Average quality score: {aggregate_metrics['avg_quality_score']:.2f}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processId': process_id,
                'qualityScore': quality_score,
                'aggregateMetrics': {
                    'successRate': aggregate_metrics['success_rate'],
                    'avgQualityScore': aggregate_metrics['avg_quality_score'],
                    'totalRecords': aggregate_metrics['total_records']
                },
                'alerts': quality_alerts
            })
        }
        
    except Exception as e:
        print(f"❌ Error in quality monitoring: {str(e)}")
        
        # Store error metadata if possible
        if 'detail' in event and 'processId' in event['detail']:
            try:
                processor.store_metadata(
                    table_name=metadata_table,
                    process_id=event['detail']['processId'],
                    metadata={
                        'Status': 'monitoring_failed',
                        'ProcessingStage': 'quality_monitoring',
                        'ErrorMessage': str(e),
                        'ErrorTimestamp': datetime.utcnow().isoformat()
                    }
                )
            except Exception as metadata_error:
                print(f"Failed to store error metadata: {str(metadata_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Quality monitoring failed'
            })
        }


def calculate_aggregate_metrics(
    processor: DataProcessor,
    metadata_table: str,
    project_name: str,
    time_window_hours: int = 24
) -> Dict[str, Any]:
    """
    Calculate aggregate quality metrics over a time window.
    
    Args:
        processor: DataProcessor instance
        metadata_table: DynamoDB metadata table name
        project_name: Project name for filtering
        time_window_hours: Time window for aggregation in hours
        
    Returns:
        Aggregate metrics dictionary
    """
    try:
        # Calculate time window
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=time_window_hours)
        
        # Query recent validation records
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(metadata_table)
        
        # Use GSI to query by processing stage and timestamp
        response = table.query(
            IndexName='ProcessingStageIndex',
            KeyConditionExpression='ProcessingStage = :stage AND #ts >= :start_time',
            ExpressionAttributeNames={'#ts': 'Timestamp'},
            ExpressionAttributeValues={
                ':stage': 'validation',
                ':start_time': start_time.isoformat()
            }
        )
        
        records = response.get('Items', [])
        
        # Calculate aggregate statistics
        total_records = len(records)
        passed_records = sum(1 for record in records 
                           if record.get('ValidationPassed', False))
        
        quality_scores = []
        for record in records:
            quality_score = record.get('QualityScore')
            if quality_score is not None:
                if isinstance(quality_score, Decimal):
                    quality_scores.append(float(quality_score))
                else:
                    quality_scores.append(float(quality_score))
        
        # Calculate metrics
        success_rate = (passed_records / total_records * 100) if total_records > 0 else 0.0
        avg_quality_score = sum(quality_scores) / len(quality_scores) if quality_scores else 0.0
        
        # Calculate additional metrics
        min_quality_score = min(quality_scores) if quality_scores else 0.0
        max_quality_score = max(quality_scores) if quality_scores else 0.0
        
        # Calculate quality distribution
        quality_distribution = calculate_quality_distribution(quality_scores)
        
        # Calculate trend metrics (compare with previous period)
        trend_metrics = calculate_trend_metrics(
            processor, metadata_table, start_time, time_window_hours
        )
        
        aggregate_metrics = {
            'success_rate': round(success_rate, 2),
            'avg_quality_score': round(avg_quality_score, 2),
            'min_quality_score': round(min_quality_score, 2),
            'max_quality_score': round(max_quality_score, 2),
            'total_records': total_records,
            'passed_records': passed_records,
            'failed_records': total_records - passed_records,
            'quality_distribution': quality_distribution,
            'trend_metrics': trend_metrics,
            'time_window_hours': time_window_hours,
            'calculation_timestamp': end_time.isoformat()
        }
        
        return aggregate_metrics
        
    except Exception as e:
        print(f"Error calculating aggregate metrics: {str(e)}")
        return {
            'success_rate': 0.0,
            'avg_quality_score': 0.0,
            'min_quality_score': 0.0,
            'max_quality_score': 0.0,
            'total_records': 0,
            'passed_records': 0,
            'failed_records': 0,
            'quality_distribution': {},
            'trend_metrics': {},
            'time_window_hours': time_window_hours,
            'calculation_timestamp': datetime.utcnow().isoformat()
        }


def calculate_quality_distribution(quality_scores: List[float]) -> Dict[str, int]:
    """
    Calculate quality score distribution across ranges.
    
    Args:
        quality_scores: List of quality scores
        
    Returns:
        Distribution dictionary with score ranges
    """
    distribution = {
        'excellent_90_100': 0,    # 90-100
        'good_80_89': 0,          # 80-89
        'fair_70_79': 0,          # 70-79
        'poor_60_69': 0,          # 60-69
        'very_poor_0_59': 0       # 0-59
    }
    
    for score in quality_scores:
        if score >= 90:
            distribution['excellent_90_100'] += 1
        elif score >= 80:
            distribution['good_80_89'] += 1
        elif score >= 70:
            distribution['fair_70_79'] += 1
        elif score >= 60:
            distribution['poor_60_69'] += 1
        else:
            distribution['very_poor_0_59'] += 1
    
    return distribution


def calculate_trend_metrics(
    processor: DataProcessor,
    metadata_table: str,
    current_start_time: datetime,
    time_window_hours: int
) -> Dict[str, Any]:
    """
    Calculate trend metrics by comparing current period with previous period.
    
    Args:
        processor: DataProcessor instance
        metadata_table: DynamoDB metadata table name
        current_start_time: Start time of current period
        time_window_hours: Time window in hours
        
    Returns:
        Trend metrics dictionary
    """
    try:
        # Calculate previous period time window
        previous_end_time = current_start_time
        previous_start_time = previous_end_time - timedelta(hours=time_window_hours)
        
        # Query previous period records
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(metadata_table)
        
        response = table.query(
            IndexName='ProcessingStageIndex',
            KeyConditionExpression='ProcessingStage = :stage AND #ts BETWEEN :start_time AND :end_time',
            ExpressionAttributeNames={'#ts': 'Timestamp'},
            ExpressionAttributeValues={
                ':stage': 'validation',
                ':start_time': previous_start_time.isoformat(),
                ':end_time': previous_end_time.isoformat()
            }
        )
        
        previous_records = response.get('Items', [])
        
        # Calculate previous period metrics
        previous_total = len(previous_records)
        previous_passed = sum(1 for record in previous_records 
                            if record.get('ValidationPassed', False))
        
        previous_quality_scores = []
        for record in previous_records:
            quality_score = record.get('QualityScore')
            if quality_score is not None:
                if isinstance(quality_score, Decimal):
                    previous_quality_scores.append(float(quality_score))
                else:
                    previous_quality_scores.append(float(quality_score))
        
        previous_success_rate = (previous_passed / previous_total * 100) if previous_total > 0 else 0.0
        previous_avg_quality = sum(previous_quality_scores) / len(previous_quality_scores) if previous_quality_scores else 0.0
        
        return {
            'previous_success_rate': round(previous_success_rate, 2),
            'previous_avg_quality_score': round(previous_avg_quality, 2),
            'previous_total_records': previous_total,
            'has_previous_data': previous_total > 0
        }
        
    except Exception as e:
        print(f"Error calculating trend metrics: {str(e)}")
        return {
            'previous_success_rate': 0.0,
            'previous_avg_quality_score': 0.0,
            'previous_total_records': 0,
            'has_previous_data': False
        }


def publish_cloudwatch_metrics(
    metrics_collector: MetricsCollector,
    project_name: str,
    aggregate_metrics: Dict[str, Any],
    current_quality_score: float
) -> None:
    """
    Publish comprehensive metrics to CloudWatch.
    
    Args:
        metrics_collector: MetricsCollector instance
        project_name: Project name for metrics dimension
        aggregate_metrics: Aggregate metrics dictionary
        current_quality_score: Current record quality score
    """
    try:
        # Publish main aggregate metrics
        metrics_collector.publish_validation_metrics(
            pipeline_name=project_name,
            success_rate=aggregate_metrics['success_rate'],
            avg_quality_score=aggregate_metrics['avg_quality_score'],
            total_records=aggregate_metrics['total_records']
        )
        
        # Publish additional detailed metrics
        cloudwatch = boto3.client('cloudwatch')
        
        detailed_metrics = [
            {
                'MetricName': 'MinQualityScore',
                'Value': aggregate_metrics['min_quality_score'],
                'Unit': 'None',
                'Dimensions': [{'Name': 'Pipeline', 'Value': project_name}]
            },
            {
                'MetricName': 'MaxQualityScore',
                'Value': aggregate_metrics['max_quality_score'],
                'Unit': 'None',
                'Dimensions': [{'Name': 'Pipeline', 'Value': project_name}]
            },
            {
                'MetricName': 'FailedRecords',
                'Value': aggregate_metrics['failed_records'],
                'Unit': 'Count',
                'Dimensions': [{'Name': 'Pipeline', 'Value': project_name}]
            },
            {
                'MetricName': 'CurrentQualityScore',
                'Value': current_quality_score,
                'Unit': 'None',
                'Dimensions': [{'Name': 'Pipeline', 'Value': project_name}]
            }
        ]
        
        # Publish quality distribution metrics
        for range_name, count in aggregate_metrics['quality_distribution'].items():
            detailed_metrics.append({
                'MetricName': f'QualityDistribution_{range_name}',
                'Value': count,
                'Unit': 'Count',
                'Dimensions': [{'Name': 'Pipeline', 'Value': project_name}]
            })
        
        cloudwatch.put_metric_data(
            Namespace='DataLake/QualityDetailed',
            MetricData=detailed_metrics
        )
        
        print(f"✅ Published {len(detailed_metrics)} detailed metrics to CloudWatch")
        
    except Exception as e:
        print(f"Error publishing CloudWatch metrics: {str(e)}")


def store_quality_metadata(
    processor: DataProcessor,
    metadata_table: str,
    process_id: str,
    quality_score: float,
    validation_passed: bool,
    validation_errors: List[str],
    aggregate_metrics: Dict[str, Any]
) -> None:
    """
    Store quality monitoring metadata in DynamoDB.
    
    Args:
        processor: DataProcessor instance
        metadata_table: DynamoDB metadata table name
        process_id: Process ID
        quality_score: Current record quality score
        validation_passed: Whether validation passed
        validation_errors: List of validation errors
        aggregate_metrics: Aggregate metrics dictionary
    """
    try:
        quality_metadata = {
            'ProcessingStage': 'quality_monitoring',
            'CurrentQualityScore': quality_score,
            'CurrentValidationPassed': validation_passed,
            'CurrentValidationErrors': validation_errors,
            'AggregateSuccessRate': aggregate_metrics['success_rate'],
            'AggregateAvgQualityScore': aggregate_metrics['avg_quality_score'],
            'AggregateTotalRecords': aggregate_metrics['total_records'],
            'QualityDistribution': aggregate_metrics['quality_distribution'],
            'TrendMetrics': aggregate_metrics['trend_metrics'],
            'MonitoringTimestamp': datetime.utcnow().isoformat()
        }
        
        # Create a unique process ID for quality monitoring record
        monitoring_process_id = f"quality-{process_id}-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
        
        processor.store_metadata(
            table_name=metadata_table,
            process_id=monitoring_process_id,
            metadata=quality_metadata
        )
        
        print(f"✅ Stored quality metadata for process {process_id}")
        
    except Exception as e:
        print(f"Error storing quality metadata: {str(e)}")


def check_quality_alerts(
    aggregate_metrics: Dict[str, Any],
    current_quality_score: float
) -> List[Dict[str, Any]]:
    """
    Check for quality-related alerts based on thresholds.
    
    Args:
        aggregate_metrics: Aggregate metrics dictionary
        current_quality_score: Current record quality score
        
    Returns:
        List of alert dictionaries
    """
    alerts = []
    
    # Alert thresholds (configurable in production)
    SUCCESS_RATE_THRESHOLD = 80.0
    AVG_QUALITY_THRESHOLD = 75.0
    CURRENT_QUALITY_THRESHOLD = 60.0
    MIN_RECORDS_FOR_ALERTING = 5
    
    # Only generate alerts if we have sufficient data
    if aggregate_metrics['total_records'] < MIN_RECORDS_FOR_ALERTING:
        return alerts
    
    # Success rate alert
    if aggregate_metrics['success_rate'] < SUCCESS_RATE_THRESHOLD:
        alerts.append({
            'type': 'LOW_SUCCESS_RATE',
            'severity': 'HIGH',
            'message': f"Success rate {aggregate_metrics['success_rate']:.2f}% "
                      f"below threshold {SUCCESS_RATE_THRESHOLD}%",
            'current_value': aggregate_metrics['success_rate'],
            'threshold': SUCCESS_RATE_THRESHOLD,
            'timestamp': datetime.utcnow().isoformat()
        })
    
    # Average quality score alert
    if aggregate_metrics['avg_quality_score'] < AVG_QUALITY_THRESHOLD:
        alerts.append({
            'type': 'LOW_AVG_QUALITY',
            'severity': 'MEDIUM',
            'message': f"Average quality score {aggregate_metrics['avg_quality_score']:.2f} "
                      f"below threshold {AVG_QUALITY_THRESHOLD}",
            'current_value': aggregate_metrics['avg_quality_score'],
            'threshold': AVG_QUALITY_THRESHOLD,
            'timestamp': datetime.utcnow().isoformat()
        })
    
    # Current record quality alert
    if current_quality_score < CURRENT_QUALITY_THRESHOLD:
        alerts.append({
            'type': 'LOW_CURRENT_QUALITY',
            'severity': 'LOW',
            'message': f"Current record quality score {current_quality_score:.2f} "
                      f"below threshold {CURRENT_QUALITY_THRESHOLD}",
            'current_value': current_quality_score,
            'threshold': CURRENT_QUALITY_THRESHOLD,
            'timestamp': datetime.utcnow().isoformat()
        })
    
    # Trend-based alerts
    trend_metrics = aggregate_metrics.get('trend_metrics', {})
    if trend_metrics.get('has_previous_data', False):
        # Success rate decline alert
        current_success_rate = aggregate_metrics['success_rate']
        previous_success_rate = trend_metrics['previous_success_rate']
        
        if previous_success_rate > 0 and current_success_rate < previous_success_rate * 0.8:
            alerts.append({
                'type': 'SUCCESS_RATE_DECLINE',
                'severity': 'MEDIUM',
                'message': f"Success rate declined from {previous_success_rate:.2f}% "
                          f"to {current_success_rate:.2f}%",
                'current_value': current_success_rate,
                'previous_value': previous_success_rate,
                'timestamp': datetime.utcnow().isoformat()
            })
    
    return alerts


def publish_quality_alerts(
    event_publisher: EventPublisher,
    process_id: str,
    alerts: List[Dict[str, Any]],
    aggregate_metrics: Dict[str, Any]
) -> None:
    """
    Publish quality alerts as events for downstream processing.
    
    Args:
        event_publisher: EventPublisher instance
        process_id: Process ID that triggered the alert
        alerts: List of alert dictionaries
        aggregate_metrics: Aggregate metrics dictionary
    """
    try:
        for alert in alerts:
            alert_detail = {
                'processId': process_id,
                'alertType': alert['type'],
                'severity': alert['severity'],
                'message': alert['message'],
                'currentValue': alert.get('current_value'),
                'threshold': alert.get('threshold'),
                'aggregateMetrics': {
                    'successRate': aggregate_metrics['success_rate'],
                    'avgQualityScore': aggregate_metrics['avg_quality_score'],
                    'totalRecords': aggregate_metrics['total_records']
                },
                'timestamp': alert['timestamp']
            }
            
            event_publisher.publish_quality_event(
                process_id=f"alert-{process_id}",
                metrics=alert_detail
            )
        
        print(f"✅ Published {len(alerts)} quality alerts")
        
    except Exception as e:
        print(f"Error publishing quality alerts: {str(e)}")