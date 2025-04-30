__copyright__ = """
Copyright 2025 Diego Broetto.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at:

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""
__license__ = "Apache 2.0"
__author__ = "Diego Broetto"
__version__ = "1.0"

import boto3
import json
import os
import time
import logging
from datetime import datetime, timezone

# Logger configuration
logger = logging.getLogger()
logger.setLevel(logging.INFO)

region = os.getenv('aws_region')
environment = os.getenv('environment')

ssm_client = boto3.client("ssm", region_name=region)
ec2_client = boto3.client("ec2", region_name=region)


def get_instance_details(instance_id):
    """
    Retrieve detailed information about an EC2 instance.
    """
    response = ec2_client.describe_instances(InstanceIds=[instance_id])
    return response['Reservations'][0]['Instances'][0]


def is_new_instance(instance, threshold_minutes=10):
    """
    Determine whether an EC2 instance is considered 'new' based on the creation time
    of its root EBS volume.
    """
    root_volume_id = instance["BlockDeviceMappings"][0]["Ebs"]["VolumeId"]
    logger.info(f"Root volume of the instance: {root_volume_id}")

    volume_response = ec2_client.describe_volumes(VolumeIds=[root_volume_id])
    volume_creation_time = volume_response["Volumes"][0]["CreateTime"].replace(tzinfo=timezone.utc)
    current_time = datetime.now(timezone.utc)

    time_since_creation = (current_time - volume_creation_time).total_seconds() / 60
    return time_since_creation <= threshold_minutes


def wait_for_ssm(instance_id, timeout_seconds=120, interval=10):
    """
    Wait until the instance is registered and available in AWS Systems Manager (SSM).
    """
    attempts = timeout_seconds // interval
    for attempt in range(attempts):
        response = ssm_client.describe_instance_information(
            Filters=[{"Key": "InstanceIds", "Values": [instance_id]}]
        )
        if response["InstanceInformationList"]:
            return True
        logger.info(f"[{attempt + 1}/{attempts}] Instance {instance_id} is not yet registered in SSM... waiting {interval}s")
        time.sleep(interval)
    return False


def send_ssm_command(instance_id):
    """
    Send an SSM command to the specified instance using a predefined document.
    """
    response = ssm_client.send_command(
        DocumentName="aws_join_linux",
        InstanceIds=[instance_id],
        Comment="Automatic execution via EventBridge when instance enters running state",
    )
    return response["Command"]["CommandId"]


def lambda_handler(event, context):
    """
    AWS Lambda function handler triggered by EC2 state change events.
    Validates if the instance is new and triggers an SSM command if applicable.
    """
    try:
        instance_id = event["detail"]["instance-id"]
        logger.info(f"Instance {instance_id} changed to 'running'. Checking if it's new...")

        instance = get_instance_details(instance_id)

        if not is_new_instance(instance):
            logger.info("Instance is not new. Skipping execution.")
            return {
                "statusCode": 200,
                "body": json.dumps({
                    "message": "Instance is not new (based on EBS volume). No action was taken.",
                    "instance_id": instance_id
                })
            }

        logger.info(f"Instance {instance_id} is new! Checking if it's registered in SSM...")

        if not wait_for_ssm(instance_id):
            logger.warning(f"Timeout! Instance {instance_id} did not become available in SSM in time.")
            return {
                "statusCode": 400,
                "body": json.dumps({
                    "message": "Instance did not become ready in SSM in time.",
                    "instance_id": instance_id
                })
            }

        logger.info(f"Instance {instance_id} registered in SSM! Sending command...")

        command_id = send_ssm_command(instance_id)

        logger.info(f"SSM command sent successfully to instance {instance_id}. Command ID: {command_id}")

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "SSM command sent successfully!",
                "instance_id": instance_id,
                "command_id": command_id
            })
        }

    except Exception as e:
        logger.error(f"Error executing Lambda: {str(e)}", exc_info=True)
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }
