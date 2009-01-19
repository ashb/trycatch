package TryCatch;

use strict;
use warnings;

use base 'DynaLoader';

our $VERSION = '1.000000';

sub dl_load_flags { 0x01 }

__PACKAGE__->bootstrap($VERSION);

use Sub::Exporter -setup => {
  exports => [qw/try/],
  groups => { default => [qw/try/] },
  installer => sub {
    my ($args, $to_export) = @_;
    my $pack = $args->{into};
    foreach my $name (@$to_export) {
      if (my $parser = __PACKAGE__->can("_parse_${name}")) {
        Devel::Declare->setup_for(
          $pack,
          { $name => { const => sub { $parser->($pack, @_) } } },
        );
      }
      #if (my $code = __PACKAGE__->can("_extras_for_${name}")) {
      #  $code->($pack);
      #}
    }
    Sub::Exporter::default_installer(@_);

  }
};

use Devel::Declare ();
use B::Hooks::EndOfScope;
use Devel::Declare::Context::Simple;
use Parse::Method::Signatures;
use Moose::Util::TypeConstraints;
use Scope::Upper qw/unwind want_at :words/;
use TryCatch::Exception;
use Carp qw/croak/;



sub try {
  my ($sub, $terminal) = @_;

  local $@;
  my $ctx = SUB(CALLER(1));
  my @ret = TryCatch::XS::_monitor_return( $sub, want_at( $ctx ), 1);
  unwind @ret => $ctx if pop @ret;

  return "TryCatch::Exception::Handled" unless defined($@);
  return bless { error => $@ }, "TryCatch::Exception";
}


# Replace 'try {' with an 'try (sub {'
sub _parse_try {
  my $pack = shift;

  # Hide Devel::Declare from carp;
  local $Carp::Internal{'Devel::Declare'} = 1;

  my $ctx = Devel::Declare::Context::Simple->new->init(@_);

  if (my $len = Devel::Declare::toke_scan_ident( $ctx->offset )) {
    $ctx->inc_offset($len);
    $ctx->skipspace;

    my $linestr = $ctx->get_linestr;
    croak "block required after try"
      unless substr($linestr, $ctx->offset, 1) eq '{';

    substr($linestr, $ctx->offset+1,0) = q# BEGIN { TryCatch::try_postlude() }#;
    substr($linestr, $ctx->offset,0) = q#(sub #;
    $ctx->set_linestr($linestr);
  }
  
}

sub try_postlude {
  on_scope_end { try_postlude_block() }
}

sub catch_postlude {
  on_scope_end { catch_postlude_block() }
}

sub try_postlude_block {
  my $offset = Devel::Declare::get_linestr_offset();
  $offset += Devel::Declare::toke_skipspace($offset);
  my $linestr = Devel::Declare::get_linestr();

  my $toke = '';
  my $len = 0;
  if ($len = Devel::Declare::toke_scan_word($offset, 1 )) {
    $toke = substr( $linestr, $offset, $len );
  }

  $offset = Devel::Declare::get_linestr_offset();

  my $ctx = Devel::Declare::Context::Simple->new->init($toke, $offset);

  if ($toke eq 'catch') {

    process_catch($ctx, 1);

  } elsif ($toke eq 'finally') {
  } else {
    my $str = ',"empty");';
    substr( $linestr, $offset, 0 ) = $str;

    $ctx->set_linestr($linestr);
  }
}

sub catch_postlude_block {

  my $linestr = Devel::Declare::get_linestr();
  my $offset = Devel::Declare::get_linestr_offset();

  my $toke = '';
  my $len = 0;
  if ($len = Devel::Declare::toke_scan_word($offset, 1 )) {
    $toke = substr( $linestr, $offset, $len );
  }


  if ($toke eq 'catch') {
    my $ctx = Devel::Declare::Context::Simple->new->init($toke, $offset);
    process_catch($ctx, 0);
  } else {
    substr($linestr, $offset, 0) = ");";
    Devel::Declare::set_linestr($linestr);
  }
}

# turn 'catch() {' into '->catch({ TC_check_code;'
sub process_catch {
  my ($ctx) = @_;

  # Hide Devel::Declare from carp;
  local $Carp::Internal{'Devel::Declare'} = 1;

  my $linestr = $ctx->get_linestr;
  $ctx->skipspace;

  substr($linestr, $ctx->offset, 0) = ')->';
  $ctx->set_linestr($linestr);
  $ctx->inc_offset(length(")->") + length "catch");
  $ctx->skipspace;

  my $tc_code = "";
  # optional ()
  if (substr($linestr, $ctx->offset, 1) eq '(') {
    my $substr = substr($linestr, $ctx->offset+1);
    local $@;
    my ($param, $left) = eval { Parse::Method::Signatures->param($substr) };
    if ($@) {
      die $@;
    }
    $tc_code .= 'my ' . $param->variable_name . ' = $@;';

    substr($linestr, $ctx->offset, length($linestr) - $ctx->offset - length($left), '');
    $ctx->set_linestr($linestr);
    $ctx->skipspace;
    if (substr($linestr, $ctx->offset, 1) ne ')') {
      croak "')' expected after catch condition: $linestr\n";
    }

    substr($linestr, $ctx->offset, 1, '');
    $ctx->set_linestr($linestr);
    $ctx->skipspace;
  }

  croak "block required after catch"
    unless substr($linestr, $ctx->offset, 1) eq '{';

  substr($linestr, $ctx->offset+1,0) = 
    q# BEGIN { TryCatch::catch_postlude() };# . $tc_code;
  substr($linestr, $ctx->offset,0) = q#(sub #;
  $ctx->set_linestr($linestr);
}


1;

__END__

=head1 NAME

TryCatch - first class try catch semantics for Perl, with no source filters.

=head1 AUTHOR

Ash Berlin <ash@cpan.org>

=head1 LICENSE

Licensed under the same terms as Perl itself.
