#!/bin/bash
set -e

echo "=== Cleaning up Temporal files for architectural specification compliance ==="
echo "Architectural Specification v4.0.4 requires:"
echo "1. Temporal in Control Plane (not Data Plane)"
echo "2. PostgreSQL in Data Plane (dependency for Temporal)"
echo "3. Clean separation of planes"
echo ""

# Create archive of current messy state
echo "📚 Creating archive of current Temporal files..."
mkdir -p archive/temporal-messy-state-$(date +%Y-%m-%d)
find . -name "*temporal*" -type f | while read file; do
  cp --parents "$file" archive/temporal-messy-state-$(date +%Y-%m-%d)/ 2>/dev/null || true
done

echo "📊 Current Temporal file count: $(find . -name "*temporal*" -type f | wc -l)"
echo ""

# According to spec: Temporal should be in Control Plane
# But we need to clean up the mess first

echo "🧹 Cleaning up experimental/debugging files..."
echo ""

# 1. Remove planes/planes-db-fix-temporal/ (experimental debugging)
if [ -d "planes/planes-db-fix-temporal" ]; then
  echo "Removing: planes/planes-db-fix-temporal/"
  rm -rf planes/planes-db-fix-temporal
fi

# 2. Remove duplicate values files
echo "Removing duplicate values files..."
rm -f temporal-helm-values-copy.yaml 2>/dev/null || true
rm -f temporal-registration-patch.yaml 2>/dev/null || true
rm -f tmp_temporal_fixed.yaml 2>/dev/null || true

# 3. Keep only essential Temporal files
echo ""
echo "📁 Organizing remaining Temporal files..."

# Create proper directory structure
mkdir -p control-plane/temporal
mkdir -p data-plane/postgresql

# Move Temporal Helm chart to control-plane
if [ -d "temporal" ]; then
  echo "Moving temporal/ to control-plane/temporal/"
  mv temporal control-plane/temporal/chart
fi

# Keep only one clean values file
if [ -f "temporal-values.yaml" ]; then
  echo "Keeping temporal-values.yaml as base configuration"
  cp temporal-values.yaml control-plane/temporal/values-base.yaml
fi

if [ -f "temporal-ha-values.yaml" ]; then
  echo "Keeping temporal-ha-values.yaml for HA configuration"
  cp temporal-ha-values.yaml control-plane/temporal/values-ha.yaml
fi

if [ -f "temporal-helm-values.yaml" ]; then
  echo "Keeping temporal-helm-values.yaml for production configuration"
  cp temporal-helm-values.yaml control-plane/temporal/values-production.yaml
fi

# Create proper Temporal deployment for Control Plane
echo ""
echo "📝 Creating proper Temporal deployment for Control Plane..."

cat > control-plane/temporal/temporal-deployment.yaml << 'EOF'
# Temporal Server Deployment for Control Plane
# Version: 1.30.4
# Namespace: control-plane
# Priority: foundation-critical
# Dependencies: PostgreSQL in data-plane

apiVersion: apps/v1
kind: Deployment
metadata:
  name: temporal-server
  namespace: control-plane
  labels:
    app: temporal
    component: server
    plane: control
    priority: foundation-critical
spec:
  replicas: 2  # HA configuration
  selector:
    matchLabels:
      app: temporal
      component: server
  template:
    metadata:
      labels:
        app: temporal
        component: server
        plane: control
        priority: foundation-critical
    spec:
      priorityClassName: foundation-critical
      serviceAccountName: temporal-server
      containers:
      - name: temporal
        image: temporalio/server:1.30.4
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 7233
          name: frontend
        - containerPort: 7234
          name: history
        - containerPort: 7235
          name: matching
        - containerPort: 7239
          name: worker
        - containerPort: 9090
          name: metrics
        env:
        - name: TEMPORAL_CLI_ADDRESS
          value: "temporal-frontend:7233"
        - name: DB
          value: "postgres"
        - name: DB_PORT
          value: "5432"
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: temporal-postgres-creds
              key: username
        - name: POSTGRES_PWD
          valueFrom:
            secretKeyRef:
              name: temporal-postgres-creds
              key: password
        - name: DYNAMIC_CONFIG_FILE_PATH
          value: "/etc/temporal/config/dynamicconfig.yaml"
        volumeMounts:
        - name: config
          mountPath: /etc/temporal/config
        resources:
          requests:
            memory: "750Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        readinessProbe:
          httpGet:
            path: /health
            port: metrics
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: metrics
          initialDelaySeconds: 60
          periodSeconds: 30
      volumes:
      - name: config
        configMap:
          name: temporal-config
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values: ["temporal"]
            topologyKey: "kubernetes.io/hostname"
EOF

# Create PostgreSQL configuration for Data Plane
echo "📝 Creating PostgreSQL configuration for Data Plane..."

cat > data-plane/postgresql/postgresql-deployment.yaml << 'EOF'
# PostgreSQL for Temporal in Data Plane
# Namespace: data-plane
# Priority: foundation-critical

apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql-temporal
  namespace: data-plane
  labels:
    app: postgresql
    component: temporal-db
    plane: data
    priority: foundation-critical
spec:
  serviceName: postgresql-temporal
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
      component: temporal-db
  template:
    metadata:
      labels:
        app: postgresql
        component: temporal-db
        plane: data
        priority: foundation-critical
    spec:
      priorityClassName: foundation-critical
      serviceAccountName: postgresql
      containers:
      - name: postgresql
        image: postgres:15
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 5432
          name: postgresql
        env:
        - name: POSTGRES_DB
          value: "temporal"
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgresql-creds
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-creds
              key: password
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - temporal
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - temporal
          initialDelaySeconds: 60
          periodSeconds: 30
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: nvme-waitfirst
      resources:
        requests:
          storage: 50Gi
EOF

# Create service for PostgreSQL
cat > data-plane/postgresql/postgresql-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: postgresql-temporal
  namespace: data-plane
  labels:
    app: postgresql
    component: temporal-db
    plane: data
spec:
  selector:
    app: postgresql
    component: temporal-db
  ports:
  - port: 5432
    targetPort: 5432
    name: postgresql
  type: ClusterIP
EOF

# Create secret template
cat > data-plane/postgresql/postgresql-secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-creds
  namespace: data-plane
type: Opaque
data:
  username: dGVtcG9yYWw=  # temporal
  password: cGFzc3dvcmQ=  # password
---
apiVersion: v1
kind: Secret
metadata:
  name: temporal-postgres-creds
  namespace: control-plane
type: Opaque
data:
  username: dGVtcG9yYWw=  # temporal
  password: cGFzc3dvcmQ=  # password
EOF

# Create cleanup summary
echo ""
echo "📋 Cleanup Summary:"
echo "=================="
echo "✅ Created archive: archive/temporal-messy-state-$(date +%Y-%m-%d)"
echo "✅ Removed experimental files: planes/planes-db-fix-temporal/"
echo "✅ Removed duplicate values files"
echo "✅ Organized Temporal in: control-plane/temporal/"
echo "✅ Created PostgreSQL for Data Plane: data-plane/postgresql/"
echo ""
echo "📁 New structure:"
echo "control-plane/temporal/"
echo "  ├── chart/           # Helm chart"
echo "  ├── values-*.yaml    # Configuration files"
echo "  └── temporal-deployment.yaml"
echo ""
echo "data-plane/postgresql/"
echo "  ├── postgresql-deployment.yaml"
echo "  ├── postgresql-service.yaml"
echo "  └── postgresql-secret.yaml"
echo ""
echo "⚠️  Important:"
echo "1. Deploy Phase 0 (Budget Scaffolding) FIRST"
echo "2. Then deploy PostgreSQL in Data Plane"
echo "3. Finally deploy Temporal in Control Plane"
echo ""
echo "This follows the architectural specification sequence."