#!/bin/bash
set -e

echo "=== Cleaning up Temporal files for Data Plane deployment ==="
echo "Updated Architectural Specification: Temporal in Data Plane"
echo ""

# Create archive of current messy state
echo "📚 Creating archive of current Temporal files..."
mkdir -p archive/temporal-data-plane-messy-$(date +%Y-%m-%d)
find . -name "*temporal*" -type f | while read file; do
  cp --parents "$file" archive/temporal-data-plane-messy-$(date +%Y-%m-%d)/ 2>/dev/null || true
done

echo "📊 Current Temporal file count: $(find . -name "*temporal*" -type f | wc -l)"
echo ""

# According to updated spec: Temporal should be in Data Plane
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
echo "📁 Organizing Temporal files for Data Plane..."

# Create proper directory structure
mkdir -p data-plane/temporal
mkdir -p data-plane/postgresql

# Move Temporal Helm chart to data-plane
if [ -d "temporal" ]; then
  echo "Moving temporal/ to data-plane/temporal/chart"
  mv temporal data-plane/temporal/chart
fi

# Keep only one clean values file
if [ -f "temporal-values.yaml" ]; then
  echo "Keeping temporal-values.yaml as base configuration"
  cp temporal-values.yaml data-plane/temporal/values-base.yaml
fi

if [ -f "temporal-ha-values.yaml" ]; then
  echo "Keeping temporal-ha-values.yaml for HA configuration"
  cp temporal-ha-values.yaml data-plane/temporal/values-ha.yaml
fi

if [ -f "temporal-helm-values.yaml" ]; then
  echo "Keeping temporal-helm-values.yaml for production configuration"
  cp temporal-helm-values.yaml data-plane/temporal/values-production.yaml
fi

# Create proper Temporal deployment for Data Plane
echo ""
echo "📝 Creating proper Temporal deployment for Data Plane..."

cat > data-plane/temporal/temporal-deployment.yaml << 'EOF'
# Temporal Server Deployment for Data Plane
# Version: 1.30.4
# Namespace: data-plane
# Priority: foundation-critical
# Dependencies: PostgreSQL in same namespace (data-plane)

apiVersion: apps/v1
kind: Deployment
metadata:
  name: temporal-server
  namespace: data-plane
  labels:
    app: temporal
    component: server
    plane: data
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
        plane: data
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

# Create service for Temporal
cat > data-plane/temporal/temporal-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: temporal-frontend
  namespace: data-plane
  labels:
    app: temporal
    component: frontend
    plane: data
spec:
  selector:
    app: temporal
    component: server
  ports:
  - port: 7233
    targetPort: 7233
    name: frontend
  - port: 9090
    targetPort: 9090
    name: metrics
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: temporal-frontend-headless
  namespace: data-plane
  labels:
    app: temporal
    component: frontend-headless
    plane: data
spec:
  clusterIP: None
  selector:
    app: temporal
    component: server
  ports:
  - port: 7233
    targetPort: 7233
    name: frontend
  - port: 9090
    targetPort: 9090
    name: metrics
EOF

# Update PostgreSQL configuration for Data Plane (same namespace)
echo "📝 Updating PostgreSQL configuration for Data Plane..."

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
  namespace: data-plane
type: Opaque
data:
  username: dGVtcG9yYWw=  # temporal
  password: cGFzc3dvcmQ=  # password
EOF

# Create cleanup summary
echo ""
echo "📋 Cleanup Summary:"
echo "=================="
echo "✅ Created archive: archive/temporal-data-plane-messy-$(date +%Y-%m-%d)"
echo "✅ Removed experimental files: planes/planes-db-fix-temporal/"
echo "✅ Removed duplicate values files"
echo "✅ Organized Temporal in: data-plane/temporal/"
echo "✅ Created PostgreSQL in: data-plane/postgresql/"
echo ""
echo "📁 New structure:"
echo "data-plane/temporal/"
echo "  ├── chart/           # Helm chart"
echo "  ├── values-*.yaml    # Configuration files"
echo "  ├── temporal-deployment.yaml"
echo "  └── temporal-service.yaml"
echo ""
echo "data-plane/postgresql/"
echo "  ├── postgresql-deployment.yaml"
echo "  ├── postgresql-service.yaml"
echo "  └── postgresql-secret.yaml"
echo ""
echo "⚠️  Important:"
echo "1. Deploy Phase 0 (Budget Scaffolding) FIRST"
echo "2. Then deploy PostgreSQL in Data Plane"
echo "3. Deploy Temporal in Data Plane (same namespace)"
echo ""
echo "This follows the updated architectural specification with Temporal in Data Plane."