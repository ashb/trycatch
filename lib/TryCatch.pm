package TryCatch;

use strict;
use warnings;
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

our $SPECIAL_VALUE = \"no return";

use Devel::Declare ();
use B::Hooks::EndOfScope;
use B::Hooks::Parser;
use Devel::Declare::Context::Simple;

sub try {}

# Replace try with an actual eval call;
sub _parse_try {
  my $pack = shift;

  my $ctx = Devel::Declare::Context::Simple->new->init(@_);

  if (my $len = Devel::Declare::toke_scan_ident( $ctx->offset )) {
    $ctx->inc_offset($len);
    $ctx->inject_if_block(q{ BEGIN { TryCatch::try_inner_postlude() } },
    #$ctx->inject_if_block(q{},
                          '; my $__t_c_ret = eval');
    print("1= '@{[Devel::Declare::get_linestr()]}'\n\n");
  }
  
}

sub try_inner_postlude {
  0 && on_scope_end {
    my $offset = Devel::Declare::get_linestr_offset();
    $offset += Devel::Declare::toke_skipspace($offset);
    my $linestr = Devel::Declare::get_linestr();
    print("2.1= '$linestr'\n\n");
    substr($linestr, $offset, 0) =
    q#
      }
      return $TryCatch::SPECIAL_VALUE;
      BEGIN { TryCatch::try_postlude() }
      #;
    print("2= '$linestr'\n\n");
    Devel::Declare::set_linestr($linestr);
  }
}

sub try_postlude {
  on_scope_end { try_postlude_block() }
}
sub try_postlude_block {
  my $offset = Devel::Declare::get_linestr_offset();
  $offset += Devel::Declare::toke_skipspace($offset);
  my $linestr = Devel::Declare::get_linestr();

  my $toke = '';  
  if (my $len = Devel::Declare::toke_scan_word($offset, 1 )) {
    $toke = substr( $linestr, $offset, $len );
  }

  $offset = Devel::Declare::get_linestr_offset();

  if ($toke eq 'catch') {
  } elsif ($toke eq 'finally') {
  } else {
    my $str = '; return $__t_c_ret if !ref($__t_c_ret) || $__t_c_ret != $TryCatch::SPECIAL_VALUE;'; 
    substr( $linestr, $offset, 0 ) = $str;

    Devel::Declare::set_linestr($linestr);
  }
  $linestr = Devel::Declare::get_linestr();
  print("3= '$linestr'\n");
}
1;
