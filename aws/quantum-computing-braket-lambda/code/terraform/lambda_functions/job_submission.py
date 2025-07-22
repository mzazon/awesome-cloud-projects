# Job Submission Lambda Function for Quantum Computing Pipeline
# This function submits quantum optimization jobs to Amazon Braket

import json
import boto3
import os
from datetime import datetime

braket = boto3.client('braket')
s3 = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Submit quantum optimization job to Amazon Braket."""
    try:
        # Extract job parameters
        input_bucket = event.get('input_bucket')
        output_bucket = event.get('output_bucket') 
        code_bucket = event.get('code_bucket')
        data_key = event.get('data_key')
        job_name = f"quantum-opt-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"
        
        print(f"Submitting quantum job: {job_name}")
        
        # Load problem data to determine optimal device and parameters
        problem_data = load_problem_data(input_bucket, data_key)
        device_config = select_optimal_device(problem_data)
        
        # Configure Braket Hybrid Job
        job_config = {
            'jobName': job_name,
            'algorithmSpecification': {
                'scriptModeConfig': {
                    'entryPoint': 'quantum_optimization.py',
                    's3Uri': f's3://{code_bucket}/quantum-code/'
                }
            },
            'instanceConfig': {
                'instanceType': device_config['instance_type'],
                'instanceCount': 1,
                'volumeSizeInGb': 30
            },
            'outputDataConfig': {
                's3Path': f's3://{output_bucket}/jobs/{job_name}/'
            },
            'roleArn': os.environ.get('EXECUTION_ROLE_ARN', '${execution_role_arn}'),
            'inputDataConfig': [
                {
                    'channelName': 'input',
                    's3Uri': f's3://{input_bucket}/{data_key}'
                }
            ],
            'hyperParameters': {
                'learning_rate': os.environ.get('LEARNING_RATE', '0.1'),
                'iterations': os.environ.get('OPTIMIZATION_ITERATIONS', '100'),
                'target_cost': '0.3',
                'num_params': str(problem_data.get('problem_size', 4) * 2)
            },
            'environment': {
                'INPUT_BUCKET': input_bucket,
                'OUTPUT_BUCKET': output_bucket,
                'PROBLEM_TYPE': problem_data.get('problem_type', 'optimization'),
                'PROJECT_NAME': os.environ.get('PROJECT_NAME', '${project_name}')
            }
        }
        
        # Add device-specific configuration
        if device_config['use_qpu'] and os.environ.get('ENABLE_BRAKET_QPU', 'false').lower() == 'true':
            job_config['deviceConfig'] = {
                'device': device_config['device_arn']
            }
        
        # Submit job to Braket
        response = braket.create_job(**job_config)
        job_arn = response['jobArn']
        
        print(f"Quantum job submitted successfully: {job_arn}")
        
        # Store job metadata
        job_metadata = {
            'job_name': job_name,
            'job_arn': job_arn,
            'created_at': datetime.utcnow().isoformat(),
            'problem_data': problem_data,
            'device_config': device_config,
            'hyperparameters': job_config['hyperParameters']
        }
        
        s3.put_object(
            Bucket=output_bucket,
            Key=f'jobs/{job_name}/metadata.json',
            Body=json.dumps(job_metadata, indent=2)
        )
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='QuantumPipeline',
            MetricData=[
                {
                    'MetricName': 'JobsSubmitted',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'DeviceType', 'Value': device_config['device_type']},
                        {'Name': 'ProblemType', 'Value': problem_data.get('problem_type', 'unknown')}
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Quantum job submitted successfully',
                'job_name': job_name,
                'job_arn': job_arn,
                'device_type': device_config['device_type']
            })
        }
        
    except Exception as e:
        print(f"Error submitting quantum job: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def load_problem_data(bucket, key):
    """Load and parse problem data from S3."""
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        return json.loads(response['Body'].read().decode('utf-8'))
    except Exception as e:
        print(f"Error loading problem data: {str(e)}")
        return {}

def select_optimal_device(problem_data):
    """Select optimal quantum device based on problem characteristics."""
    problem_size = problem_data.get('problem_size', 4)
    problem_type = problem_data.get('problem_type', 'optimization')
    
    # Device selection logic
    if problem_size <= 8:
        # Use local simulator for small problems
        return {
            'device_type': 'simulator',
            'device_arn': 'local:braket/braket.devices.braket_sv_v2/BraketSvV2',
            'instance_type': 'ml.m5.large',
            'use_qpu': False
        }
    elif problem_size <= 16:
        # Use SV1 simulator for medium problems
        return {
            'device_type': 'simulator',
            'device_arn': 'arn:aws:braket:::device/quantum-simulator/amazon/sv1',
            'instance_type': 'ml.m5.xlarge', 
            'use_qpu': False
        }
    else:
        # QPU required for large problems (requires approval)
        return {
            'device_type': 'qpu',
            'device_arn': 'arn:aws:braket:us-east-1::device/qpu/rigetti/Aspen-M-3',
            'instance_type': 'ml.m5.2xlarge',
            'use_qpu': True
        }