# Connection Diagnostics

Systematic debugging for network connection failures.

## First Steps (Always)

1. **Enable verbose logging:**
   - Environment variable: `CFNETWORK_DIAGNOSTICS=3`
   - Or: `OS_ACTIVITY_MODE=debug`
2. **Check connection state history** — log every state transition
3. **Verify TLS configuration** — expired certs, pinning mismatch, ATS violations
4. **Packet capture** — `rvictl -s <UDID>` for device, Wireshark for analysis

## Symptom → Diagnosis Map

### DNS Resolution Failure
**Symptom:** Connection fails immediately with `dns` error.

**Check:**
- `nslookup hostname` from Terminal
- Is the hostname correct? Typos are common.
- Is there a VPN or proxy affecting DNS?
- Are you on a restrictive network (hotel, corporate)?

**Fix:** Verify hostname, check DNS settings, try `8.8.8.8` as DNS to isolate.

### TLS Handshake Failure
**Symptom:** Connection fails during TLS negotiation.

**Check:**
- Certificate validity: `openssl s_client -connect host:port`
- Certificate pinning: is the pinned cert up to date?
- ATS exceptions: does Info.plist allow this configuration?
- TLS version: server may require TLS 1.3

**Fix:** Update pinned certificates, add ATS exceptions if justified, verify server TLS config.

### Connection Timeout
**Symptom:** Connection hangs, then fails after timeout.

**Check:**
- Is the port correct and open? `nc -zv host port`
- Firewall blocking? Try from different network.
- Is `waitsForConnectivity` set? It may wait silently.
- Is the server responding? Check server logs.

**Fix:** Verify port, check firewall rules, add explicit timeout handling.

### Works on Wi-Fi, Fails on Cellular
**Symptom:** App works on Wi-Fi but fails on mobile data.

**Check:**
- IPv6-only network — carrier requirement since 2016
- Hardcoded IPv4 addresses in the codebase
- Different proxy/VPN configuration on cellular
- Content filtering by carrier

**Fix:** Remove hardcoded IPs, test on IPv6-only hotspot (Settings → Developer → Network Link Conditioner), ensure hostnames resolve to both IPv4 and IPv6.

### Works in Simulator, Fails on Device
**Symptom:** Networking works in Simulator but not on real device.

**Check:**
- ATS (App Transport Security) — Simulator may be more lenient
- Missing entitlements (e.g., network client)
- Proxy/VPN on device
- Different DNS resolution

**Fix:** Check ATS configuration, verify entitlements, test without VPN.

### Connection Stuck in .waiting
**Symptom:** NWConnection enters `.waiting` state and never progresses.

**Check:**
- Network is constrained (VPN, proxy, parental controls)
- No route to host
- Port blocked by firewall

**Fix:**
```swift
// Implement timeout for waiting state
connection.stateUpdateHandler = { state in
    switch state {
    case .waiting:
        // Start a timeout timer
        Task {
            try await Task.sleep(for: .seconds(10))
            connection.cancel()
            onTimeout()
        }
    case .ready:
        // Cancel timeout
    }
}
```

### Intermittent Failures
**Symptom:** Connections work sometimes, fail other times.

**Check:**
- Network transitions (Wi-Fi ↔ cellular)
- Connection reuse issues
- Server load balancer health
- Race conditions in connection setup

**Fix:** Monitor `NWPathMonitor` for transitions, retry with backoff, ensure connections are properly cleaned up.

### Data Corruption / Incomplete Responses
**Symptom:** Response data is truncated or malformed.

**Check:**
- `Content-Length` header matches actual body
- `Transfer-Encoding: chunked` handled correctly
- Response decompression (`Content-Encoding: gzip`)
- Intermediate proxy modifying response

**Fix:** Log raw response bytes, compare `Content-Length` with received bytes, check for proxy interference.

## ATS (App Transport Security) Checklist

ATS enforces HTTPS for all connections by default.

| Scenario | Info.plist Key |
|---|---|
| Allow specific HTTP domain | `NSExceptionDomains` → domain → `NSExceptionAllowsInsecureHTTPLoads` |
| Allow all HTTP (NOT recommended) | `NSAllowsArbitraryLoads` |
| Require specific TLS version | `NSExceptionMinimumTLSVersion` |
| Allow local networking | `NSAllowsLocalNetworking` |

**App Review note:** Apple may reject apps with `NSAllowsArbitraryLoads` without justification. Use specific domain exceptions.

## Production Crisis: iOS Update Causes Connection Failures

**Scenario:** 15% of users report connection failures after iOS update.

1. **Check iOS release notes** for networking changes (TLS requirements, ATS changes)
2. **Reproduce on affected iOS version** — beta or release
3. **Compare CFNetwork logs** between working and failing versions
4. **Check certificate compatibility** — new iOS may reject previously accepted certs
5. **Check for deprecated API usage** — removed in new iOS
6. **Ship hotfix** — most common fix is updating TLS configuration or certificate chain
