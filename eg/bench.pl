#!/usr/bin/perl

use lib 'lib', '../lib';

BEGIN {
    package My::Common;
    *throw_something = $0 =~ /_ok/ ? sub () { 0 } : sub () { 1 };
};

{
    package My::EvalDieObject;
    sub throw {
        my %args = @_;
        die bless {%args}, shift;
    };
};



our %tests = (
    '01_EvalDieScalar' => sub {

        eval {
            die 'Message' if My::Common::throw_something;
        };
        if ($@ =~ /^Message/) {
            1;
        };

    },
    '02_EvalDieObject' => sub {

        eval {
             My::EvalDieObject->throw if My::Common::throw_something;
        };
        if ($@) {
            if (ref $@ && $@->isa('My::EvalDieObject')) {
              my $e = $@;
              1;
            }
        }
    },
);


eval { 
  eval q{use Exception::Base 'Exception::My'};
$tests{ '03_ExceptionEval' } = sub {

        eval {
            Exception::My->throw(message=>'Message') if My::Common::throw_something;
        };
        if ($@) {
            my $e = Exception::Base->catch;
            if ($e->isa('Exception::My') and $e->matches('Message')) {
                1;
            };
        };

    };
$tests{ '04_Exception1Eval' } = sub {

        eval {
            Exception::My->throw(message=>'Message', verbosity=>1) if My::Common::throw_something;
        };
        if ($@) {
            my $e = Exception::Base->catch;
            if ($e->isa('Exception::My') and $e->matches('Message')) {
                1;
            };
        };

    };
};

eval q{
    die 1;
    package My::Error;
    BEGIN {
        eval {
            require Error;
            Error->import(':try');
        };
    };
    Error->VERSION or die;

    $main::tests{'05_Error'} = sub {

        try {
            Error::Simple->throw('Message') if My::Common::throw_something;
        }
        Error->catch(with {
            my $e = $_[0];
            if ($e->text eq 'Message') {
                1;
            }
        });

    };
};

eval {
    package My::ClassThrowable;
    require Class::Throwable;
    Class::Throwable->import;

    $main::tests{'06_ClassThrowable'} = sub {

        eval {
            Class::Throwable->throw('Message') if My::Common::throw_something;
        };
        if ($@) {
            my $e = $@;
            if (ref $e and $e->isa('Class::Throwable') and $e->getMessage eq 'Message') {
                1;
            };
        };

    };
};

eval {
    package My::ExceptionClass;
    require Exception::Class;
    Exception::Class->import('MyException');

    $main::tests{'07_ExceptionClass'} = sub {

        eval {
            MyException->throw(error=>'Message') if My::Common::throw_something;
        };
        my $e;
        if ($e = Exception::Class->caught('MyException') and $e->error eq 'Message') {
            1;
        };

    };
};

eval q{
    package My::ExceptionClassTC;
    BEGIN {
        eval {
            require Exception::Class;
            Exception::Class->import('MyException');
            require Exception::Class::TryCatch;
            Exception::Class::TryCatch->import;
        };
    };
    Exception::Class::TryCatch->VERSION or die;

    $main::tests{'08_ExceptionClassTC'} = sub {

        try eval {
            MyException->throw(error=>'Message') if My::Common::throw_something;
        };
        if (catch my $e) {
            if ($e->isa('MyException') and $e->error eq 'Message') {
                1;
            }
        };

    };
};


{
    package My::TryCatch;
    use TryCatch;

    $main::tests{'09_TryCatch'} = sub {

        try {
            die 'Message this message' if My::Common::throw_something;
        }
        catch ($e) {
            if ($@ =~ /^Message/) {
                1;
            };
        };

    };
};


use Benchmark ':all';

print "Benchmark for ", (My::Common::throw_something ? "FAIL" : "OK"), "\n";
my $result = timethese($ARGV[0] || -1, { %tests });
cmpthese($result);

