#!/usr/bin/env python3
"""Find Airbyte API credentials"""
import subprocess
import json
import base64

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=15, shell=True)
    return r.stdout.strip(), r.stderr.strip()

# List all secrets in all namespaces
print("=== ALL SECRETS ===")
out, _ = run("sudo docker exec airbyte-abctl-control-plane kubectl get secrets --all-namespaces --no-headers")
for line in out.split("\n"):
    if "airbyte" in line.lower() or "auth" in line.lower() or "token" in line.lower():
        print(f"  {line}")

# Try various secret names and namespaces
for ns in ["airbyte-abctl", "default", "airbyte"]:
    for name in ["airbyte-abctl-auth-token", "airbyte-auth-token", "airbyte-abctl-instance-admin-token"]:
        out, err = run(f"sudo docker exec airbyte-abctl-control-plane kubectl get secret {name} -n {ns} -o json 2>/dev/null")
        if out and "kind" in out:
            data = json.loads(out)
            print(f"\nFOUND SECRET: {ns}/{name}")
            for k, v in data.get("data", {}).items():
                decoded = base64.b64decode(v).decode()
                print(f"  {k} = {decoded}")

# Check env vars in server pod
print("\n=== SERVER POD ENV (auth related) ===")
out, _ = run("sudo docker exec airbyte-abctl-control-plane kubectl get pods -n airbyte-abctl -l app.kubernetes.io/name=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null")
if out:
    server_pod = out.strip("'")
    env_out, _ = run(f"sudo docker exec airbyte-abctl-control-plane kubectl exec -n airbyte-abctl {server_pod} -- env 2>/dev/null")
    for line in env_out.split("\n"):
        if any(x in line.lower() for x in ["client", "secret", "token", "auth", "api_key"]):
            print(f"  {line}")
else:
    # Try listing pods
    out2, _ = run("sudo docker exec airbyte-abctl-control-plane kubectl get pods -n airbyte-abctl --no-headers")
    print(f"  Pods in airbyte-abctl: {out2[:500]}")

# Also try the Keycloak approach
print("\n=== KEYCLOAK/AUTH CONFIG ===")
out, _ = run("sudo docker exec airbyte-abctl-control-plane kubectl get configmaps -n airbyte-abctl --no-headers 2>/dev/null")
for line in out.split("\n"):
    if line.strip():
        print(f"  {line}")
