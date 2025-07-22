"""
Setup configuration for Comprehend Custom Models CDK Python application.

This setup file configures the Python package for deploying custom entity recognition
and classification models using Amazon Comprehend with AWS CDK.
"""

import setuptools
from pathlib import Path

# Read README for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements
requirements_path = Path(__file__).parent / "requirements.txt"
with open(requirements_path, encoding="utf-8") as fp:
    install_requires = [
        line.strip()
        for line in fp
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="comprehend-custom-models-cdk",
    version="1.0.0",
    
    description="CDK Python application for custom entity recognition and classification with Amazon Comprehend",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipe Generator",
    author_email="example@example.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=install_requires,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    entry_points={
        "console_scripts": [
            "cdk-comprehend=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "comprehend",
        "machine-learning",
        "nlp",
        "entity-recognition",
        "classification",
        "custom-models",
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/comprehend/latest/dg/custom-entity-recognition.html",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
)