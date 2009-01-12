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
      if (my $code = __PACKAGE__->can("_extras_for_${name}")) {
        $code->($pack);
      }
    }
    Sub::Exporter::default_installer(@_);

  }
};

# Used to detect when there is an explicity return from an eval block
our $SPECIAL_VALUE = \"no return";

use Devel::Declare ();
use B::Hooks::EndOfScope;
use Devel::Declare::Context::Simple;
#use Parse::Method::Signautres;
use Moose::Util::TypeConstraints;
use Scope::Upper qw/unwind want_at/;

sub try ($) {
  my @ret = TryCatch::XS::_monitor_return($_[0], want_at(1));
  #print("_monitor_return returned @ret @{[scalar @ret]}\n");
  unwind @ret, 1 if pop @ret;
}

# This might be what catch should be
sub catch{
  my ($cond, $err, $tc) = @_;

  local $@ = $@;
  local *_ = \$err;

  if (defined $tc) {
    my $type = Moose::Util::TypeConstraints::find_or_create_isa_type_constraint($tc);
    unless ($type) {
      warn "Couldn't convert '$tc' to a type constraint";
      return
    }

    return unless $type->check($err);
  }
  return $err if $cond->($err);
}

# Replace try {} with an try sub {};
sub _parse_try {
  my $pack = shift;

  my $ctx = Devel::Declare::Context::Simple->new->init(@_);

  if (my $len = Devel::Declare::toke_scan_ident( $ctx->offset )) {
    $ctx->inc_offset($len);
    $ctx->skipspace;
    my $ret = $ctx->inject_if_block(
      q# BEGIN { TryCatch::try_postlude() } #,
      'sub '
    );
  }
  
}

sub try_inner_postlude {
  on_scope_end {
    my $offset = Devel::Declare::get_linestr_offset();
    $offset += Devel::Declare::toke_skipspace($offset);
    my $linestr = Devel::Declare::get_linestr();
    substr($linestr, $offset, 0) = q# return $TryCatch::SPECIAL_VALUE; }#;
    Devel::Declare::set_linestr($linestr);
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

    substr( $linestr, $offset, $len ) = ';';
    $ctx->set_linestr($linestr);
    $ctx->inc_offset(1);
    $ctx->skipspace;
    process_catch($ctx, 1);

  } elsif ($toke eq 'finally') {
  } else {
    my $str = ';';# return $__t_c_ret if !ref($__t_c_ret) || $__t_c_ret != $TryCatch::SPECIAL_VALUE;'; 
    substr( $linestr, $offset, 0 ) = $str;

    $ctx->set_linestr($linestr);
  }
}

sub catch_postlude_block {

  my $linestr = Devel::Declare::get_linestr();
  my $offset = Devel::Declare::get_linestr_offset();

  print "post catch: '$linestr'\noffset = $offset\n";
  $offset += Devel::Declare::toke_skipspace($offset);

  my $toke = '';
  my $len = 0;
  if ($len = Devel::Declare::toke_scan_word($offset, 1 )) {
    $toke = substr( $linestr, $offset, $len );
  }


  if ($toke eq 'catch') {
    my $ctx = Devel::Declare::Context::Simple->new->init($toke, $offset);
    substr( $linestr, $offset, $len ) = '';
    $ctx->set_linestr($linestr);
    $ctx->inc_offset(1);
    $ctx->skipspace;
    process_catch($ctx, 0);
  }
}


sub process_catch {
  my ($ctx, $first) = @_;
  
  my $linestr = $ctx->get_linestr;
  my $sub = substr($linestr, $ctx->offset);
  print("process_catch: $first '$sub'\n");

  if (substr($linestr, $ctx->offset, 1) eq '(') {
    my ($param, $left) = ( # TODO: Parse::Method::Signatures->param
      input => $linestr,
      offset => $ctx->offset+1 );

    substr($linestr, $ctx->offset, length($linestr) - ($ctx->offset + length($left)), '');
    $ctx->set_linestr($linestr);
    $ctx->skipspace;

    if (substr($linestr, $ctx->offset, 1) ne ')') {
      die "')' expected after catch condition: $linestr\n";
    }
    substr($linestr, $ctx->offset, 1, '');
    $ctx->set_linestr($linestr);

    my $code;
    $code = 'else ' unless $first;

    $code .= 'if( my '
           . ($param->{var} || '$e')
           . ' = TryCatch::catch(';
    if ($param->{where}) {
      $code .= $param->{where}[0];
    } else {
      $code .= 'sub { 1 }'
    }
    $code .= ', $@';
    if ($param->{tc}) {
      $code .= ', \'' . $param->{tc} . '\''
    }

    $code .= ')) ';

    substr($linestr, $ctx->offset, 1) = $code;

    $ctx->set_linestr($linestr);
    $ctx->inc_offset(length($code));
  } else {
    my $str;
    $str = 'else ' unless $first;
    $str .= 'if ($@)'; 

    #TODO: Check a { is next thing
    substr( $linestr, $ctx->offset, 1 ) = $str;

    $ctx->set_linestr($linestr);
    $ctx->inc_offset(length($str));
  }
  print("linestr = '" .
    substr($linestr, $ctx->offset) . "'\n");
  $ctx->inject_if_block( 'BEGIN { TryCatch::catch_postlude() }');
}

1;

__END__

=head1 NAME

TryCatch - first class try catch semantics for Perl, with no source filters.

=head1 AUTHOR

Ash Berlin <ash@cpan.org>

=head1 LICENSE

Licensed under the same terms as Perl itself.
