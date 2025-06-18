Server:
sudo apt update
sudo apt install nfs-kernel-server -y
sudo mkdir -p /store
sudo chmod 777 /store

Edit nano /etc/exports
/store 192.168.100.0/24(rw,sync,no_subtree_check,no_root_squash)

sudo exportfs -ra
sudo systemctl restart nfs-server


Client:
sudo apt install nfs-common -y
sudo mkdir -p /mnt/shared
sudo mount 192.168.100.201:/store /mnt/shared

Edit /etc/fstab and add:
192.168.100.201:/store /mnt/shared nfs nofail,x-systemd.automount,_netdev 0 0