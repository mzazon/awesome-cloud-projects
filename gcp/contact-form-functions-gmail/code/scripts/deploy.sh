#!/bin/bash

# Contact Form with Cloud Functions and Gmail API - Deployment Script
# This script deploys a serverless contact form backend using Google Cloud Functions
# and Gmail API integration for email notifications.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${PURPLE}=== $1 ===${NC}"
}

# Script metadata
SCRIPT_NAME="Contact Form Cloud Functions Deployment"
SCRIPT_VERSION="1.0"
RECIPE_NAME="contact-form-functions-gmail"

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="contact-form-handler"
DEFAULT_MEMORY="512Mi"
DEFAULT_TIMEOUT="60s"

# Configuration variables (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-$DEFAULT_REGION}"
FUNCTION_NAME="${FUNCTION_NAME:-$DEFAULT_FUNCTION_NAME}"
MEMORY="${MEMORY:-$DEFAULT_MEMORY}"
TIMEOUT="${TIMEOUT:-$DEFAULT_TIMEOUT}"
GMAIL_EMAIL="${GMAIL_EMAIL:-}"
DRY_RUN="${DRY_RUN:-false}"

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy a serverless contact form backend using Google Cloud Functions and Gmail API.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: $DEFAULT_REGION)
    -f, --function-name NAME      Cloud Function name (default: $DEFAULT_FUNCTION_NAME)
    -m, --memory MEMORY           Function memory allocation (default: $DEFAULT_MEMORY)
    -t, --timeout TIMEOUT         Function timeout (default: $DEFAULT_TIMEOUT)
    -e, --gmail-email EMAIL       Gmail address for receiving emails (required)
    -d, --dry-run                 Show what would be done without executing
    -h, --help                    Display this help message

ENVIRONMENT VARIABLES:
    PROJECT_ID                    Google Cloud Project ID
    REGION                        Deployment region
    FUNCTION_NAME                 Cloud Function name
    MEMORY                        Function memory allocation
    TIMEOUT                       Function timeout
    GMAIL_EMAIL                   Gmail address for receiving emails
    DRY_RUN                       Set to 'true' for dry-run mode

EXAMPLES:
    $0 --project-id my-project --gmail-email admin@example.com
    $0 -p my-project -e admin@example.com -r us-east1
    DRY_RUN=true $0 --project-id my-project --gmail-email admin@example.com

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -m|--memory)
                MEMORY="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -e|--gmail-email)
                GMAIL_EMAIL="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Function to validate prerequisites
validate_prerequisites() {
    log_section "Validating Prerequisites"
    
    # Check for required tools
    local required_tools=("gcloud" "python3" "pip3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed or not in PATH"
            exit 1
        fi
        log_info "✓ $tool is available"
    done
    
    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id or set PROJECT_ID environment variable"
        exit 1
    fi
    
    if [[ -z "$GMAIL_EMAIL" ]]; then
        log_error "Gmail email is required. Use --gmail-email or set GMAIL_EMAIL environment variable"
        exit 1
    fi
    
    # Validate email format
    if [[ ! "$GMAIL_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid email format: $GMAIL_EMAIL"
        exit 1
    fi
    
    log_info "✓ Project ID: $PROJECT_ID"
    log_info "✓ Gmail Email: $GMAIL_EMAIL"
    log_info "✓ Region: $REGION"
    log_info "✓ Function Name: $FUNCTION_NAME"
}

# Function to authenticate and set up gcloud
setup_gcloud() {
    log_section "Setting up Google Cloud SDK"
    
    # Check if already authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_warning "No active authentication found"
        if [[ "$DRY_RUN" == "false" ]]; then
            log_info "Initiating authentication..."
            gcloud auth login
        else
            log_info "[DRY RUN] Would initiate gcloud authentication"
        fi
    else
        log_info "✓ Already authenticated with gcloud"
    fi
    
    # Set default project
    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
        gcloud config set functions/region "$REGION"
    else
        log_info "[DRY RUN] Would set project to $PROJECT_ID and region to $REGION"
    fi
    
    log_success "Google Cloud SDK configured"
}

# Function to enable required APIs
enable_apis() {
    log_section "Enabling Required APIs"
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "gmail.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if [[ "$DRY_RUN" == "false" ]]; then
            gcloud services enable "$api" --quiet
        else
            log_info "[DRY RUN] Would enable $api"
        fi
    done
    
    log_success "Required APIs enabled"
}

# Function to setup OAuth credentials
setup_oauth_credentials() {
    log_section "Setting up OAuth 2.0 Credentials"
    
    local credentials_file="$HOME/Downloads/credentials.json"
    local token_file="token.pickle"
    
    # Check if credentials already exist
    if [[ -f "$credentials_file" && -f "$token_file" ]]; then
        log_info "✓ OAuth credentials and token already exist"
        return 0
    fi
    
    if [[ ! -f "$credentials_file" ]]; then
        log_warning "OAuth credentials not found at $credentials_file"
        cat << EOF

Please follow these steps to create OAuth 2.0 credentials:

1. Go to the Google Cloud Console: https://console.cloud.google.com/
2. Navigate to APIs & Credentials > Credentials
3. Click 'Create Credentials' > 'OAuth client ID'
4. Select 'Desktop application'
5. Name it 'Contact Form Gmail Client'
6. Download the credentials JSON file to: $credentials_file

EOF
        
        if [[ "$DRY_RUN" == "false" ]]; then
            read -p "Press Enter after completing the OAuth setup..."
            
            if [[ ! -f "$credentials_file" ]]; then
                log_error "Credentials file not found. Please complete the OAuth setup first."
                exit 1
            fi
        else
            log_info "[DRY RUN] Would wait for OAuth credentials setup"
            return 0
        fi
    fi
    
    # Install required Python packages
    log_info "Installing required Python packages..."
    if [[ "$DRY_RUN" == "false" ]]; then
        pip3 install --user google-auth==2.30.0 google-auth-oauthlib==1.2.1 \
            google-auth-httplib2==0.2.0 google-api-python-client==2.150.0
    else
        log_info "[DRY RUN] Would install Python packages for Gmail API"
    fi
    
    # Generate token if it doesn't exist
    if [[ ! -f "$token_file" && "$DRY_RUN" == "false" ]]; then
        log_info "Generating Gmail API access token..."
        
        # Create token generation script
        cat > generate_token.py << 'EOF'
import json
import pickle
import os
from google.auth.transport.requests import Request
from google_auth_oauthlib.flow import InstalledAppFlow

SCOPES = ['https://www.googleapis.com/auth/gmail.send']

def generate_token():
    creds = None
    if os.path.exists('token.pickle'):
        with open('token.pickle', 'rb') as token:
            creds = pickle.load(token)
    
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(
                'credentials.json', SCOPES)
            creds = flow.run_local_server(port=0)
        
        with open('token.pickle', 'wb') as token:
            pickle.dump(creds, token)
    
    print("Token generated successfully!")

if __name__ == '__main__':
    generate_token()
EOF
        
        # Copy credentials and generate token
        cp "$credentials_file" credentials.json
        python3 generate_token.py
        
        # Clean up
        rm -f generate_token.py credentials.json
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate Gmail API access token"
    fi
    
    log_success "OAuth credentials configured"
}

# Function to create Cloud Function source code
create_function_source() {
    log_section "Creating Cloud Function Source Code"
    
    local function_dir="contact-form-function"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$function_dir"
        cd "$function_dir"
    else
        log_info "[DRY RUN] Would create directory: $function_dir"
    fi
    
    # Create requirements.txt
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > requirements.txt << 'EOF'
google-auth==2.30.0
google-auth-oauthlib==1.2.1
google-auth-httplib2==0.2.0
google-api-python-client==2.150.0
functions-framework==3.8.0
EOF
    else
        log_info "[DRY RUN] Would create requirements.txt"
    fi
    
    # Create main function file
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > main.py << EOF
import json
import base64
import pickle
from email.message import EmailMessage
from googleapiclient.discovery import build
from google.auth.transport.requests import Request
import functions_framework

def load_credentials():
    """Load Gmail API credentials from token.pickle file"""
    with open('token.pickle', 'rb') as token:
        creds = pickle.load(token)
    
    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
    
    return creds

def send_email(name, email, subject, message):
    """Send email using Gmail API"""
    creds = load_credentials()
    service = build('gmail', 'v1', credentials=creds)
    
    # Create email message
    msg = EmailMessage()
    msg['Subject'] = f'Contact Form: {subject}'
    msg['From'] = 'me'  # 'me' represents the authenticated user
    msg['To'] = '$GMAIL_EMAIL'  # Configured recipient email
    
    # Email body with proper formatting
    email_body = f"""
New contact form submission:

Name: {name}
Email: {email}
Subject: {subject}

Message:
{message}

---
This email was sent automatically from your website contact form.
"""
    
    msg.set_content(email_body)
    
    # Send email
    raw_message = base64.urlsafe_b64encode(
        msg.as_bytes()).decode('utf-8')
    
    service.users().messages().send(
        userId='me',
        body={'raw': raw_message}
    ).execute()

@functions_framework.http
def contact_form_handler(request):
    """HTTP Cloud Function to handle contact form submissions"""
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    if request.method != 'POST':
        return ({'error': 'Method not allowed'}, 405, headers)
    
    try:
        # Parse form data
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return ({'error': 'Invalid JSON'}, 400, headers)
        
        # Extract form fields
        name = request_json.get('name', '').strip()
        email = request_json.get('email', '').strip()
        subject = request_json.get('subject', '').strip()
        message = request_json.get('message', '').strip()
        
        # Validate required fields
        if not all([name, email, subject, message]):
            return ({'error': 'All fields are required'}, 400, headers)
        
        # Basic email validation
        if '@' not in email or '.' not in email.split('@')[1]:
            return ({'error': 'Invalid email address'}, 400, headers)
        
        # Send email
        send_email(name, email, subject, message)
        
        return ({'success': True, 'message': 'Email sent successfully'}, 200, headers)
        
    except Exception as e:
        print(f'Error: {str(e)}')
        return ({'error': 'Internal server error'}, 500, headers)
EOF
    else
        log_info "[DRY RUN] Would create main.py with Gmail integration"
    fi
    
    # Copy token file if it exists
    if [[ -f "../token.pickle" && "$DRY_RUN" == "false" ]]; then
        cp ../token.pickle .
        log_info "✓ Token file copied to function directory"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would copy token.pickle to function directory"
    fi
    
    log_success "Cloud Function source code created"
}

# Function to deploy Cloud Function
deploy_function() {
    log_section "Deploying Cloud Function"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if [[ ! -d "contact-form-function" ]]; then
            log_error "Function directory not found. Please run the create_function_source step first."
            exit 1
        fi
        
        cd contact-form-function
        
        log_info "Deploying $FUNCTION_NAME with the following configuration:"
        log_info "  Memory: $MEMORY"
        log_info "  Timeout: $TIMEOUT"
        log_info "  Region: $REGION"
        
        gcloud functions deploy "$FUNCTION_NAME" \
            --gen2 \
            --runtime python312 \
            --trigger-http \
            --allow-unauthenticated \
            --memory "$MEMORY" \
            --timeout "$TIMEOUT" \
            --source . \
            --entry-point contact_form_handler \
            --region "$REGION" \
            --quiet
        
        # Get function URL
        FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
            --gen2 \
            --region "$REGION" \
            --format="value(serviceConfig.uri)")
        
        log_success "Cloud Function deployed successfully"
        log_info "Function URL: $FUNCTION_URL"
        
        # Store URL in environment file for later use
        echo "FUNCTION_URL=$FUNCTION_URL" > ../deployment.env
        
        cd ..
    else
        log_info "[DRY RUN] Would deploy Cloud Function with the following configuration:"
        log_info "  Name: $FUNCTION_NAME"
        log_info "  Memory: $MEMORY"
        log_info "  Timeout: $TIMEOUT"
        log_info "  Region: $REGION"
        log_info "  Runtime: python312"
        log_info "  Trigger: HTTP"
        log_info "  Authentication: Allow unauthenticated"
    fi
}

# Function to create sample HTML form
create_sample_form() {
    log_section "Creating Sample HTML Contact Form"
    
    local function_url="${FUNCTION_URL:-https://your-function-url}"
    
    if [[ "$DRY_RUN" == "false" && -f "deployment.env" ]]; then
        source deployment.env
        function_url="$FUNCTION_URL"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > contact-form.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Contact Form</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            max-width: 600px; 
            margin: 50px auto; 
            padding: 20px; 
            background-color: #f5f5f5;
        }
        .form-container { 
            background: white; 
            padding: 30px; 
            border-radius: 8px; 
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .form-group { margin-bottom: 20px; }
        label { 
            display: block; 
            margin-bottom: 8px; 
            font-weight: 600; 
            color: #333;
        }
        input, textarea { 
            width: 100%; 
            padding: 12px; 
            border: 2px solid #ddd; 
            border-radius: 6px; 
            font-size: 16px;
            transition: border-color 0.3s ease;
        }
        input:focus, textarea:focus { 
            outline: none; 
            border-color: #4285F4; 
        }
        button { 
            background: #4285F4; 
            color: white; 
            padding: 12px 24px; 
            border: none; 
            border-radius: 6px; 
            cursor: pointer; 
            font-size: 16px;
            font-weight: 600;
            transition: background-color 0.3s ease;
        }
        button:hover { background: #3367D6; }
        button:disabled { 
            background: #ccc; 
            cursor: not-allowed; 
        }
        .message { 
            margin-top: 20px; 
            padding: 15px; 
            border-radius: 6px; 
            font-weight: 500;
        }
        .success { 
            background: #d4edda; 
            color: #155724; 
            border: 1px solid #c3e6cb; 
        }
        .error { 
            background: #f8d7da; 
            color: #721c24; 
            border: 1px solid #f5c6cb; 
        }
        .loading {
            color: #6c757d;
        }
    </style>
</head>
<body>
    <div class="form-container">
        <h1>Contact Us</h1>
        <p>Send us a message and we'll get back to you as soon as possible.</p>
        
        <form id="contactForm">
            <div class="form-group">
                <label for="name">Full Name:</label>
                <input type="text" id="name" name="name" required>
            </div>
            
            <div class="form-group">
                <label for="email">Email Address:</label>
                <input type="email" id="email" name="email" required>
            </div>
            
            <div class="form-group">
                <label for="subject">Subject:</label>
                <input type="text" id="subject" name="subject" required>
            </div>
            
            <div class="form-group">
                <label for="message">Message:</label>
                <textarea id="message" name="message" rows="6" required></textarea>
            </div>
            
            <button type="submit" id="submitBtn">Send Message</button>
        </form>
        
        <div id="responseMessage"></div>
    </div>
    
    <script>
        document.getElementById('contactForm').addEventListener('submit', async function(e) {
            e.preventDefault();
            
            const submitBtn = document.getElementById('submitBtn');
            const responseDiv = document.getElementById('responseMessage');
            
            // Disable button and show loading state
            submitBtn.disabled = true;
            submitBtn.textContent = 'Sending...';
            responseDiv.innerHTML = '<div class="message loading">Sending your message...</div>';
            
            const formData = {
                name: document.getElementById('name').value,
                email: document.getElementById('email').value,
                subject: document.getElementById('subject').value,
                message: document.getElementById('message').value
            };
            
            try {
                const response = await fetch('$function_url', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(formData)
                });
                
                const result = await response.json();
                
                if (response.ok) {
                    responseDiv.innerHTML = '<div class="message success">✅ Message sent successfully! We\\'ll get back to you soon.</div>';
                    document.getElementById('contactForm').reset();
                } else {
                    responseDiv.innerHTML = '<div class="message error">❌ Error: ' + (result.error || 'Unknown error occurred') + '</div>';
                }
            } catch (error) {
                responseDiv.innerHTML = '<div class="message error">❌ Network error. Please check your connection and try again.</div>';
            } finally {
                // Re-enable button
                submitBtn.disabled = false;
                submitBtn.textContent = 'Send Message';
            }
        });
    </script>
</body>
</html>
EOF
        log_success "Sample HTML contact form created: contact-form.html"
    else
        log_info "[DRY RUN] Would create contact-form.html with function URL: $function_url"
    fi
}

# Function to perform deployment validation
validate_deployment() {
    log_section "Validating Deployment"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate the deployment"
        return 0
    fi
    
    # Check if function exists and is active
    if gcloud functions describe "$FUNCTION_NAME" --gen2 --region "$REGION" --format="value(state)" | grep -q "ACTIVE"; then
        log_success "✓ Cloud Function is active"
    else
        log_error "Cloud Function deployment validation failed"
        exit 1
    fi
    
    # Get function URL for testing
    local function_url
    if [[ -f "deployment.env" ]]; then
        source deployment.env
        function_url="$FUNCTION_URL"
    else
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --gen2 \
            --region "$REGION" \
            --format="value(serviceConfig.uri)")
    fi
    
    # Test function with a sample request
    log_info "Testing function with sample request..."
    local test_response
    test_response=$(curl -s -X POST "$function_url" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Test User",
            "email": "test@example.com",
            "subject": "Test Contact Form",
            "message": "This is a test message from the deployment script."
        }')
    
    if echo "$test_response" | grep -q "success"; then
        log_success "✓ Function test completed successfully"
    else
        log_warning "Function test returned unexpected response: $test_response"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_section "Deployment Summary"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        cat << EOF
${CYAN}DRY RUN SUMMARY${NC}
The following actions would be performed:

1. Enable Google Cloud APIs:
   - Cloud Functions API
   - Cloud Build API
   - Gmail API

2. Set up OAuth 2.0 credentials for Gmail API access

3. Deploy Cloud Function:
   - Name: $FUNCTION_NAME
   - Region: $REGION
   - Runtime: Python 3.12
   - Memory: $MEMORY
   - Timeout: $TIMEOUT
   - Trigger: HTTP (unauthenticated)

4. Create sample HTML contact form

5. Configure email notifications to: $GMAIL_EMAIL

EOF
        return 0
    fi
    
    local function_url
    if [[ -f "deployment.env" ]]; then
        source deployment.env
        function_url="$FUNCTION_URL"
    else
        function_url="Not available"
    fi
    
    cat << EOF
${GREEN}DEPLOYMENT COMPLETED SUCCESSFULLY${NC}

📋 Deployment Details:
   Project ID: $PROJECT_ID
   Region: $REGION
   Function Name: $FUNCTION_NAME
   Gmail Email: $GMAIL_EMAIL

🔗 Resources Created:
   Cloud Function: $FUNCTION_NAME
   Function URL: $function_url

📄 Files Created:
   contact-form.html - Sample HTML contact form
   deployment.env - Environment variables for cleanup

🧪 Next Steps:
   1. Open contact-form.html in your browser to test the form
   2. Submit a test message to verify email delivery
   3. Integrate the function URL into your website

💡 Tips:
   - Check your Gmail inbox for test emails
   - Monitor function logs in Cloud Console for debugging
   - Use the destroy.sh script to clean up resources when done

EOF
}

# Main deployment function
main() {
    log_section "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute deployment steps
    validate_prerequisites
    setup_gcloud
    enable_apis
    setup_oauth_credentials
    create_function_source
    deploy_function
    create_sample_form
    validate_deployment
    display_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Contact form deployment completed successfully!"
        log_info "Check your email at $GMAIL_EMAIL for test messages"
    else
        log_info "Dry run completed. Use without --dry-run to perform actual deployment."
    fi
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Exit code: $?"' ERR

# Execute main function with all arguments
main "$@"