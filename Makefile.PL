use strict;
use warnings;

require 5.008001;

use inc::Module::Install 0.77;

name 'TryCatch';
all_from 'lib/TryCatch.pm';

requires 'Parse::Method::Signatures';
requires 'B::Hooks::EndOfScope' => 0.05;
requires 'Devel::Declare';
requires 'Moose';
requires 'Scope::Upper' => 0.06;

WriteAll;


