"""
AWS Lambda function for converting Markdown files to HTML.

This function is triggered by S3 events when Markdown files are uploaded.
It downloads the file, converts it to HTML using the markdown2 library,
and uploads the result to the output S3 bucket.

Environment Variables:
    OUTPUT_BUCKET_NAME: Name of the S3 bucket for HTML output files

Author: AWS Recipe Generator
Version: 1.0.0
"""

import json
import boto3
import urllib.parse
import os
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3 = boto3.client('s3')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for converting Markdown files to HTML.
    
    This function is triggered by S3 PUT events on markdown files.
    It processes each uploaded file and converts it to HTML format.
    
    Args:
        event: S3 event data containing bucket and object information
        context: Lambda runtime context (unused)
        
    Returns:
        Dict containing status code and response message
        
    Raises:
        Exception: Re-raises any processing exceptions for Lambda error handling
    """
    try:
        logger.info(f"Processing S3 event with {len(event.get('Records', []))} records")
        
        # Process each S3 event record
        for record in event.get('Records', []):
            process_s3_record(record)
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Markdown conversion completed successfully',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        raise e


def process_s3_record(record: Dict[str, Any]) -> None:
    """
    Process a single S3 event record.
    
    Args:
        record: Individual S3 event record containing bucket and object info
        
    Raises:
        Exception: If file processing fails
    """
    try:
        # Extract bucket and object information from S3 event
        input_bucket = record['s3']['bucket']['name']
        input_key = urllib.parse.unquote_plus(
            record['s3']['object']['key'], encoding='utf-8'
        )
        
        logger.info(f"Processing file: {input_key} from bucket: {input_bucket}")
        
        # Verify file is a markdown file
        if not is_markdown_file(input_key):
            logger.info(f"Skipping non-markdown file: {input_key}")
            return
            
        # Download and convert the markdown file
        markdown_content = download_markdown_file(input_bucket, input_key)
        html_content = convert_markdown_to_html(markdown_content, input_key)
        
        # Upload the converted HTML file
        output_key = generate_output_filename(input_key)
        upload_html_file(html_content, output_key, input_key)
        
        logger.info(f"Successfully converted {input_key} to {output_key}")
        
    except Exception as e:
        logger.error(f"Error processing file {input_key}: {str(e)}")
        raise e


def is_markdown_file(filename: str) -> bool:
    """
    Check if the file is a Markdown file based on its extension.
    
    Args:
        filename: The name/path of the file to check
        
    Returns:
        True if the file has a Markdown extension, False otherwise
    """
    markdown_extensions = ('.md', '.markdown', '.mdown', '.mkdn', '.mkd')
    return filename.lower().endswith(markdown_extensions)


def download_markdown_file(bucket: str, key: str) -> str:
    """
    Download a Markdown file from S3 and return its content.
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        
    Returns:
        String content of the Markdown file
        
    Raises:
        Exception: If download fails or content cannot be decoded
    """
    try:
        logger.info(f"Downloading s3://{bucket}/{key}")
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        logger.info(f"Downloaded {len(content)} characters from {key}")
        return content
        
    except Exception as e:
        logger.error(f"Failed to download file s3://{bucket}/{key}: {str(e)}")
        raise e


def convert_markdown_to_html(markdown_text: str, source_filename: str = "") -> str:
    """
    Convert markdown text to HTML using markdown2 library with enhanced features.
    
    Args:
        markdown_text: The Markdown content to convert
        source_filename: Original filename for title generation
        
    Returns:
        Complete HTML document with styling and converted content
    """
    try:
        # Try to import and use markdown2 library
        import markdown2
        
        logger.info("Converting markdown to HTML using markdown2 library")
        
        # Configure markdown2 with useful extras for enhanced formatting
        html_body = markdown2.markdown(
            markdown_text,
            extras=[
                'code-friendly',      # Better code block handling
                'fenced-code-blocks', # Support for ``` code blocks
                'tables',            # Support for markdown tables
                'strike',            # Support for ~~strikethrough~~
                'task-list',         # Support for - [ ] task lists
                'header-ids',        # Add IDs to headers for linking
                'footnotes',         # Support for footnotes
                'smarty-pants'       # Smart quotes and dashes
            ]
        )
        
    except ImportError:
        logger.warning("markdown2 library not available, using basic conversion")
        html_body = convert_markdown_basic(markdown_text)
    
    # Generate document title from filename or use default
    title = generate_document_title(source_filename)
    
    # Create complete HTML document with professional styling
    full_html = create_html_document(html_body, title)
    
    logger.info(f"Generated HTML document with {len(full_html)} characters")
    return full_html


def convert_markdown_basic(markdown_text: str) -> str:
    """
    Basic Markdown to HTML conversion using string operations.
    
    This is a fallback method when markdown2 library is not available.
    Supports basic formatting like headers, bold, italic, and code blocks.
    
    Args:
        markdown_text: Markdown content to convert
        
    Returns:
        Basic HTML content (body only, no document structure)
    """
    html = markdown_text
    
    # Convert headers (must be done in order from h6 to h1)
    html = html.replace('\n###### ', '\n<h6>').replace('###### ', '<h6>')
    html = html.replace('\n##### ', '\n<h5>').replace('##### ', '<h5>')
    html = html.replace('\n#### ', '\n<h4>').replace('#### ', '<h4>')
    html = html.replace('\n### ', '\n<h3>').replace('### ', '<h3>')
    html = html.replace('\n## ', '\n<h2>').replace('## ', '<h2>')
    html = html.replace('\n# ', '\n<h1>').replace('# ', '<h1>')
    
    # Convert bold and italic text
    html = convert_emphasis(html)
    
    # Convert code blocks and inline code
    html = convert_code_blocks(html)
    
    # Convert line breaks and paragraphs
    html = convert_paragraphs(html)
    
    return html


def convert_emphasis(text: str) -> str:
    """Convert bold and italic markdown to HTML."""
    # Convert bold text (**text** or __text__)
    import re
    text = re.sub(r'\*\*(.*?)\*\*', r'<strong>\1</strong>', text)
    text = re.sub(r'__(.*?)__', r'<strong>\1</strong>', text)
    
    # Convert italic text (*text* or _text_)
    text = re.sub(r'\*(.*?)\*', r'<em>\1</em>', text)
    text = re.sub(r'_(.*?)_', r'<em>\1</em>', text)
    
    return text


def convert_code_blocks(text: str) -> str:
    """Convert code blocks and inline code to HTML."""
    import re
    
    # Convert inline code (`code`)
    text = re.sub(r'`(.*?)`', r'<code>\1</code>', text)
    
    # Convert code blocks (```code```)
    text = re.sub(r'```(.*?)```', r'<pre><code>\1</code></pre>', text, flags=re.DOTALL)
    
    return text


def convert_paragraphs(text: str) -> str:
    """Convert line breaks to HTML paragraphs."""
    # Convert double line breaks to paragraph breaks
    paragraphs = text.split('\n\n')
    html_paragraphs = []
    
    for paragraph in paragraphs:
        if paragraph.strip():
            # Convert single line breaks to <br> within paragraphs
            paragraph = paragraph.replace('\n', '<br>')
            # Don't wrap headers in <p> tags
            if not paragraph.strip().startswith('<h'):
                paragraph = f'<p>{paragraph}</p>'
            html_paragraphs.append(paragraph)
    
    return '\n\n'.join(html_paragraphs)


def generate_document_title(filename: str) -> str:
    """
    Generate a document title from the filename.
    
    Args:
        filename: Original filename
        
    Returns:
        Formatted title string
    """
    if not filename:
        return "Converted Document"
    
    # Remove path and extension
    name = os.path.splitext(os.path.basename(filename))[0]
    
    # Convert hyphens and underscores to spaces and title case
    title = name.replace('-', ' ').replace('_', ' ').title()
    
    return title if title else "Converted Document"


def create_html_document(body_content: str, title: str) -> str:
    """
    Create a complete HTML document with professional styling.
    
    Args:
        body_content: HTML content for the body
        title: Document title
        
    Returns:
        Complete HTML document string
    """
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="generator" content="AWS Lambda Markdown Converter">
    <title>{title}</title>
    <style>
        /* Professional document styling */
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            max-width: 900px;
            margin: 0 auto;
            padding: 2rem;
            color: #333;
            background-color: #fff;
        }}
        
        h1, h2, h3, h4, h5, h6 {{
            margin-top: 2rem;
            margin-bottom: 1rem;
            font-weight: 600;
            line-height: 1.25;
        }}
        
        h1 {{ font-size: 2.5rem; border-bottom: 2px solid #eaecef; padding-bottom: 0.5rem; }}
        h2 {{ font-size: 2rem; border-bottom: 1px solid #eaecef; padding-bottom: 0.3rem; }}
        h3 {{ font-size: 1.5rem; }}
        h4 {{ font-size: 1.25rem; }}
        h5 {{ font-size: 1rem; }}
        h6 {{ font-size: 0.875rem; }}
        
        p {{ margin-bottom: 1rem; }}
        
        code {{
            background-color: rgba(175, 184, 193, 0.2);
            padding: 0.2rem 0.4rem;
            border-radius: 3px;
            font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
            font-size: 0.9em;
        }}
        
        pre {{
            background-color: #f6f8fa;
            padding: 1rem;
            border-radius: 6px;
            overflow-x: auto;
            margin: 1rem 0;
            border: 1px solid #e1e4e8;
        }}
        
        pre code {{
            background-color: transparent;
            padding: 0;
        }}
        
        table {{
            border-collapse: collapse;
            width: 100%;
            margin: 1rem 0;
            border: 1px solid #e1e4e8;
        }}
        
        th, td {{
            border: 1px solid #e1e4e8;
            padding: 0.75rem;
            text-align: left;
        }}
        
        th {{
            background-color: #f6f8fa;
            font-weight: 600;
        }}
        
        tr:nth-child(even) {{
            background-color: #f6f8fa;
        }}
        
        blockquote {{
            margin: 1rem 0;
            padding: 0 1rem;
            color: #6a737d;
            border-left: 4px solid #dfe2e5;
        }}
        
        a {{
            color: #0066cc;
            text-decoration: none;
        }}
        
        a:hover {{
            text-decoration: underline;
        }}
        
        .document-meta {{
            font-size: 0.875rem;
            color: #6a737d;
            border-top: 1px solid #e1e4e8;
            margin-top: 3rem;
            padding-top: 1rem;
            text-align: center;
        }}
    </style>
</head>
<body>
    {body_content}
    
    <div class="document-meta">
        <p>Document converted by AWS Lambda • {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC</p>
    </div>
</body>
</html>"""


def generate_output_filename(input_key: str) -> str:
    """
    Generate the output filename by replacing the extension with .html.
    
    Args:
        input_key: S3 key of the input file
        
    Returns:
        Output filename with .html extension
    """
    # Remove the file extension and add .html
    name_without_ext = os.path.splitext(input_key)[0]
    return f"{name_without_ext}.html"


def upload_html_file(html_content: str, output_key: str, source_file: str) -> None:
    """
    Upload the converted HTML content to the output S3 bucket.
    
    Args:
        html_content: The HTML content to upload
        output_key: S3 key for the output file
        source_file: Original source filename for metadata
        
    Raises:
        Exception: If upload fails
    """
    try:
        output_bucket = os.environ['OUTPUT_BUCKET_NAME']
        
        logger.info(f"Uploading HTML to s3://{output_bucket}/{output_key}")
        
        # Upload with appropriate metadata
        s3.put_object(
            Bucket=output_bucket,
            Key=output_key,
            Body=html_content,
            ContentType='text/html',
            Metadata={
                'source-file': source_file,
                'conversion-timestamp': datetime.utcnow().isoformat(),
                'converter': 'lambda-markdown2',
                'content-length': str(len(html_content))
            },
            # Set cache control for web serving
            CacheControl='max-age=3600'
        )
        
        logger.info(f"Successfully uploaded {len(html_content)} bytes to {output_key}")
        
    except Exception as e:
        logger.error(f"Failed to upload HTML file: {str(e)}")
        raise e