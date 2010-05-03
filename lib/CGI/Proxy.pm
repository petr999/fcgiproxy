package CGI::Proxy;

use strict;
use warnings;

use base qw/Exporter/;

our @EXPORT_OK = qw/full_url proxy_encode wrap_proxy_encode/;

# If you want to encode the URLs of visited pages so that they don't show
#   up within the full URL in your browser bar, then use proxy_encode() and
#   proxy_decode().  These are Perl routines that transform the way the
#   destination URL is included in the full URL.  You can either use
#   some combination of the example encodings below, or you can program your
#   own routines.  The encoded form of URLs should only contain characters
#   that are legal in PATH_INFO.  This varies by server, but using only
#   printable chars and no "?" or "#" works on most servers.  Don't let
#   PATH_INFO contain the strings "./", "/.", "../", or "/..", or else it
#   may get compressed like a pathname somewhere.  Try not to make the
#   resulting string too long, either.
# Of course, proxy_decode() must exactly undo whatever proxy_encode() does.
# Make proxy_encode() as fast as possible-- it's a bottleneck for the whole
#   program.  The speed of proxy_decode() is not as important.
# If you're not a Perl programmer, you can use the example encodings that are
#   commented out, i.e. the lines beginning with "#".  To use them, merely
#   uncomment them, i.e. remove the "#" at the start of the line.  If you
#   uncomment a line in proxy_encode(), you MUST uncomment the corresponding
#   line in proxy_decode() (note that "corresponding lines" in
#   proxy_decode() are in reverse order of those in proxy_encode()).  You
#   can use one, two, or all three encodings at the same time, as long as
#   the correct lines are uncommented.
# Starting in version 2.1beta9, don't call these functions directly.  Rather,
#   call wrap_proxy_encode() and wrap_proxy_decode() instead, which handle
#   certain details that you shouldn't have to worry about in these functions.
# IMPORTANT: If you modify these routines, and if $PROXIFY_SCRIPTS is set
#   below (on by default), then you MUST modify $ENCODE_DECODE_BLOCK_IN_JS
#   below!!  (You'll need to write corresponding routines in JavaScript to do
#   the same as these routines in Perl, used when proxifying JavaScript.)
# Because of the simplified absolute URL resolution in full_url(), there may
#   be ".." segments in the default encoding here, notably in the first path
#   segment.  Normally, that's just an HTML mistake, but please tell me if
#   you see any privacy exploit with it.
# Note that a few sites have embedded applications (like applets or Shockwave)
#   that expect to access URLs relative to the page's URL.  This means they
#   may not work if the encoded target URL can't be treated like a base URL,
#   e.g. that it can't be appended with something like "../data/foo.data"
#   to get that expected data file.  In such cases, the default encoding below
#   should let these sites work fine, as should any other encoding that can
#   support URLs relative to it.

sub proxy_encode {
    my($URL)= @_ ;
		my @url_array = split /\//, $URL;
		if( 3 < scalar @url_array ){
			my $scheme = lc $url_array[0]; chop $scheme;
			eval "use URI::$scheme;";
			unless( $@ ){
				my $base_url = join '/', map{
					shift @url_array;
				} ( 0..2 );
				my $last_slash = 1 if '/' eq substr $URL, length( $URL )-1, 1;
				$URL = URI->new( join '/', @url_array )->abs( $base_url );
				$URL .= '/' if $last_slash;
			}
		}
    $URL=~ s#^([\w+.-]+)://#$1/# ;                 # http://xxx -> http/xxx
#    $URL=~ s/(.)/ sprintf('%02x',ord($1)) /ge ;   # each char -> 2-hex
#    $URL=~ tr/a-zA-Z/n-za-mN-ZA-M/ ;              # rot-13

    return $URL ;
}

# Because encoding and decoding the URL requires some steps that are not
#   user-configurable, we "purify" the functions proxy_encode() and
#   proxy_decode() and move the extra steps to these wrapper functions.
# Don't encode the URI fragment.
# Don't decode the query component or URI fragment.
# Note that we encode "?" to "=3f", and similar for "=" itself.  This is to
#   prevent "?" from being in the encoded URL, where it would prematurely
#   terminate PATH_INFO.
# Also, Apache has a bug where it compresses multiple "/" in PATH_INFO.  To
#   work around this, we encode all "//" to "/=2f", which will be unencoded
#   by proxy_decode() as described in the previous paragraph.  Same goes for
#   "%", since Apache has the same problem when "%2f%2f" is in PATH_INFO.
sub wrap_proxy_encode {
    my($URL)= @_ ;

    my($uri, $frag)= $URL=~ /^([^#]*)(.*)/ ;

    $uri= &proxy_encode($uri) ;

    # Encode ? so it doesn't prematurely end PATH_INFO.
    $uri=~ s/=/=3d/g ;
    $uri=~ s/\?/=3f/g ;
    $uri=~ s/%/=25/g ;
    $uri=~ s/&/=26/g ;
    $uri=~ s/;/=3b/g ;
    1 while $uri=~ s#//#/=2f#g ;    # work around Apache PATH_INFO bug

    return $uri . $frag ;
}


#--------------------------------------------------------------------------


# Returns the full absolute URL to query our script for the given URI
#   reference.  PATH_INFO will include the encoded absolute URL of the target,
#   but the fragment will be appended unencoded so browsers will resolve it
#   correctly.
# If $retain_query is set, then the query string is removed before proxifying,
#   then readded at the end.  This is required for e.g. Flash apps, which
#   read any query parameters into program variables, and thus the query
#   string must be retained.  The downside of this is that the query string
#   is not encoded for such URLs, possibly reducing privacy.  The "real"
#   solution might be to rewrite the Flash proxification to parse the query
#   string out of document.URL and set those program variables initially.
#   We may do this at some point.  A broader solution would be to set up
#   general handlers similar to _proxy_jslib_handle() and _proxy_jslib_assign()
#   in the SWF library, to be called instead of every getMember and setMember
#   action; maybe we can get away without doing that, since that might slow
#   down Flash apps considerably.  We'll see.
# If a "javascript:" URL is in e.g. a "src" attribute, then the result of the
#   last JS statement becomes the contents of that element.  Thus, the last
#   statement needs to be wrapped in "_proxy_jslib_proxify_html(...)".  Since
#   there may be multiple statements in the URL, separated by semicolons, we
#   need to use separate_last_js_statement().
# This is a major bottleneck for the whole program, so speed is important here.
# Note that the calculations of $url_start, $base_scheme, $base_host, 
#   $base_path, and $base_file throughout the program are an integral part of
#   this routine, placed elsewhere for speed.
# For HTTP, The URL to be encoded should include everything that is sent in
#   the request, including any query, but not any fragment.
# This only returns absolute URLs, though relative URLs would usually suffice.
#   If it matters, we could have a fullrelurl() and fullabsurl(), the latter
#   used for those HTML attributes that require an absolute URL (like <base>).
#
# The ?:?:?: statement resolves relative URLs to absolute URLs, given the
#   $base_{url,scheme,host,path} variables figured earlier.  It does it
#   simply and efficiently, and accurately enough; the full procedure is
#   described in RFC 2396 (URI syntax), section 5.2.
# RFC 2396, section 5 states that there are three types of relative URIs:
#   net_path (beginning with //, rarely used), abs_path (beginning with /),
#   and rel_path, any of which may be followed by a "?query"; the query must
#   be included in the result.  Thus, we only need to examine the start of
#   the relative URL.
# This ?:?:?: statement passes all test cases in RFC 2396 appendix C, except
#   for the following:  It does not reduce . and .. path segments (to do
#   so would take a lot more time), and it assumes $uri_ref has something
#   other than an empty fragment in it, i.e. that the URI is non-empty.
# This only works for hierarchical schemes, like HTTP or FTP.  Conceivably,
#   there's a problem if the base URL uses a non-hierarchical scheme, and
#   the document contains relative URLs.  Absolute URLs will be OK.
# Any HTML-escaping/unescaping should be done outside of this routine, since
#   it is used for any relative->absolute URL conversion, not just HTML.
# NOTE: IF YOU MODIFY THIS ROUTINE, then be sure to review and possibly
#   modify the corresponding routine _proxy_jslib_full_url() in the
#   JavaScript library, far below in the routine return_jslib().  It is
#   a Perl-to-JavaScript translation of this routine.

sub full_url {
    my($uri_ref, $retain_query)= @_ ;

    # Disable $retain_query until potential anonymity issues are resolved.
    $retain_query= 0 ;

    $uri_ref=~ s/^\s+|\s+$//g ;  # remove leading/trailing whitespace

    return $uri_ref if ($uri_ref=~ /^about:\s*blank$/i) ;

    # For now, prevent redirecting into x-proxy URLs.
    # This slows down the main tag-converting loop by 0-1%.
    return undef if $uri_ref=~ m#^x-proxy:#i ;

    # Handle "javascript:" URLs separately.  "livescript:" is an old synonym.
    if ($uri_ref=~ /^(?:javascript|livescript):/i) {
  return undef if $main::scripts_are_banned_here ;
  return $uri_ref unless $main::PROXIFY_SCRIPTS ;
  my($script)= $uri_ref=~ /^(?:javascript|livescript):(.*)$/si ;
  my($rest, $last)= &separate_last_js_statement(\$script) ;
  $last=~ s/\s*;\s*$// ;
  return 'javascript:' . (&proxify_js($rest, 1))[0]
           . '; _proxy_jslib_proxify_html(' . (&proxify_js($last, 0))[0] . ')[0]' ;
    }

    # Separate fragment from URI
    my($uri, $frag)= $uri_ref=~ /^([^#]*)(#.*)?/ ;
    return $uri_ref if $uri eq '' ;  # allow bare fragments to pass unchanged

    # Hack here-- some sites (e.g. eBay) create erroneous URLs with linefeeds
    #   in them, which makes the links unusable if they are encoded here.
    #   So, here we strip CR and LF from $uri before proceeding.  :P
    $uri=~ s/[\015\012]//g ;

    # Sometimes needed for SWF apps; see comments above this routine.
    my($query) ;
    ($uri, $query)= split(/\?/, $uri)  if $retain_query ;
    $query= '?' . $query   if $query ;

    # calculate absolute URL based on four possible cases
    my($absurl)=
      $uri=~ m#^[\w+.-]*:#i   ?  $uri                 # absolute URL
    : $uri=~ m#^//#           ?  $main::base_scheme . $uri  # net_path (rare)
    : $uri=~ m#^/#            ?  $main::base_host . $uri    # abs_path, rel URL
    : $uri=~ m#^\?#           ?  $main::base_file . $uri    # abs_path, rel URL
    :                            $main::base_path . $uri ;  # relative path

    my $rv = $main::url_start . &wrap_proxy_encode($absurl) . $query . $frag ;
    return $rv ;
}

1;
