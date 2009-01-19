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
  local $@ = $self->{error};

  my $ctx = SUB(CALLER(1));
  my @ret = TryCatch::XS::_monitor_return($sub, want_at( $ctx ), 0);

  # TODO: This will be wrong if i allow finally
  unwind @ret => $ctx if pop @ret;
 
  return "TryCatch::Exception::Handled" if $MATCHED;
  return $self;
}

package TryCatch::Exception::Handled;

sub catch {}

1;
