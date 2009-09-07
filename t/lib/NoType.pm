package NoType;

use strict;
use warnings;

#use Moose;
use TryCatch;

BEGIN { 
    package Error;
    sub new { bless {}, $_[0]}
    #use Moose;
}
my $t = Error->new;

sub error {
    die bless {}, 'Error';
}

try {
    error();
}
catch(Error $e) {
    print "Error catched\n";
}

1;
