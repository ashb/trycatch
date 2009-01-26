package TryCatch::TypeParser;

# This will eventually belong somewhere else. probably in
# Parse::Method::Signatures
#
# There's probably half a dozen functions in Moose::Util::TypeConstraints I
# should be using instead of what I'm doing here.

use Moose;
use Moose::Meta::TypeConstraint::Union;
use Data::Dumper;
use Carp::Clan qw/^TryCatch/;

use namespace::clean -except => 'meta';

has 'type_registry' => (
  is => 'ro',
  lazy_build => 1
);

has 'package' => (  
  is => 'ro',
  isa => 'ClassName'
);

sub _build_type_registry {
  Moose::Util::TypeConstraints->get_type_constraint_registry;
}

sub str_tc {
  my ($self, $type) = @_;
  
  if (my $code = $self->package->can($type)) {
    my $tc = $code->();
    # TODO: some checking on what $tc is
    return $tc if defined $tc;
  }

  $self->type_registry->find_type_constraint($type) || $type;
}

sub visit {
  my ($self, $tc) = @_;

  unless (ref $tc) {
    return $self->str_tc($tc);
  } elsif ($tc->{-or}) {
    return $self->union_tc( $tc->{-or} );
  } elsif ( $tc->{-type} ) {
    return $self->param_tc( $tc->{-type}, $tc->{-params} );
  } else {
    local $Data::Dumper::Indent = 1;
    croak "Cannot deal with tc struct: \n" . Dumper($tc);
  }
}

sub union_tc {
  my ($self, $types) = @_;

  my @types = map { $self->visit($_) } @$types;

  return $types[0] if @types == 1;

  return Moose::Meta::TypeConstraint::Union->new( type_constraints => \@types );
}

sub param_tc {
  my ($self, $type, $params) = @_;
  my @params = map { $self->visit($_) } @$params;

  $type = $self->str_tc($type);

  return $type->parameterize(@params);
}

1;
