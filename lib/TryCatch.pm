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

use Devel::Declare ();
use B::Hooks::EndOfScope;
use B::Hooks::Parser;
use Devel::Declare::Context::Simple;

sub try () {}

# Replace try with an actual eval call;
sub _parse_try {
  my $pack = shift;

  my $ctx = Devel::Declare::Context::Simple->new->init(@_);

  if (my $len = Devel::Declare::toke_scan_ident( $ctx->offset )) {
    my $linestr = $ctx->get_linestr();
    substr( $linestr, $ctx->offset, $len ) = 'try; eval';
    $ctx->set_linestr($linestr);
  }
  
  $ctx->skip_declarator;
  $ctx->inject_if_block(q{ BEGIN { TryCatch::geif_semicolon() } });
}


sub geif_semicolon {
  B::Hooks::Parser::inject(';');
}
1;
