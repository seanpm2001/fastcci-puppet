# == Define: cassandra::instance
#
# Installs and configures a Cassandra server instance
#
# === Usage
# cassandra::instance { 'instance-name':
#     instances => ...
# }
#
# === Parameters
#
# [*title*]
#   The name of this cassandra instance, it must have a corresponding key in
#   $instances, see below. The name "default" can be used as instance name to
#   obtain cassandra's standard behaviour with a single instance.
#
#   Unless default behaviour (as in Cassandra's Debian package) is wanted, each
#   instance will have its configuration deployed at /etc/cassandra-<TITLE>
#   with data at /srv/cassandra-<TITLE> and a corresponding nodetool
#   binary named nodetool-<TITLE> to be used to access instances individually.
#   Similarly each instance service will be available under
#   "cassandra-<TITLE>".
#
# [*instances*]
#   An hash from instance name to several instance-specific parameters,
#   including:
#     * jmx_port        must be unique per-host
#     * listen_address  address to use for cassandra clients
#     * rpc_address     address to use for cassandra cluster traffic
#
#   Note any other parameter from the "cassandra" class is in scope and
#   will be inherited here and can be used e.g. in templates.
#
#   Default: $::cassandra::instances
#
define cassandra::instance(
    $instances = $::cassandra::instances,
) {
    $instance_name = $title
    if ! has_key($instances, $instance_name) {
        fail("instance ${instance_name} not found in ${instances}")
    }

    # Default jmx port; only works with 1-letter instnaces
    $default_jmx_port     = 7189 + inline_template("<%= @title.ord - 'a'.ord %>")

    # Relevant values, choosing convention over configuration
    $this_instance        = $instances[$instance_name]
    $jmx_port             = pick($this_instance['jmx_port'], $default_jmx_port)
    $listen_address       = $this_instance['listen_address']
    $rpc_address          = pick($this_instance['rpc_address'], $listen_address)
    $jmx_exporter_enabled = pick($this_instance['jmx_exporter_enabled'], false)

    # Add the IP address if not present
    if $rpc_address != $facts['ipaddress'] {
        interface::alias { "cassandra-${instance_name}":
            ipv4      => $rpc_address,
        }
    }

    if $instance_name == 'default' {
        $data_directory_base = $this_instance['data_directory_base']
        $config_directory    = '/etc/cassandra'
        $service_name        = 'cassandra'
        $tls_hostname        = $::hostname
        $pid_file            = '/var/run/cassandra/cassandra.pid'
        $instance_id         = $::hostname
        $data_file_directories  = $this_instance['data_file_directories']
        $commitlog_directory    = $this_instance['commitlog_directory']
        $hints_directory        = $this_instance['hints_directory']
        $heapdump_directory     = $this_instance['heapdump_directory']
        $saved_caches_directory = $this_instance['saved_caches_directory']
    } else {
        $data_directory_base = "/srv/cassandra-${instance_name}"
        $config_directory    = "/etc/cassandra-${instance_name}"
        $service_name        = "cassandra-${instance_name}"
        $tls_hostname        = "${::hostname}-${instance_name}"
        $pid_file            = "/var/run/cassandra/cassandra-${instance_name}.pid"
        $instance_id         = "${::hostname}-${instance_name}"
        $data_file_directories  = ["${data_directory_base}/data"]
        $commitlog_directory    = "${data_directory_base}/commitlog"
        $hints_directory        = "${data_directory_base}/data/hints"
        $heapdump_directory     = $data_directory_base
        $saved_caches_directory = "${data_directory_base}/saved_caches"
    }

    $tls_cluster_name       = $::cassandra::tls_cluster_name
    $application_username   = $::cassandra::application_username
    $native_transport_port  = $::cassandra::native_transport_port
    $target_version         = $::cassandra::target_version

    file { $config_directory:
        ensure  => directory,
        owner   => 'root',
        group   => 'root',
        mode    => '0755',
        require => Package['cassandra'],
    }

    file { $data_directory_base:
        ensure  => directory,
        owner   => 'cassandra',
        group   => 'cassandra',
        mode    => '0750',
        require => Package['cassandra'],
    }

    file { [$data_file_directories,
            $commitlog_directory,
            $saved_caches_directory]:
        ensure  => directory,
        owner   => 'cassandra',
        group   => 'cassandra',
        mode    => '0750',
        require => File[$data_directory_base],
    }

    file { "${config_directory}/cassandra-env.sh":
        ensure  => present,
        content => template("${module_name}/cassandra-env.sh-${target_version}.erb"),
        owner   => 'cassandra',
        group   => 'cassandra',
        mode    => '0444',
        require => File[$config_directory],
    }

    file { "${config_directory}/cassandra.yaml":
        ensure  => present,
        content => template("${module_name}/cassandra.yaml-${target_version}.erb"),
        owner   => 'cassandra',
        group   => 'cassandra',
        mode    => '0444',
        require => File[$config_directory],
    }

    file { "${config_directory}/cassandra-rackdc.properties":
        ensure  => present,
        content => template("${module_name}/cassandra-rackdc.properties.erb"),
        owner   => 'cassandra',
        group   => 'cassandra',
        mode    => '0444',
        require => File[$config_directory],
    }

    file { "${config_directory}/logback.xml":
        ensure  => present,
        content => template("${module_name}/logback.xml-${target_version}.erb"),
        owner   => 'cassandra',
        group   => 'cassandra',
        mode    => '0444',
        require => File[$config_directory],
    }

    file { "${config_directory}/logback-tools.xml":
        ensure  => present,
        source  => "puppet:///modules/${module_name}/logback-tools.xml",
        owner   => 'cassandra',
        group   => 'cassandra',
        mode    => '0444',
        require => File[$config_directory],
    }

    file { "${config_directory}/cqlshrc":
        content => template("${module_name}/cqlshrc.erb"),
        owner   => 'root',
        group   => 'root',
        mode    => '0400',
        require => Package['cassandra'],
    }

    file { "${config_directory}/prometheus_jmx_exporter.yaml":
        ensure  => present,
        source  => "puppet:///modules/${module_name}/prometheus_jmx_exporter.yaml",
        owner   => 'cassandra',
        group   => 'cassandra',
        mode    => '0400',
        require => Package['cassandra'],
    }

    if $application_username != undef {
        file { "${config_directory}/adduser.cql":
            content => template("${module_name}/adduser.cql.erb"),
            owner   => 'root',
            group   => 'root',
            mode    => '0400',
            require => Package['cassandra'],
        }
    }

    if ($tls_cluster_name) {
        file { "${config_directory}/tls":
            ensure  => directory,
            owner   => 'cassandra',
            group   => 'cassandra',
            mode    => '0400',
            require => Package['cassandra'],
        }

        file { "${config_directory}/tls/server.key":
            content => secret("cassandra/${tls_cluster_name}/${tls_hostname}/${tls_hostname}.kst"),
            owner   => 'cassandra',
            group   => 'cassandra',
            mode    => '0400',
            require => File["${config_directory}/tls"],
        }

        file { "${config_directory}/tls/server.trust":
            content => secret("cassandra/${tls_cluster_name}/truststore"),
            owner   => 'cassandra',
            group   => 'cassandra',
            mode    => '0400',
            require => File["${config_directory}/tls"],
        }

        file { "${config_directory}/tls/rootCa.crt":
            content => secret("cassandra/${tls_cluster_name}/rootCa.crt"),
            owner   => 'cassandra',
            group   => 'cassandra',
            mode    => '0400',
            require => File["${config_directory}/tls"],
        }
    }

    if $instance_name != 'default' {
        file { "/usr/local/bin/nodetool-${instance_name}":
            ensure  => link,
            target  => '/usr/local/bin/nodetool-instance',
            require => File['/usr/local/bin/nodetool-instance'],
        }
    }

    file { "/etc/cassandra-instances.d/${tls_hostname}.yaml":
        content => template("${module_name}/instance.yaml.erb"),
        owner   => 'cassandra',
        group   => 'cassandra',
        mode    => '0444',
        require => File['/etc/cassandra-instances.d'],
    }

    if ($target_version == '3.x') {
        file { "${config_directory}/jvm.options":
            ensure  => present,
            content => template("${module_name}/jvm.options-${target_version}.erb"),
            owner   => 'cassandra',
            group   => 'cassandra',
            mode    => '0444',
            require => File[$config_directory],
        }

        file { "${config_directory}/hotspot_compiler":
            ensure  => present,
            source  => "puppet:///modules/${module_name}/hotspot_compiler",
            owner   => 'cassandra',
            group   => 'cassandra',
            mode    => '0444',
            require => File[$config_directory],
        }

        file { "${config_directory}/commitlog_archiving.properties":
            ensure  => present,
            source  => "puppet:///modules/${module_name}/commitlog_archiving.properties",
            owner   => 'cassandra',
            group   => 'cassandra',
            mode    => '0444',
            require => File[$config_directory],
        }
    }

    base::service_unit { $service_name:
        ensure        => present,
        template_name => 'cassandra',
        systemd       => true,
        refresh       => false,
        require       => [
            File[$data_file_directories],
            File["${config_directory}/cassandra-env.sh"],
            File["${config_directory}/cassandra.yaml"],
            File["${config_directory}/cassandra-rackdc.properties"],
        ],
    }
}
