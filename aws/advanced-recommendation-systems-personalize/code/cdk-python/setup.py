"""
Setup script for Amazon Personalize Recommendation System CDK Application

This setup.py file configures the Python package for the CDK application
that deploys a comprehensive recommendation system using Amazon Personalize.
"""

import setuptools
from typing import List

# Read the README file for the long description
def read_requirements() -> List[str]:
    """Read requirements from requirements.txt file."""
    with open("requirements.txt", "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]

def read_readme() -> str:
    """Read README file for long description."""
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return "Amazon Personalize Recommendation System CDK Application"

setuptools.setup(
    name="personalize-recommendation-system-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="developer@example.com",
    description="CDK Python application for Building Advanced Recommendation Systems with Amazon Personalize",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/personalize-recommendation-system",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/personalize-recommendation-system/issues",
        "Documentation": "https://docs.aws.amazon.com/personalize/",
        "Source Code": "https://github.com/aws-samples/personalize-recommendation-system",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "personalize-cdk=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "amazon-personalize",
        "recommendation-system",
        "machine-learning",
        "artificial-intelligence",
        "collaborative-filtering",
        "content-based-filtering",
        "a-b-testing",
        "serverless",
        "lambda",
        "api-gateway",
        "s3",
        "eventbridge",
        "cloudwatch",
        "infrastructure-as-code",
        "cloud-development-kit",
    ],
    platforms=["any"],
    license="MIT",
    license_files=["LICENSE"],
)

# Optional: Add custom commands for development
class DevelopCommand(setuptools.Command):
    """Custom command for development setup."""
    
    description = "Setup development environment"
    user_options = []
    
    def initialize_options(self):
        pass
    
    def finalize_options(self):
        pass
    
    def run(self):
        """Run development setup commands."""
        import subprocess
        import sys
        
        # Install development dependencies
        subprocess.check_call([
            sys.executable, "-m", "pip", "install", "-e", ".[dev,docs]"
        ])
        
        # Install pre-commit hooks if available
        try:
            subprocess.check_call(["pre-commit", "install"])
            print("Pre-commit hooks installed successfully")
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("Pre-commit not available, skipping hook installation")

# Add custom command
setuptools.setup(
    cmdclass={
        "develop": DevelopCommand,
    }
)