package TryCatch::Exception;

use Moose;
use TryCatch qw//;

use MooseX::Types::Moose qw/CodeRef ArrayRef/;

use Scope::Upper qw/unwind want_at :words/;
use namespace::clean -except => 'meta';

has try => (
  is => 'ro',
  isa => CodeRef,
  required => 1
);

has catches => (
  is => 'ro',
  isa => ArrayRef[ArrayRef[CodeRef]],
  default => sub { [] }
);

has ctx => (
  is => 'ro',
  required => 1
);

our $CTX;

sub _run_block {
  my ($self, $code) = (shift,shift);

  my @ret;
  my $wa = want_at $CTX;
  if ($wa) {
    @ret = $code->(); 
  } elsif (defined $wa) {
    $ret[0] = $code->();
  } else {
    $code->();
  }
  return @ret;
}

sub run {
  my ($self, @args) = @_;
  local $CTX = $CTX;

  my ($package) = caller(1);
  if ($package eq __PACKAGE__) {
    # nested: try { try {} }
    die "Internal Error: Nested try without CTX" unless defined $CTX;
  } else {
    $CTX = $self->ctx;
  }

  my $wa = want_at $CTX;
  local $@;
  eval {
    $self->_run_block($self->try, @args);
  };

  # If we get here there was either no explicit return or an error
  return unless $@;
  my $err = $@;

  CATCH: for my $catch ( @{$self->catches} ) {
    my $sub = pop @$catch;
    for my $cond (@$catch) {
      if (ref $cond) {
        local *_;
        $_ = $err;
        next CATCH unless $cond->();
      }
      else {
        my $tc = TryCatch->get_tc($cond);
        next CATCH unless $tc->check($err);
      }
          
    }
    #TryCatch::XS::_run_block($sub, $wa);
    $self->_run_block($sub, @args);
    last;
  }

  return;
}

sub catch {
  my ($self, @conds) = @_;
  push @{$self->catches}, [@conds];
  return $self;

}

__PACKAGE__->meta->make_immutable;

1;
