package TryCatchTest;

sub foo {
  return bar() + baz();
}

sub bar { return 12; }
sub baz { return 30; }

1;
