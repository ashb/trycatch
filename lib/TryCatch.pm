package TryCatch;

use strict;
use warnings;


use Devel::Declare ();
use B::Hooks::EndOfScope;
use B::Hooks::OP::PPAddr;
use Devel::Declare::Context::Simple;
use Parse::Method::Signatures;
use Moose::Util::TypeConstraints;
use Scope::Upper qw/localize unwind want_at :words/;
use Carp qw/croak/;
use XSLoader;

use base qw/Devel::Declare::Context::Simple/;


our $VERSION = '1.003000';

# Signal to the xs PL_check hooks.
our $NEXT_EVAL_IS_TRY = 0;

# Constants
my ($LOOKAHEAD_TRY, $LOOKAHEAD_CATCH) = (0,1);

XSLoader::load(__PACKAGE__, $VERSION);

use namespace::clean;

use Sub::Exporter -setup => {
  exports => [qw/try/],
  groups => { default => [qw/try/] },
  installer => sub {
    my ($args, $to_export) = @_;
    my $pack = $args->{into};
    my $ctx_class = $args->{parser} || 'TryCatch';

    foreach my $name (@$to_export) {
      if (my $parser = __PACKAGE__->can("_parse_${name}")) {
        Devel::Declare->setup_for(
          $pack,
          { $name => { const => sub { $ctx_class->$parser($pack, @_) } } },
        );
      }
    }
    Sub::Exporter::default_installer(@_);

  }
};


# The actual try call itself. Nothing to do with parsing.
sub try () {
  return;
}

# Where we store all the TCs for catch blocks created at compile time
# Not sure we really want to do this, but we will for now.
our $TC_LIBRARY = {};

sub check_tc {
  my ($class, $tc) = @_;

  my $type = $TC_LIBRARY->{$tc} or die "Unable to find parse TC for '$tc'";

  return $type->check($TryCatch::Error);
}

# From here on out its parsing methods.

# Replace 'try {' with an 'try; { local $@; eval {'
sub _parse_try {
  my ($class,$pack, @args) = @_;

  # Hide from carp - report errors from line of 'try {' in user source.
  local $Carp::Internal{'Devel::Declare'} = 1;

  my $ctx = $class->new->init(@args);

  # Move parse head past 'try ' (space is optional
  $ctx->skip_declarator;
  $ctx->skipspace;

  # Shadow try to be a constant no-op sub. Hopefully
  $ctx->shadow(sub () { } );

  $ctx->inject_if_block(
    $ctx->inject_into_try . $ctx->scope_injector_call( $LOOKAHEAD_TRY ),
    ';'
  ) or croak "block required after try";

  $ctx->debug_linestr('post try');
}

sub scope_injector_call {
  my ($self, $state) = @_;
  return ' BEGIN { ' . ref( $self ) . "->inject_scope($state) }; ";
}


sub inject_scope {
  my ($class, $opts) = @_;

  my $hooks = TryCatch::XS::install_op_checks();

  on_scope_end {
    $class->lookahead_after_block( $opts );

    # TODO: Rethink how i install the hooks. If i uninstall(/disable) them here
    # then they get removed before the LEAVETRY check gets called. Probably
    # switch to a single global set of hooks at look at %^H (?) for lexical
    # goodness.

    #TryCatch::XS::uninstall_op_checks( $hooks );
    #undef $hooks;
  }
}

# Called after the block from try {} or catch {}
#
# Look ahead and determine what action to take based on wether or not we see
# a 'catch' token after the block
sub lookahead_after_block {
  my ($class, $state) = @_;
  my $orig_offset = Devel::Declare::get_linestr_offset();
  my $ctx = $class->new->init( '', $orig_offset );

  my $offset = $ctx->skipspace;
  my $linestr = $ctx->get_linestr;

  my $toke = '';
  my $len = 0;

  # Since we're not being called from a normal D::D callback, we have to
  # find this info manually.
  if ($len = Devel::Declare::toke_scan_word($offset, 1 )) {
    $toke = substr( $linestr, $offset, $len );
    $ctx->{Declarator} = $toke;
  }

  if ($toke eq 'catch') {
    # We don't want the 'catch' token in the output since it messes up the
    # if/else we build up. So dont let control go back to perl just yet.

    $ctx->_parse_catch( $state );

  } else  {
    # No (more) catch blocks, so write the postlude
    my $code;
    if ($state == $LOOKAHEAD_CATCH) {
      $code = $ctx->inject_post_catch;
    }
    else {
      $code = $ctx->inject_when_no_catch;
      $NEXT_EVAL_IS_TRY = 1;
    }

    # Don't try this at home kids
    #
    # Since there was no 'catch' following, move back to the end of the
    # closing brace (where offset was when we started). If we are after the
    # skip space then the 'parse pointer' could be at the start of a POD line,
    # and ";=head1" isn't valid perl ;)
    #
    # This seems to cause problems with nested try so taken out for now
    #
    #TryCatch::XS::set_linestr_offset($orig_offset);
    #$ctx->{Offset} = $orig_offset;

    substr($linestr, $ctx->offset, 0, $code);

    $ctx->set_linestr($linestr);
    $ctx->debug_linestr("finalizer");
  }
}

sub _parse_catch {
  my ($ctx, $state) = @_;

  # Hide these things from carp - this makes C<croak> appear to come from the source line.
  local $Carp::Internal{'TryCatch'} = 1;
  local $Carp::Internal{'Devel::Declare'} = 1;
  local $Carp::Internal{'B::Hooks::EndOfScope'} = 1;

  # This isn't a normal DD-callback, so we can strip_name to get rid of 'catch'
  my $offset = $ctx->offset;
  $ctx->strip_name;
  $ctx->skipspace;
 
  $ctx->debug_linestr('catch');
  my $linestr = $ctx->get_linestr;

  my ($code, $var_code, @conditions) = ("","");

  # optional ()
  if (substr($linestr, $ctx->offset, 1) eq '(') {
    ($var_code, @conditions) = $ctx->parse_proto()
  }

  @conditions = ('1') unless @conditions;

  if ( $state != $LOOKAHEAD_CATCH ) {
    $NEXT_EVAL_IS_TRY = 1;
    $code = $ctx->inject_after_try . "if (";
  }
  else {
    $code = "elsif (";
  }

  $var_code = $ctx->scope_injector_call( $LOOKAHEAD_CATCH ) . $var_code;

  $ctx->inject_if_block(
    $var_code,
    $code . join(' && ', @conditions) . ')'
  ) or croak "block required after catch";

  $ctx->debug_linestr('post catch');

}

sub parse_proto {
  my ($self) = @_;

  my $proto = $self->strip_proto;
  croak "Run-away catch signature"
    unless (length $proto);

  return $self->parse_proto_using_pms($proto);
}

sub _string_to_tc {
  my ($class, $name) = @_;

  my $tc = $class->find_registered_constraint($name);

  return $tc if ref $tc;

  return Moose::Util::TypeConstraints::find_or_create_isa_type_constraint($name)
}

sub parse_proto_using_pms {
  my ($self, $proto) = @_;

  my @conditions;

  my $sig = Parse::Method::Signatures->new(
    input => $proto,
    from_namespace => $self->get_curstash_name,
    type_constraint_callback => \&_string_to_tc,
  );
  my $errctx = $sig->ppi;
  my $param = $sig->param;

  $sig->error( $errctx, "Parameter expected")
    unless $param;

  my $left = $sig->remaining_input;

  my $var_code = '';

  if (my $var_name = $param->can('variable_name') ) {

    my $name = $param->$var_name();
    $var_code = "my $name = \$TryCatch::Error;";
  }

  # (TC $var)
  if ($param->has_type_constraints) {
    my $tc = $param->meta_type_constraint;
    $TryCatch::TC_LIBRARY->{"$tc"} = $tc;
    push @conditions, "TryCatch->check_tc('$tc')";
  }

  # ($var where { $_ } )
  if ($param->has_constraints) {
    foreach my $con (@{$param->constraints}) {
      $con =~ s/^{|}$//g;
      push @conditions, "do {local \$_ = \$TryCatch::Error; $con }";
    }
  }

  return $var_code, @conditions;
}


#######################################################################
# Injected snippets

sub inject_into_try {
  # try { ...
  # ->
  # try; { local $@; eval { ...

  'local $@; eval {'
}

sub inject_after_try {
  # This semicolon is for the end of the eval
  return ';$TryCatch::Error = $@; } if ($TryCatch::Error) { ';
}

sub inject_when_no_catch {
  # This undef is to ensure that there is the eval{}; is called in void context
  # i.e that its not the last op in a subroutine
  return "};undef;";
}

sub inject_post_catch {
  # We do it like this so that PROPGATE gets called, in case anyone is using it
  return 'else { $@ = $TryCatch::Error; die } };undef;';
}

#######################################################################

require Devel::PartialDump if $ENV{TRYCATCH_DEBUG};

*debug_linestr = !( ($ENV{TRYCATCH_DEBUG} || 0) & 1)
               ? sub {}
               : sub {
  my ($ctx, $message) = @_;

  local $Carp::Internal{'TryCatch'} = 1;
  local $Carp::Internal{'TryCatch::Basic'} = 1;
  local $Carp::Internal{'Devel::Declare'} = 1;
  local $Carp::Internal{'B::Hooks::EndOfScope'} = 1;
  local $Carp::Internal{'Devel::PartialDump'} = 1;
  Carp::cluck($message) if $message;

  warn   "  Substr: ", Devel::PartialDump::dump(substr($ctx->get_linestr, $ctx->offset)),
       "\n  Whole:  ", Devel::PartialDump::dump($ctx->get_linestr), "\n\n";
};


1;

__END__

=head1 NAME

TryCatch - first class try catch semantics for Perl, without source filters.

=head1 DESCRIPTION

This module aims to provide a nicer syntax and method to catch errors in Perl,
similar to what is found in other languages (such as Java, Python or C++).  The
standard method of using C<< eval {}; if ($@) {} >> is often prone to subtle
bugs, primarily that its far too easy to stomp on the error in error handlers.
And also eval/if isn't the nicest idiom.

=head1 SYNOPSIS

 use TryCatch;

 sub foo {
   my ($self) = @_;

   try {
     die Some::Class->new(code => 404 ) if $self->not_found;
     return "return value from foo";
   }
   catch (Some::Class $e where { $_->code > 100 } ) {
   }
 }

=head1 SYNTAX

This module aims to give first class exception handling to perl via 'try' and
'catch' keywords. The basic syntax this module provides is C<try { # block }>
followed by zero or more catch blocks. Each catch block has an optional type
constraint on it the resembles Perl6's method signatures. 

Also worth noting is that the error variable (C<$@>) is localised to the
try/catch blocks and will not leak outside the scope, or stomp on a previous
value of C<$@>.

The simplest case of a catch block is just

 catch { ... }

where upon the error is available in the standard C<$@> variable and no type
checking is performed. The exception can instead be accessed via a named
lexical variable by providing a simple signature to the catch block as follows:

 catch ($err) { ... }

Type checking of the exception can be performed by specifing a type constraint
or where clauses in the signature as follows:

 catch (TypeFoo $e) { ... }
 catch (Dict[code => Int, message => Str] $err) { ... }

As shown in the above example, complex Moose types can be used, including
L<MooseX::Types> style of type constraints

In addition to type checking via Moose type constraints, you can also use where
clauses to only match a certain sub-condition on an error. For example,
assuming that C<HTTPError> is a suitably defined TC:

 catch (HTTPError $e where { $_->code >= 400 && $_->code <= 499 } ) { 
   return "4XX error";
 }
 catch (HTTPError $e) {
   return "other http code";
 }

would return "4XX error" in the case of a 404 error, and "other http code" in
the case of a 302.

In the case where multiple catch blocks are present, the first one that matches
the type constraints (if any) will executed.

=head1 BENEFITS

B<return>. You can put a return in a try block, and it would do the right thing
- namely return a value from the subroutine you are in, instead of just from
the eval block. 

B<Type Checking>. This is nothing you couldn't do manually yourself, it does it
for you using Moose type constraints.

=head1 TODO

=over

=item *

Decide on C<finally> semantics w.r.t return values.

=item *

Write some more documentation

=item *

Split out the dependancy on Moose

=back

=head1 SEE ALSO

L<MooseX::Types>, L<Moose::Util::TypeConstraints>, L<Parse::Method::Signatures>.

=head1 AUTHOR

Ash Berlin <ash@cpan.org>

=head1 THANKS

Thanks to Matt S Trout and Florian Ragwitz for work on L<Devel::Declare> and
various B::Hooks modules

Vincent Pit for L<Scope::Upper> that makes the return from block possible.

Zefram for providing support and XS guidance.

Xavier Bergade for the impetus to finally fix this module in 5.12.

=head1 LICENSE

Licensed under the same terms as Perl itself.

