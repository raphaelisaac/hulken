#!/usr/bin/env python3
"""
Execute commands on GCP VM via IAP tunnel
Usage: python vm_command.py "docker ps"
"""
import subprocess
import sys
import os

VM_NAME = "instance-20260129-133637"
ZONE = "us-central1-a"
PROJECT = "hulken"

def run_vm_command(command):
    """Run a command on the VM using gcloud"""
    gcloud_path = r"C:\Users\Jarvis\AppData\Local\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"

    # Use gcloud compute ssh with --command
    full_cmd = [
        gcloud_path,
        "compute", "ssh",
        f"jarvis@{VM_NAME}",
        f"--zone={ZONE}",
        f"--project={PROJECT}",
        "--tunnel-through-iap",
        f"--command={command}"
    ]

    print(f"Executing: {command}")
    print("-" * 50)

    # Run and capture output
    result = subprocess.run(full_cmd, capture_output=True, text=True)

    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)

    return result.returncode

if __name__ == "__main__":
    if len(sys.argv) < 2:
        # Default: check Airbyte status
        commands = [
            "docker ps --format 'table {{.Names}}\\t{{.Status}}' | grep -E 'airbyte|NAME'",
            "pm2 status",
        ]
        for cmd in commands:
            run_vm_command(cmd)
    else:
        run_vm_command(" ".join(sys.argv[1:]))
