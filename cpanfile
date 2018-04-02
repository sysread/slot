requires 'perl', '5.008';
requires 'Carp';

recommends 'Class::XSAccessor', '1.19';

on test => sub {
  requires 'Type::Tiny';
  requires 'Test::More';
};
