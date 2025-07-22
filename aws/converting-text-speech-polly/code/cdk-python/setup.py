"""
Setup configuration for Text-to-Speech Solutions with Amazon Polly CDK Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        install_requires = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#") and not line.startswith("-")
        ]
else:
    # Fallback requirements if requirements.txt is not found
    install_requires = [
        "aws-cdk-lib>=2.150.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ]

# Development dependencies
dev_requires = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "black>=22.0.0",
    "flake8>=5.0.0",
    "mypy>=1.0.0",
    "isort>=5.12.0",
    "autopep8>=2.0.0",
    "boto3-stubs[polly,s3,lambda,iam,logs,cloudfront,apigateway,events]>=1.34.0",
    "moto[polly,s3,lambda,iam]>=4.2.0",
]

# Documentation dependencies
docs_requires = [
    "sphinx>=5.0.0",
    "sphinx-rtd-theme>=1.2.0",
    "sphinxcontrib-mermaid>=0.9.0",
]

# Testing dependencies
test_requires = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "pytest-mock>=3.10.0",
    "moto[polly,s3,lambda,iam]>=4.2.0",
    "requests>=2.31.0",
]

setuptools.setup(
    name="text-to-speech-polly-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for Text-to-Speech Solutions using Amazon Polly",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Multimedia :: Sound/Audio :: Speech",
    ],
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    install_requires=install_requires,
    
    extras_require={
        "dev": dev_requires,
        "docs": docs_requires,
        "test": test_requires,
        "all": dev_requires + docs_requires + test_requires,
    },
    
    entry_points={
        "console_scripts": [
            "deploy-polly-stack=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
        "AWS Polly Documentation": "https://docs.aws.amazon.com/polly/",
    },
    
    keywords=[
        "aws",
        "cdk",
        "polly",
        "text-to-speech",
        "tts",
        "speech-synthesis",
        "accessibility",
        "neural-voices",
        "ssml",
        "serverless",
        "lambda",
        "s3",
        "cloudfront",
        "api-gateway"
    ],
    
    include_package_data=True,
    
    zip_safe=False,
    
    # Additional metadata
    license="MIT",
    platforms=["any"],
    
    # Package data to include
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # CDK specific configuration
    options={
        "build_ext": {
            "inplace": True,
        },
    },
)

# Additional configuration for development tools
# This can be used by IDEs and development tools

# Black configuration (code formatting)
black_config = {
    "line-length": 88,
    "target-version": ["py38", "py39", "py310", "py311"],
    "include": r"\.pyi?$",
    "exclude": r"""
    /(
        \.eggs
      | \.git
      | \.hg
      | \.mypy_cache
      | \.tox
      | \.venv
      | _build
      | buck-out
      | build
      | dist
      | cdk.out
    )/
    """,
}

# isort configuration (import sorting)
isort_config = {
    "profile": "black",
    "multi_line_output": 3,
    "line_length": 88,
    "known_third_party": ["aws_cdk", "constructs", "boto3"],
}

# mypy configuration (type checking)
mypy_config = {
    "python_version": "3.8",
    "warn_return_any": True,
    "warn_unused_configs": True,
    "disallow_untyped_defs": True,
    "disallow_incomplete_defs": True,
    "check_untyped_defs": True,
    "disallow_untyped_decorators": True,
    "no_implicit_optional": True,
    "warn_redundant_casts": True,
    "warn_unused_ignores": True,
    "warn_no_return": True,
    "warn_unreachable": True,
    "strict_equality": True,
}

# pytest configuration
pytest_config = {
    "testpaths": ["tests"],
    "python_files": ["test_*.py", "*_test.py"],
    "python_functions": ["test_*"],
    "addopts": [
        "--cov=.",
        "--cov-report=html",
        "--cov-report=term-missing",
        "--cov-fail-under=80",
        "-v"
    ],
    "markers": [
        "unit: Unit tests",
        "integration: Integration tests",
        "aws: Tests that require AWS credentials",
        "slow: Slow running tests",
    ],
}

# flake8 configuration (linting)
flake8_config = {
    "max-line-length": 88,
    "extend-ignore": ["E203", "W503"],
    "exclude": [
        ".git",
        "__pycache__",
        "build",
        "dist",
        "cdk.out",
        ".venv",
        ".eggs",
    ],
}