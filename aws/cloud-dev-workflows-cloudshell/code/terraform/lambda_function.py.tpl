"""
Lambda function to initialize CodeCommit repository with sample content.

This function creates initial files in the CodeCommit repository to provide
a starting point for development teams using the cloud-based workflow.
"""

import json
import boto3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
codecommit = boto3.client('codecommit')

def handler(event, context):
    """
    Lambda handler function to initialize CodeCommit repository.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        dict: Response with status and message
    """
    try:
        repository_name = "${repository_name}"
        project_name = "${project_name}"
        environment = "${environment}"
        
        logger.info(f"Initializing repository: {repository_name}")
        
        # Create README.md content
        readme_content = f"""# {project_name.title()} - Cloud Development Workflow

This repository demonstrates cloud-based development workflows using AWS CloudShell and CodeCommit.

## Project Information
- **Project**: {project_name}
- **Environment**: {environment}
- **Repository**: {repository_name}
- **Created**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} UTC

## Getting Started

### Prerequisites
1. Access to AWS CloudShell
2. IAM permissions for CodeCommit
3. Git configured with AWS credential helper

### Setup Instructions

1. **Launch CloudShell**:
   ```bash
   # Access CloudShell from AWS Management Console
   # Wait for environment initialization
   ```

2. **Configure Git**:
   ```bash
   git config --global credential.helper '!aws codecommit credential-helper $@'
   git config --global credential.UseHttpPath true
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   ```

3. **Clone Repository**:
   ```bash
   git clone {repository_name}
   cd {repository_name}
   ```

4. **Start Developing**:
   ```bash
   # Create your application code
   # Commit and push changes
   git add .
   git commit -m "Your commit message"
   git push origin main
   ```

## Development Workflow

### Feature Development
1. Create feature branch: `git checkout -b feature/feature-name`
2. Develop and test your changes
3. Commit changes: `git commit -m "Add feature description"`
4. Push branch: `git push origin feature/feature-name`
5. Create pull request for review
6. Merge to main after approval

### Best Practices
- Use descriptive commit messages
- Keep commits focused and atomic
- Write tests for new functionality
- Update documentation as needed
- Follow code review process

## Project Structure

```
{repository_name}/
├── src/                 # Source code
├── tests/              # Test files
├── docs/               # Documentation
├── scripts/            # Utility scripts
├── .gitignore          # Git ignore patterns
└── README.md           # This file
```

## Resources

- [AWS CloudShell User Guide](https://docs.aws.amazon.com/cloudshell/latest/userguide/)
- [AWS CodeCommit Documentation](https://docs.aws.amazon.com/codecommit/)
- [Git Documentation](https://git-scm.com/doc)

## Support

For issues with this repository or development environment:
1. Check AWS CloudShell documentation
2. Verify IAM permissions
3. Contact your development team lead
"""

        # Create .gitignore content
        gitignore_content = """# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*$py.class

# C extensions
*.so

# Distribution / packaging
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# PyInstaller
*.manifest
*.spec

# Installer logs
pip-log.txt
pip-delete-this-directory.txt

# Unit test / coverage reports
htmlcov/
.tox/
.coverage
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover
.hypothesis/
.pytest_cache/

# Translations
*.mo
*.pot

# Django stuff:
*.log
local_settings.py
db.sqlite3

# Flask stuff:
instance/
.webassets-cache

# Scrapy stuff:
.scrapy

# Sphinx documentation
docs/_build/

# PyBuilder
target/

# Jupyter Notebook
.ipynb_checkpoints

# pyenv
.python-version

# celery beat schedule file
celerybeat-schedule

# SageMath parsed files
*.sage.py

# Environments
.env
.venv
env/
venv/
ENV/
env.bak/
venv.bak/

# Spyder project settings
.spyderproject
.spyproject

# Rope project settings
.ropeproject

# mkdocs documentation
/site

# mypy
.mypy_cache/
.dmypy.json
dmypy.json

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Terraform
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl

# AWS
.aws/
"""

        # Create sample application
        app_content = f"""#!/usr/bin/env python3
\"\"\"
Sample application for {project_name} development workflow demonstration.

This application provides a simple example of cloud-based development
using AWS CloudShell and CodeCommit for version control.
\"\"\"

import sys
import json
from datetime import datetime
from typing import Dict, Any

def get_environment_info() -> Dict[str, Any]:
    \"\"\"
    Get information about the current environment.
    
    Returns:
        dict: Environment information
    \"\"\"
    return {{
        "project": "{project_name}",
        "environment": "{environment}",
        "repository": "{repository_name}",
        "timestamp": datetime.now().isoformat(),
        "python_version": sys.version,
    }}

def main() -> int:
    \"\"\"
    Main application entry point.
    
    Returns:
        int: Exit code
    \"\"\"
    print(f"Welcome to {{get_environment_info()['project']}}!")
    print("Cloud-based development workflow demo")
    print("-" * 40)
    
    env_info = get_environment_info()
    print(json.dumps(env_info, indent=2))
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
"""

        # Check if repository exists and has commits
        try:
            response = codecommit.get_repository(repositoryName=repository_name)
            logger.info(f"Repository exists: {response['repositoryMetadata']['repositoryName']}")
            
            # Try to get the main branch
            try:
                codecommit.get_branch(repositoryName=repository_name, branchName='main')
                logger.info("Repository already has commits, skipping initialization")
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Repository already initialized',
                        'repository': repository_name
                    })
                }
            except codecommit.exceptions.BranchDoesNotExistException:
                logger.info("Repository exists but has no commits, proceeding with initialization")
        
        except codecommit.exceptions.RepositoryDoesNotExistException:
            logger.error(f"Repository {repository_name} does not exist")
            return {
                'statusCode': 404,
                'body': json.dumps({
                    'error': f'Repository {repository_name} not found'
                })
            }
        
        # Create initial commit with multiple files
        response = codecommit.create_commit(
            repositoryName=repository_name,
            branchName='main',
            parentCommitId='',
            authorName='AWS Lambda',
            email='lambda@aws.amazon.com',
            commitMessage=f'''Initial commit for {project_name}

- Add README.md with project documentation
- Add .gitignore for common file patterns  
- Add sample Python application
- Configure repository for cloud-based development workflow

Repository: {repository_name}
Environment: {environment}
Created: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} UTC''',
            putFiles=[
                {
                    'filePath': 'README.md',
                    'fileContent': readme_content.encode('utf-8')
                },
                {
                    'filePath': '.gitignore',
                    'fileContent': gitignore_content.encode('utf-8')
                },
                {
                    'filePath': 'src/app.py',
                    'fileContent': app_content.encode('utf-8')
                }
            ]
        )
        
        logger.info(f"Successfully initialized repository with commit: {response['commitId']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Repository successfully initialized',
                'repository': repository_name,
                'commitId': response['commitId'],
                'files_created': ['README.md', '.gitignore', 'src/app.py']
            })
        }
        
    except Exception as e:
        logger.error(f"Error initializing repository: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Failed to initialize repository: {str(e)}'
            })
        }