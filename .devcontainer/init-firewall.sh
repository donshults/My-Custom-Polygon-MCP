#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow HTTP/HTTPS
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# Allow specific Polygon.io domains
for domain in api.polygon.io socket.polygon.io delayed.polygon.io reference-data.polygon.io; do
    iptables -A OUTPUT -p tcp -m multiport --dports 80,443 -m string --string "$domain" --algo bm --to 65535 -j ACCEPT
done

# Development domains
for domain in github.com pkg.go.dev proxy.golang.org; do
    iptables -A OUTPUT -p tcp -m multiport --dports 80,443 -m string --string "$domain" --algo bm --to 65535 -j ACCEPT
done

# Google OAuth domains
for domain in accounts.google.com oauth2.googleapis.com www.googleapis.com; do
    iptables -A OUTPUT -p tcp -m multiport --dports 80,443 -m string --string "$domain" --algo bm --to 65535 -j ACCEPT
done

# Allow established/related connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Default deny all other outbound traffic
iptables -P OUTPUT DROP

# Verification
echo "Firewall rules applied. Verifying connectivity..."

# Verify DNS resolution
if ! nslookup google.com >/dev/null 2>&1; then
    echo "ERROR: DNS resolution test failed"
    exit 1
else
    echo "DNS resolution test passed"
fi

# Verify Polygon.io API access
if ! curl --connect-timeout 5 "https://api.polygon.io/v1/meta/symbols?apiKey=TEST" >/dev/null 2>&1; then
    echo "WARNING: Unable to reach Polygon.io API (expected if no valid API key)"
else
    echo "Successfully connected to Polygon.io API"
fi

# Verify GitHub access
if ! curl --connect-timeout 5 https://github.com >/dev/null 2>&1; then
    echo "ERROR: Unable to reach GitHub"
    exit 1
else
    echo "Successfully connected to GitHub"
fi

# Verify Google OAuth endpoints
for domain in accounts.google.com oauth2.googleapis.com; do
    if ! curl --connect-timeout 5 "https://$domain" >/dev/null 2>&1; then
        echo "WARNING: Unable to reach Google OAuth endpoint: $domain"
    else
        echo "Successfully connected to Google OAuth: $domain"
    fi
done

echo "Firewall configuration completed successfully"