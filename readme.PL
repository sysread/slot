use strict;
use warnings;
use Pod::Select 'podselect';

print "Generating README.pod\n";

podselect {-output => 'README.pod'}, 'lib/prop.pm';

exit 0;
