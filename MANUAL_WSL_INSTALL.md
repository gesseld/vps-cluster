# Manual WSL Tool Installation Guide

Since automated installation is timing out, follow these steps manually:

## 1. Open WSL Ubuntu Terminal
- Press `Win + R`, type `wsl`, press Enter
- Or open Ubuntu from Start Menu

## 2. Navigate to Project Directory
```bash
cd "/mnt/c/Users/Daniel/Documents/k3s code v2"
```

## 3. Install Required Tools

### Step 3.1: Install Basic Packages
```bash
sudo apt-get update
sudo apt-get install -y unzip jq ansible
```

### Step 3.2: Install Terraform
```bash
cd /tmp
wget https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_linux_amd64.zip
unzip terraform_1.9.5_linux_amd64.zip
sudo mv terraform /usr/local/bin/
rm terraform_1.9.5_linux_amd64.zip
cd -
```

### Step 3.3: Install hcloud CLI (Already exists in directory)
```bash
sudo mv hcloud /usr/local/bin/
```

### Step 3.4: Install Cilium CLI
```bash
curl -L -o cilium.tar.gz https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
tar xzvf cilium.tar.gz
sudo mv cilium /usr/local/bin/
rm cilium.tar.gz
```

## 4. Verify Installations
```bash
echo "=== Tool Versions ==="
kubectl version --client 2>/dev/null || echo "kubectl: Not found"
helm version 2>/dev/null || echo "helm: Not found"
terraform version 2>/dev/null || echo "terraform: Not found"
hcloud version 2>/dev/null || echo "hcloud: Not found"
ansible --version 2>/dev/null || echo "ansible: Not found"
jq --version 2>/dev/null || echo "jq: Not found"
cilium version 2>/dev/null || echo "cilium: Not found"
```

## 5. Test Environment Variables
```bash
source .env
echo "HCLOUD_TOKEN: ${HCLOUD_TOKEN:0:10}..."
echo "S3_BUCKET: $S3_BUCKET"
echo "S3_ENDPOINT: $S3_ENDPOINT"
```

## 6. Test Hetzner Connection
```bash
hcloud context create k3s-cluster --token $HCLOUD_TOKEN
hcloud server list
```

## Next Steps After Installation
1. Proceed to Phase 0.3: Infrastructure Provisioning
2. Run `terraform init` in the project directory
3. Follow the deployment guide in Phase-0.txt