package TryCatch::Exception;

use Moose;

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
  my ($self, $code) = @_;

  my $wa = want_at $CTX;
  if ($wa) {
    my @ret = $code->(); 
  } elsif (defined $wa) {
    my $ret = $code->();
  } else {
    $code->();
  }
}

sub run {
  my ($self) = @_;
  local $CTX = $CTX;

  my ($package) = caller(1);
  if ($package eq __PACKAGE__) {
    # nested: try { try {} }
    die "Internal Error: Nested try without CTX" unless defined $CTX;
  } else {
    $CTX = $self->ctx;
  }

  local $@;
  eval {
    $self->_run_block($self->try);
  };

  # If we get here there was either no explicit return or an error
  return unless defined($@);
  my $err = $@;

  CATCH: for my $catch ( @{$self->catches} ) {
    my $sub = pop @$catch;
    for my $cond (@$catch) {
      if (ref $cond) {
        local *_ = \$err;
        next CATCH unless $cond->();
      }
      else {
        my $tc = TryCatch->get_tc($cond);
        next CATCH unless $tc->check($err);
      }
          
    }

    $self->_run_block($sub);
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
