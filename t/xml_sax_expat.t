use strict;
use warnings;
use Test::More;

use TryCatch;


try {
  require XML::SAX::Expat;
}
catch ($e where { qr{Can't load XML/SAX/Expat} } ) {
  plan skip_all => 'This test requires XML::SAX::Expat';
}

# Use an explict plan since the problem was that it didn't behave and catch properly.
plan tests => 5;

my $parser = XML::SAX::Expat->new(
	Handler => MyHandler->new(),
);

$parser->parse_string(<<EOF);
<foo>
 <bar id="1">
 </bar>
 <bar id="2">
 </bar>
 <bar id="3">
 </bar>
 <bar id="4">
 </bar>
</foo>
EOF

print "Completed successfully\n";

package MyHandler;
use base qw(XML::SAX::Base);
use TryCatch;
use Test::More;

sub end_element {
	try {
		die "error message";
	} catch( $e where { $_ =~ /message/ } ){
		ok "caught message\n";
	}
}
