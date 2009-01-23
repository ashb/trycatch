package TryCatch::Exception;

use strict;
use warnings;

use Scope::Upper qw/unwind want_at :words/;
use namespace::clean;

use vars qw/$MATCHED/;

sub catch {
  my ($self, $sub) = @_;
  return unless ref $sub && ref $sub eq 'CODE';
  
  #TODO: Check $self, better yet work out how to do the check at compile time
  #      (i.e. that catch is preceded by catch or try)

  local $TryCatch::Exception::MATCHED;
  local $@;

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
 
  return "TryCatch::Exception::Handled" if $MATCHED;
  return $self;
}

package TryCatch::Exception::Handled;

sub catch {}

1;
