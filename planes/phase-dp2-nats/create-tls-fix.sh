#!/bin/bash

set -e

NAMESPACE=${1:-data-plane}

echo "Creating TLS certificates for NATS in namespace: $NAMESPACE"

# Create a simple TLS certificate using a different method
# that works on Windows/WSL

# Method 1: Use kubectl create secret tls (if available)
if command -v kubectl &> /dev/null; then
    echo "Attempting to create TLS secret using kubectl..."
    
    # Create a temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Generate a simple self-signed certificate using a method that works on Windows
    # Using PowerShell if available, or alternative methods
    
    if command -v powershell.exe &> /dev/null; then
        echo "Using PowerShell to generate certificates..."
        powershell.exe -Command "
            \$cert = New-SelfSignedCertificate -DnsName 'nats.data-plane.svc.cluster.local', 'nats' -CertStoreLocation 'Cert:\CurrentUser\My'
            Export-Certificate -Cert \$cert -FilePath '.\tls.crt' -Type CERT
            \$certKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey(\$cert)
            \$keyBytes = \$certKey.Key.Export([System.Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
            [System.IO.File]::WriteAllBytes('.\tls.key', \$keyBytes)
        " 2>/dev/null || true
    fi
    
    # If PowerShell method didn't work or files don't exist, create dummy certificates
    if [ ! -f "tls.crt" ] || [ ! -f "tls.key" ]; then
        echo "Creating dummy certificates for testing..."
        echo "-----BEGIN CERTIFICATE-----" > tls.crt
        echo "DUMMY CERTIFICATE - FOR TESTING ONLY" >> tls.crt
        echo "-----END CERTIFICATE-----" >> tls.crt
        
        echo "-----BEGIN PRIVATE KEY-----" > tls.key
        echo "DUMMY PRIVATE KEY - FOR TESTING ONLY" >> tls.key
        echo "-----END PRIVATE KEY-----" >> tls.key
        
        echo "-----BEGIN CERTIFICATE-----" > ca.crt
        echo "DUMMY CA CERTIFICATE - FOR TESTING ONLY" >> ca.crt
        echo "-----END CERTIFICATE-----" >> ca.crt
    fi
    
    # Create the Kubernetes secret
    kubectl create secret generic nats-tls -n "$NAMESPACE" \
        --from-file=tls.crt=./tls.crt \
        --from-file=tls.key=./tls.key \
        --from-file=ca.crt=./ca.crt 2>/dev/null || \
    kubectl create secret generic nats-tls -n "$NAMESPACE" \
        --from-literal=tls.crt="-----BEGIN CERTIFICATE-----\nDUMMY\n-----END CERTIFICATE-----" \
        --from-literal=tls.key="-----BEGIN PRIVATE KEY-----\nDUMMY\n-----END PRIVATE KEY-----" \
        --from-literal=ca.crt="-----BEGIN CERTIFICATE-----\nDUMMY\n-----END CERTIFICATE-----"
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
    
    echo "TLS secret created successfully (using dummy certificates for testing)"
else
    echo "kubectl not found. Cannot create TLS secret."
    exit 1
fi