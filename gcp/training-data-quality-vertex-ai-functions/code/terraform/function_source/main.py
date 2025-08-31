"""
Training Data Quality Assessment with Vertex AI and Cloud Functions

This Cloud Function provides automated analysis of training datasets for:
- Bias detection using Google Cloud recommended metrics
- Content quality assessment using Vertex AI Gemini models
- Vocabulary diversity analysis
- Actionable recommendations for data improvement

The function integrates with Cloud Storage for data input/output and
Vertex AI for advanced natural language understanding capabilities.
"""

import json
import pandas as pd
import numpy as np
from google.cloud import aiplatform
from google.cloud import storage
import google.genai as genai
from sklearn.metrics import accuracy_score
import re
from collections import Counter, defaultdict
import os
import logging
from typing import Dict, List, Any, Optional
import traceback
from datetime import datetime
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def analyze_data_quality(request):
    """
    Cloud Function entry point for analyzing training data quality and bias.
    
    Expected request JSON payload:
    {
        "project_id": "your-gcp-project-id",
        "region": "us-central1",
        "bucket_name": "your-bucket-name",
        "dataset_path": "datasets/training_data.json",
        "vertex_ai_model": "gemini-1.5-flash" (optional),
        "sample_size": 5 (optional),
        "bias_threshold": 0.1 (optional)
    }
    
    Returns:
    {
        "status": "success" | "error",
        "report_location": "gs://bucket/reports/report.json",
        "summary": {...},
        "error": "error message" (if status is error)
    }
    """
    
    # Initialize timing for performance monitoring
    start_time = time.time()
    
    try:
        # Parse and validate request
        logger.info("Starting data quality analysis request")
        request_data = _parse_request(request)
        
        # Initialize services
        _initialize_services(request_data['project_id'], request_data['region'])
        
        # Load and validate dataset
        dataset = _load_dataset(request_data['bucket_name'], request_data['dataset_path'])
        
        # Perform comprehensive analysis
        quality_report = _perform_analysis(dataset, request_data)
        
        # Save report and return response
        report_location = _save_report(quality_report, request_data['bucket_name'])
        
        execution_time = time.time() - start_time
        logger.info(f"Analysis completed successfully in {execution_time:.2f} seconds")
        
        return {
            'status': 'success',
            'report_location': report_location,
            'execution_time_seconds': execution_time,
            'summary': {
                'total_samples': quality_report['dataset_info']['total_samples'],
                'bias_detected': len(quality_report['bias_analysis']) > 0,
                'content_issues': len(quality_report['content_quality'].get('issues', [])),
                'recommendations_count': len(quality_report['recommendations'])
            }
        }
        
    except Exception as e:
        execution_time = time.time() - start_time
        error_message = f"Analysis failed after {execution_time:.2f} seconds: {str(e)}"
        logger.error(error_message)
        logger.error(traceback.format_exc())
        
        return {
            'status': 'error',
            'error': error_message,
            'execution_time_seconds': execution_time
        }, 500

def _parse_request(request) -> Dict[str, Any]:
    """Parse and validate the incoming request."""
    try:
        request_json = request.get_json()
        if not request_json:
            raise ValueError("No JSON payload provided")
    except Exception as e:
        raise ValueError(f"Invalid JSON payload: {str(e)}")
    
    # Extract and validate required parameters
    project_id = request_json.get('project_id')
    bucket_name = request_json.get('bucket_name')
    
    if not project_id or not bucket_name:
        raise ValueError("project_id and bucket_name are required parameters")
    
    # Extract optional parameters with defaults
    request_data = {
        'project_id': project_id,
        'region': request_json.get('region', 'us-central1'),
        'bucket_name': bucket_name,
        'dataset_path': request_json.get('dataset_path', 'datasets/sample_training_data.json'),
        'vertex_ai_model': request_json.get('vertex_ai_model', 'gemini-1.5-flash'),
        'sample_size': request_json.get('sample_size', 5),
        'bias_threshold': request_json.get('bias_threshold', 0.1),
        'vocabulary_threshold': request_json.get('vocabulary_threshold', 0.3)
    }
    
    logger.info(f"Parsed request: {request_data}")
    return request_data

def _initialize_services(project_id: str, region: str) -> None:
    """Initialize Vertex AI and other Google Cloud services."""
    try:
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=region)
        logger.info(f"Vertex AI initialized for project {project_id} in region {region}")
        
        # Initialize Vertex AI Generative AI
        genai.configure(project=project_id, location=region)
        logger.info("Google GenAI SDK configured successfully")
        
    except Exception as e:
        raise RuntimeError(f"Failed to initialize Vertex AI services: {str(e)}")

def _load_dataset(bucket_name: str, dataset_path: str) -> List[Dict[str, Any]]:
    """Load and validate the training dataset from Cloud Storage."""
    try:
        # Initialize Storage client
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(dataset_path)
        
        if not blob.exists():
            raise FileNotFoundError(f"Dataset not found at gs://{bucket_name}/{dataset_path}")
        
        # Download and parse dataset
        data_content = blob.download_as_text()
        dataset = json.loads(data_content)
        
        if not dataset or not isinstance(dataset, list):
            raise ValueError("Dataset must be a non-empty list of records")
        
        logger.info(f"Successfully loaded dataset with {len(dataset)} records")
        return dataset
        
    except Exception as e:
        raise RuntimeError(f"Failed to load dataset: {str(e)}")

def _perform_analysis(dataset: List[Dict[str, Any]], request_data: Dict[str, Any]) -> Dict[str, Any]:
    """Perform comprehensive data quality analysis."""
    
    # Convert to DataFrame for analysis
    df = pd.DataFrame(dataset)
    logger.info(f"Dataset shape: {df.shape}")
    
    # Initialize quality report structure
    quality_report = {
        'dataset_info': _analyze_dataset_info(df),
        'bias_analysis': {},
        'content_quality': {},
        'recommendations': [],
        'analysis_metadata': {
            'timestamp': datetime.utcnow().isoformat(),
            'analyzer_version': '1.0.0',
            'vertex_ai_model': request_data['vertex_ai_model'],
            'sample_size_analyzed': request_data['sample_size']
        }
    }
    
    # Perform bias analysis
    if 'demographic' in df.columns and 'label' in df.columns:
        logger.info("Performing demographic bias analysis")
        quality_report['bias_analysis'] = _analyze_demographic_bias(df, request_data['bias_threshold'])
    else:
        logger.warning("Skipping bias analysis - missing 'demographic' or 'label' columns")
    
    # Perform content quality analysis with Vertex AI
    if 'text' in df.columns:
        logger.info("Performing content quality analysis with Vertex AI")
        quality_report['content_quality'] = _analyze_content_with_gemini(
            df, request_data['project_id'], request_data['region'], 
            request_data['vertex_ai_model'], request_data['sample_size']
        )
    else:
        logger.warning("Skipping content analysis - missing 'text' column")
    
    # Generate actionable recommendations
    logger.info("Generating recommendations")
    quality_report['recommendations'] = _generate_recommendations(quality_report, request_data)
    
    return quality_report

def _analyze_dataset_info(df: pd.DataFrame) -> Dict[str, Any]:
    """Analyze basic dataset information and statistics."""
    info = {
        'total_samples': len(df),
        'columns': list(df.columns),
        'missing_values': df.isnull().sum().to_dict(),
        'data_types': df.dtypes.astype(str).to_dict()
    }
    
    # Add column-specific information
    if 'label' in df.columns:
        info['unique_labels'] = df['label'].unique().tolist()
        info['label_distribution'] = df['label'].value_counts().to_dict()
    
    if 'demographic' in df.columns:
        info['demographics'] = df['demographic'].unique().tolist()
        info['demographic_distribution'] = df['demographic'].value_counts().to_dict()
    
    if 'text' in df.columns:
        info['text_statistics'] = {
            'avg_length': df['text'].str.len().mean(),
            'min_length': df['text'].str.len().min(),
            'max_length': df['text'].str.len().max(),
            'total_words': df['text'].str.split().str.len().sum()
        }
    
    return info

def _analyze_demographic_bias(df: pd.DataFrame, bias_threshold: float) -> Dict[str, Any]:
    """
    Implement Google Cloud recommended bias detection metrics.
    
    References:
    - Vertex AI Fairness Evaluation: https://cloud.google.com/vertex-ai/docs/evaluation/intro-evaluation-fairness
    - Data Bias Metrics: https://cloud.google.com/vertex-ai/docs/evaluation/data-bias-metrics
    """
    bias_results = {}
    
    # 1. Difference in Population Size (DPS)
    demo_counts = df['demographic'].value_counts()
    if len(demo_counts) >= 2:
        demo_1, demo_2 = demo_counts.index[:2]
        n1, n2 = demo_counts.iloc[0], demo_counts.iloc[1]
        
        # Calculate population difference ratio
        pop_diff = (n1 - n2) / (n1 + n2)
        
        bias_results['population_difference'] = {
            'value': float(pop_diff),
            'demographics': {demo_1: int(n1), demo_2: int(n2)},
            'interpretation': 'bias_detected' if abs(pop_diff) > bias_threshold else 'balanced',
            'metric_description': 'Difference in Population Size (DPS) - measures representation imbalance'
        }
        
        logger.info(f"Population difference: {pop_diff:.3f} (threshold: {bias_threshold})")
    
    # 2. Difference in Positive Proportions in True Labels (DPPTL)
    if 'label' in df.columns:
        positive_labels = ['positive']  # Define what constitutes positive labels
        
        # Calculate positive proportions for each demographic
        demo_proportions = {}
        for demo in df['demographic'].unique():
            demo_data = df[df['demographic'] == demo]
            positive_count = len(demo_data[demo_data['label'].isin(positive_labels)])
            total_count = len(demo_data)
            positive_prop = positive_count / total_count if total_count > 0 else 0
            demo_proportions[demo] = positive_prop
            
            bias_results[f'{demo}_positive_proportion'] = float(positive_prop)
        
        # Calculate DPPTL between top two demographics
        if len(demo_proportions) >= 2:
            sorted_demos = sorted(demo_proportions.items(), key=lambda x: demo_counts.get(x[0], 0), reverse=True)
            demo1, prop1 = sorted_demos[0]
            demo2, prop2 = sorted_demos[1]
            
            dpptl = prop1 - prop2
            
            bias_results['label_bias_dpptl'] = {
                'value': float(dpptl),
                'demographics': {demo1: float(prop1), demo2: float(prop2)},
                'interpretation': 'significant_bias' if abs(dpptl) > bias_threshold else 'minimal_bias',
                'metric_description': 'Difference in Positive Proportions in True Labels (DPPTL)'
            }
            
            logger.info(f"DPPTL: {dpptl:.3f} (threshold: {bias_threshold})")
    
    # 3. Additional bias metrics
    bias_results['bias_summary'] = {
        'total_metrics_calculated': len([k for k in bias_results.keys() if not k.endswith('_positive_proportion')]),
        'bias_detected': any(
            result.get('interpretation') in ['bias_detected', 'significant_bias'] 
            for result in bias_results.values() 
            if isinstance(result, dict) and 'interpretation' in result
        ),
        'threshold_used': bias_threshold
    }
    
    return bias_results

def _analyze_content_with_gemini(df: pd.DataFrame, project_id: str, region: str, 
                                model_name: str, sample_size: int) -> Dict[str, Any]:
    """Use Vertex AI Gemini for advanced content quality analysis."""
    try:
        # Initialize Gemini model
        model = genai.GenerativeModel(model_name)
        logger.info(f"Initialized Gemini model: {model_name}")
        
        # Sample texts for analysis (to control API costs)
        sample_texts = df['text'].head(sample_size).tolist()
        logger.info(f"Analyzing {len(sample_texts)} sample texts")
        
        # Construct analysis prompt
        prompt = f"""
        Analyze the following training data samples for content quality issues:
        
        Texts: {sample_texts}
        
        Evaluate for:
        1. Language consistency and clarity
        2. Potential bias in language use (subtle word choices, descriptions)
        3. Data quality issues (typos, formatting problems)
        4. Sentiment consistency with labels (if applicable)
        5. Vocabulary diversity and richness
        
        Provide specific examples and actionable recommendations for improvement.
        Rate the overall quality on a scale of 1-10.
        """
        
        # Generate content analysis
        response = model.generate_content(prompt)
        logger.info("Gemini analysis completed successfully")
        
        # Parse and structure the response
        content_analysis = {
            'gemini_assessment': response.text,
            'language_quality_score': _extract_quality_score(response.text),
            'issues': _extract_issues(response.text),
            'vocabulary_stats': _analyze_vocabulary(df['text']),
            'sample_size_analyzed': len(sample_texts),
            'model_used': model_name
        }
        
        return content_analysis
        
    except Exception as e:
        logger.error(f"Gemini analysis failed: {str(e)}")
        # Return fallback analysis without Gemini
        return {
            'error': f'Gemini analysis failed: {str(e)}',
            'vocabulary_stats': _analyze_vocabulary(df['text']),
            'fallback_analysis': True
        }

def _extract_quality_score(text: str) -> float:
    """Extract quality score from Gemini response."""
    text_lower = text.lower()
    
    # Look for numerical scores (1-10 scale)
    score_patterns = [
        r'score[:\s]*(\d+(?:\.\d+)?)/10',
        r'rate[:\s]*(\d+(?:\.\d+)?)/10',
        r'quality[:\s]*(\d+(?:\.\d+)?)/10',
        r'(\d+(?:\.\d+)?)\s*/\s*10'
    ]
    
    for pattern in score_patterns:
        match = re.search(pattern, text_lower)
        if match:
            score = float(match.group(1))
            return min(max(score / 10.0, 0.0), 1.0)  # Normalize to 0-1
    
    # Fallback to qualitative indicators
    quality_indicators = {
        'excellent': 0.9,
        'very good': 0.8,
        'good': 0.7,
        'fair': 0.6,
        'poor': 0.4,
        'very poor': 0.2
    }
    
    for indicator, score in quality_indicators.items():
        if indicator in text_lower:
            return score
    
    return 0.5  # Default neutral score

def _extract_issues(text: str) -> List[str]:
    """Extract specific issues mentioned in Gemini analysis."""
    issue_keywords = [
        'bias', 'biased', 'inconsistency', 'inconsistent', 
        'typo', 'spelling', 'grammar', 'unclear', 'ambiguous',
        'repetitive', 'repetition', 'imbalanced', 'imbalance',
        'stereotype', 'stereotypical', 'discriminatory'
    ]
    
    issues = []
    text_lower = text.lower()
    
    for keyword in issue_keywords:
        if keyword in text_lower:
            issues.append(keyword)
    
    # Remove duplicates while preserving order
    return list(dict.fromkeys(issues))

def _analyze_vocabulary(texts: pd.Series) -> Dict[str, Any]:
    """Statistical analysis of vocabulary diversity and richness."""
    # Combine all text
    all_text = ' '.join(texts.astype(str))
    
    # Extract words
    words = re.findall(r'\b\w+\b', all_text.lower())
    
    # Calculate statistics
    vocab_stats = {
        'total_words': len(words),
        'unique_words': len(set(words)),
        'vocabulary_diversity': len(set(words)) / len(words) if words else 0,
        'most_common_words': Counter(words).most_common(10),
        'average_word_length': np.mean([len(word) for word in words]) if words else 0,
        'words_per_sample': len(words) / len(texts) if len(texts) > 0 else 0
    }
    
    return vocab_stats

def _generate_recommendations(report: Dict[str, Any], request_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Generate actionable recommendations based on analysis results."""
    recommendations = []
    
    # Bias-related recommendations
    bias_analysis = report.get('bias_analysis', {})
    
    # Population imbalance recommendations
    if 'population_difference' in bias_analysis:
        pop_diff = bias_analysis['population_difference']
        if pop_diff.get('interpretation') == 'bias_detected':
            recommendations.append({
                'type': 'bias_mitigation',
                'priority': 'high',
                'category': 'data_balance',
                'description': 'Balance demographic representation in dataset',
                'action': f'Add more samples for underrepresented group (current imbalance: {pop_diff["value"]:.2f})',
                'impact': 'Reduces model bias and improves fairness across demographic groups'
            })
    
    # Label bias recommendations
    if 'label_bias_dpptl' in bias_analysis:
        dpptl = bias_analysis['label_bias_dpptl']
        if dpptl.get('interpretation') == 'significant_bias':
            recommendations.append({
                'type': 'bias_mitigation',
                'priority': 'high',
                'category': 'label_fairness',
                'description': 'Address label distribution bias across demographics',
                'action': f'Review labeling criteria and ensure consistent application across all demographic groups (DPPTL: {dpptl["value"]:.2f})',
                'impact': 'Improves model fairness and reduces discriminatory outcomes'
            })
    
    # Content quality recommendations
    content_quality = report.get('content_quality', {})
    
    # Address identified issues
    if 'issues' in content_quality and content_quality['issues']:
        for issue in content_quality['issues']:
            recommendations.append({
                'type': 'content_quality',
                'priority': 'medium',
                'category': 'data_cleaning',
                'description': f'Address {issue} issues in training data',
                'action': f'Review and clean data entries with {issue} problems',
                'impact': 'Improves data quality and model performance'
            })
    
    # Vocabulary diversity recommendations
    vocab_stats = content_quality.get('vocabulary_stats', {})
    vocab_diversity = vocab_stats.get('vocabulary_diversity', 0)
    
    if vocab_diversity < request_data.get('vocabulary_threshold', 0.3):
        recommendations.append({
            'type': 'diversity',
            'priority': 'medium',
            'category': 'vocabulary_expansion',
            'description': 'Increase vocabulary diversity',
            'action': f'Add more varied examples to improve model generalization (current diversity: {vocab_diversity:.2f})',
            'impact': 'Improves model robustness and generalization capabilities'
        })
    
    # Quality score recommendations
    quality_score = content_quality.get('language_quality_score', 0.5)
    if quality_score < 0.7:
        recommendations.append({
            'type': 'content_quality',
            'priority': 'medium',
            'category': 'content_improvement',
            'description': 'Improve overall content quality',
            'action': f'Review and enhance content clarity and consistency (current score: {quality_score:.2f})',
            'impact': 'Better training data leads to more reliable model performance'
        })
    
    # Sample size recommendations
    dataset_info = report.get('dataset_info', {})
    total_samples = dataset_info.get('total_samples', 0)
    
    if total_samples < 100:
        recommendations.append({
            'type': 'data_volume',
            'priority': 'low',
            'category': 'dataset_expansion',
            'description': 'Consider expanding dataset size',
            'action': f'Collect additional training samples (current: {total_samples})',
            'impact': 'Larger datasets typically lead to more robust model performance'
        })
    
    # Sort recommendations by priority
    priority_order = {'high': 0, 'medium': 1, 'low': 2}
    recommendations.sort(key=lambda x: priority_order.get(x['priority'], 2))
    
    return recommendations

def _save_report(quality_report: Dict[str, Any], bucket_name: str) -> str:
    """Save the quality analysis report to Cloud Storage."""
    try:
        # Generate report filename with timestamp
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        report_filename = f'reports/quality_report_{timestamp}.json'
        
        # Initialize Storage client and upload report
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(report_filename)
        
        # Add metadata to the report
        quality_report['report_metadata'] = {
            'generated_at': datetime.utcnow().isoformat(),
            'report_version': '1.0.0',
            'storage_location': f'gs://{bucket_name}/{report_filename}'
        }
        
        # Upload the report
        blob.upload_from_string(
            json.dumps(quality_report, indent=2, default=str),
            content_type='application/json'
        )
        
        report_location = f'gs://{bucket_name}/{report_filename}'
        logger.info(f"Report saved to: {report_location}")
        
        return report_location
        
    except Exception as e:
        raise RuntimeError(f"Failed to save report: {str(e)}")

# Additional utility functions for enhanced functionality

def validate_dataset_schema(dataset: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Validate dataset schema and return validation results."""
    validation_results = {
        'is_valid': True,
        'errors': [],
        'warnings': [],
        'schema_info': {}
    }
    
    if not dataset:
        validation_results['is_valid'] = False
        validation_results['errors'].append("Dataset is empty")
        return validation_results
    
    # Check for required fields
    first_record = dataset[0]
    required_fields = ['text']
    optional_fields = ['label', 'demographic']
    
    for field in required_fields:
        if field not in first_record:
            validation_results['is_valid'] = False
            validation_results['errors'].append(f"Required field '{field}' is missing")
    
    # Check schema consistency
    all_keys = set()
    for record in dataset:
        all_keys.update(record.keys())
    
    validation_results['schema_info'] = {
        'all_fields': list(all_keys),
        'record_count': len(dataset),
        'has_labels': 'label' in all_keys,
        'has_demographics': 'demographic' in all_keys
    }
    
    return validation_results

# Health check endpoint for monitoring
def health_check(request):
    """Simple health check endpoint for the Cloud Function."""
    return {
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'service': 'training-data-quality-analyzer',
        'version': '1.0.0'
    }