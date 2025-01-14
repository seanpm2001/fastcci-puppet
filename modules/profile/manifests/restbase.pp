# == class profile::restbase
#
# sets up a REST API & storage service
#
# === Parameters
#
# [*cassandra_user*]
#   Cassandra user name.
#
# [*cassandra_password*]
#   Cassandra password.
#
# [*seeds*]
#   Array of cassandra hosts (IP or host names) to contact.
#
# [*cassandra_local_dc*]
#   Which DC should be considered local.
#
# [*cassandra_datacenters*]
#   The full list of member datacenters.
#
# [*cassandra_tls*]
#   An associative array of TLS options for the Cassandra driver.
#   See: https://nodejs.org/api/tls.html#tls_tls_createsecurecontext_options
#
# [*logging_label*]
#   The logging label to use both for logging and statsd.
#
# [*monitor_domain*]
#   The domain to monitor during the service's operation.
#
# [*hosts*]
#   The list of RESTBase hosts used for setting up the rate-limiting DHT.
#
# [*parsoid_uri*]
#   URI to reach Parsoid. Format: http://parsoid.svc.eqiad.wmnet:8000
#
# [*graphoid_uri*]
#   graphoid host + port. Format: http://graphoid.svc.eqiad.wmnet:19000
#
# [*mobileapps_uri*]
#   MobileApps service URI. Format: http://mobileapps.svc.eqiad.wmnet:8888
#
# [*mathoid_uri*]
#   Mathoid service URI. Format: http://mathoid.svc.eqiad.wmnet:10042
#
# [*aqs_uri*]
#   Analytics Query Service URI. Format:
#   http://aqs.svc.eqiad.wmnet:7232/analytics.wikimedia.org/v1
#
# [*eventlogging_service_uri*]
#   Eventlogging service URI. Format: http://eventbus.svc.eqiad.wmnet:8085/v1/events
#
# [*pdfrender_uri*]
#   PDF Render service URI. Format: http://pdfrender.svc.eqiad.wmnet:5252
#
# [*citoid_uri*]
#   Citoid service URI. Format: http://citoid.svc.eqiad.wmnet:1970
#
# [*trendingedits_uri*]
#   Trending edits service URI. Format:
#   http://trendingedits.svc.eqiad.wmnet:6699
#
# [*cxserver_uri*]
#   CXServer service uri. Format: http://cxserver.discovery.wmnet:8080
#

class profile::restbase(
    $cassandra_user = hiera('profile::restbase::cassandra_user'),
    $cassandra_password = hiera('profile::restbase::cassandra_password'),
    $seeds = hiera('profile::restbase::seeds'),
    $hosts = hiera('profile::restbase::hosts'),
    $cassandra_local_dc = hiera('profile::restbase::cassandra_local_dc'),
    $cassandra_datacenters = hiera('profile::restbase::cassandra_datacenters'),
    $cassandra_tls = hiera('profile::restbase::cassandra_tls', {}),
    $salt_key = hiera('profile::restbase::salt_key'),
    $logging_label = hiera('profile::restbase::logging_label'),
    $parsoid_uri = hiera('profile::restbase::parsoid_uri'),
    $graphoid_uri = hiera('profile::restbase::graphoid_uri'),
    $mobileapps_uri = hiera('profile::restbase::mobileapps_uri'),
    $mathoid_uri    = hiera('profile::restbase::mathoid_uri'),
    $aqs_uri        = hiera('profile::restbase::aqs_uri'),
    $eventlogging_service_uri = hiera('profile::restbase::eventlogging_service_uri'),
    $pdfrender_uri  = hiera('profile::restbase::pdfrender_uri'),
    $citoid_uri     = hiera('profile::restbase::citoid_uri'),
    $trendingedits_uri = hiera('profile::restbase::trendingedits_uri'),
    $cxserver_uri   = hiera('profile::restbase::cxserver_uri'),
    $monitor_domain = hiera('profile::restbase::monitor_domain'),
) {
    # Default values that need no overriding
    $port = 7231
    $page_size = 250

    require ::service::configuration
    $pdfrender_key = $::service::configuration::pdfrender_key
    $local_logfile = "${service::configuration::log_dir}/${title}/main.log"

    service::node { 'restbase':
        port              => $port,
        no_file           => 200000,
        healthcheck_url   => "/${monitor_domain}/v1",
        has_spec          => true,
        starter_script    => 'restbase/server.js',
        auto_refresh      => false,
        deployment        => 'scap3',
        deployment_config => true,
        deployment_vars   => {
            ipaddress                => $::ipaddress,
            rl_seeds                 => reject(reject($hosts, $::hostname), $::ipaddress),
            seeds                    => $seeds,
            cassandra_local_dc       => $cassandra_local_dc,
            cassandra_datacenters    => $cassandra_datacenters,
            cassandra_user           => $cassandra_user,
            cassandra_password       => $cassandra_password,
            cassandra_tls            => $cassandra_tls,
            parsoid_uri              => $parsoid_uri,
            graphoid_uri             => $graphoid_uri,
            mathoid_uri              => $mathoid_uri,
            mobileapps_uri           => $mobileapps_uri,
            citoid_uri               => $citoid_uri,
            eventlogging_service_uri => $eventlogging_service_uri,
            pdfrender_uri            => $pdfrender_uri,
            pdfrender_key            => $pdfrender_key,
            trendingedits_uri        => $trendingedits_uri,
            cxserver_uri             => $cxserver_uri,
            aqs_uri                  => $aqs_uri,
            salt_key                 => $salt_key,
            page_size                => $page_size,
        },
        logging_name      => $logging_label,
        statsd_prefix     => $logging_label,
    }

    monitoring::service { 'restbase_http_root':
        description   => 'Restbase root url',
        check_command => "check_http_port_url!${port}!/",
        contact_group => 'admins,team-services',
    }

    # RESTBase rate limiting DHT firewall rule
    $rb_hosts_ferm = join($hosts, ' ')
    ferm::service { 'restbase-ratelimit':
        proto  => 'tcp',
        port   => '3050',
        srange => "@resolve((${rb_hosts_ferm}))",
    }

    ferm::service {'restbase_web':
        proto => 'tcp',
        port  => '7231',
    }

}
