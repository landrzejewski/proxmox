#!/bin/bash

# Interfaces
PUBLIC_IF="ens3"
PRIVATE_IF="zt6nthpxpi"

# Subnet Base
BASE_IP="192.168.195"

# Clear existing rules
iptables -t nat -F
iptables -F FORWARD

# SSH and RDP rules
for i in $(seq 101 200); do
    ssh_port=$((10000 + i - 100))
    rdp_port=$((20000 + i - 100))

    target_ip="$BASE_IP.$i"

    # SSH DNAT
    iptables -t nat -A PREROUTING -i $PUBLIC_IF -p tcp --dport $ssh_port -j DNAT --to-destination $target_ip:22
    # RDP DNAT
    iptables -t nat -A PREROUTING -i $PUBLIC_IF -p tcp --dport $rdp_port -j DNAT --to-destination $target_ip:3389

    # Allow forwarding
    iptables -A FORWARD -p tcp -d $target_ip --dport 22 -j ACCEPT
    iptables -A FORWARD -p tcp -d $target_ip --dport 3389 -j ACCEPT
done

# MASQUERADE traffic going out the public interface
iptables -t nat -A POSTROUTING -s $BASE_IP.0/24 -o $PUBLIC_IF -j MASQUERADE

# Forwarding rules for established traffic
iptables -A FORWARD -i $PUBLIC_IF -o $PRIVATE_IF -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i $PRIVATE_IF -o $PUBLIC_IF -m state --state ESTABLISHED,RELATED -j ACCEPT

# Log accepted SSH/RDP traffic
iptables -A FORWARD -p tcp --dport 22 -j LOG --log-prefix "SSH FORWARD: " --log-level 6
iptables -A FORWARD -p tcp --dport 3389 -j LOG --log-prefix "RDP FORWARD: " --log-level 6
