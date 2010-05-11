package CGI::Proxy::Nginx;
use strict;
use warnings;
use CGI::Proxy qw/full_url/;
use nginx;
use Data::Dumper;  

=pod

Nginx should be configured like this:

  http {
    ...
    perl_modules /path_to_fcgiproxy/lib;
    perl_require CGI/Proxy/Nginx.pm;
    perl_require /path_to/fcgiproxy.conf;
    perl_set $cpn_url CGI::Proxy::Nginx::nginxer;
    ...
  server {
    ...
    listen       ip_addr_for_http:http_port_number default;
    listen       ip_addr_for_https:https_port_number default ssl;
    ...
    server_name  _;
    ...
        location / {
    ...
          proxy_pass $cpn_url;

Special thanks to: "Oleksandr V. Typlyns'kyi" <wangsamp@gmail.com>

It is assumed that HTTP URL is rewritten already ( I do it with Squid's url_rewrite, it uses the nginx's address in its own fcgiproxy.conf )

=cut

sub nginxer{
  my $r = shift;
  my( $method, $uri ) = ( '', '' );
  ( $method, $uri ) = $r->variable( 'request' ) =~/^([^\s]+)\s+([^\s]+)\s/; 
  if( $r->remote_addr eq $main::ssl_addr ){
    $uri="https://".$r->header_in( 'Host' ).$uri;
    return &full_url( $uri ) ;
  } else {
    return $main::scheme_host_proxy.$uri ;
  }
}
1;
__END__
