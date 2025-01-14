class role::configcluster {
    include ::standard
    include ::base::firewall
    include ::profile::zookeeper::server
    include ::profile::etcd
    include ::profile::etcd::tlsproxy
    include ::profile::etcd::replication
}
