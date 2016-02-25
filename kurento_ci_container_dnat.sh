#!/bin/bash -x

echo "##################### EXECUTE: kurento_ci_container_dnat #####################"

############################################
# Craete container
container=$1
action=$2
transport=$3
ip=$4

short=${container:0:7}
echo "Sort: ${short}"

echo "Performing $action on container ID $container with transport $transport"

if [ $action = 'start' ]; then

echo "Starting..."

#ip=172.17.0.$(( ( RANDOM % 100 )  + 101 ))
#while [ ping -c 1 $ip ]; do
#  ip=172.17.0.$(( ( RANDOM % 100 )  + 101 ))
#done

echo "Selected ip: $ip"

docker_pid=$(docker inspect -f '{{.State.Pid}}' $container)
# Add Net namespaces
ln -s /proc/$docker_pid/ns/net /var/run/netns/$docker_pid
ip netns add $docker_pid-bridge
ip netns add $docker_pid-route

# Create bridge & interfaces
ip netns exec $docker_pid-bridge brctl addbr br0
ip link add vethci$docker_pid type veth peer name vethce$docker_pid
ip link add vethrbi$docker_pid type veth peer name vethrbe$docker_pid
ip link add vethrai$docker_pid type veth peer name vethrae$docker_pid

# Assign interfaces to Net namespaces
ip link set vethci$docker_pid netns $docker_pid
ip link set vethce$docker_pid netns $docker_pid-bridge
ip link set vethrbi$docker_pid netns $docker_pid-route
ip link set vethrbe$docker_pid netns $docker_pid-bridge
ip link set vethrai$docker_pid netns $docker_pid-route

# Link interfaces to bridges
brctl addif docker0 vethrae$docker_pid
ip netns exec $docker_pid-bridge brctl addif br0 vethce$docker_pid
ip netns exec $docker_pid-bridge brctl addif br0 vethrbe$docker_pid


# Configure IP addresses

# Container Internal
ip netns exec $docker_pid ip link set dev vethci$docker_pid name eth0
ip netns exec $docker_pid ip link set eth0 up
ip netns exec $docker_pid ip addr add 192.168.0.100/24 dev eth0
ip netns exec $docker_pid ip route add default via 192.168.0.1

# Container external (peer)
ip netns exec $docker_pid-bridge ip link set vethce$docker_pid up

# Bridge
ip netns exec $docker_pid-bridge ip link set br0 up
ip netns exec $docker_pid-bridge ip addr add 192.168.0.254/24 dev br0

# Router bridge internal
ip netns exec $docker_pid-route ip link set vethrbi$docker_pid up
ip netns exec $docker_pid-route ip addr add 192.168.0.1/24 dev vethrbi$docker_pid

# Router bridge external (peer)
ip netns exec $docker_pid-bridge ip link set vethrbe$docker_pid up

# Agent internal
ip netns exec $docker_pid-route ip link set vethrai$docker_pid up
ip netns exec $docker_pid-route ip addr add 172.17.100.100/16 dev vethrai$docker_pid
ip netns exec $docker_pid-route ip route add default via 172.17.0.1

# Agent external
ip link set vethrae$docker_pid up

# Add SNAT
ip netns exec $docker_pid-route iptables -t nat -A POSTROUTING -o vethrai$docker_pid -j SNAT --to $ip
ip netns exec $docker_pid-route iptables -t nat -A PREROUTING -i vethrai$docker_pid -j DNAT --to 192.168.0.100
if [ $transport = 'tcp' ]; then
  # Comment out following line to force RLFX TCP
  ip netns exec $docker_pid-route iptables iptables -A INPUT -p udp -s 172.16.0.0/16 -j DROP
fi

# Set IP for container
pid=$(docker inspect -f '{{.State.Pid}}' $container)
#destpid=a${pid}
#[ ! -d /var/run/netns ] && mkdir -p /var/run/netns
#ln -s /proc/$pid/net /var/run/netns/$destpid

# Check the bridge's IP address and netmask

# Create a pair of "peer" interfaces A and B,
# bind the A end to the bridge, and bring it up

ip link add A_${short} type veth peer name B_${short}
brctl addif docker0 A_${short}
ip link set A_${short} up

# Place B inside the container's network namespace,
# rename to eth0, and activate it with a free IP
# We rename it to eth1 because there is already an eth0 with a 192.168 ip

ip link set B_${short} netns $pid
ip netns exec $pid ip link set dev B_${short} name eth1${pid}
ip netns exec $pid ip link set eth1${pid} up
ip netns exec $pid ip addr add ${ip}/16 dev eth1${pid}
ip netns exec $pid ip route add default via 172.17.0.1

fi

if [ $action = 'destroy' ]; then
######################################################
# Delete container
echo "Destroying..."

ip netns del $docker_pid-route
ip netns del $docker_pid-bridge
ip netns del $docker_pid

fi
