#!/usr/bin/perl -w

use strict;
use warnings;

our $cgiproxyDir;

BEGIN{
  use File::Basename qw/dirname/;
  use Cwd qw/realpath/;
  $cgiproxyDir = realpath( dirname( __FILE__ ).'/..' );
  my $libDir = $cgiproxyDir.'/lib';
  push( @INC, $libDir  )
    unless grep { $_ eq $libDir } @INC;
}

require "$cgiproxyDir/etc/fcgiproxy.conf";
use CGI::Proxy qw/full_url/;

# flush after every print
$| = 1;

# Process lines of the form 'URL ip-address/fqdn ident method'
# See release notes of Squid 1.1 for details
my ($url, $addr, $fqdn, $ident, $method);
my $url_proxy_length = length $main::url_proxy;
use Data::Dumper;
while ( <> ) {
  ($url, $addr, $fqdn, $ident, $method) = m:(\S*) ?(\S*)?/?(\S*)? ?(\S*)? ?(\S*)?:;
  ( $url =  # '302:'.
           full_url( $url ) )
    unless ( $method eq 'CONNECT' ) or $main::url_proxy eq substr $url, 0, $url_proxy_length;
} continue {
  print "$url $addr/$fqdn $ident $method\n";
}

1;
