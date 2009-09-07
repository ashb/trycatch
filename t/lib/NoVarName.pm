package NoVarName;

use strict;
use warnings;

#use Moose;
use TryCatch;

try {
}
catch(Error $) {
    print "Error catched\n";
}

1;

