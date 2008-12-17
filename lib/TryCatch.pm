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

sub try (&) {}

# Replace try with an actual eval call;
sub _parse_try {
  my ($pack) = @_;

  on_scope_end {
    geif_semicolon();
  }
}


sub geif_semicolon {
  my $offset = Devel::Declare::get_linestr_offset();
  $offset += Devel::Declare::toke_skipspace($offset);
  my $linestr = Devel::Declare::get_linestr();

  $offset = Devel::Declare::get_linestr_offset();
  substr( $linestr, $offset, 0 ) = ';';
  Devel::Declare::set_linestr($linestr);
}
1;
