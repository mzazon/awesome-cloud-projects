import json
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
rds = boto3.client('rds')
elasticache = boto3.client('elasticache')
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    """
    Lambda function to monitor infrastructure health across multiple AWS services.
    This function checks RDS, ElastiCache, and EC2/ECS health and publishes health scores.
    """
    try:
        health_scores = {}
        
        # Check RDS health
        rds_health = check_rds_health()
        health_scores['RDS'] = rds_health
        
        # Check ElastiCache health
        cache_health = check_elasticache_health()
        health_scores['ElastiCache'] = cache_health
        
        # Check EC2/ECS health
        compute_health = check_compute_health()
        health_scores['Compute'] = compute_health
        
        # Calculate overall infrastructure health
        if health_scores:
            overall_health = sum(health_scores.values()) / len(health_scores)
        else:
            overall_health = 100  # Default if no resources to monitor
        
        # Publish infrastructure health metrics
        metrics = []
        for service, score in health_scores.items():
            metrics.append({
                'MetricName': f'{service}HealthScore',
                'Value': score,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Service', 'Value': service},
                    {'Name': 'Environment', 'Value': '${environment}'}
                ]
            })
        
        # Add overall health score
        metrics.append({
            'MetricName': 'OverallInfrastructureHealth',
            'Value': overall_health,
            'Unit': 'Percent',
            'Dimensions': [
                {'Name': 'Environment', 'Value': '${environment}'}
            ]
        })
        
        # Submit metrics to CloudWatch
        if metrics:
            cloudwatch.put_metric_data(
                Namespace='Infrastructure/Health',
                MetricData=metrics
            )
        
        print(f"Infrastructure health scores: {health_scores}")
        print(f"Overall infrastructure health: {overall_health:.2f}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'health_scores': health_scores,
                'overall_health': overall_health,
                'metrics_published': len(metrics)
            })
        }
        
    except Exception as e:
        print(f"Error monitoring infrastructure health: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def check_rds_health():
    """
    Check the health of RDS instances.
    
    Returns:
        float: RDS health score (0-100)
    """
    try:
        instances = rds.describe_db_instances()
        if not instances['DBInstances']:
            print("No RDS instances found")
            return 100  # No instances to monitor
        
        healthy_count = 0
        total_count = len(instances['DBInstances'])
        
        for instance in instances['DBInstances']:
            instance_id = instance['DBInstanceIdentifier']
            status = instance['DBInstanceStatus']
            
            print(f"RDS Instance {instance_id}: {status}")
            
            if status == 'available':
                healthy_count += 1
            elif status in ['creating', 'backing-up', 'modifying']:
                # Consider these as partially healthy
                healthy_count += 0.5
        
        health_score = (healthy_count / total_count) * 100
        print(f"RDS Health: {healthy_count}/{total_count} instances healthy ({health_score:.1f}%)")
        
        return health_score
        
    except Exception as e:
        print(f"Error checking RDS health: {str(e)}")
        return 50  # Assume degraded if can't check

def check_elasticache_health():
    """
    Check the health of ElastiCache clusters.
    
    Returns:
        float: ElastiCache health score (0-100)
    """
    try:
        clusters = elasticache.describe_cache_clusters()
        if not clusters['CacheClusters']:
            print("No ElastiCache clusters found")
            return 100  # No clusters to monitor
        
        healthy_count = 0
        total_count = len(clusters['CacheClusters'])
        
        for cluster in clusters['CacheClusters']:
            cluster_id = cluster['CacheClusterId']
            status = cluster['CacheClusterStatus']
            
            print(f"ElastiCache Cluster {cluster_id}: {status}")
            
            if status == 'available':
                healthy_count += 1
            elif status in ['creating', 'modifying', 'snapshotting']:
                # Consider these as partially healthy
                healthy_count += 0.5
        
        health_score = (healthy_count / total_count) * 100
        print(f"ElastiCache Health: {healthy_count}/{total_count} clusters healthy ({health_score:.1f}%)")
        
        return health_score
        
    except Exception as e:
        print(f"Error checking ElastiCache health: {str(e)}")
        return 50  # Assume degraded if can't check

def check_compute_health():
    """
    Check the health of compute resources (EC2 instances).
    This is a simplified check that can be extended for ECS services.
    
    Returns:
        float: Compute health score (0-100)
    """
    try:
        # Get running EC2 instances
        instances = ec2.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        total_instances = 0
        healthy_instances = 0
        
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                total_instances += 1
                
                # Check instance status
                instance_id = instance['InstanceId']
                state = instance['State']['Name']
                
                print(f"EC2 Instance {instance_id}: {state}")
                
                if state == 'running':
                    healthy_instances += 1
        
        print(f"Found {total_instances} running EC2 instances")
        
        # Simple health heuristic based on running instances
        if total_instances == 0:
            print("No EC2 instances found - assuming healthy")
            return 100  # No instances to monitor
        elif total_instances >= 3:
            health_score = 95   # Good redundancy
        elif total_instances >= 2:
            health_score = 80   # Acceptable redundancy
        else:
            health_score = 60   # Limited redundancy
        
        # Adjust based on actual health
        if healthy_instances < total_instances:
            health_score *= (healthy_instances / total_instances)
        
        print(f"Compute Health: {healthy_instances}/{total_instances} instances healthy ({health_score:.1f}%)")
        
        return health_score
        
    except Exception as e:
        print(f"Error checking compute health: {str(e)}")
        return 50  # Assume degraded if can't check