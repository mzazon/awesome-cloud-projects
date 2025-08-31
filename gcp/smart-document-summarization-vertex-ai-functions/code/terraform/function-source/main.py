import os
import json
import tempfile
from typing import Optional
from google.cloud import storage
from google.cloud.functions import CloudEvent
import functions_framework
import vertexai
from vertexai.generative_models import GenerativeModel
import PyPDF2
import docx

# Initialize Vertex AI
PROJECT_ID = "${project_id}"
REGION = "${region}"
vertexai.init(project=PROJECT_ID, location=REGION)

def extract_text_from_file(file_path: str, file_name: str) -> str:
    """Extract text from various document formats."""
    text = ""
    
    try:
        if file_name.lower().endswith('.pdf'):
            with open(file_path, 'rb') as file:
                pdf_reader = PyPDF2.PdfReader(file)
                for page in pdf_reader.pages:
                    text += page.extract_text() + "\n"
        
        elif file_name.lower().endswith('.docx'):
            doc = docx.Document(file_path)
            for paragraph in doc.paragraphs:
                text += paragraph.text + "\n"
        
        elif file_name.lower().endswith('.txt'):
            with open(file_path, 'r', encoding='utf-8') as file:
                text = file.read()
        
        else:
            # Attempt to read as plain text
            with open(file_path, 'r', encoding='utf-8') as file:
                text = file.read()
                
    except Exception as e:
        print(f"Error extracting text: {str(e)}")
        text = f"Error processing file: {str(e)}"
    
    return text

def generate_summary(text: str, file_name: str) -> str:
    """Generate document summary using Vertex AI Gemini."""
    try:
        model = GenerativeModel("gemini-1.5-pro")
        
        prompt = f"""
        Please provide a comprehensive summary of the following document.
        
        Document: {file_name}
        
        Requirements for the summary:
        1. Identify the main topic and purpose
        2. List key points and findings
        3. Highlight important dates, numbers, or decisions
        4. Keep the summary concise but informative (2-3 paragraphs)
        5. Use clear, professional language
        
        Document content:
        {text[:8000]}  # Limit content to stay within token limits
        """
        
        response = model.generate_content(prompt)
        return response.text
        
    except Exception as e:
        print(f"Error generating summary: {str(e)}")
        return f"Error generating summary: {str(e)}"

@functions_framework.cloud_event
def summarize_document(cloud_event: CloudEvent) -> None:
    """Main function triggered by Cloud Storage events."""
    try:
        # Parse the Cloud Storage event
        data = cloud_event.data
        bucket_name = data["bucket"]
        file_name = data["name"]
        
        print(f"Processing file: {file_name} from bucket: {bucket_name}")
        
        # Skip processing summary files to avoid recursion
        if file_name.endswith('_summary.txt') or file_name == 'ready.txt':
            print(f"Skipping {file_name}")
            return
        
        # Initialize Cloud Storage client
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Download file to temporary location
        with tempfile.NamedTemporaryFile(delete=False) as temp_file:
            blob.download_to_filename(temp_file.name)
            
            # Extract text from document
            text_content = extract_text_from_file(temp_file.name, file_name)
            
            # Generate summary using Vertex AI
            summary = generate_summary(text_content, file_name)
            
            # Create summary metadata
            metadata = {
                "original_file": file_name,
                "processed_at": cloud_event.time,
                "file_size_bytes": blob.size,
                "content_length": len(text_content),
                "summary_length": len(summary)
            }
            
            # Save summary with metadata
            summary_content = f"""DOCUMENT SUMMARY
==================

Original File: {file_name}
Processed: {cloud_event.time}
File Size: {blob.size} bytes

SUMMARY:
{summary}

METADATA:
{json.dumps(metadata, indent=2)}
"""
            
            # Upload summary to Cloud Storage
            summary_file_name = f"{file_name}_summary.txt"
            summary_blob = bucket.blob(summary_file_name)
            summary_blob.upload_from_string(summary_content)
            
            print(f"✅ Summary created: {summary_file_name}")
            
            # Clean up temporary file
            os.unlink(temp_file.name)
            
    except Exception as e:
        print(f"Error processing document: {str(e)}")
        raise e