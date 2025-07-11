nano /etc/network/interfaces

auto vmbr1
iface vmbr1 inet static
    address  192.168.100.1
    netmask  255.255.255.0
    bridge_ports none
    bridge_stp off
    bridge_fd 0




ifreload -a

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Make it permanent
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# NAT outgoing traffic from vmbr1 to external interface
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o ens18 -j MASQUERADE

# Drop traffic from VMs to local network
iptables -I FORWARD -i vmbr1 -d 192.168.0.0/16 -j DROP

# Allow VM traffic to go out to the internet
iptables -A FORWARD -i vmbr1 -o vmbr0 -j ACCEPT

# Allow return traffic from internet to VMs (for established connections)
iptables -A FORWARD -i vmbr0 -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Add NAT rule to masquerade VM traffic as Proxmox host IP
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o vmbr0 -j MASQUERADE

apt update
apt install iptables-persistent dnsmasq -y

netfilter-persistent save

nano /etc/dnsmasq.d/vmbr1.conf

interface=vmbr1
bind-interfaces
dhcp-range=192.168.100.10,192.168.100.100,12h



systemctl restart dnsmasq


