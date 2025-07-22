"""
Setup configuration for Edge AI Inference CDK Python Application
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "AWS CDK Python application for real-time edge AI inference with IoT Greengrass v2"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith("#"):
                # Remove version constraints for setup.py
                package = line.split(">=")[0].split("==")[0].split("<")[0]
                install_requires.append(package)

setuptools.setup(
    name="edge-ai-inference-cdk",
    version="1.0.0",
    
    author="AWS Solutions Architecture",
    author_email="solutions-team@aws.com",
    
    description="AWS CDK Python application for real-time edge AI inference",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/edge-ai-inference-cdk",
    
    packages=setuptools.find_packages(),
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "edge-computing",
        "machine-learning",
        "iot",
        "greengrass",
        "sagemaker",
        "inference",
        "real-time",
        "eventbridge",
        "onnx",
    ],
    
    python_requires=">=3.8",
    
    install_requires=[
        "aws-cdk-lib>=2.100.0",
        "constructs>=10.0.0",
        "boto3>=1.30.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.950",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",
        ],
        "ml": [
            "onnxruntime>=1.16.0",
            "numpy>=1.24.0",
            "opencv-python-headless>=4.8.0",
        ],
        "validation": [
            "jsonschema>=4.17.0",
            "PyYAML>=6.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "edge-ai-inference=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/edge-ai-inference-cdk/issues",
        "Source": "https://github.com/aws-samples/edge-ai-inference-cdk",
        "Documentation": "https://docs.aws.amazon.com/greengrass/",
    },
    
    include_package_data=True,
    zip_safe=False,
)