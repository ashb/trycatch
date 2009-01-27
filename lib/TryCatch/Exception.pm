package TryCatch::Exception;

use strict;
use warnings;

use Scope::Upper qw/unwind want_at :words/;
use namespace::clean;

sub catch {
  my ($self, @conds) = @_;
  my $sub = pop @conds;
  die "no code to catch!" unless ref $sub && ref $sub eq 'CODE';
  
  local $@;
  for my $cond (@conds) {
    if (ref $cond) {
      local *_ = \$self->{error};
      return $self unless $cond->();
    }
    else {
      my $tc = TryCatch->get_tc($cond);
      return $self unless $tc->check($self->{error});
    }
        
  }

  # If we get here then the conditions match

  my $ctx = want_at SUB(CALLER(1));
  eval {
    $@ = $self->{error};
    if ($ctx) {
      my @ret = $sub->(); 
    } elsif (defined $ctx) {
      my $ret = $sub->();
    } else {
      $sub->();
    }
  };

  return "TryCatch::Exception::Handled";
}

package TryCatch::Exception::Handled;

sub catch {}

1;
