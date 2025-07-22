import json
import boto3
import urllib.parse
import os

def lambda_handler(event, context):
    """
    Lambda function to process video files uploaded to S3.
    Creates MediaConvert jobs for HLS and MP4 output formats.
    """
    # Initialize MediaConvert client with region-specific endpoint
    mediaconvert = boto3.client('mediaconvert', 
        endpoint_url=os.environ['MEDIACONVERT_ENDPOINT'])
    
    # Process each S3 event record
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        
        print(f"Processing video file: {key} from bucket: {bucket}")
        
        # Skip if not a video file
        if not key.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.m4v')):
            print(f"Skipping non-video file: {key}")
            continue
        
        # Extract filename without extension for output naming
        filename_without_ext = key.split('.')[0]
        
        # Create MediaConvert job settings
        job_settings = {
            "Role": os.environ['MEDIACONVERT_ROLE_ARN'],
            "Settings": {
                "Inputs": [{
                    "AudioSelectors": {
                        "Audio Selector 1": {
                            "Offset": 0,
                            "DefaultSelection": "DEFAULT",
                            "ProgramSelection": 1
                        }
                    },
                    "VideoSelector": {
                        "ColorSpace": "FOLLOW"
                    },
                    "FilterEnable": "AUTO",
                    "PsiControl": "USE_PSI",
                    "FilterStrength": 0,
                    "DeblockFilter": "DISABLED",
                    "DenoiseFilter": "DISABLED",
                    "TimecodeSource": "EMBEDDED",
                    "FileInput": f"s3://{bucket}/{key}"
                }],
                "OutputGroups": [
                    {
                        "Name": "Apple HLS",
                        "OutputGroupSettings": {
                            "Type": "HLS_GROUP_SETTINGS",
                            "HlsGroupSettings": {
                                "ManifestDurationFormat": "INTEGER",
                                "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/hls/{filename_without_ext}/",
                                "TimedMetadataId3Frame": "PRIV",
                                "CodecSpecification": "RFC_4281",
                                "OutputSelection": "MANIFESTS_AND_SEGMENTS",
                                "ProgramDateTimePeriod": 600,
                                "MinSegmentLength": 0,
                                "DirectoryStructure": "SINGLE_DIRECTORY",
                                "ProgramDateTime": "EXCLUDE",
                                "SegmentLength": 10,
                                "ManifestCompression": "NONE",
                                "ClientCache": "ENABLED",
                                "AudioOnlyHeader": "INCLUDE"
                            }
                        },
                        "Outputs": [
                            {
                                "VideoDescription": {
                                    "ScalingBehavior": "DEFAULT",
                                    "TimecodeInsertion": "DISABLED",
                                    "AntiAlias": "ENABLED",
                                    "Sharpness": 50,
                                    "CodecSettings": {
                                        "Codec": "H_264",
                                        "H264Settings": {
                                            "InterlaceMode": "PROGRESSIVE",
                                            "NumberReferenceFrames": 3,
                                            "Syntax": "DEFAULT",
                                            "Softness": 0,
                                            "GopClosedCadence": 1,
                                            "GopSize": 90,
                                            "Slices": 1,
                                            "GopBReference": "DISABLED",
                                            "SlowPal": "DISABLED",
                                            "SpatialAdaptiveQuantization": "ENABLED",
                                            "TemporalAdaptiveQuantization": "ENABLED",
                                            "FlickerAdaptiveQuantization": "DISABLED",
                                            "EntropyEncoding": "CABAC",
                                            "Bitrate": int(os.environ.get('VIDEO_BITRATE', ${video_bitrate})),
                                            "FramerateControl": "SPECIFIED",
                                            "RateControlMode": "CBR",
                                            "CodecProfile": "MAIN",
                                            "Telecine": "NONE",
                                            "MinIInterval": 0,
                                            "AdaptiveQuantization": "HIGH",
                                            "CodecLevel": "AUTO",
                                            "FieldEncoding": "PAFF",
                                            "SceneChangeDetect": "ENABLED",
                                            "QualityTuningLevel": "SINGLE_PASS",
                                            "FramerateConversionAlgorithm": "DUPLICATE_DROP",
                                            "UnregisteredSeiTimecode": "DISABLED",
                                            "GopSizeUnits": "FRAMES",
                                            "ParControl": "SPECIFIED",
                                            "NumberBFramesBetweenReferenceFrames": 2,
                                            "RepeatPps": "DISABLED",
                                            "FramerateNumerator": int(os.environ.get('VIDEO_FRAMERATE', ${video_framerate})),
                                            "FramerateDenominator": 1,
                                            "ParNumerator": 1,
                                            "ParDenominator": 1
                                        }
                                    },
                                    "AfdSignaling": "NONE",
                                    "DropFrameTimecode": "ENABLED",
                                    "RespondToAfd": "NONE",
                                    "ColorMetadata": "INSERT",
                                    "Width": int(os.environ.get('VIDEO_WIDTH', ${video_width})),
                                    "Height": int(os.environ.get('VIDEO_HEIGHT', ${video_height}))
                                },
                                "AudioDescriptions": [
                                    {
                                        "AudioTypeControl": "FOLLOW_INPUT",
                                        "CodecSettings": {
                                            "Codec": "AAC",
                                            "AacSettings": {
                                                "AudioDescriptionBroadcasterMix": "NORMAL",
                                                "Bitrate": 96000,
                                                "RateControlMode": "CBR",
                                                "CodecProfile": "LC",
                                                "CodingMode": "CODING_MODE_2_0",
                                                "RawFormat": "NONE",
                                                "SampleRate": 48000,
                                                "Specification": "MPEG4"
                                            }
                                        },
                                        "AudioSourceName": "Audio Selector 1",
                                        "LanguageCodeControl": "FOLLOW_INPUT"
                                    }
                                ],
                                "OutputSettings": {
                                    "HlsSettings": {
                                        "AudioGroupId": "program_audio",
                                        "AudioTrackType": "ALTERNATE_AUDIO_AUTO_SELECT_DEFAULT",
                                        "IFrameOnlyManifest": "EXCLUDE"
                                    }
                                },
                                "NameModifier": "_720p"
                            }
                        ]
                    },
                    {
                        "Name": "File Group",
                        "OutputGroupSettings": {
                            "Type": "FILE_GROUP_SETTINGS",
                            "FileGroupSettings": {
                                "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/mp4/"
                            }
                        },
                        "Outputs": [
                            {
                                "VideoDescription": {
                                    "Width": int(os.environ.get('VIDEO_WIDTH', ${video_width})),
                                    "Height": int(os.environ.get('VIDEO_HEIGHT', ${video_height})),
                                    "CodecSettings": {
                                        "Codec": "H_264",
                                        "H264Settings": {
                                            "Bitrate": int(os.environ.get('VIDEO_BITRATE', ${video_bitrate})),
                                            "RateControlMode": "CBR",
                                            "CodecProfile": "MAIN",
                                            "GopSize": 90,
                                            "FramerateControl": "SPECIFIED",
                                            "FramerateNumerator": int(os.environ.get('VIDEO_FRAMERATE', ${video_framerate})),
                                            "FramerateDenominator": 1
                                        }
                                    }
                                },
                                "AudioDescriptions": [
                                    {
                                        "CodecSettings": {
                                            "Codec": "AAC",
                                            "AacSettings": {
                                                "Bitrate": 96000,
                                                "SampleRate": 48000
                                            }
                                        },
                                        "AudioSourceName": "Audio Selector 1"
                                    }
                                ],
                                "ContainerSettings": {
                                    "Container": "MP4",
                                    "Mp4Settings": {
                                        "CslgAtom": "INCLUDE",
                                        "FreeSpaceBox": "EXCLUDE",
                                        "MoovPlacement": "PROGRESSIVE_DOWNLOAD"
                                    }
                                },
                                "NameModifier": "_720p"
                            }
                        ]
                    }
                ]
            }
        }
        
        # Create MediaConvert job
        try:
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            print(f"Successfully created MediaConvert job: {job_id} for file: {key}")
            
            # Log job configuration for debugging
            print(f"Job configuration - Bitrate: {os.environ.get('VIDEO_BITRATE', ${video_bitrate})}, "
                  f"Framerate: {os.environ.get('VIDEO_FRAMERATE', ${video_framerate})}, "
                  f"Resolution: {os.environ.get('VIDEO_WIDTH', ${video_width})}x{os.environ.get('VIDEO_HEIGHT', ${video_height})}")
            
        except Exception as e:
            print(f"Error creating MediaConvert job for {key}: {str(e)}")
            # Re-raise the exception to ensure Lambda shows as failed
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Video processing initiated successfully',
            'processed_files': len(event['Records'])
        })
    }