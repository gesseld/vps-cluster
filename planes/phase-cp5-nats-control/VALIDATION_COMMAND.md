# CP-5 Validation Command

## Original Task Validation Command
From the task specification:
```bash
nats-sub control.critical.alert  # receives test message from control-plane namespace
```

## Enhanced Implementation
The implementation provides several validation options:

### 1. **Basic Validation (as specified)**
```bash
nats sub control.critical.alert \
  --server=nats-stateless.control-plane.svc.cluster.local:4222 \
  --user=controller \
  --password=changeme
```

### 2. **With Actual Password**
```bash
# Get the actual password
PASSWORD=$(kubectl get secret nats-auth-secrets -n control-plane -o jsonpath='{.data.controller-password}' | base64 -d)

# Run validation
nats sub control.critical.alert \
  --server=nats-stateless.control-plane.svc.cluster.local:4222 \
  --user=controller \
  --password="$PASSWORD"
```

### 3. **Complete Test Script**
```bash
# Run the comprehensive test
./test-credentials.sh

# Or quick test
./test-nats-quick.sh
```

### 4. **Full Validation Suite**
```bash
# Run all validation tests
./03-validation.sh
```

## Test Message Publishing
To test that messages are being received:

**Terminal 1 (Subscribe):**
```bash
nats sub control.critical.alert \
  --server=nats-stateless.control-plane.svc.cluster.local:4222 \
  --user=controller \
  --password=changeme
```

**Terminal 2 (Publish):**
```bash
nats pub control.critical.alert "Test alert message" \
  --server=nats-stateless.control-plane.svc.cluster.local:4222 \
  --user=controller \
  --password=changeme
```

## Expected Output
When successful, you should see:
1. Subscriber terminal shows connection established
2. Published messages appear in subscriber terminal
3. No error messages about authentication or connection

## Troubleshooting
If the validation command fails:

1. **Check deployment status:**
   ```bash
   kubectl get deployment nats-stateless -n control-plane
   kubectl get pods -n control-plane -l app=nats-stateless
   ```

2. **Check service:**
   ```bash
   kubectl get service nats-stateless -n control-plane
   ```

3. **Test connectivity from within cluster:**
   ```bash
   kubectl run test --image=natsio/nats-box --restart=Never --rm -it -- \
     nats server info --server=nats-stateless.control-plane.svc.cluster.local:4222
   ```

4. **Check logs:**
   ```bash
   kubectl logs -n control-plane -l app=nats-stateless
   ```

## Validation Success Criteria
- ✅ Can connect to NATS server
- ✅ Authentication succeeds
- ✅ Can subscribe to `control.critical.alert`
- ✅ Can publish to `control.critical.alert`
- ✅ Messages are delivered (at-most-once)
- ✅ Monitoring endpoint accessible (port 8222)

The implementation meets all validation requirements from the original task specification.