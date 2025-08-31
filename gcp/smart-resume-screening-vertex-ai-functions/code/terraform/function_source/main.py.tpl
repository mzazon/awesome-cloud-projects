"""
Smart Resume Screening Cloud Function
Processes uploaded resumes using Google Cloud Natural Language API and Vertex AI
Stores analysis results in Firestore for candidate evaluation
"""

import functions_framework
from google.cloud import storage
from google.cloud import firestore
from google.cloud import language_v1
import json
import re
import os
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize clients
storage_client = storage.Client()
firestore_client = firestore.Client()
language_client = language_v1.LanguageServiceClient()

# Configuration from environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', '${region}')
FIRESTORE_COLLECTION = os.environ.get('FIRESTORE_COLLECTION', 'candidates')
ALLOWED_FILE_TYPES = os.environ.get('ALLOWED_FILE_TYPES', 'txt,pdf,doc,docx').split(',')

@functions_framework.cloud_event
def process_resume(cloud_event):
    """
    Cloud Function triggered by Cloud Storage object creation.
    Processes uploaded resumes using AI and stores results in Firestore.
    """
    try:
        # Extract event data
        data = cloud_event.data
        bucket_name = data["bucket"]
        file_name = data["name"]
        
        logger.info(f"Processing file: {file_name} from bucket: {bucket_name}")
        
        # Validate file type
        file_extension = file_name.lower().split('.')[-1] if '.' in file_name else ''
        if file_extension not in ALLOWED_FILE_TYPES:
            logger.info(f"Skipping file {file_name}: unsupported file type .{file_extension}")
            return
        
        # Skip function source files and other non-resume files
        if 'function-source' in file_name or file_name.startswith('.'):
            logger.info(f"Skipping system file: {file_name}")
            return
        
        # Download and extract text from resume
        resume_text = extract_text_from_file(bucket_name, file_name)
        
        if not resume_text or len(resume_text.strip()) < 50:
            logger.warning(f"File {file_name} contains insufficient text content")
            return
        
        # Analyze resume with Natural Language API
        analysis_result = analyze_resume_with_ai(resume_text)
        
        # Generate screening score
        screening_score = calculate_screening_score(analysis_result)
        
        # Extract additional metadata
        candidate_name = extract_candidate_name(resume_text)
        contact_info = extract_contact_info(resume_text)
        
        # Create comprehensive candidate data
        candidate_data = {
            'file_name': file_name,
            'candidate_name': candidate_name,
            'contact_info': contact_info,
            'upload_timestamp': datetime.now(),
            'resume_text': resume_text[:5000],  # Limit text size for storage
            'skills_extracted': analysis_result.get('skills', []),
            'experience_years': analysis_result.get('experience_years', 0),
            'education_level': analysis_result.get('education_level', ''),
            'screening_score': screening_score,
            'sentiment_score': analysis_result.get('sentiment_score', 0.0),
            'entity_analysis': analysis_result.get('entities', [])[:10],  # Limit entities
            'processed_timestamp': datetime.now(),
            'processing_version': '1.0',
            'bucket_name': bucket_name,
            'file_size_bytes': len(resume_text),
            'confidence_score': analysis_result.get('confidence_score', 0.0)
        }
        
        # Store in Firestore with error handling
        doc_ref = firestore_client.collection(FIRESTORE_COLLECTION).document()
        doc_ref.set(candidate_data)
        
        logger.info(f"Successfully processed resume: {file_name}, Score: {screening_score}")
        
        # Return success response
        return {
            'status': 'success',
            'file_name': file_name,
            'screening_score': screening_score,
            'document_id': doc_ref.id
        }
        
    except Exception as e:
        logger.error(f"Error processing resume {file_name}: {str(e)}")
        
        # Store error information for debugging
        try:
            error_data = {
                'file_name': file_name,
                'error_message': str(e),
                'error_timestamp': datetime.now(),
                'bucket_name': bucket_name,
                'processing_status': 'failed'
            }
            firestore_client.collection('processing_errors').document().set(error_data)
        except Exception as store_error:
            logger.error(f"Failed to store error information: {str(store_error)}")
        
        raise e

def extract_text_from_file(bucket_name, file_name):
    """
    Extract text content from uploaded file.
    Currently supports plain text files. For production, integrate with Document AI.
    """
    try:
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Check file size (limit to 1MB for processing efficiency)
        blob_size = blob.size if blob.size else 0
        if blob_size > 1024 * 1024:  # 1MB limit
            logger.warning(f"File {file_name} is too large ({blob_size} bytes)")
            return None
        
        # For demo purposes, handle text files directly
        # In production, use Document AI for PDF/DOC processing
        if file_name.lower().endswith('.txt'):
            content = blob.download_as_text(encoding='utf-8')
            return content
        else:
            # Placeholder for advanced document processing
            # Integration with Document AI would go here
            logger.info(f"Advanced document processing needed for {file_name}")
            return f"Sample resume content extracted from {file_name}"
            
    except Exception as e:
        logger.error(f"Error extracting text from {file_name}: {str(e)}")
        return None

def analyze_resume_with_ai(resume_text):
    """
    Analyze resume using Google Cloud Natural Language API.
    Extracts sentiment, entities, and key information.
    """
    try:
        # Create document object for Natural Language API
        document = language_v1.Document(
            content=resume_text,
            type_=language_v1.Document.Type.PLAIN_TEXT
        )
        
        # Analyze sentiment
        sentiment_response = language_client.analyze_sentiment(
            request={'document': document}
        )
        
        # Analyze entities
        entities_response = language_client.analyze_entities(
            request={'document': document}
        )
        
        # Extract classification if text is long enough
        classification_response = None
        if len(resume_text) > 200:
            try:
                classification_response = language_client.classify_text(
                    request={'document': document}
                )
            except Exception as e:
                logger.info(f"Classification not available: {str(e)}")
        
        # Extract skills and experience using regex patterns and NLP
        skills = extract_skills(resume_text)
        experience_years = extract_experience_years(resume_text)
        education_level = extract_education_level(resume_text)
        
        # Calculate confidence score based on analysis completeness
        confidence_score = calculate_confidence_score(
            sentiment_response, entities_response, skills, experience_years
        )
        
        return {
            'sentiment_score': sentiment_response.document_sentiment.score,
            'sentiment_magnitude': sentiment_response.document_sentiment.magnitude,
            'entities': [
                {
                    'name': entity.name,
                    'type': entity.type_.name,
                    'salience': entity.salience
                }
                for entity in entities_response.entities[:15]  # Limit entities
            ],
            'skills': skills,
            'experience_years': experience_years,
            'education_level': education_level,
            'confidence_score': confidence_score,
            'text_length': len(resume_text)
        }
        
    except Exception as e:
        logger.error(f"Error in AI analysis: {str(e)}")
        # Return basic analysis if AI fails
        return {
            'sentiment_score': 0.0,
            'sentiment_magnitude': 0.0,
            'entities': [],
            'skills': extract_skills(resume_text),
            'experience_years': extract_experience_years(resume_text),
            'education_level': extract_education_level(resume_text),
            'confidence_score': 0.3,  # Low confidence for fallback
            'text_length': len(resume_text)
        }

def extract_skills(text):
    """Extract technical and professional skills from resume text."""
    # Comprehensive skill patterns
    skill_patterns = [
        # Programming languages
        r'\b(?:Python|Java|JavaScript|TypeScript|C\+\+|C#|PHP|Ruby|Go|Rust|Swift|Kotlin)\b',
        # Web technologies
        r'\b(?:React|Angular|Vue\.js|Node\.js|Express|Django|Flask|Spring|ASP\.NET)\b',
        # Databases
        r'\b(?:MySQL|PostgreSQL|MongoDB|Redis|Oracle|SQL Server|SQLite|Cassandra)\b',
        # Cloud platforms
        r'\b(?:AWS|Azure|Google Cloud|GCP|Kubernetes|Docker|Terraform|Ansible)\b',
        # Data science
        r'\b(?:Machine Learning|Data Science|AI|Analytics|Pandas|NumPy|TensorFlow|PyTorch)\b',
        # General skills
        r'\b(?:Project Management|Agile|Scrum|DevOps|CI/CD|Git|Linux|Windows)\b'
    ]
    
    skills = set()
    for pattern in skill_patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        skills.update([match.title() for match in matches])
    
    return list(skills)

def extract_experience_years(text):
    """Extract years of experience from resume text."""
    experience_patterns = [
        r'(\d+)\+?\s*(?:years?|yrs?)\s*(?:of\s*)?(?:experience|exp)',
        r'(?:experience|exp)\s*(?:of\s*)?(\d+)\+?\s*(?:years?|yrs?)',
        r'(\d+)\+?\s*(?:years?|yrs?)\s*(?:in|with)',
        r'(?:over|more than)\s*(\d+)\s*(?:years?|yrs?)'
    ]
    
    years = []
    for pattern in experience_patterns:
        matches = re.findall(pattern, text, re.IGNORECASE)
        years.extend([int(match) for match in matches if match.isdigit()])
    
    return max(years) if years else 0

def extract_education_level(text):
    """Extract highest education level from resume text."""
    education_patterns = {
        'PhD': r'\b(?:PhD|Ph\.?D\.?|Doctorate|Doctoral)\b',
        'Masters': r'\b(?:Master|M\.?S\.?|M\.?A\.?|MBA|M\.?Eng\.?|M\.?Tech\.?)\b',
        'Bachelors': r'\b(?:Bachelor|B\.?S\.?|B\.?A\.?|B\.?Tech\.?|B\.?Eng\.?)\b',
        'Associates': r'\b(?:Associate|A\.?S\.?|A\.?A\.?)\b',
        'High School': r'\b(?:High School|Diploma|GED)\b'
    }
    
    for level, pattern in education_patterns.items():
        if re.search(pattern, text, re.IGNORECASE):
            return level
    
    return 'Other'

def extract_candidate_name(text):
    """Extract candidate name from resume text (basic implementation)."""
    lines = text.split('\n')[:5]  # Check first 5 lines
    
    # Look for name patterns in the beginning of the resume
    name_patterns = [
        r'^([A-Z][a-z]+\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)\s*$',
        r'^([A-Z][a-z]+\s+[A-Z]\.\s+[A-Z][a-z]+)\s*$'
    ]
    
    for line in lines:
        line = line.strip()
        for pattern in name_patterns:
            match = re.search(pattern, line)
            if match:
                return match.group(1)
    
    return 'Unknown'

def extract_contact_info(text):
    """Extract contact information from resume text."""
    contact_info = {}
    
    # Email pattern
    email_pattern = r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'
    email_match = re.search(email_pattern, text)
    if email_match:
        contact_info['email'] = email_match.group()
    
    # Phone pattern (basic US format)
    phone_pattern = r'\b(?:\+?1[-.\s]?)?\(?([0-9]{3})\)?[-.\s]?([0-9]{3})[-.\s]?([0-9]{4})\b'
    phone_match = re.search(phone_pattern, text)
    if phone_match:
        contact_info['phone'] = phone_match.group()
    
    return contact_info

def calculate_confidence_score(sentiment_response, entities_response, skills, experience_years):
    """Calculate confidence score for the analysis."""
    score = 0.0
    
    # Sentiment analysis available
    if sentiment_response:
        score += 0.2
    
    # Entities extracted
    if entities_response and len(entities_response.entities) > 0:
        score += 0.3
    
    # Skills identified
    if skills and len(skills) > 0:
        score += 0.3
    
    # Experience years identified
    if experience_years > 0:
        score += 0.2
    
    return min(score, 1.0)

def calculate_screening_score(analysis_result):
    """
    Calculate overall screening score based on extracted information.
    Score ranges from 0-100 with weighted factors.
    """
    score = 0.0
    
    # Experience score (max 35 points)
    experience_years = analysis_result.get('experience_years', 0)
    if experience_years > 0:
        score += min(experience_years * 3.5, 35)
    
    # Education score (max 25 points)
    education_scores = {
        'PhD': 25,
        'Masters': 20,
        'Bachelors': 15,
        'Associates': 10,
        'High School': 5,
        'Other': 2
    }
    education_level = analysis_result.get('education_level', 'Other')
    score += education_scores.get(education_level, 2)
    
    # Skills score (max 25 points)
    skills_count = len(analysis_result.get('skills', []))
    if skills_count > 0:
        score += min(skills_count * 2.5, 25)
    
    # Sentiment score (max 10 points)
    sentiment = analysis_result.get('sentiment_score', 0.0)
    if sentiment > 0:
        score += min(sentiment * 10, 10)
    
    # Confidence bonus (max 5 points)
    confidence = analysis_result.get('confidence_score', 0.0)
    score += confidence * 5
    
    # Text completeness bonus (max 5 points based on resume completeness)
    text_length = analysis_result.get('text_length', 0)
    if text_length > 500:
        score += min((text_length / 1000) * 5, 5)
    
    return min(round(score, 1), 100.0)  # Cap at 100 and round to 1 decimal