"""
Cloud Function for Accessibility Compliance Analysis
Processes documents using Document AI and Gemini for WCAG 2.1 AA compliance evaluation
"""

import json
import os
import tempfile
from typing import Dict, List, Any
import logging

from google.cloud import documentai
from google.cloud import storage
from google.cloud import functions_framework
import vertexai
from vertexai.generative_models import GenerativeModel
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet

# Initialize clients
documentai_client = documentai.DocumentProcessorServiceClient()
storage_client = storage.Client()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Template variables will be replaced by Terraform
PROJECT_ID = "${project_id}"
REGION = "${region}"
PROCESSOR_ID = "${processor_id}"
GEMINI_MODEL = "${gemini_model}"


def analyze_accessibility_with_gemini(document_content: str, layout_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Use Gemini to analyze document accessibility against WCAG 2.1 AA guidelines.
    
    Args:
        document_content: Extracted text content from the document
        layout_data: Structured layout information from Document AI
        
    Returns:
        Dictionary containing accessibility analysis results
    """
    try:
        # Initialize Vertex AI
        vertexai.init(project=PROJECT_ID, location=REGION)
        model = GenerativeModel(GEMINI_MODEL)
        
        # Comprehensive WCAG 2.1 AA evaluation prompt
        wcag_prompt = f"""
        You are an accessibility expert evaluating a document against WCAG 2.1 AA guidelines.
        
        Document Layout Analysis:
        {json.dumps(layout_data, indent=2)[:2000]}...
        
        Document Text Content (first 3000 characters):
        {document_content[:3000]}...
        
        Please evaluate this document against these WCAG 2.1 AA success criteria:
        
        1. Perceivable (Guidelines 1.1-1.4):
           - 1.1.1: Non-text content has text alternatives
           - 1.3.1: Info and relationships are programmatically determinable
           - 1.3.2: Meaningful sequence can be programmatically determined
           - 1.4.3: Color contrast ratio is at least 4.5:1
           - 1.4.4: Text can be resized up to 200% without loss of functionality
        
        2. Operable (Guidelines 2.1-2.4):
           - 2.1.1: All functionality is available from keyboard
           - 2.1.2: No keyboard trap
           - 2.4.1: Blocks of content can be bypassed
           - 2.4.2: Pages have titles that describe topic or purpose
           - 2.4.6: Headings and labels describe topic or purpose
        
        3. Understandable (Guidelines 3.1-3.3):
           - 3.1.1: Default human language of page is programmatically determined
           - 3.1.2: Human language of parts can be programmatically determined
           - 3.2.1: When component receives focus, it doesn't initiate context change
           - 3.2.2: Changing input doesn't cause unexpected context changes
        
        4. Robust (Guideline 4.1):
           - 4.1.1: Content can be parsed unambiguously
           - 4.1.2: Name, role, value can be programmatically determined
        
        Based on the document structure and content, provide a detailed JSON response:
        
        {{
            "overall_score": "Pass|Fail|Partial",
            "compliance_percentage": 85,
            "total_issues": 5,
            "critical_issues": 1,
            "high_issues": 2,
            "medium_issues": 2,
            "low_issues": 0,
            "issues": [
                {{
                    "guideline": "1.1.1",
                    "level": "A",
                    "severity": "Critical|High|Medium|Low",
                    "title": "Missing Alt Text for Images",
                    "description": "Detailed description of the accessibility issue found",
                    "location": "Page 1, Figure 2",
                    "recommendation": "Add descriptive alt text for all images and graphics",
                    "wcag_reference": "https://www.w3.org/WAI/WCAG21/Understanding/non-text-content.html"
                }}
            ],
            "positive_findings": [
                "Document has clear heading structure",
                "Text contrast appears adequate",
                "Reading order is logical"
            ],
            "recommendations": [
                "Implement alternative text for all images",
                "Ensure table headers are properly marked",
                "Add language identification markup"
            ],
            "summary": "Overall accessibility assessment summary with key findings and next steps"
        }}
        
        Focus on issues that can be identified from the document structure and content provided.
        Be specific about locations where issues are found and provide actionable recommendations.
        """
        
        logger.info(f"Sending request to {GEMINI_MODEL} for accessibility analysis")
        response = model.generate_content(wcag_prompt)
        
        # Clean and parse JSON response from Gemini
        response_text = response.text.strip()
        if response_text.startswith('```json'):
            response_text = response_text[7:]
        if response_text.endswith('```'):
            response_text = response_text[:-3]
        
        result = json.loads(response_text.strip())
        logger.info(f"Gemini analysis completed with {result.get('total_issues', 0)} issues found")
        return result
        
    except json.JSONDecodeError as e:
        logger.error(f"Error parsing Gemini JSON response: {e}")
        return create_error_result(f"JSON parsing error: {str(e)}")
    except Exception as e:
        logger.error(f"Error in Gemini analysis: {e}")
        return create_error_result(f"Analysis error: {str(e)}")


def create_error_result(error_message: str) -> Dict[str, Any]:
    """Create a standardized error result structure."""
    return {
        "overall_score": "Error",
        "compliance_percentage": 0,
        "total_issues": 0,
        "critical_issues": 0,
        "high_issues": 0,
        "medium_issues": 0,
        "low_issues": 0,
        "issues": [],
        "positive_findings": [],
        "recommendations": ["Retry analysis after resolving technical issues"],
        "summary": f"Analysis could not be completed: {error_message}"
    }


def process_document_with_docai(file_content: bytes, processor_path: str) -> tuple[str, Dict[str, Any]]:
    """
    Process document with Document AI to extract structure and content.
    
    Args:
        file_content: Raw document bytes
        processor_path: Full path to Document AI processor
        
    Returns:
        Tuple of (extracted_text, layout_data)
    """
    try:
        logger.info(f"Processing document with Document AI processor: {processor_path}")
        
        # Create document for processing
        raw_document = documentai.RawDocument(
            content=file_content,
            mime_type="application/pdf"
        )
        
        # Configure processing request
        request = documentai.ProcessRequest(
            name=processor_path,
            raw_document=raw_document
        )
        
        # Process document
        result = documentai_client.process_document(request=request)
        document = result.document
        
        logger.info(f"Document processed - {len(document.pages)} pages, {len(document.text)} characters")
        
        # Extract comprehensive layout information
        layout_data = {
            "pages": len(document.pages),
            "total_characters": len(document.text),
            "paragraphs": [],
            "tables": [],
            "form_fields": [],
            "blocks": [],
            "has_images": False,
            "reading_order_issues": []
        }
        
        for page_idx, page in enumerate(document.pages):
            # Extract paragraphs with structure info
            for para_idx, paragraph in enumerate(page.paragraphs):
                para_text = get_text(paragraph, document)
                layout_data["paragraphs"].append({
                    "page": page_idx + 1,
                    "index": para_idx,
                    "text": para_text[:200] + "..." if len(para_text) > 200 else para_text,
                    "confidence": paragraph.layout.confidence,
                    "is_heading": is_likely_heading(para_text),
                    "char_count": len(para_text)
                })
            
            # Extract table information
            for table_idx, table in enumerate(page.tables):
                header_rows = len(table.header_rows)
                body_rows = len(table.body_rows)
                columns = len(table.header_rows[0].cells) if header_rows > 0 else 0
                
                layout_data["tables"].append({
                    "page": page_idx + 1,
                    "index": table_idx,
                    "header_rows": header_rows,
                    "body_rows": body_rows,
                    "columns": columns,
                    "has_headers": header_rows > 0,
                    "accessibility_score": calculate_table_accessibility_score(header_rows, columns)
                })
            
            # Extract form fields
            for field_idx, form_field in enumerate(page.form_fields):
                field_name = get_text(form_field.field_name, document) if form_field.field_name else ""
                field_value = get_text(form_field.field_value, document) if form_field.field_value else ""
                
                layout_data["form_fields"].append({
                    "page": page_idx + 1,
                    "index": field_idx,
                    "field_name": field_name,
                    "field_value": field_value,
                    "has_label": len(field_name.strip()) > 0,
                    "confidence": form_field.field_name.confidence if form_field.field_name else 0
                })
            
            # Check for images/visual elements
            if hasattr(page, 'image') and page.image:
                layout_data["has_images"] = True
            
            # Extract text blocks for reading order analysis
            for block_idx, block in enumerate(page.blocks):
                block_text = get_text(block, document)
                layout_data["blocks"].append({
                    "page": page_idx + 1,
                    "index": block_idx,
                    "text": block_text[:100] + "..." if len(block_text) > 100 else block_text,
                    "confidence": block.layout.confidence
                })
        
        # Analyze document structure for accessibility insights
        layout_data["structure_analysis"] = analyze_document_structure(layout_data)
        
        return document.text, layout_data
        
    except Exception as e:
        logger.error(f"Error processing document with Document AI: {e}")
        raise e


def get_text(doc_element, document: documentai.Document) -> str:
    """Extract text from document element using text anchor."""
    if not doc_element or not doc_element.layout or not doc_element.layout.text_anchor:
        return ""
    
    response = ""
    for segment in doc_element.layout.text_anchor.text_segments:
        start_index = int(segment.start_index) if segment.start_index else 0
        end_index = int(segment.end_index) if segment.end_index else 0
        response += document.text[start_index:end_index]
    return response


def is_likely_heading(text: str) -> bool:
    """Simple heuristic to identify potential headings."""
    text = text.strip()
    if len(text) == 0:
        return False
    
    # Check for common heading patterns
    heading_indicators = [
        len(text) < 100,  # Short text
        text.isupper(),   # All uppercase
        text.endswith(':'),  # Ends with colon
        any(text.startswith(prefix) for prefix in ['Chapter', 'Section', 'Part', 'Appendix']),
        text.count('.') <= 1 and not text.endswith('.')  # Minimal punctuation
    ]
    
    return sum(heading_indicators) >= 2


def calculate_table_accessibility_score(header_rows: int, columns: int) -> float:
    """Calculate a simple accessibility score for tables."""
    if columns == 0:
        return 0.0
    
    score = 0.0
    if header_rows > 0:
        score += 0.7  # Has headers
    if columns <= 6:
        score += 0.2  # Reasonable number of columns
    if header_rows == 1:
        score += 0.1  # Single header row (ideal)
    
    return min(score, 1.0)


def analyze_document_structure(layout_data: Dict[str, Any]) -> Dict[str, Any]:
    """Analyze document structure for accessibility insights."""
    analysis = {
        "heading_structure": "unknown",
        "table_accessibility": "unknown",
        "form_accessibility": "unknown",
        "image_accessibility": "unknown"
    }
    
    # Analyze heading structure
    headings = [p for p in layout_data["paragraphs"] if p["is_heading"]]
    if len(headings) > 0:
        analysis["heading_structure"] = "present"
        if len(headings) >= 3:
            analysis["heading_structure"] = "good"
    else:
        analysis["heading_structure"] = "missing"
    
    # Analyze table accessibility
    if layout_data["tables"]:
        tables_with_headers = sum(1 for t in layout_data["tables"] if t["has_headers"])
        if tables_with_headers == len(layout_data["tables"]):
            analysis["table_accessibility"] = "good"
        elif tables_with_headers > 0:
            analysis["table_accessibility"] = "partial"
        else:
            analysis["table_accessibility"] = "poor"
    
    # Analyze form accessibility
    if layout_data["form_fields"]:
        fields_with_labels = sum(1 for f in layout_data["form_fields"] if f["has_label"])
        if fields_with_labels == len(layout_data["form_fields"]):
            analysis["form_accessibility"] = "good"
        elif fields_with_labels > 0:
            analysis["form_accessibility"] = "partial"
        else:
            analysis["form_accessibility"] = "poor"
    
    # Analyze image accessibility (simplified check)
    if layout_data["has_images"]:
        analysis["image_accessibility"] = "needs_review"  # Cannot determine alt text from PDF
    
    return analysis


def generate_accessibility_report(analysis_result: Dict[str, Any], filename: str) -> str:
    """Generate professional PDF accessibility report."""
    try:
        with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as tmp_file:
            doc = SimpleDocTemplate(tmp_file.name, pagesize=letter)
            styles = getSampleStyleSheet()
            story = []
            
            # Title and metadata
            story.append(Paragraph(f"WCAG 2.1 AA Accessibility Compliance Report", styles['Title']))
            story.append(Spacer(1, 12))
            story.append(Paragraph(f"Document: {filename}", styles['Heading2']))
            story.append(Paragraph(f"Analysis Date: {os.environ.get('TIMESTAMP', 'N/A')}", styles['Normal']))
            story.append(Spacer(1, 20))
            
            # Executive Summary
            story.append(Paragraph("Executive Summary", styles['Heading1']))
            story.append(Paragraph(f"Overall Compliance Score: {analysis_result['overall_score']}", styles['Normal']))
            story.append(Paragraph(f"Compliance Percentage: {analysis_result.get('compliance_percentage', 'N/A')}%", styles['Normal']))
            story.append(Paragraph(f"Total Issues Found: {analysis_result['total_issues']}", styles['Normal']))
            story.append(Paragraph(f"Critical Issues: {analysis_result['critical_issues']}", styles['Normal']))
            story.append(Paragraph(f"High Priority Issues: {analysis_result.get('high_issues', 0)}", styles['Normal']))
            story.append(Spacer(1, 16))
            
            # Summary
            story.append(Paragraph("Assessment Summary", styles['Heading2']))
            story.append(Paragraph(analysis_result['summary'], styles['Normal']))
            story.append(Spacer(1, 16))
            
            # Positive Findings
            if analysis_result.get('positive_findings'):
                story.append(Paragraph("Positive Findings", styles['Heading2']))
                for finding in analysis_result['positive_findings']:
                    story.append(Paragraph(f"• {finding}", styles['Normal']))
                story.append(Spacer(1, 16))
            
            # Detailed Issues
            if analysis_result['issues']:
                story.append(Paragraph("Detailed Accessibility Issues", styles['Heading1']))
                for i, issue in enumerate(analysis_result['issues'], 1):
                    story.append(Paragraph(f"Issue {i}: {issue.get('title', issue['guideline'])}", styles['Heading2']))
                    story.append(Paragraph(f"WCAG Guideline: {issue['guideline']} (Level {issue['level']})", styles['Normal']))
                    story.append(Paragraph(f"Severity: {issue['severity']}", styles['Normal']))
                    story.append(Paragraph(f"Description: {issue['description']}", styles['Normal']))
                    story.append(Paragraph(f"Location: {issue['location']}", styles['Normal']))
                    story.append(Paragraph(f"Recommendation: {issue['recommendation']}", styles['Normal']))
                    if issue.get('wcag_reference'):
                        story.append(Paragraph(f"WCAG Reference: {issue['wcag_reference']}", styles['Normal']))
                    story.append(Spacer(1, 12))
            
            # Recommendations
            if analysis_result.get('recommendations'):
                story.append(Paragraph("Priority Recommendations", styles['Heading1']))
                for i, rec in enumerate(analysis_result['recommendations'], 1):
                    story.append(Paragraph(f"{i}. {rec}", styles['Normal']))
                story.append(Spacer(1, 16))
            
            # Footer
            story.append(Paragraph("Generated by Google Cloud Accessibility Compliance System", styles['Normal']))
            story.append(Paragraph("Powered by Document AI and Gemini", styles['Normal']))
            
            doc.build(story)
            logger.info(f"PDF report generated: {tmp_file.name}")
            return tmp_file.name
            
    except Exception as e:
        logger.error(f"Error generating PDF report: {e}")
        raise e


@functions_framework.cloud_event
def process_accessibility_compliance(cloud_event):
    """
    Main Cloud Function to process document accessibility compliance.
    Triggered by Cloud Storage object creation events.
    """
    try:
        # Extract file information from Cloud Storage event
        event_data = cloud_event.data
        bucket_name = event_data["bucket"]
        file_name = event_data["name"]
        
        logger.info(f"Processing Cloud Storage event - Bucket: {bucket_name}, File: {file_name}")
        
        # Only process files in the uploads folder
        if not file_name.startswith("uploads/"):
            logger.info(f"Skipping file {file_name} - not in uploads folder")
            return
        
        # Skip placeholder files
        if file_name.endswith(".placeholder"):
            logger.info(f"Skipping placeholder file {file_name}")
            return
        
        logger.info(f"Starting accessibility analysis for: {file_name}")
        
        # Download file from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        if not blob.exists():
            logger.error(f"File {file_name} does not exist in bucket {bucket_name}")
            return
        
        file_content = blob.download_as_bytes()
        logger.info(f"Downloaded file {file_name} - Size: {len(file_content)} bytes")
        
        # Process with Document AI
        processor_path = PROCESSOR_ID
        logger.info(f"Processing with Document AI processor: {processor_path}")
        document_text, layout_data = process_document_with_docai(file_content, processor_path)
        
        # Analyze accessibility with Gemini
        logger.info("Starting Gemini accessibility analysis")
        accessibility_analysis = analyze_accessibility_with_gemini(document_text, layout_data)
        
        # Generate professional PDF report
        base_filename = os.path.basename(file_name)
        logger.info(f"Generating accessibility report for: {base_filename}")
        report_path = generate_accessibility_report(accessibility_analysis, base_filename)
        
        # Upload report to Cloud Storage
        report_filename = f"reports/{base_filename}_accessibility_report.pdf"
        report_blob = bucket.blob(report_filename)
        with open(report_path, 'rb') as report_file:
            report_blob.upload_from_file(report_file)
        logger.info(f"Uploaded PDF report: {report_filename}")
        
        # Upload JSON results for programmatic access
        json_filename = f"reports/{base_filename}_results.json"
        json_blob = bucket.blob(json_filename)
        
        # Add metadata to JSON results
        accessibility_analysis['metadata'] = {
            'original_file': file_name,
            'processed_date': os.environ.get('TIMESTAMP', 'N/A'),
            'processor_id': processor_path,
            'gemini_model': GEMINI_MODEL,
            'document_stats': {
                'pages': layout_data.get('pages', 0),
                'characters': layout_data.get('total_characters', 0),
                'tables': len(layout_data.get('tables', [])),
                'forms': len(layout_data.get('form_fields', [])),
                'paragraphs': len(layout_data.get('paragraphs', []))
            }
        }
        
        json_blob.upload_from_string(json.dumps(accessibility_analysis, indent=2))
        logger.info(f"Uploaded JSON results: {json_filename}")
        
        # Move original file to processed folder for archival
        processed_filename = f"processed/{base_filename}"
        processed_blob = bucket.blob(processed_filename)
        bucket.copy_blob(blob, bucket, processed_blob.name)
        blob.delete()
        logger.info(f"Moved original file to: {processed_filename}")
        
        # Clean up temporary files
        if os.path.exists(report_path):
            os.unlink(report_path)
        
        # Log completion summary
        total_issues = accessibility_analysis.get('total_issues', 0)
        critical_issues = accessibility_analysis.get('critical_issues', 0)
        overall_score = accessibility_analysis.get('overall_score', 'Unknown')
        
        logger.info(f"✅ Accessibility analysis completed for {file_name}")
        logger.info(f"Results: {overall_score} score, {total_issues} total issues, {critical_issues} critical issues")
        logger.info(f"Reports available at: gs://{bucket_name}/{report_filename}")
        
        return {
            'status': 'success',
            'file': file_name,
            'report': report_filename,
            'results': json_filename,
            'summary': {
                'overall_score': overall_score,
                'total_issues': total_issues,
                'critical_issues': critical_issues
            }
        }
        
    except Exception as e:
        logger.error(f"Error processing {file_name}: {str(e)}", exc_info=True)
        # Don't re-raise to avoid function retry on permanent errors
        return {
            'status': 'error',
            'file': file_name,
            'error': str(e)
        }